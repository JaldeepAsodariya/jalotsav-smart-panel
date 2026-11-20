# ESP32-C3 sensor nodes (BLE + Wi-Fi)

| Folder | Board + parts | Does |
|---|---|---|
| [`node1_temperature/`](node1_temperature/node1_temperature.ino) | ESP32-C3 Super Mini + ADS1115 + PT100 | measures °C once a second, sends it to Node 2 |
| [`node2_siren/`](node2_siren/node2_siren.ino) | ESP32-C3 Super Mini + 5V relay (2N2222, 1N4007) + TTP223 + common-anode RGB LED + 220V hooter | hosts the `FC26-NET` Wi-Fi, decides the alarm, drives the hooter |

- **[build-guide.html](build-guide.html)**: everything on one page (wiring, setup, tests, BLE contract, full firmware with download buttons). Start here.
- **[wiring.html](wiring.html)**: circuit diagrams, pin-to-pin tables, buy list and the 220V safety notes. Open it in any browser. [WIRING.md](WIRING.md) is the plain-text version.
- **[ble-test.html](ble-test.html)**: test both boards from a browser over Bluetooth, no app needed (section 4).

## How it works

```
 Node 1 (PT100) ──Wi-Fi FC26-NET, UDP 1×/s──▶ Node 2 (siren, access point): decides the alarm, drives the hooter
      │                                   │
      │ BLE: temperature                  │ BLE: alarm state, Acknowledge, Test, limits
      ▼                                   ▼
   Display: Jalotsav Panel (Flutter) on a phone / tablet / Mac
            (or ble-test.html in Chrome)
```

- **Node 2 makes its own Wi-Fi network, no router needed.** Node 2 is a Wi-Fi access point called **`FC26-NET`** (password `fc26-panel`, channel 1, address `192.168.4.1`). Node 1 joins it and sends one 10-byte UDP packet a second to port 4626. If Node 2 reboots, Node 1 rejoins by itself within about 15 s. Node 2 only accepts packets that start with `FC26` and carry the same `NETWORK_ID`. Both boards log the link to Serial every 10 s (`[wifi] … sent N ok` / `… N packets from Node 1`).
- **Wi-Fi power is turned down to 8.5 dBm** (`FC26_WIFI_TX_POWER` in `fc26_protocol.h`). ESP32-C3 Super Mini antennas are poorly matched: at full power their Wi-Fi often doesn't get out at all. Don't raise it.
- **Node 2 is the brain.** The alarm works with no phone, laptop or app in the room:
  - temperature ≥ **setpoint** for **delay** seconds → **ALARM**, hooter ON
  - touch the **TTP223** → **ACKNOWLEDGED**, hooter OFF (it stays off until the temperature drops)
  - temperature ≤ setpoint − **hysteresis** → back to **NORMAL** automatically
  - hold the TTP223 for 2 s while normal → 2-second hooter test
  - Node 1 silent for 6 s, or reporting a probe fault → hooter OFF, LED blinks blue
  - hooter ON for 2 minutes → silences itself (counts as acknowledged)
- **BLE is for watching and settings.** The display app connects to **both** nodes: Node 1 (`FC26-TEMP`) for the temperature, and Node 2 (`FC26-SIREN`) to read the alarm state, acknowledge, test the hooter, and change setpoint/hysteresis/delay. Node 2 saves the limits in flash. The alarm itself runs on Node 2 from Node 1's Wi-Fi readings, so it works with the display off. Each board takes **one** BLE connection: close the app before using the test page, and the other way round.

Defaults: setpoint **35 °C**, hysteresis **2 °C** (clears at 33 °C), delay **3 s**.

## The display: Jalotsav Panel

One Flutter app, **Jalotsav Panel** ([`../jalotsav_panel`](../jalotsav_panel/README.md), ID `com.jalotsav.smartpanel`), is the display:

- **Main display: Raspberry Pi with a touchscreen**, running the app through flutter-pi.
- **Backup display: a phone or tablet** (Android, iOS) or a Mac, running the same app. Same screens, same Bluetooth links.

