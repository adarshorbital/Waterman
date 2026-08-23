import 'package:flutter/material.dart';
import '../ble_service.dart';

class ManualTab extends StatefulWidget {
  final BleService ble;
  final bool connected;
  const ManualTab({super.key, required this.ble, required this.connected});

  @override
  State<ManualTab> createState() => _ManualTabState();
}

class _ManualTabState extends State<ManualTab> {
  bool _pressed = false;

  void _start() {
    if (!widget.connected) return;
    setState(() => _pressed = true);
    widget.ble.pumpOn();
  }

  void _stop() {
    if (!_pressed) return;
    setState(() => _pressed = false);
    widget.ble.pumpOff();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "Press and hold to water.\nAuto-stops after ${kMaxRunSecondsLabel()} for safety.",
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 32),
          GestureDetector(
            onTapDown: (_) => _start(),
            onTapUp: (_) => _stop(),
            onTapCancel: () => _stop(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: !widget.connected
                    ? Colors.grey.shade400
                    : (_pressed ? Colors.blue.shade700 : Colors.blue.shade400),
                boxShadow: _pressed
                    ? [BoxShadow(color: Colors.blue.withOpacity(0.5), blurRadius: 24, spreadRadius: 4)]
                    : [],
              ),
              child: Icon(
                Icons.water_drop,
                color: Colors.white,
                size: 64,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(_pressed ? "Watering..." : (widget.connected ? "Idle" : "Connect device first")),
        ],
      ),
    );
  }
}

String kMaxRunSecondsLabel() {
  final s = kMaxRunSeconds;
  return s >= 60 ? "${s ~/ 60} min" : "${s}s";
}
