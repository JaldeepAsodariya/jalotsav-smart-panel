// FlutterCon India 2026: the contract shared by both nodes, the test page and the app.
// Keep this file IDENTICAL in node1_temperature/ and node2_siren/ (Arduino can't share
// a header between sketch folders). Check with: diff */fc26_protocol.h
#pragma once
#include <stdint.h>

namespace fc26 {

// ---------- Wi-Fi (node 1 → node 2, no router: Node 2 is the access point) ----------
// Node 2 creates the FC26-NET network; Node 1 joins it and sends one UDP packet a second to
// Node 2's address. If two of these kits are in the same room, give each kit its own SSID
// and NETWORK_ID. The password only keeps strangers' phones off the network.
constexpr char     WIFI_SSID[]  = "FC26-NET";
constexpr char     WIFI_PASS[]  = "fc26-panel";   // WPA2 needs at least 8 characters
constexpr uint8_t  WIFI_CHANNEL = 1;
constexpr uint8_t  NODE2_IP[4]  = {192, 168, 4, 1};   // ESP32 access point default address
constexpr uint16_t UDP_PORT     = 4626;
// ESP32-C3 Super Mini boards have a poorly matched antenna: at full power (19.5 dBm) their
// Wi-Fi often doesn't get out at all. 8.5 dBm is the usual fix and plenty for a table-top demo.
#define FC26_WIFI_TX_POWER WIFI_POWER_8_5dBm
constexpr uint8_t  NETWORK_ID   = 26;
constexpr uint8_t  VERSION      = 1;
constexpr int16_t  NO_READING   = INT16_MIN;   // centi-°C value meaning "no valid reading"

enum Fault : uint8_t {
  FAULT_NONE        = 0,
  FAULT_ADC_MISSING = 1,   // ADS1115 not answering on I2C
  FAULT_OPEN        = 2,   // probe or a wire disconnected
  FAULT_SHORT       = 3,   // probe wires touching
  FAULT_RANGE       = 4,   // resistance outside -200…850 °C
};

struct __attribute__((packed)) TempPacket {   // 10 bytes, one UDP packet a second
  char     magic[4];    // "FC26"
  uint8_t  version;     // VERSION
  uint8_t  networkId;   // NETWORK_ID
  uint8_t  seq;         // increments every packet
  uint8_t  fault;       // Fault
  int16_t  centiC;      // °C × 100, or NO_READING
};

// ---------- BLE (nodes ↔ test page / Flutter app). UUIDs must be lowercase. ----------
// Node 1 "FC26-TEMP"
#define FC26_TEMP_SERVICE   "fc260100-6a1b-4d2e-9f3c-8b5e7a0c1d2f"
#define FC26_TEMP_READING   "fc260101-6a1b-4d2e-9f3c-8b5e7a0c1d2f"  // read+notify, 8 bytes, see README
#define FC26_TEMP_COMMAND   "fc260102-6a1b-4d2e-9f3c-8b5e7a0c1d2f"  // write text: "OFS=-0.5", "CAL=25.0"
// Node 2 "FC26-SIREN"
#define FC26_SIREN_SERVICE  "fc260200-6a1b-4d2e-9f3c-8b5e7a0c1d2f"
#define FC26_SIREN_STATE    "fc260201-6a1b-4d2e-9f3c-8b5e7a0c1d2f"  // read+notify, 10 bytes, see README
#define FC26_SIREN_COMMAND  "fc260202-6a1b-4d2e-9f3c-8b5e7a0c1d2f"  // write text: "ACK", "TEST", "STOP", "CFG=35,2,3"

}  // namespace fc26
