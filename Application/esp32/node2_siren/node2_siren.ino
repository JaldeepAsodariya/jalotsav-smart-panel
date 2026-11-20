/*
 * FlutterCon India 2026: Node 2, siren (the brain of the demo)
 * ESP32-C3 Super Mini + 5V relay (2N2222 driver, 1N4007 flyback) + TTP223 touch + common-anode RGB LED
 * + 220V hooter
 *
 * The alarm decision lives HERE, so the demo works with no app and no laptop:
 *   - creates the Wi-Fi network "FC26-NET" (no router needed); Node 1 joins it and sends °C
 *     as one UDP packet a second
 *   - temp ≥ setpoint for `delay` seconds  → ALARM, hooter ON
 *   - touch the TTP223                      → ACKNOWLEDGED, hooter OFF (stays off until it cools)
 *   - temp ≤ setpoint − hysteresis          → back to NORMAL automatically, hooter OFF
 *   - hold the TTP223 for 2 s when normal   → 2-second siren test
 *   - serves state + accepts commands over BLE as "FC26-SIREN" (test page and Flutter app)
 *
 * Board: "ESP32C3 Dev Module", USB CDC On Boot: Enabled, Partition: Huge APP (3MB No OTA)
 * Libraries: none beyond the esp32 core.
 * Wiring: see ../WIRING.md  —  ⚠️ 220V: read the mains section before wiring.
 */

#include <WiFi.h>
#include <WiFiUdp.h>
#include <Preferences.h>
#include <BLEDevice.h>
#include <BLEServer.h>

#include "fc26_protocol.h"

// ---------- Pins (ESP32-C3 Super Mini) ----------
constexpr int PIN_TOUCH = 5;    // right header. TTP223 I/O (active HIGH, momentary: jumpers A and B open)
constexpr int PIN_RELAY = 10;   // right header. → base resistor → 2N2222 base
constexpr int PIN_LED_R = 4;    // left header (GPIO2 skipped: boot strapping pin)
constexpr int PIN_LED_G = 3;
constexpr int PIN_LED_B = 1;
constexpr uint8_t LED_R_MAX = 60, LED_G_MAX = 255, LED_B_MAX = 255;

// ---------- Behaviour ----------
constexpr float    DEFAULT_SETPOINT   = 35.0f;   // °C: low enough for a warm hand to trigger on stage
constexpr float    DEFAULT_HYSTERESIS = 2.0f;    // °C: clears at setpoint − hysteresis
constexpr uint8_t  DEFAULT_DELAY_S    = 3;       // seconds above setpoint before the alarm
constexpr uint32_t SENSOR_TIMEOUT_MS  = 6000;    // no packet from Node 1 for this long = sensor lost
constexpr uint32_t MAX_ON_MS          = 120000;  // siren auto-silences after 2 min (counts as an ack)
constexpr uint32_t TEST_MS            = 2000;    // siren test length
constexpr uint32_t HOLD_FOR_TEST_MS   = 2000;
constexpr uint32_t DEBOUNCE_MS        = 30;
constexpr uint32_t NOTIFY_EVERY_MS    = 1000;

enum AlarmState : uint8_t { ST_NORMAL = 0, ST_PENDING = 1, ST_ALARM = 2, ST_ACKED = 3 };
const char *STATE_NAMES[] = {"NORMAL", "PENDING", "ALARM", "ACKNOWLEDGED"};

// Config (persisted in flash)
Preferences prefs;
float setpoint = DEFAULT_SETPOINT, hysteresis = DEFAULT_HYSTERESIS;
uint8_t delayS = DEFAULT_DELAY_S;

// Alarm engine
AlarmState state = ST_NORMAL;
uint32_t aboveSince = 0, alarmSince = 0, testUntil = 0;
bool relayOn = false;

// Latest from Node 1 (over UDP, read in loop)
portMUX_TYPE mux = portMUX_INITIALIZER_UNLOCKED;   // guards pendingCmd (written by BLE)
WiFiUDP udp;
uint32_t lastPacketAt = 0, rxOk = 0, rxRejected = 0;
int16_t centiC = fc26::NO_READING;
uint8_t sensorFault = fc26::FAULT_NONE;
bool sensorOnline = false;

