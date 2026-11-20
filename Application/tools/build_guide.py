"""Builds esp32/build-guide.html from esp32/wiring.html and the firmware sources.

Usage (from the Application folder):
    python3 tools/build_guide.py esp32

Run it again after changing wiring.html or any firmware file.
"""
import html, re, sys, os
if len(sys.argv) != 2:
    sys.exit('usage: python3 tools/build_guide.py <path to the esp32 folder>')
root = sys.argv[1]
w = open(os.path.join(root, 'wiring.html')).read()
code = {n: open(os.path.join(root, p)).read() for n, p in [
    ('node1_temperature.ino', 'node1_temperature/node1_temperature.ino'),
    ('node2_siren.ino', 'node2_siren/node2_siren.ino'),
    ('fc26_protocol.h', 'node1_temperature/fc26_protocol.h')]}

w = w.replace('<title>FC26 Node Wiring</title>', '<title>FC26 Build Guide</title>')
extra_css = """
  nav.toc { display: flex; flex-wrap: wrap; gap: 6px; margin: 14px 0 4px; }
  nav.toc a { font-size: 13px; text-decoration: none; color: var(--text); background: var(--card); border: 1px solid var(--line); border-radius: 999px; padding: 3px 11px; }
  nav.toc a:hover { border-color: var(--boardline); }
  h2 { scroll-margin-top: 12px; }
  pre.flow { background: var(--card); border: 1px solid var(--line); border-radius: 12px; padding: 12px; overflow-x: auto; font-size: 13px; line-height: 1.4; }
  ol li, ul li { margin: 3px 0; }
  .codehead { display: flex; align-items: center; gap: 8px; margin: 22px 0 6px; flex-wrap: wrap; }
  .codehead h3 { margin: 0; flex: 1; font-family: ui-monospace, Menlo, monospace; }
  .codehead button { font: inherit; font-size: 13px; border: 1px solid var(--line); background: var(--card); color: var(--text); border-radius: 8px; padding: 5px 11px; cursor: pointer; }
  pre.code { background: var(--card); border: 1px solid var(--line); border-radius: 12px; padding: 12px; overflow: auto; max-height: 460px; font: 12px/1.45 ui-monospace, Menlo, monospace; margin: 0; }
  .note { border-left: 3px solid var(--boardline); padding: 4px 12px; color: var(--muted); }
"""
w = w.replace('</style>', extra_css + '</style>', 1)

