/// Parses the firmware's status string, e.g.:
/// "STATE:RUNNING;REMAIN:45;SCHED:07:00;SCHEDSEC:60;SYNCED:1"
class PumpStatus {
  final bool running;
  final int remainingSeconds;
  final String? scheduleTime; // "HH:MM" or null if none set
  final int scheduleDurationSec;
  final bool timeSynced;

  const PumpStatus({
    required this.running,
    required this.remainingSeconds,
    required this.scheduleTime,
    required this.scheduleDurationSec,
    required this.timeSynced,
  });

  factory PumpStatus.unknown() => const PumpStatus(
        running: false,
        remainingSeconds: 0,
        scheduleTime: null,
        scheduleDurationSec: 0,
        timeSynced: false,
      );

  factory PumpStatus.fromRaw(String raw) {
    final parts = raw.split(';');
    final map = <String, String>{};
    for (final p in parts) {
      final idx = p.indexOf(':');
      if (idx <= 0) continue;
      map[p.substring(0, idx)] = p.substring(idx + 1);
    }

    final schedRaw = map['SCHED'];
    final schedTime = (schedRaw == null || schedRaw == 'NONE') ? null : schedRaw;

    return PumpStatus(
      running: map['STATE'] == 'RUNNING',
      remainingSeconds: int.tryParse(map['REMAIN'] ?? '0') ?? 0,
      scheduleTime: schedTime,
      scheduleDurationSec: int.tryParse(map['SCHEDSEC'] ?? '0') ?? 0,
      timeSynced: map['SYNCED'] == '1',
    );
  }
}
