/// All user-facing copy in one place (single language for the demo; easy to
/// swap for real l10n later).
abstract final class S {
  static const appTitle = 'Jalotsav Panel';
  static const live = 'Live';
  static const trend = 'Trend';
  static const alarms = 'Alarms';
  static const settings = 'Settings';

  static const sensorNode = 'PT100 node';
  static const buzzerNode = 'Siren node';
  static const online = 'Online';
  static const offline = 'Offline';

  static const stateNormal = 'NORMAL';
  static const statePending = 'RISING';
  static const stateAlarm = 'ALARM';
  static const stateAcknowledged = 'ACKNOWLEDGED';
  static const stateSensorLost = 'SENSOR LOST';

  static const setpoint = 'Setpoint';
  static const clearsBelow = 'Clears below';
  static const siren = 'Siren';
  static const sirenOn = 'SOUNDING';
  static const sirenOff = 'Silent';
  static const acknowledge = 'Acknowledge';
  static const phoneAlarm = 'Phone alarm';
  static const testSiren = 'Test siren';
  static const waiting = 'Waiting for sensor…';
  static const lastMinute = 'Last 60 s';
  static const trendTitle = 'Temperature trend';
  static const noEvents = 'No events yet';

  static const appearance = 'Appearance';
  static const themeSystem = 'System';
  static const themeLight = 'Light';
  static const themeDark = 'Dark';
  static const switchTheme = 'Switch light / dark';

  static const calibration = 'PT100 calibration';
  static const calibrationHint =
      'Put a reference thermometer next to the probe, wait until both are '
      'steady, set the real temperature, then tap Calibrate.';
  static const realTemperature = 'Real temperature';
  static const calibrate = 'Calibrate';
  static const resetOffset = 'Reset offset';
  static const calibrationUnavailable =
      'Connect the PT100 node (FC26-TEMP) to calibrate.';
  static String calibrationStatus(
    double? reading,
    double offset,
    double ohms,
  ) =>
      'Reading ${reading == null ? '--' : reading.toStringAsFixed(1)} °C  ·  '
      'offset ${offset >= 0 ? '+' : ''}${offset.toStringAsFixed(2)} °C  ·  '
      '${ohms.toStringAsFixed(1)} Ω';

  static const hysteresis = 'Hysteresis';
  static const alarmDelay = 'Alarm delay';
  static const demoControls = 'Demo controls (simulator)';
  static const heatProbe = 'Heat the probe';
  static const sensorOnline = 'Sensor node online';

  static String eventRaised(double c) =>
      'Alarm raised at ${c.toStringAsFixed(1)} °C';
  static String eventCleared(double c) =>
      'Cleared at ${c.toStringAsFixed(1)} °C';
  static const eventAcknowledged = 'Acknowledged by operator';
  static const eventSensorLost = 'Sensor stopped reporting';
  static const eventSensorRestored = 'Sensor back online';
  static const eventBuzzerTest = 'Siren test';
}
