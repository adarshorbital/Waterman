import 'package:flutter/material.dart';
import '../ble_service.dart';
import 'manual_tab.dart';
import 'timed_tab.dart';
import 'schedule_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final ble = BleService.instance;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    ble.addListener(_onBleChanged);
  }

  @override
  void dispose() {
    ble.removeListener(_onBleChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onBleChanged() {
    if (mounted) setState(() {});
  }

  Color _statusColor() {
    switch (ble.state) {
      case BleConnState.connected:
        return Colors.green;
      case BleConnState.connecting:
      case BleConnState.scanning:
        return Colors.orange;
      case BleConnState.disconnected:
        return Colors.red;
    }
  }

  String _statusLabel() {
    switch (ble.state) {
      case BleConnState.connected:
        return "Connected";
      case BleConnState.connecting:
        return "Connecting...";
      case BleConnState.scanning:
        return "Scanning...";
      case BleConnState.disconnected:
        return "Disconnected";
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = ble.state == BleConnState.connected;

    return Scaffold(
      appBar: AppBar(
        title: const Text("WaterMan"),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.touch_app), text: "Manual"),
            Tab(icon: Icon(Icons.timer), text: "Timed"),
            Tab(icon: Icon(Icons.schedule), text: "Schedule"),
          ],
        ),
      ),
      body: Column(
        children: [
          _ConnectionBar(
            color: _statusColor(),
            label: _statusLabel(),
            connected: connected,
            busy: ble.state == BleConnState.scanning || ble.state == BleConnState.connecting,
            onConnect: () => ble.scanAndConnect(),
            onDisconnect: () => ble.disconnect(),
            error: ble.lastError,
          ),
          if (connected && !ble.status.timeSynced)
            Container(
              width: double.infinity,
              color: Colors.amber.shade100,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: const Text(
                "Time not synced yet — schedule won't fire until this resolves. "
                "Stay connected a moment; syncing on every connect.",
                style: TextStyle(fontSize: 12),
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                ManualTab(ble: ble, connected: connected),
                TimedTab(ble: ble, connected: connected),
                ScheduleTab(ble: ble, connected: connected),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionBar extends StatelessWidget {
  final Color color;
  final String label;
  final bool connected;
  final bool busy;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final String? error;

  const _ConnectionBar({
    required this.color,
    required this.label,
    required this.connected,
    required this.busy,
    required this.onConnect,
    required this.onDisconnect,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(radius: 6, backgroundColor: color),
              const SizedBox(width: 8),
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
              const Spacer(),
              if (busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                FilledButton.tonal(
                  onPressed: connected ? onDisconnect : onConnect,
                  child: Text(connected ? "Disconnect" : "Connect"),
                ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