intro = """  <h1>FC26 Build Guide</h1>
  <p class="muted">FlutterCon India 2026 smart-home demo: two ESP32-C3 Super Mini nodes and one Flutter display app, Jalotsav Panel. Node 1 measures a PT100. Node 2 sounds a 220V hooter when it gets too hot. The display shows it all over Bluetooth. Everything you need is on this page: wiring, setup, tests, the app and the full firmware.</p>
  <nav class="toc">
    <a href="#how">How it works</a><a href="#app">The display app</a><a href="#buy">Buy list</a><a href="#wire1">Node 1 wiring</a><a href="#wire2">Node 2 wiring</a>
    <a href="#setup">Arduino setup</a><a href="#first">First test</a><a href="#browser">Browser test</a><a href="#led">LEDs</a><a href="#ble">BLE contract</a><a href="#code">Firmware</a>
  </nav>

  <h2 id="how">How it works</h2>
  <pre class="flow"> Node 1 (PT100) ──Wi-Fi FC26-NET, UDP 1×/s──▶ Node 2 (siren, access point): decides the alarm, drives the hooter
      │                                   │
      │ BLE: temperature                  │ BLE: alarm state, Acknowledge, Test, limits
      ▼                                   ▼
   Display: Jalotsav Panel (Flutter)
     main:   Raspberry Pi + touchscreen
     backup: phone / tablet / Mac  (or ble-test.html in Chrome)</pre>
  <ul>
    <li><b>Node 2 makes its own Wi-Fi network, no router.</b> Node 2 is an access point called <b>FC26-NET</b> (password <code>fc26-panel</code>, channel 1, 192.168.4.1). Node 1 joins it and sends one UDP packet a second to port 4626, and rejoins by itself if Node 2 reboots. Node 2 only accepts packets that start with <code>FC26</code> and carry the same <code>NETWORK_ID</code>.</li>
    <li><b>Wi-Fi power is 8.5 dBm on purpose.</b> ESP32-C3 Super Mini antennas are poorly matched; at full power their Wi-Fi often doesn't get out at all. Don't raise <code>FC26_WIFI_TX_POWER</code>.</li>
    <li><b>Node 2 is the brain</b>, so the alarm works with no phone or laptop around:
      <ul>
        <li>temperature ≥ <b>setpoint</b> for <b>delay</b> seconds → <b>ALARM</b>, hooter ON</li>
        <li>touch the <b>TTP223</b> → <b>ACKNOWLEDGED</b>, hooter OFF (stays off until it cools)</li>
        <li>temperature ≤ setpoint − <b>hysteresis</b> → back to <b>NORMAL</b> by itself</li>
        <li>hold the TTP223 for 2 s while normal → 2-second hooter test</li>
        <li>Node 1 silent for 6 s, or reporting a probe fault → hooter OFF, LED blinks blue</li>
        <li>hooter ON for 2 minutes → silences itself</li>
      </ul></li>
    <li><b>BLE is for watching and settings.</b> The display app connects to <b>both</b> nodes: Node 1 (<code>FC26-TEMP</code>) for the temperature, Node 2 (<code>FC26-SIREN</code>) for the alarm, the hooter and the limits. The alarm runs on Node 2, so it works with the display off. Each board takes <b>one</b> BLE connection: close the app before using the test page.</li>
  </ul>
  <p>Defaults: setpoint <b>35 °C</b>, hysteresis <b>2 °C</b> (clears at 33 °C), delay <b>3 s</b>.</p>

  <h2 id="app">The display: Jalotsav Panel</h2>
  <p>One Flutter app, <b>Jalotsav Panel</b> (<code>Application/jalotsav_panel</code>, ID <code>com.jalotsav.smartpanel</code>), is the display:</p>
  <ul>
    <li><b>Main display: Raspberry Pi with a touchscreen</b>, running the app through flutter-pi.</li>
    <li><b>Backup display: a phone or tablet</b> (Android, iOS) or a Mac, running the same app. Same screens, same Bluetooth links.</li>
  </ul>
  <p>What it does:</p>
  <ul>
    <li><b>Connects to both nodes by itself</b>: <code>FC26-TEMP</code> for the temperature (the main source) and <code>FC26-SIREN</code> for the alarm, the hooter and the limits. No pairing. The two dots in the top bar turn green when each board is linked.</li>
    <li><b>Live</b>: temperature gauge, alarm state (Normal / Rising / Alarm / Acknowledged), siren card with <b>Acknowledge</b> and <b>Test siren</b>, last 60 s chart. <b>Trend</b> and <b>Alarms</b> show history.</li>
    <li><b>Settings</b>: setpoint, hysteresis and delay (saved on Node 2), <b>PT100 calibration</b> (set the real temperature with ± buttons, tap Calibrate; saved on Node 1), and light/dark theme.</li>
    <li><b>Backup siren on the display</b>: if Node 2 isn't linked, the app applies the same alarm rules to Node 1's readings and <b>sounds an alarm itself</b> (Android alarm volume). Acknowledge silences it; it stops when the probe cools or when Node 2 links and takes over. Limits changed while Node 2 is offline aren't saved.</li>
    <li><b>One display at a time</b>: each board takes one Bluetooth connection, so close the app on one device (or the test page) before connecting another.</li>
  </ul>
  <pre class="flow">cd jalotsav_panel
flutter run          # on a connected phone; Android asks for "Nearby devices" once</pre>
"""
# replace original h1 + first muted paragraph with intro, keep the pin-order note
w = re.sub(r'  <h1>FC26 Node Wiring</h1>\n  <p class="muted">.*?</p>\n', intro, w, count=1, flags=re.S)
w = w.replace('<h2>Buy before you solder', '<h2 id="buy">Buy before you solder')
w = w.replace('<h2>Node 1 ·', '<h2 id="wire1">Node 1 ·')
w = w.replace('<h2>Node 2 ·', '<h2 id="wire2">Node 2 ·')
w = w.replace('<h2>LED colours</h2>', '<h2 id="led">LED colours</h2>')