// BLE
BLECharacteristic *stateChr = nullptr;
volatile bool bleConnected = false;
char pendingCmd[24] = {0};
bool stateDirty = true;

// ---------- Outputs ----------
void led(uint8_t r, uint8_t g, uint8_t b) {
  analogWrite(PIN_LED_R, 255 - r * LED_R_MAX / 255);
  analogWrite(PIN_LED_G, 255 - g * LED_G_MAX / 255);
  analogWrite(PIN_LED_B, 255 - b * LED_B_MAX / 255);
}

void applyRelay() {
  const bool want = state == ST_ALARM || millis() < testUntil;
  if (want == relayOn) return;
  relayOn = want;
  digitalWrite(PIN_RELAY, want ? HIGH : LOW);
  Serial.printf("[relay] %s\n", want ? "ON" : "OFF");
  stateDirty = true;
}

void setState(AlarmState next, const char *why) {
  if (next == state) return;
  Serial.printf("[alarm] %s → %s (%s)\n", STATE_NAMES[state], STATE_NAMES[next], why);
  state = next;
  if (next == ST_ALARM) alarmSince = millis();
  stateDirty = true;
}

// ---------- Alarm engine (same rules as the Flutter app's AlarmEngine) ----------
void evaluate(float t, uint32_t now) {
  switch (state) {
    case ST_NORMAL:
      if (t >= setpoint) { aboveSince = now; setState(ST_PENDING, "above setpoint"); }
      break;
    case ST_PENDING:
      if (t < setpoint) setState(ST_NORMAL, "dropped below setpoint");
      break;
    case ST_ALARM:
    case ST_ACKED:
      if (t <= setpoint - hysteresis) setState(ST_NORMAL, "cooled down");
      break;
  }
  if (state == ST_PENDING && now - aboveSince >= delayS * 1000UL) setState(ST_ALARM, "above setpoint for the delay");
}

void acknowledge(const char *who) {
  if (state == ST_ALARM) setState(ST_ACKED, who);
  if (testUntil) { testUntil = 0; stateDirty = true; }
}

void startTest(const char *who) {
  if (state == ST_ALARM) return;   // already sounding
  Serial.printf("[test] siren test (%s)\n", who);
  testUntil = millis() + TEST_MS;
  stateDirty = true;
}

// ---------- Wi-Fi access point + UDP ----------
void onWifiEvent(arduino_event_id_t event, arduino_event_info_t) {
  if (event == ARDUINO_EVENT_WIFI_AP_STACONNECTED) Serial.println("[wifi] a device joined FC26-NET");
  if (event == ARDUINO_EVENT_WIFI_AP_STADISCONNECTED) Serial.println("[wifi] a device left FC26-NET");
}

void setupWifi() {
  WiFi.onEvent(onWifiEvent);
  WiFi.mode(WIFI_AP);
  // Hidden = 0, max 2 devices (Node 1 + a laptop for debugging).
  const bool ok = WiFi.softAP(fc26::WIFI_SSID, fc26::WIFI_PASS, fc26::WIFI_CHANNEL, 0, 2);
  WiFi.setTxPower(FC26_WIFI_TX_POWER);
  udp.begin(fc26::UDP_PORT);
  Serial.printf("[wifi] access point %s %s on channel %u, IP %s, UDP port %u\n", fc26::WIFI_SSID,
                ok ? "up" : "FAILED", fc26::WIFI_CHANNEL, WiFi.softAPIP().toString().c_str(), fc26::UDP_PORT);
}

// Reads every waiting packet; returns true with the newest valid one in `out`.
bool receivePacket(fc26::TempPacket &out) {
  bool got = false;
  uint8_t buf[32];
  for (int size = udp.parsePacket(); size > 0; size = udp.parsePacket()) {
    const int len = udp.read(buf, sizeof(buf));
    const auto *p = (const fc26::TempPacket *)buf;
    if (len != (int)sizeof(fc26::TempPacket) || memcmp(p->magic, "FC26", 4) || p->version != fc26::VERSION ||
        p->networkId != fc26::NETWORK_ID) {
      if (rxRejected++ % 10 == 0) Serial.printf("[wifi] rejected a %d-byte packet (not FC26 v%u, network %u)\n",
                                                len, fc26::VERSION, fc26::NETWORK_ID);
      continue;
    }
    memcpy(&out, buf, sizeof(out));
    rxOk++;
    got = true;
  }
  return got;
}