What it does:

- **Connects to both nodes by itself:** `FC26-TEMP` for the temperature (the main source) and `FC26-SIREN` for the alarm, the hooter and the limits. No pairing. The two dots in the top bar turn green when each board is linked.
- **Live:** temperature gauge, alarm state, siren card with **Acknowledge** and **Test siren**, last 60 s chart. **Trend** and **Alarms** show history.
- **Settings:** setpoint, hysteresis and delay (saved on Node 2), **PT100 calibration** (set the real temperature with ± buttons, tap Calibrate; saved on Node 1), and light/dark theme.
- **Backup siren on the display:** if Node 2 isn't linked, the app applies the same alarm rules to Node 1's readings and **sounds an alarm itself** (Android alarm volume). Acknowledge silences it; it stops when the probe cools or when Node 2 links and takes over. Limits changed while Node 2 is offline aren't saved.
- **One display at a time:** each board takes one Bluetooth connection, so close the app on one device (or the test page) before connecting another.

## 1. Arduino IDE setup (once)

1. **Boards Manager** → install **"esp32" by Espressif Systems** (3.x).
2. **Library Manager** → install **"Adafruit ADS1X15"** (Node 1 only; accept its dependency Adafruit BusIO). Node 2 needs no extra libraries.
3. **Tools** menu, for both boards:
   - Board: **ESP32C3 Dev Module**
   - **USB CDC On Boot: Enabled**. Without this you get nothing in Serial Monitor.
   - **Partition Scheme: Huge APP (3MB No OTA/1MB SPIFFS)**. BLE + Wi-Fi is ~1.27 MB, right at the edge of the default 1.2 MB partition.
4. If an upload won't start: **hold BOOT, tap RESET, release BOOT**, then upload again.

**Built with** esp32 core **3.3.12** (BLE runs on its NimBLE backend) and Adafruit ADS1X15 **2.6.2**, for `esp32:esp32:esp32c3` with the two options above, no warnings. **Tested on hardware:** Node 1 (PT100, ADS1115, BLE to the app, calibration from the app) and the app's backup siren. Node 2 is compile-tested; its hardware is in progress.

> ⚠️ **Flash with USB only, with mains unplugged.** Never have USB and the Hi-Link connected at the same time.

## 2. Before the first power-up

- **Node 1:** measure your reference resistor with a multimeter and put the value in `RREF` at the top of the sketch (e.g. `987.0`).
- **Node 2:** if the hooter clicks at the wrong time, check the 2N2222 leg order (wiring.html explains how).
- Two kits in one room? Give each kit its own `NETWORK_ID` in **both** copies of `fc26_protocol.h`. The two copies must stay identical: `diff */fc26_protocol.h` prints nothing when they match.

## 3. First test with Serial Monitor (115200 baud)

1. Flash Node 2 first. Serial shows `[wifi] access point FC26-NET up on channel 1, IP 192.168.4.1`. Its LED blinks blue until Node 1 joins.
2. Flash Node 1. Serial shows `[wifi] joined FC26-NET, IP 192.168.4.2`, then `[temp] 27.84 °C (110.85 Ω, offset +0.00)` every second and `[wifi] linked, sent N ok, 0 failed` every 10 s. Hold the probe: it rises.
3. Node 2's LED turns green and its Serial shows `[sensor] Node 1 online`, then every 10 s `[wifi] 1 device(s) on FC26-NET, N packets from Node 1`.
4. Bench-test the relay with a **bulb**, not the hooter: hold the TTP223 for 2 s and the bulb comes on for 2 s.
5. Run the full flow with the default 35 °C setpoint: warm the probe, wait 3 s → bulb on; touch the TTP223 → off; let it cool below 33 °C → back to green. If Node 2 kept an older saved setpoint, set 35 °C in the app's Settings.

## 4. Test from a browser (no app): `ble-test.html`

Close the display app first (one connection per board). Web Bluetooth works in **Chrome or Edge** (Mac, Windows, Android, ChromeOS); not Safari or Firefox. It must be opened from `localhost`:

```bash
cd esp32
```

```bash
python3 -m http.server 8766
```

Then open **http://localhost:8766/ble-test.html** in Chrome:

- **Connect** on the Node 2 card → pick `FC26-SIREN`. You see live temperature, alarm state, hooter and Node 1 link. Use **Acknowledge**, **Test siren** and **Save to Node 2** for the limits.
- **Connect** on the Node 1 card → pick `FC26-TEMP`. Shows probe resistance and faults. **Calibrate**: type the reading of a trusted thermometer next to the probe and press Calibrate. Node 1 stores the offset.
- **Simulate** on either card runs a fake node in the page, handy to see the flow before the hardware is ready.

Both cards can be connected at the same time. With the default 35 °C setpoint, warming the probe in your hand runs the whole alarm flow at your desk.

On a phone you can also use **nRF Connect** to see the raw characteristics.

## 5. BLE contract (for the display app)

All numbers are **little-endian**. Temperatures are **°C × 100** as int16; `-32768` means no reading. UUIDs share the suffix `-6a1b-4d2e-9f3c-8b5e7a0c1d2f`.

**Node 2 `FC26-SIREN`**, service `fc260200-…`

| Characteristic | Access | Content |
|---|---|---|
| `fc260201-…` state | read, notify (1×/s and on every change) | 10 bytes: `int16 temp` · `uint8 state` (0 normal, 1 pending, 2 alarm, 3 acknowledged) · `uint8 flags` (bit0 hooter on, bit1 Node 1 online, bit2 test running, bit3 probe fault) · `int16 setpoint` · `uint16 hysteresis` (× 100) · `uint8 delay s` · `uint8 seq` |
| `fc260202-…` command | write (text) | `ACK` · `TEST` · `STOP` · `CFG=<setpoint>,<hysteresis>,<delay>` e.g. `CFG=35,2,3` (limits 0–150 °C, 0.1–20 °C, 0–60 s) |

**Node 1 `FC26-TEMP`**, service `fc260100-…`

| Characteristic | Access | Content |
|---|---|---|
| `fc260101-…` reading | read, notify (1×/s) | 8 bytes: `int16 temp` (offset applied) · `uint16 ohms × 100` · `uint8 fault` (0 ok, 1 ADS1115 missing, 2 open, 3 short, 4 out of range) · `uint8 seq` · `int16 offset × 100` |
| `fc260102-…` command | write (text) | `CAL=<real °C>` · `OFS=<offset °C>` (±10) |

**Wi-Fi packet** (Node 1 → UDP `192.168.4.1:4626` on `FC26-NET`): 10 bytes, `"FC26"` · `uint8 version` · `uint8 network id` · `uint8 seq` · `uint8 fault` · `int16 temp`.

## 6. Tunable settings (top of each sketch)

| Setting | Default | Change when |
|---|---|---|
| `RREF` (Node 1) | `980.0` | always: set it to your resistor's measured value |
| `WIRES` (Node 1) | `2` | 3-wire probe (`3`; lead compensation via A2) |
| `DEFAULT_SETPOINT` / `_HYSTERESIS` / `_DELAY_S` (Node 2) | 35 / 2 / 3 | first-boot values; after that the app or test page sets them |
| `SENSOR_TIMEOUT_MS` (Node 2) | 6 s | how quickly a silent Node 1 counts as lost |
| `MAX_ON_MS` (Node 2) | 2 min | hooter self-silence limit (`0` = never) |
| `LED_R_MAX` (Node 2) | 60 | red too dim or too bright compared with green and blue |
| `NETWORK_ID`, `WIFI_SSID` (`fc26_protocol.h`) | 26, `FC26-NET` | two kits in the same room |

## LED meanings

| LED | Node 1 | Node 2 |
|---|---|---|
| R → G → B at power-up | (no LED: watch Serial) | self-test |
| green | | solid: normal |
| blue | | slow blink: no data from Node 1 (not on `FC26-NET` yet) |
| red | | slow blink: above setpoint · fast: hooter ON · solid: acknowledged |