setup = """
  <h2 id="setup">Arduino IDE setup (once)</h2>
  <ol>
    <li><b>Boards Manager</b> → install <b>"esp32" by Espressif Systems</b> (3.x).</li>
    <li><b>Library Manager</b> → install <b>"Adafruit ADS1X15"</b> (Node 1 only; accept Adafruit BusIO). Node 2 needs no extra libraries.</li>
    <li><b>Tools</b> menu, for both boards:
      <ul>
        <li>Board: <b>ESP32C3 Dev Module</b></li>
        <li><b>USB CDC On Boot: Enabled</b>. Without it, Serial Monitor stays empty.</li>
        <li><b>Partition Scheme: Huge APP (3MB No OTA/1MB SPIFFS)</b>. BLE + Wi-Fi is ~1.27 MB, right at the edge of the default partition.</li>
      </ul></li>
    <li>Make one sketch folder per node. Each folder needs its <code>.ino</code> <b>and</b> a copy of <code>fc26_protocol.h</code> (download buttons at the bottom of this page).</li>
    <li>If an upload won't start: <b>hold BOOT, tap RESET, release BOOT</b>, then upload again.</li>
  </ol>
  <p class="note">Built with esp32 core 3.3.12 (BLE on the NimBLE backend) and Adafruit ADS1X15 2.6.2, no warnings. <b>Tested on hardware:</b> Node 1 (PT100, ADS1115, BLE to the app, calibration from the app) and the app's backup siren. Node 2 is compile-tested; its hardware is in progress.</p>
  <p><b>Before the first power-up</b></p>
  <ul>
    <li><b>Node 1:</b> measure the reference resistor with a multimeter and put the value in <code>RREF</code> at the top of the sketch (e.g. <code>987.0</code>).</li>
    <li><b>Flash with USB only, mains unplugged.</b> Never have USB and the Hi-Link connected at the same time.</li>
    <li>Two kits in one room? Give each kit its own <code>NETWORK_ID</code> in <code>fc26_protocol.h</code>, the same in both folders.</li>
  </ul>

  <h2 id="first">First test with Serial Monitor (115200 baud)</h2>
  <ol>
    <li>Flash Node 2 first. Serial shows <code>[wifi] access point FC26-NET up</code>; its LED blinks blue until Node 1 joins.</li>
    <li>Flash Node 1. Serial shows <code>[wifi] joined FC26-NET</code>, then <code>[temp] 27.84 °C (110.85 Ω, offset +0.00)</code> every second. Hold the probe: it rises.</li>
    <li>Node 2's LED turns green and its Serial shows <code>[sensor] Node 1 online</code>, then every 10 s <code>1 device(s) on FC26-NET, N packets from Node 1</code>.</li>
    <li>Bench-test the relay with a <b>bulb</b>, not the hooter: hold the TTP223 for 2 s and the bulb comes on for 2 s.</li>
    <li>Run the full flow with the default 35 °C setpoint: warm the probe (hand, warm water or a lighter held well away), wait 3 s → bulb on; touch the TTP223 → off; let it cool below 33 °C → back to green. If Node 2 kept an older saved setpoint, set 35 °C in the app's Settings.</li>
  </ol>

  <h2 id="browser">Test from a browser (no app)</h2>
  <p><code>ble-test.html</code> is in the same folder as this page. Close the display app first (one connection per board). It needs <b>Chrome or Edge</b> (Mac, Windows, Android); Safari and Firefox have no Web Bluetooth. Serve it from localhost:</p>
  <pre class="flow">cd esp32
python3 -m http.server 8766
# then open http://localhost:8766/ble-test.html</pre>
  <ul>
    <li><b>Connect</b> on the Node 2 card → pick <code>FC26-SIREN</code>: live temperature, alarm state, hooter, Node 1 link. Buttons for Acknowledge, Test siren and Save limits.</li>
    <li><b>Connect</b> on the Node 1 card → pick <code>FC26-TEMP</code>: probe resistance, faults, and <b>Calibrate</b> (type a trusted thermometer's reading, press Calibrate).</li>
    <li><b>Simulate</b> runs a fake node in the page, to try the flow before the hardware is ready.</li>
    <li>On a phone, <b>nRF Connect</b> also shows the raw characteristics.</li>
  </ul>
"""
ble = """
  <h2 id="ble">BLE contract</h2>
  <p class="muted">Little-endian. Temperatures are °C × 100 as int16; <code>-32768</code> = no reading. All UUIDs end in <code>-6a1b-4d2e-9f3c-8b5e7a0c1d2f</code>.</p>
  <h3>Node 2 <code>FC26-SIREN</code> · service <code>fc260200-…</code></h3>
  <div class="tablewrap"><table>
    <tr><th>Characteristic</th><th>Access</th><th>Content</th></tr>
    <tr><td><code>fc260201-…</code> state</td><td>read, notify</td><td>10 bytes: int16 temp · uint8 state (0 normal, 1 pending, 2 alarm, 3 acknowledged) · uint8 flags (bit0 hooter, bit1 Node 1 online, bit2 test, bit3 probe fault) · int16 setpoint · uint16 hysteresis (×100) · uint8 delay s · uint8 seq</td></tr>
    <tr><td><code>fc260202-…</code> command</td><td>write (text)</td><td><code>ACK</code> · <code>TEST</code> · <code>STOP</code> · <code>CFG=35,2,3</code> (setpoint, hysteresis, delay)</td></tr>
  </table></div>
  <h3>Node 1 <code>FC26-TEMP</code> · service <code>fc260100-…</code></h3>
  <div class="tablewrap"><table>
    <tr><th>Characteristic</th><th>Access</th><th>Content</th></tr>
    <tr><td><code>fc260101-…</code> reading</td><td>read, notify</td><td>8 bytes: int16 temp · uint16 ohms×100 · uint8 fault (0 ok, 1 ADS1115 missing, 2 open, 3 short, 4 range) · uint8 seq · int16 offset×100</td></tr>
    <tr><td><code>fc260102-…</code> command</td><td>write (text)</td><td><code>CAL=&lt;real °C&gt;</code> · <code>OFS=&lt;offset °C&gt;</code></td></tr>
  </table></div>
  <p class="muted">Wi-Fi packet (Node 1 → UDP 192.168.4.1:4626 on FC26-NET): 10 bytes, "FC26" · version · network id · seq · fault · int16 temp.</p>
"""
blocks = []
for name, src in code.items():
    where = {'node1_temperature.ino': 'folder <code>node1_temperature/</code>',
             'node2_siren.ino': 'folder <code>node2_siren/</code>',
             'fc26_protocol.h': 'put a copy in <b>both</b> folders'}[name]
    blocks.append(f"""  <div class="codehead"><h3>{name}</h3><span class="muted">{where}</span>
    <button data-copy="{name}">Copy</button><button data-dl="{name}">Download</button></div>
  <pre class="code" id="src-{name}">{html.escape(src)}</pre>""")