void handleSensor() {
  fc26::TempPacket p = {};
  const bool fresh = receivePacket(p);

  const uint32_t now = millis();
  if (fresh) {
    lastPacketAt = now;
    if (!sensorOnline) Serial.println("[sensor] Node 1 online");
    sensorOnline = true;
    sensorFault = p.fault;
    centiC = p.centiC;
    stateDirty = true;
    if (p.centiC != fc26::NO_READING) evaluate(p.centiC / 100.0f, now);
  }
  const bool lost = sensorOnline && now - lastPacketAt > SENSOR_TIMEOUT_MS;
  const bool noData = lost || (fresh && p.centiC == fc26::NO_READING);
  if (lost) {
    sensorOnline = false;
    centiC = fc26::NO_READING;
    Serial.println("[sensor] Node 1 lost");
  }
  // No trustworthy temperature: stand down. (A real plant might sound the alarm instead.)
  if (noData) setState(ST_NORMAL, lost ? "sensor lost" : "sensor fault");
}

void logLinkStats() {
  static uint32_t last = 0;
  if (millis() - last < 10000) return;
  last = millis();
  Serial.printf("[wifi] %u device(s) on FC26-NET, %lu packets from Node 1, %lu rejected, sensor %s\n",
                WiFi.softAPgetStationNum(), (unsigned long)rxOk, (unsigned long)rxRejected,
                sensorOnline ? "online" : "waiting");
}

void handleMaxOn() {
  if (state == ST_ALARM && MAX_ON_MS && millis() - alarmSince >= MAX_ON_MS) setState(ST_ACKED, "max on-time reached");
}

// ---------- TTP223 ----------
void handleTouch() {
  static bool stable = false, last = false, testFired = false;
  static uint32_t changedAt = 0, pressedAt = 0;
  const bool raw = digitalRead(PIN_TOUCH) == HIGH;
  if (raw != last) { last = raw; changedAt = millis(); }
  if (millis() - changedAt < DEBOUNCE_MS || raw == stable) {
    if (stable && !testFired && millis() - pressedAt >= HOLD_FOR_TEST_MS && (state == ST_NORMAL || state == ST_PENDING)) {
      testFired = true;
      startTest("touch hold");
    }
    return;
  }
  stable = raw;
  if (stable) {                       // pressed
    pressedAt = millis();
    testFired = false;
    if (state == ST_ALARM || testUntil) { acknowledge("touch"); testFired = true; }
  }
}

// ---------- BLE ----------
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *) override { bleConnected = true; }
  void onDisconnect(BLEServer *) override {
    bleConnected = false;
    BLEDevice::startAdvertising();
  }
};

class CommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) override {
    String v = c->getValue();
    portENTER_CRITICAL(&mux);
    strlcpy(pendingCmd, v.c_str(), sizeof(pendingCmd));
    portEXIT_CRITICAL(&mux);
  }
};

