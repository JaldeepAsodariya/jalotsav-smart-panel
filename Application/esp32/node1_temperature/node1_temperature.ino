/*
 * FlutterCon India 2026: Node 1, temperature
 * ESP32-C3 Super Mini + ADS1115 + PT100
 *
 * Measures the PT100 with the ADS1115 (ratiometric) once a second and:
 *   - joins Node 2's Wi-Fi network "FC26-NET" and sends it °C as one UDP packet a second
 *     (no router: Node 2 is the access point)
 *   - serves it over BLE as "FC26-TEMP" (the app reads the temperature here and calibrates)
 *
 * Circuit (see ../WIRING.md):
 *   3V3 ── A0 ── Rref ── A1 ── lead A ──┐
 *                                       PT100 ── lead C ── GND
 *                         A2 ── lead B ──┘   (lead B is the sense wire: no current flows)
 *
 * Board: "ESP32C3 Dev Module", USB CDC On Boot: Enabled, Partition: Huge APP (3MB No OTA)
 * Library: "Adafruit ADS1X15"
 */

#include <Wire.h>
#include <WiFi.h>
#include <WiFiUdp.h>
#include <Preferences.h>
#include <Adafruit_ADS1X15.h>
#include <BLEDevice.h>
#include <BLEServer.h>

#include "fc26_protocol.h"

struct Measurement { fc26::Fault fault; float ohms; float celsius; };

// ---------- Pins (ESP32-C3 Super Mini) ----------
constexpr int PIN_SDA   = 5;   // right header
constexpr int PIN_SCL   = 6;

// ---------- PT100 measurement ----------
constexpr float RREF  = 980.0f;  // ohms. Measure YOUR resistor with a multimeter and put the value here.
constexpr float R0    = 100.0f;   // PT100 = 100 Ω at 0 °C
constexpr int   WIRES = 2;        // 3 = lead compensation via A2; 2 = 2-wire probe (A2 unused)
constexpr int   SAMPLES = 4;      // conversions averaged per channel
constexpr uint32_t READ_EVERY_MS = 1000;


Adafruit_ADS1115 ads;
Preferences prefs;
bool adsOk = false;
float offsetC = 0;           // calibration offset, stored in flash
float lastRawC = NAN;        // before offset, used by "CAL="
uint8_t seq = 0;

BLECharacteristic *readingChr = nullptr;
volatile bool bleConnected = false;
portMUX_TYPE cmdMux = portMUX_INITIALIZER_UNLOCKED;
char pendingCmd[24] = {0};

WiFiUDP udp;
const IPAddress NODE2(fc26::NODE2_IP[0], fc26::NODE2_IP[1], fc26::NODE2_IP[2], fc26::NODE2_IP[3]);
uint32_t sentOk = 0, sentFail = 0;

// ---------- PT100 maths ----------
// Callendar–Van Dusen (IEC 60751), solved for t ≥ 0 °C; within 0.1 °C down to −40 °C.
float ohmsToCelsius(float r) {
  constexpr float A = 3.9083e-3f, B = -5.775e-7f;
  const float disc = A * A - 4 * B * (1 - r / R0);
  return (-A + sqrtf(disc)) / (2 * B);
}

// Reads one input in volts, choosing the most sensitive ADS1115 range that fits.
float readVolts(uint8_t ch) {
  struct Range { adsGain_t gain; float fullScale; };
  static const Range ranges[] = {
    {GAIN_SIXTEEN, 0.256f}, {GAIN_EIGHT, 0.512f}, {GAIN_FOUR, 1.024f},
    {GAIN_TWO, 2.048f}, {GAIN_ONE, 4.096f},
  };
  ads.setGain(GAIN_ONE);
  const float coarse = ads.computeVolts(ads.readADC_SingleEnded(ch));
  for (const Range &r : ranges) {
    if (fabsf(coarse) < r.fullScale * 0.9f || r.gain == GAIN_ONE) {
      ads.setGain(r.gain);
      float sum = 0;
      for (int i = 0; i < SAMPLES; ++i) sum += ads.computeVolts(ads.readADC_SingleEnded(ch));
      return sum / SAMPLES;
    }
  }
  return coarse;
}

