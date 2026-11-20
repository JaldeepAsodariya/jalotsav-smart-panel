# PICO-PI-IMX7: wipe Android Things, install Linux, run Flutter

> **Dropped on 15 Nov 2026.** This board is too risky for FlutterCon India: it has no GPU, Flutter can only run with software rendering, and nobody has proven that works. The demo runs on a Raspberry Pi instead. This guide is kept for reference and for the "why not Android Things hardware" part of the talk.
>
> **Current design:** two ESP32-C3 nodes (Node 1 reads the PT100, Node 2 drives the hooter). Node 2 hosts a Wi-Fi network (`FC26-NET`) and Node 1 sends it the temperature as UDP packets. The Flutter app, [Jalotsav Panel](../Application/jalotsav_panel/README.md), talks to both nodes over Bluetooth LE. The main display is a Raspberry Pi touchscreen running the app through flutter-pi, with a phone as the backup. See [`Application/esp32`](../Application/esp32/README.md).

**Goal:** a Flutter hello-world on the 7" screen that responds to touch.
If that works, it's a go. If it doesn't, use a fallback (see the end of this guide).

> ⚠️ Items marked **[verify]** weren't confirmed from documentation. Check them against the board or the files before relying on them.

---

## 0. What you need

| Item | Why |
|---|---|
| **A Windows laptop** (or any x86-64 Linux PC) | For flashing with NXP's `uuu` tool. Its Linux and Windows builds are reliable. On an Apple Silicon Mac it's known to fail ("Failure Claim Interface"), so don't use the MacBook for this step. |
| USB-C **data** cable | Board ↔ PC (the OTG port, which also powers the board) |
| Micro-USB cable | Serial console (the board has a built-in USB-to-serial chip), 115200 baud |
| Mac | Backup (step 1), building the Flutter app, SSH |

---

## 1. Back up the Android Things eMMC (optional, ~20 min)

Google has shut Android Things down, so once you wipe the board **you can't reinstall your old demo**. A backup lets you restore it later.

1. Connect micro-USB to the Mac. Open the console:
   ```bash
   ls /dev/cu.usbserial*      # find the port [verify name]
   screen /dev/cu.usbserial-XXXX 115200
   ```
2. Power on the board. When the log shows `Hit any key to stop autoboot`, press a key to get the `=>` prompt.
3. Expose the eMMC as a USB disk: `=> ums 0 mmc 0`
   *(The Android Things U-Boot may not include `ums`. If it says "Unknown command", skip the backup.)*
4. With USB-C also connected to the Mac:
   ```bash
   diskutil list                       # find the ~3.8 GB disk, e.g. /dev/disk4
   diskutil unmountDisk /dev/disk4
   sudo dd if=/dev/rdisk4 of=~/androidthings-imx7d-backup.img bs=1m status=progress
   ```
5. In `screen`, press Ctrl-C, then type `reset`.

---

## 2. Download (on the Windows laptop)

- **uuu tool + bootloader:** `imx-mfg-uuu-tool_20261022.zip` from
  https://download.technexion.com/development_resources/development_tools/installer/
- **OS image (recommended: Ubuntu, since `apt` makes installing flutter-pi's dependencies easy):**
  `pico-imx7_pico-pi_ubuntu-22.04_qca9377_lcd-800x480_20240426.zip` from
  https://download.technexion.com/demo_software/PICO/IMX7/pico-imx7-emmc/DiskImage/
  - Alternative: `pico-imx7_pico-pi_yocto-6.0-qt6_qca9377_lcd-800x480_20261015.zip` (newer, but no `apt`)
  - "lcd-800x480" is the only display option. Check that your 7" panel is 800×480 **[verify]**.
  - Wi-Fi: if your board has the AP6335 chip instead of QCA9377, use the images in the `archived/` folder **[verify]**.

Unzip both. The image inside is a `.wic`/`.sdcard`/`.bz2` file, and uuu can read `.bz2` directly.

---

## 3. Flash (this wipes Android Things)

1. **Power off** the board. Set the 4 boot jumpers to **Serial Download Mode**.
   The jumper diagram is on page 18 of the NXP user guide: https://www.nxp.com/docs/en/user-guide/PICO-IMX7D-USG.pdf **[verify positions]**
2. Connect USB-C to the Windows laptop. Open **Command Prompt as Administrator** in the unzipped uuu folder.
3. Check that the board is detected:
   ```bat
   uuu\windows64\uuu.exe -lsusb
   ```
4. Flash (adjust paths to match the zip layout **[verify]**):
   ```bat
   uuu\windows64\uuu.exe -b emmc_imx7_img imx7\pico-imx7\imx7-SPL imx7\pico-imx7\imx7-u-boot.img C:\path\to\<image>.wic.bz2
   ```
   If `emmc_imx7_img` isn't found, use `multiboard\emmc_imx7_img.auto` in its place.
5. Wait for "Done". Power off and set the jumpers back to **eMMC boot**. Power on.

---

## 4. First boot checks (decides go/no-go)

Log in over the serial console or the touchscreen, then:

```bash
uname -m                 # expect armv7l (32-bit ARM)
free -h                  # RAM (512 MB or 1 GB SOM)
ls /dev/dri              # need card0 here, or flutter-pi can't draw
ls /dev/input            # touch device
sudo apt update && sudo apt install -y evtest
sudo evtest              # tap the screen → events should print
```

| Result | Meaning |
|---|---|
| `/dev/dri/card0` exists and touch prints events | ✅ Continue to step 5 |
| No `/dev/dri` | ❌ The display driver isn't DRM. flutter-pi can't run. Stop here. |
| Touch shows no events | ⚠️ Fixable, but it costs time (check the touch driver and its device tree). |

Connect the board to any Wi-Fi network and enable SSH so the rest can be done from the Mac.

---

## 5. Install flutter-pi on the board

The i.MX7D has **no 3D GPU**, so we rely on Mesa's software renderer (kms_swrast + llvmpipe). That's the experimental part.

```bash
sudo apt install -y cmake build-essential git pkg-config \
  libgl1-mesa-dev libgles2-mesa-dev libegl1-mesa-dev libdrm-dev libgbm-dev \
  libgl1-mesa-dri mesa-utils fontconfig libsystemd-dev libinput-dev libudev-dev libxkbcommon-dev
git clone https://github.com/ardera/flutter-pi && cd flutter-pi
mkdir build && cd build && cmake .. && make -j2 && sudo make install
```

---

## 6. Build hello-world on the Mac and run it

```bash
flutter pub global activate flutterpi_tool
flutter create hello_imx && cd hello_imx
flutterpi_tool build --help               # confirm the 32-bit ARM flags [verify]
flutterpi_tool build --arch=arm --cpu=generic --release
rsync -a build/flutter_assets/ <user>@<board-ip>:~/hello_imx/
```

On the board (from the console, not a desktop session):

```bash
MESA_LOADER_DRIVER_OVERRIDE=kms_swrast flutter-pi --release ~/hello_imx
```

---

## 7. Go / no-go

- ✅ **Go** if the counter app opens fullscreen, a tap increments the count, and the screen updates within about ½ s.
- ❌ **No-go** if flutter-pi errors out, it's below ~5 fps, or the board runs out of memory.

**Fallback options if it's a no-go:**
1. **Use a Raspberry Pi 4** with a touchscreen and flutter-pi (the option chosen).
2. Run Flutter Embedded (`flutter-elinux`) on an Ubuntu x86 laptop.
3. Keep the i.MX7D on stage as the honest "why this board couldn't do it" part of the talk.

Either way, the ESP32 nodes and the Flutter app don't change.
