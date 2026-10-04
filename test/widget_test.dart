import 'package:flutter_test/flutter_test.dart';

import 'package:waterman_app/models/pump_status.dart';

void main() {
  test('parses a status with a schedule', () {
    final s = PumpStatus.fromRaw('STATE:RUNNING;REMAIN:45;SCHED:07:00;SCHEDSEC:60;SYNCED:1');
    expect(s.running, isTrue);
    expect(s.remainingSeconds, 45);
    expect(s.scheduleTime, '07:00');
    expect(s.scheduleDurationSec, 60);
    expect(s.timeSynced, isTrue);
  });

  test('parses a status with no schedule', () {
    final s = PumpStatus.fromRaw('STATE:IDLE;REMAIN:0;SCHED:NONE;SCHEDSEC:0;SYNCED:0');
    expect(s.running, isFalse);
    expect(s.scheduleTime, isNull);
    expect(s.timeSynced, isFalse);
  });
}
