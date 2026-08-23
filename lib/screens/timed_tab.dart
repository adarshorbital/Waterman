import 'package:flutter/material.dart';
import '../ble_service.dart';
import 'manual_tab.dart' show kMaxRunSecondsLabel;

class TimedTab extends StatefulWidget {
  final BleService ble;
  final bool connected;
  const TimedTab({super.key, required this.ble, required this.connected});

  @override
  State<TimedTab> createState() => _TimedTabState();
}

class _TimedTabState extends State<TimedTab> {
  double _customSeconds = 45;

  static const presets = [30, 60, 120, 180];

  @override
  Widget build(BuildContext context) {
    final status = widget.ble.status;
    final running = status.running;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text("Presets", style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            children: presets.map((s) {
              final label = s >= 60 ? "${s ~/ 60} min" : "${s}s";
              return ElevatedButton(
                onPressed: (widget.connected && !running) ? () => widget.ble.runFor(s) : null,
                child: Text(label),
              );
            }).toList(),
          ),
          const SizedBox(height: 28),
          Text("Custom duration: ${_customSeconds.round()}s (max ${kMaxRunSecondsLabel()})",
              style: Theme.of(context).textTheme.titleMedium),
          Slider(
            value: _customSeconds,
            min: 5,
            max: kMaxRunSeconds.toDouble(),
            divisions: (kMaxRunSeconds - 5) ~/ 5,
            label: "${_customSeconds.round()}s",
            onChanged: (widget.connected && !running)
                ? (v) => setState(() => _customSeconds = v)
                : null,
          ),
          FilledButton.icon(
            onPressed: (widget.connected && !running)
                ? () => widget.ble.runFor(_customSeconds.round())
                : null,
            icon: const Icon(Icons.play_arrow),
            label: const Text("Start custom burst"),
          ),
          const SizedBox(height: 28),
          if (running)
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text("Watering — ${status.remainingSeconds}s remaining",
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: widget.connected ? () => widget.ble.pumpOff() : null,
                      icon: const Icon(Icons.stop),
                      label: const Text("Stop now"),
                    ),
                  ],
                ),
              ),
            )
          else
            Text(
              widget.connected ? "Idle" : "Connect device first",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
        ],
      ),
    );
  }
}
