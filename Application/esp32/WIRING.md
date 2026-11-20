# Wiring: pin-to-pin

The drawn diagrams are in **[wiring.html](wiring.html)**. This file is the same information as text.

Both nodes use an **ESP32-C3 Super Mini**. GPIO 2, 8 and 9 are boot strapping pins and GPIO 18/19 are USB, so none of them are used. Every GND on a node is the same wire.

## Buy first (₹20)

| Part | For |
|---|---|
| 1 kΩ resistor, **1% or better** (0.1% ideal) | Node 1 reference resistor (Rref). Its tolerance becomes your error: 1% ≈ ±2.5 °C before calibration. |
| 1 kΩ resistor, any | Node 2 transistor base. Don't use 100 Ω here: it pulls ~26 mA from the pin, above the ESP32-C3's ~20 mA recommendation |
| 2 × inline fuse holder + 1 A fuse | mains live wire on each node |

---

## Node 1: ESP32-C3 + ADS1115 + PT100 (2- or 3-wire)

| From | To | Notes |
|---|---|---|
| Hi-Link **+Vo** | ESP32 **5V** | never connect USB while on mains |
| Hi-Link **−Vo** | ESP32 **GND** | |
| ESP32 **3V3** | ADS1115 **VDD**, ADS1115 **A0**, top of **Rref** | A0 measures the 3V3 rail (cancels supply drift) |
| ESP32 **GND** | ADS1115 **GND**, ADS1115 **ADDR** | ADDR → GND = I2C address 0x48 |
| ESP32 **GPIO5** | ADS1115 **SDA** | |
| ESP32 **GPIO6** | ADS1115 **SCL** | |
| bottom of **Rref** | ADS1115 **A1** + PT100 **lead A** | lead A / B = the two same-colour wires |
| PT100 **lead B** | ADS1115 **A2** | sense wire, no current. Used only with `WIRES = 3` (default is 2) |
| PT100 **lead C** (odd colour) | **GND** | |
| ADS1115 **A3**, **ALRT** | — | unconnected |

Node 1 has no LED: watch its Serial output (115200 baud).

```
 3V3 ──┬──────────── ADS A0
       │
      [Rref 1 kΩ]
       │
       ├──────────── ADS A1
       │
       └── lead A ──┐ (same colour)
                    ├─[ PT100 ]── lead C (odd colour) ── GND
 ADS A2 ── lead B ──┘ (same colour)
```

Check the probe with a multimeter first: same-colour pair ~0–2 Ω; same-colour ↔ odd-colour ~108–112 Ω at room temperature.

**How it measures:** the current through Rref is (A0 − A1) / Rref. Because no current flows in lead B, (2 × A2 − A1) is the voltage across the PT100 alone: the two lead resistances cancel. This needs `WIRES = 3` at the top of `node1_temperature.ino`; the default `WIRES = 2` uses A1 only and ignores A2.

---

## Node 2: ESP32-C3 + 5V relay + 2N2222 + 1N4007 + TTP223 + common-anode RGB LED + hooter

| From | To | Notes |
|---|---|---|
| Hi-Link **+Vo** | ESP32 **5V** and relay **coil +** | coil ≈ 70–90 mA |
| Hi-Link **−Vo** | ESP32 **GND** | |
| ESP32 **GPIO10** | **1 kΩ** → 2N2222 **base** | HIGH = relay on |
| 2N2222 **emitter** | **GND** | |
| 2N2222 **collector** | relay **coil −** | |
| 1N4007 **stripe** | relay **coil +** | diode across the coil, reverse-biased |
| 1N4007 **anode** | relay **coil −** | backwards = short circuit on 5V |
| TTP223 **VCC / GND** | ESP32 **3V3 / GND** | |
| TTP223 **I/O** | ESP32 **GPIO5** | pads A and B open (momentary, active-HIGH) |
| ESP32 **GPIO4 / GPIO3 / GPIO1** | LED **R / G / B** | the firmware pulls a leg LOW to light it |
| LED **common anode** (longest leg) | **100 Ω** → **3V3** | use a common-anode LED; a common-cathode one shows inverted colours |

```
            5V ──┬───────────┐
                 │           │
              [coil]     1N4007 (stripe up)
                 │           │
                 ├───────────┘
                 │ C
 GPIO10 ─[1 kΩ]─B  2N2222
                 │ E
                GND
```

**2N2222 legs:** PN2222A is usually **E-B-C** (flat face toward you, legs down) but P2N2222A is **C-B-E**. Find the base with a multimeter's diode mode: red probe on the base reads ~0.6 V to both other legs.

**Bare relay:** coil = the two pins that read ~70 Ω. The other three are COM, NO, NC. The contacts must be rated for at least 250 VAC and more than the hooter's current.

### ⚠️ 220V side

Node 1:

```
 Mains L ──[1 A fuse]──▶ Hi-Link AC L
 Mains N ──────────────▶ Hi-Link AC N
```

Node 2:

```
 Mains L ──[1 A fuse]──┬──▶ relay COM ── NO ──▶ hooter ──▶ Mains N
                       └──▶ Hi-Link AC L
 Mains N ─────────────────▶ Hi-Link AC N
                           relay NC: unconnected
```

- Switch **live**, never neutral. **COM → NO**, so the hooter is silent whenever the board is off.
- If the hooter has a metal body or an earth terminal, connect it to mains earth.
- Fuse first, on live. Everything at 220V goes **inside a closed plastic box**, with strain relief on the mains lead, kept ≥ 6 mm from the low-voltage side.
- **Never connect USB while on mains.** Flash first, unplug USB, then plug in mains.
- Bench-test with a **bulb** in place of the hooter. Ask the venue whether a mains device on stage is OK.

---

## Power and stage notes

- Each node runs from its own Hi-Link on mains. For bench work, USB-C alone is fine (with mains unplugged).
- No router is needed: Node 2 makes its own Wi-Fi network (`FC26-NET`) for Node 1, and the app uses BLE. Keep the nodes within ~10 m of each other and of the device running the app.
- Label the boards (**N1 TEMP**, **N2 SIREN**). Keep a spare ESP32-C3, already flashed, in the bag.
