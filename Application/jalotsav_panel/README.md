# Jalotsav Panel

Flutter touch panel for the FlutterCon India 2026 demo. It shows the PT100 temperature, the alarm state and the hooter, all over **Bluetooth LE**: the temperature from **Node 1** (`FC26-TEMP`), the alarm and the hooter from **Node 2** (`FC26-SIREN`). It runs on Android, iOS and macOS.

**Architecture:** the **siren node (ESP32 Node 2) decides the alarm**, so the demo still works with the app closed. The app mirrors what the node reports, and sends Acknowledge, Test siren and new limits. Firmware, wiring and the BLE contract live in [`../esp32`](../esp32/README.md).

## Run it

```bash
flutter run -d macos                               # real nodes over BLE (opens a 1024×600 landscape window)
```

```bash
flutter run -d macos --dart-define=SIMULATOR=true  # no hardware: simulated nodes
```

```bash
flutter test                                       # alarm rules, BLE packet codec, controller, UI flow + layout
```

- **BLE:** power both nodes and start the app. It finds `FC26-TEMP` and `FC26-SIREN`, connects to both, and reconnects by itself: no pairing, no passwords. A red dot in the status bar means that board isn't linked. The first run on macOS asks for Bluetooth permission.
- **Phone/tablet:** the app locks to landscape and goes full screen (swipe from an edge to show the system bars). Android asks for **Nearby devices** on first run: allow it.
- **Phone alarm (Node 2 offline or blind):** while the siren node isn't linked, or is linked but gets no readings from Node 1 over Wi-Fi (its LED blinks blue), the phone applies the same alarm rules to Node 1's readings and plays a looping siren (`assets/sounds/siren.wav`) on the **alarm** volume. **Acknowledge** silences it, **Test siren** plays it for 2 s, and it stops by itself when the probe cools or when Node 2 is linked and hearing Node 1 again, and takes over. The siren card then reads **Phone alarm**.
- **PT100 calibration:** **Settings → PT100 calibration**. Put a reference thermometer next to the probe, set the real temperature with the ± buttons, and tap **Calibrate**. Node 1 stores offset = real − raw in its flash (limited to ±10 °C). **Reset offset** sets it back to 0. This needs the link to Node 1 (`FC26-TEMP`).
- **Simulator:** **Settings → Demo controls → Heat the probe**, then go back to **Live**.
- **Raspberry Pi:** the plan for the talk is a Raspberry Pi with a touchscreen as the main display, running this app through [flutter-pi](https://github.com/ardera/flutter-pi), with a phone as the backup. That build isn't in this repository yet (there is no `linux/` target), so Android, iOS and macOS are the tested platforms.

## Structure

```
lib/
  core/                       # pure Dart, no plugins
    models.dart               # readings, node status, alarm config/events, SirenSnapshot
    alarm_engine.dart         # setpoint + delay + hysteresis state machine (same rules as the firmware)
    siren_node_model.dart     # Dart twin of Node 2's firmware (uses alarm_engine): drives the simulator and the tests
    ble_protocol.dart         # BLE UUIDs, 10-byte state decoder, text commands
    link_merger.dart          # combines the two BLE links: Node 1 temperature first, Node 2's copy as fallback
    alarm_sound.dart          # interface for the phone's own siren (used when Node 2 isn't linked)
    device_gateway.dart       # interface to the hardware
    fake_device_gateway.dart  # simulator
    panel_controller.dart     # mirrors node state → UI, event log, sensor-lost watchdog, commands
  hardware/
    ble_device_gateway.dart   # universal_ble: scan → connect → subscribe → reconnect
    phone_siren.dart          # audioplayers: looping siren on the alarm volume
  ui/                         # theme, strings, shell, screens, custom-painted gauge and chart
```

## Choices made

- **BLE plugin: [universal_ble](https://pub.dev/packages/universal_ble)** (BSD-3). It covers Android, iOS and macOS with one API. (flutter_blue_plus 2.x now requires a paid licence for commercial use, so it is avoided in code people will copy from the talk.)
- **Two BLE links at once:** the temperature comes from **Node 1 (`FC26-TEMP`)**, the primary source. Alarm state, siren, limits and commands come from **Node 2 (`FC26-SIREN`)**. Each link reconnects on its own. Node 2 also relays Node 1's temperature (Node 1 sends it over Node 2's Wi-Fi network, `FC26-NET`), and the app shows that copy only while it has no link to Node 1 (`lib/core/link_merger.dart`).
- Each board takes one BLE connection, so close `ble-test.html` before you start the app.
- **Glass design, light and dark:** frosted translucent panes over a soft coloured backdrop (`lib/ui/widgets/glass.dart`, tokens in `lib/ui/theme.dart`). Switch with the sun/moon button in the status bar, or **Settings → Appearance** (System / Light / Dark). The choice is saved on the device.
- **Blur stays cheap:** all panes share one backdrop read (`BackdropGroup` + `BackdropFilter.grouped`) instead of one per pane.
- **Charts and the gauge are custom-painted**, with no chart package and no shadows.
- **Settings sliders are debounced** (400 ms) so dragging sends one `CFG=` write, not dozens.


## Alarm rules (enforced on Node 2)

| State | Enters when | Hooter |
|---|---|---|
| Normal | temp ≤ setpoint − hysteresis after an alarm (clears by itself); from Rising, as soon as temp drops below the setpoint | off |
| Rising (`PENDING` in the firmware and BLE) | temp ≥ setpoint, waiting for the alarm delay | off |
| Alarm | still ≥ setpoint after the delay | **on** |
| Acknowledged | Acknowledge in the app, the test page, or a touch on the TTP223 | off (stays on screen until it clears) |
| Sensor lost | no reading for 10 s (Node 2 also silences after 6 s without Node 1) | off |

If the hooter stays on for 2 minutes, Node 2 silences it by itself (`MAX_ON_MS`) and treats it as acknowledged.

Defaults: setpoint 35 °C (low enough for a warm hand), hysteresis 2 °C, delay 3 s. Changes from Settings are stored on Node 2.