codesec = '\n  <h2 id="code">Firmware</h2>\n  <p class="muted">The same files are in the <code>node1_temperature</code> and <code>node2_siren</code> folders next to this page. Use Download to save each one with the right name.</p>\n' + '\n'.join(blocks) + '\n'
w = w.replace('  <h2 id="led">', setup + '\n  <h2 id="led">', 1)
w = w.replace('</main>', ble + codesec + '</main>', 1)
js = """
// Copy / download buttons for the firmware listings.
document.querySelectorAll('[data-copy]').forEach((b) => b.addEventListener('click', async () => {
  const text = document.getElementById('src-' + b.dataset.copy).textContent;
  try { await navigator.clipboard.writeText(text); b.textContent = 'Copied'; }
  catch (e) { b.textContent = 'Select and copy manually'; console.error(e); }
  setTimeout(() => (b.textContent = 'Copy'), 1500);
}));
document.querySelectorAll('[data-dl]').forEach((b) => b.addEventListener('click', () => {
  const text = document.getElementById('src-' + b.dataset.dl).textContent;
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([text], { type: 'text/plain' }));
  a.download = b.dataset.dl;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}));
</script>"""
i = w.rindex('</script>')
w = w[:i] + js + w[i+len('</script>'):]
open(os.path.join(root, 'build-guide.html'), 'w').write(w)
print('ok', len(w))
