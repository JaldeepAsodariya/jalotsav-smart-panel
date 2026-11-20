# From Android Things to Flutter: a smart temperature panel

Code, hardware guides and research for the FlutterCon India 2026 talk *"From Android Things to Flutter: Building a Smart Home App on Raspberry Pi"*.

A PT100 probe measures temperature. When it stays too hot, a 220V hooter sounds. A Flutter app, **Jalotsav Panel**, shows everything live and lets you acknowledge the alarm, test the hooter, change the limits and calibrate the probe.

```
 PT100 → Node 1 (ESP32-C3 + ADS1115) ──Wi-Fi "FC26-NET", UDP──▶ Node 2 (ESP32-C3 + relay + hooter)
              │                                                       │
              └──────────── Bluetooth LE ──────────┬──────────────────┘
                                                   ▼
                              Jalotsav Panel (Flutter)
                 Raspberry Pi touchscreen (main) · phone, tablet or Mac (backup)
```

- **Node 2 decides the alarm**, so the demo works even with the app closed.
- **The app** reads the temperature from Node 1 and the alarm state from Node 2. If Node 2 is offline, the phone sounds the alarm itself.

## What's here

| Folder | What it is |
|---|---|
| [`Application/esp32`](Application/esp32/README.md) | Firmware for both nodes (Arduino, ESP32-C3), wiring, a step-by-step build guide, and a Web Bluetooth test page |
| [`Application/jalotsav_panel`](Application/jalotsav_panel/README.md) | The Flutter app (Android, iOS, macOS) with a hardware simulator and tests |
| [`Application/tools`](Application/tools/build_guide.py) | Generates `esp32/build-guide.html` from the wiring page and the firmware |
| [`Research`](Research/imx7d-setup.md) | Notes on running Flutter on the NXP Pico i.MX7D (the old Android Things board), and why it was dropped |
| `Presentation/assets/screens` | App screenshots |

## Quick start

1. **Build the hardware:** open `Application/esp32/build-guide.html` in a browser. It has the wiring, Arduino setup, first tests and the full firmware.
2. **Run the app without hardware:**
   ```bash
   cd Application/jalotsav_panel
   flutter run -d macos --dart-define=SIMULATOR=true
   ```
3. **Run the tests:**
   ```bash
   cd Application/jalotsav_panel
   flutter test
   ```

## ⚠️ Mains safety

Both nodes run from 220V through Hi-Link modules, and Node 2 switches a 220V hooter. Read the 220V section of [`Application/esp32/WIRING.md`](Application/esp32/WIRING.md) before wiring anything. Fuse the live wire, keep everything at mains voltage inside a closed box, and never connect USB while a board is on mains. Build and use this at your own risk.

## License

[MIT](LICENSE). Third-party packages keep their own licences (for example [universal_ble](https://pub.dev/packages/universal_ble), BSD-3).