Measurement measure() {
  if (!adsOk) return {fc26::FAULT_ADC_MISSING, NAN, NAN};
  const float v0 = readVolts(0);              // top of Rref (3V3 rail)
  const float v1 = readVolts(1);              // bottom of Rref = lead A
  const float v2 = WIRES == 3 ? readVolts(2) : v1;  // sense lead B
  const float vRef = v0 - v1;                 // volts across Rref → current
  if (v0 < 2.5f) return {fc26::FAULT_ADC_MISSING, NAN, NAN};   // A0 not wired to 3V3
  if (vRef < 0.02f) return {fc26::FAULT_OPEN, NAN, NAN};      // almost no current: probe open
  if (v2 > v1 + 0.005f || v2 < -0.005f) return {fc26::FAULT_OPEN, NAN, NAN};  // sense wire loose
  const float vElement = WIRES == 3 ? 2 * v2 - v1 : v1;       // lead resistances cancel
  const float ohms = RREF * vElement / vRef;
  if (ohms < 10.0f) return {fc26::FAULT_SHORT, ohms, NAN};
  if (ohms < 18.0f || ohms > 390.0f) return {fc26::FAULT_RANGE, ohms, NAN};
  return {fc26::FAULT_NONE, ohms, ohmsToCelsius(ohms)};
}

// ---------- BLE ----------
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *) override { bleConnected = true; }
  void onDisconnect(BLEServer *) override {
    bleConnected = false;
    BLEDevice::startAdvertising();   // let the next client in
  }
};

class CommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) override {
    String v = c->getValue();
    portENTER_CRITICAL(&cmdMux);
    strlcpy(pendingCmd, v.c_str(), sizeof(pendingCmd));
    portEXIT_CRITICAL(&cmdMux);
  }
};

