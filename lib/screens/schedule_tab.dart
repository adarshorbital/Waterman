import 'package:flutter/material.dart';
import '../ble_service.dart';

class ScheduleTab extends StatefulWidget {
  final BleService ble;
  final bool connected;
  const ScheduleTab({super.key, required this.ble, required this.connected});

  @override
  State<ScheduleTab> createState() => _ScheduleTabState();
}

class _ScheduleTabState extends State<ScheduleTab> {
  double _durationSeconds = 60;

  Future<void> _pickAndSetSchedule() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      helpText: "Daily watering time",
    );
    if (time == null || !mounted) return;

    final duration = await showDialog<double>(
      context: context,
      builder: (ctx) {
        double local = _durationSeconds;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text("Watering duration"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("${local.round()}s (max ${kMaxRunSeconds}s)"),
                Slider(
                  value: local,
                  min: 5,
                  max: kMaxRunSeconds.toDouble(),
                  divisions: (kMaxRunSeconds - 5) ~/ 5,
                  label: "${local.round()}s",
                  onChanged: (v) => setLocal(() => local = v),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
              FilledButton(onPressed: () => Navigator.pop(ctx, local), child: const Text("Set")),
            ],
          ),
        );
      },
    );
    if (duration == null) return;

    _durationSeconds = duration;
    await widget.ble.setSchedule(time.hour, time.minute, duration.round());
    await widget.ble.requestStatus();
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.ble.status;
    final hasSchedule = status.scheduleTime != null;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.schedule, size: 40, color: hasSchedule ? Colors.teal : Colors.grey),
                  const SizedBox(height: 12),
                  Text(
                    hasSchedule
                        ? "Waters daily at ${status.scheduleTime} for ${status.scheduleDurationSec}s"
                        : "No schedule set",
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  if (hasSchedule && !status.timeSynced)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        "⚠ Device time isn't synced — this schedule won't fire until reconnected.",
                        style: TextStyle(color: Colors.orange, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: widget.connected ? _pickAndSetSchedule : null,
            icon: const Icon(Icons.edit_calendar),
            label: Text(hasSchedule ? "Change schedule" : "Set daily schedule"),
          ),
          const SizedBox(height: 12),
          if (hasSchedule)
            OutlinedButton.icon(
              onPressed: widget.connected
                  ? () async {
                      await widget.ble.clearSchedule();
                      await widget.ble.requestStatus();
                    }
                  : null,
              icon: const Icon(Icons.delete_outline),
              label: const Text("Clear schedule"),
            ),
          const SizedBox(height: 20),
          if (!widget.connected)
            const Text("Connect device first", textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