void setupBle() {
  BLEDevice::init("FC26-SIREN");
  BLEServer *server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());
  BLEService *svc = server->createService(FC26_SIREN_SERVICE);
  stateChr = svc->createCharacteristic(
      FC26_SIREN_STATE, BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  BLECharacteristic *cmd = svc->createCharacteristic(
      FC26_SIREN_COMMAND, BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  cmd->setCallbacks(new CommandCallbacks());
  svc->start();
  BLEAdvertising *adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(FC26_SIREN_SERVICE);
  adv->setScanResponse(true);
  BLEDevice::startAdvertising();
}

void saveConfig() {
  prefs.putFloat("sp", setpoint);
  prefs.putFloat("hy", hysteresis);
  prefs.putUChar("dl", delayS);
}

void handleCommand() {
  char cmd[sizeof(pendingCmd)];
  portENTER_CRITICAL(&mux);
  strlcpy(cmd, pendingCmd, sizeof(cmd));
  pendingCmd[0] = 0;
  portEXIT_CRITICAL(&mux);
  if (!cmd[0]) return;
  Serial.printf("[ble] command '%s'\n", cmd);

  if (!strcmp(cmd, "ACK") || !strcmp(cmd, "STOP")) {
    acknowledge("ble");
  } else if (!strcmp(cmd, "TEST")) {
    startTest("ble");
  } else if (!strncmp(cmd, "CFG=", 4)) {   // CFG=<setpoint>,<hysteresis>,<delay s>
    float sp, hy;
    int dl;
    if (sscanf(cmd + 4, "%f,%f,%d", &sp, &hy, &dl) == 3 && sp >= 0 && sp <= 150 && hy >= 0.1f && hy <= 20 &&
        dl >= 0 && dl <= 60) {
      setpoint = sp;
      hysteresis = hy;
      delayS = (uint8_t)dl;
      saveConfig();
      Serial.printf("[cfg] setpoint %.2f, hysteresis %.2f, delay %u s\n", setpoint, hysteresis, delayS);
      // Re-check against the new limits on the next reading.
      if (state == ST_PENDING) setState(ST_NORMAL, "config changed");
    } else {
      Serial.println("[cfg] rejected: out of range");
    }
  } else {
    Serial.println("[ble] unknown command");
  }
  stateDirty = true;
}

// State packet, 10 bytes little-endian (see README):
// int16 centi-°C | uint8 state | uint8 flags | int16 centi setpoint | uint16 centi hysteresis | uint8 delay s | uint8 seq
void notifyState() {
  static uint32_t lastNotify = 0;
  static uint8_t seq = 0;
  if (!stateDirty && millis() - lastNotify < NOTIFY_EVERY_MS) return;
  lastNotify = millis();
  stateDirty = false;

  const uint8_t flags = (relayOn ? 1 : 0) | (sensorOnline ? 2 : 0) | (testUntil ? 4 : 0) |
                        (sensorFault != fc26::FAULT_NONE ? 8 : 0);
  const int16_t sp = (int16_t)lroundf(setpoint * 100);
  const uint16_t hy = (uint16_t)lroundf(hysteresis * 100);
  uint8_t b[10];
  memcpy(b, &centiC, 2);
  b[2] = state;
  b[3] = flags;
  memcpy(b + 4, &sp, 2);
  memcpy(b + 6, &hy, 2);
  b[8] = delayS;
  b[9] = seq++;
  stateChr->setValue(b, sizeof(b));
  if (bleConnected) stateChr->notify();
}

void updateLed() {
  const uint32_t t = millis();
  if (relayOn)                led((t / 100) % 2 ? 255 : 0, 0, 0);    // siren: fast red
  else if (state == ST_ACKED)    led(255, 0, 0);                          // silenced, still hot: solid red
  else if (state == ST_PENDING)  led((t / 400) % 2 ? 255 : 0, 0, 0);     // rising: slow red
  else if (!sensorOnline || centiC == fc26::NO_READING)
                              led(0, 0, (t / 500) % 2 ? 255 : 0);     // waiting for Node 1: slow blue
  else                        led(0, 255, 0);                          // all good: green
}

// ---------- Arduino ----------
void setup() {
  // Relay OFF before anything else.
  digitalWrite(PIN_RELAY, LOW);
  pinMode(PIN_RELAY, OUTPUT);
  digitalWrite(PIN_RELAY, LOW);

  Serial.begin(115200);
  pinMode(PIN_TOUCH, INPUT);
  pinMode(PIN_LED_R, OUTPUT);
  pinMode(PIN_LED_G, OUTPUT);
  pinMode(PIN_LED_B, OUTPUT);
  led(255, 0, 0); delay(250);
  led(0, 255, 0); delay(250);
  led(0, 0, 255); delay(250);
  led(0, 0, 0);

  prefs.begin("fc26n2");
  setpoint = prefs.getFloat("sp", DEFAULT_SETPOINT);
  hysteresis = prefs.getFloat("hy", DEFAULT_HYSTERESIS);
  delayS = prefs.getUChar("dl", DEFAULT_DELAY_S);
  Serial.printf("\nNode 2 (siren) starting. Relay OFF. Setpoint %.2f °C, hysteresis %.2f, delay %u s\n",
                setpoint, hysteresis, delayS);

  setupWifi();
  setupBle();
}

void loop() {
  handleSensor();
  logLinkStats();
  handleCommand();
  handleTouch();
  handleMaxOn();
  if (testUntil && millis() >= testUntil) { testUntil = 0; stateDirty = true; }
  applyRelay();
  notifyState();
  updateLed();
}