void setupBle() {
  BLEDevice::init("FC26-TEMP");
  BLEServer *server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());
  BLEService *svc = server->createService(FC26_TEMP_SERVICE);
  readingChr = svc->createCharacteristic(
      FC26_TEMP_READING, BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  BLECharacteristic *cmd = svc->createCharacteristic(
      FC26_TEMP_COMMAND, BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  cmd->setCallbacks(new CommandCallbacks());
  svc->start();
  BLEAdvertising *adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(FC26_TEMP_SERVICE);
  adv->setScanResponse(true);
  BLEDevice::startAdvertising();
}

void handleCommand() {
  char cmd[sizeof(pendingCmd)];
  portENTER_CRITICAL(&cmdMux);
  strlcpy(cmd, pendingCmd, sizeof(cmd));
  pendingCmd[0] = 0;
  portEXIT_CRITICAL(&cmdMux);
  if (!cmd[0]) return;

  if (!strncmp(cmd, "OFS=", 4)) {          // set the offset directly
    offsetC = constrain(atof(cmd + 4), -10.0f, 10.0f);
  } else if (!strncmp(cmd, "CAL=", 4)) {   // "the real temperature is X": offset = X − raw
    if (isnan(lastRawC)) { Serial.println("[cal] no valid reading yet"); return; }
    offsetC = constrain(atof(cmd + 4) - lastRawC, -10.0f, 10.0f);
  } else {
    Serial.printf("[ble] unknown command '%s'\n", cmd);
    return;
  }
  prefs.putFloat("ofs", offsetC);
  Serial.printf("[cal] offset now %+.2f °C\n", offsetC);
}

// ---------- Wi-Fi (join Node 2's network) ----------
void setupWifi() {
  WiFi.mode(WIFI_STA);
  WiFi.setTxPower(FC26_WIFI_TX_POWER);
  WiFi.setAutoReconnect(true);
  WiFi.begin(fc26::WIFI_SSID, fc26::WIFI_PASS, fc26::WIFI_CHANNEL);
  WiFi.setTxPower(FC26_WIFI_TX_POWER);
  Serial.printf("[wifi] joining %s\n", fc26::WIFI_SSID);
}

// Logs joins and drops, and retries if Node 2 wasn't up yet (or rebooted).
void handleWifi() {
  static bool wasUp = false;
  static uint32_t lastTry = 0, lastStats = 0;
  const bool up = WiFi.status() == WL_CONNECTED;
  if (up != wasUp) {
    wasUp = up;
    if (up) Serial.printf("[wifi] joined %s, IP %s, sending to %s:%u\n", fc26::WIFI_SSID,
                          WiFi.localIP().toString().c_str(), NODE2.toString().c_str(), fc26::UDP_PORT);
    else Serial.printf("[wifi] lost %s, looking again\n", fc26::WIFI_SSID);
    lastTry = millis();
  }
  if (!up && millis() - lastTry >= 10000) {
    lastTry = millis();
    Serial.printf("[wifi] %s not found yet (is Node 2 on?), retrying\n", fc26::WIFI_SSID);
    WiFi.disconnect();
    delay(100);   // let the old attempt stop, or begin() is refused ("sta is connecting")
    WiFi.begin(fc26::WIFI_SSID, fc26::WIFI_PASS, fc26::WIFI_CHANNEL);
    WiFi.setTxPower(FC26_WIFI_TX_POWER);
  }
  if (millis() - lastStats >= 10000) {
    lastStats = millis();
    Serial.printf("[wifi] %s, sent %lu ok, %lu failed\n", up ? "linked" : "not linked",
                  (unsigned long)sentOk, (unsigned long)sentFail);
  }
}

void sendToNode2(const fc26::TempPacket &pkt) {
  if (WiFi.status() != WL_CONNECTED) return;
  const bool ok = udp.beginPacket(NODE2, fc26::UDP_PORT) &&
                  udp.write((const uint8_t *)&pkt, sizeof(pkt)) == sizeof(pkt) && udp.endPacket();
  ok ? sentOk++ : sentFail++;
}

void publish(const Measurement &m) {
  int16_t centi = fc26::NO_READING;
  if (m.fault == fc26::FAULT_NONE) centi = (int16_t)lroundf((m.celsius + offsetC) * 100);

  fc26::TempPacket pkt = {{'F', 'C', '2', '6'}, fc26::VERSION, fc26::NETWORK_ID, seq, m.fault, centi};
  sendToNode2(pkt);

  // BLE reading: int16 centi-°C, uint16 centi-ohms, uint8 fault, uint8 seq, int16 centi-°C offset
  uint8_t b[8];
  const uint16_t centiOhms = isnan(m.ohms) ? 0 : (uint16_t)constrain(lroundf(m.ohms * 100), 0L, 65535L);
  const int16_t centiOfs = (int16_t)lroundf(offsetC * 100);
  memcpy(b, &centi, 2);
  memcpy(b + 2, &centiOhms, 2);
  b[4] = m.fault;
  b[5] = seq;
  memcpy(b + 6, &centiOfs, 2);
  readingChr->setValue(b, sizeof(b));
  if (bleConnected) readingChr->notify();
  seq++;
}

// ---------- Arduino ----------
void setup() {
  Serial.begin(115200);
  prefs.begin("fc26n1");
  offsetC = prefs.getFloat("ofs", 0);

  Wire.begin(PIN_SDA, PIN_SCL);
  adsOk = ads.begin(0x48, &Wire);
  ads.setDataRate(RATE_ADS1115_128SPS);
  Serial.printf("\nNode 1 (temperature) starting. ADS1115 %s, offset %+.2f °C\n",
                adsOk ? "found" : "NOT FOUND (check SDA/SCL/ADDR)", offsetC);

  setupWifi();
  setupBle();
}

void loop() {
  static uint32_t lastRead = 0;
  handleCommand();
  handleWifi();

  if (millis() - lastRead >= READ_EVERY_MS) {
    lastRead = millis();
    if (!adsOk) adsOk = ads.begin(0x48, &Wire);   // recover if the ADS was plugged in late
    const Measurement m = measure();
    lastRawC = m.fault == fc26::FAULT_NONE ? m.celsius : NAN;
    publish(m);
    if (m.fault == fc26::FAULT_NONE) {
      Serial.printf("[temp] %.2f °C  (%.2f Ω, offset %+.2f)\n", m.celsius + offsetC, m.ohms, offsetC);
    } else {
      Serial.printf("[temp] fault %u  (%.2f Ω)\n", m.fault, m.ohms);
    }
  }

}
