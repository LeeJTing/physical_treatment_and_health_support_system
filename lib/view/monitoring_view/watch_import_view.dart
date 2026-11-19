import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/device_platform/wearable/veepoo_watch_source.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/monitoring_view_model/monitoring_view_model.dart';

class WatchImportView extends StatefulWidget {
  final MonitoringViewModel viewModel;
  final VeepooWatchSource? source;
  const WatchImportView({super.key, required this.viewModel, this.source});

  @override
  State<WatchImportView> createState() => _WatchImportViewState();
}

class _WatchImportViewState extends State<WatchImportView> {
  late final _source = widget.source ?? VeepooWatchSource();
  final _pin = TextEditingController(text: '0000');
  List<WatchDevice> _devices = const [];
  WatchHistory? _history;
  String? _status;
  String? _error;
  bool _busy = false;
  bool _saving = false;

  @override
  void dispose() {
    unawaited(_source.cancel());
    _pin.dispose();
    super.dispose();
  }

  Future<void> _run(String status, Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = status;
      _error = null;
    });
    try {
      await action();
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message ?? 'Unable to read the watch. Try again.');
    } on MissingPluginException {
      if (mounted) setState(() => _error = 'Direct watch import is available on Android.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to read the watch. Try again with H Band closed.');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
    }
  }

  Future<void> _scan() => _run('Looking for your watch...', () async {
    final devices = await _source.scan();
    if (!mounted) return;
    setState(() {
      _devices = devices;
      _history = null;
      if (devices.isEmpty) {
        _error = 'No K202 Pro or KS02 Pro found. Close H Band, keep the watch nearby and scan again.';
      }
    });
  });

  Future<void> _read(WatchDevice device) async {
    if (!RegExp(r'^\d{4}$').hasMatch(_pin.text)) {
      setState(() => _error = 'Enter the watch’s four-digit PIN.');
      return;
    }
    await _run('Reading saved blood pressure records. Confirm on your watch if asked...', () async {
      final history = await _source.read(device, pin: _pin.text);
      if (mounted) setState(() => _history = history);
    });
  }

  Future<void> _save() async {
    final history = _history;
    if (history == null || _busy || _saving) return;
    setState(() => _saving = true);
    try {
      final count = await widget.viewModel.importWatchHistory(history);
      if (!mounted) return;
      if (count != null) {
        Navigator.pop(context, true);
      } else {
        setState(() => _error = widget.viewModel.takeMessage() ?? 'The readings could not be saved. Try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = _history;
    final disabled = _busy || _saving;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        backgroundColor: AppTokens.screenBackground,
        appBar: AppBar(
          title: const Text('Import from watch'),
          backgroundColor: AppTokens.brandDeep,
          foregroundColor: Colors.white,
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('K202 Pro / KS02 Pro', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            const Text(
              'Close H Band while importing so HealthGuide can connect to your watch. '
              'Keep the watch near this phone with Bluetooth on.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Watch blood pressure values are estimates. Compare them with a validated upper-arm monitor. '
              'Review the dates and values before importing.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pin,
              enabled: !disabled,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Watch PIN',
                helperText: 'Use 0000 unless you changed the watch PIN.',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: disabled ? null : _scan,
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text('Find my watch'),
            ),
            if (_status case final status?) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(status),
            ],
            if (_error case final error?) ...[
              const SizedBox(height: 12),
              Text(error, style: const TextStyle(color: AppTokens.danger)),
            ],
            if (history == null)
              for (final device in _devices)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.watch),
                    title: Text(device.name),
                    subtitle: const Text('Read stored blood pressure'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: disabled ? null : () => _read(device),
                  ),
                ),
            if (history != null) ...[
              const SizedBox(height: 20),
              Text(
                '${history.deviceName} · ${history.readings.length} saved records',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              if (history.readings.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'The watch returned no saved blood pressure records. Record blood pressure on the watch, '
                    'then try again. The watch may keep only a few days of history.',
                  ),
                ),
              for (final row in history.readings)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${row.systolic.round()}/${row.diastolic.round()} mmHg'),
                  subtitle: Text('${DateFormat('d MMM yyyy, HH:mm').format(row.at)} · Watch estimate'),
                ),
              if (history.readings.isNotEmpty) ...[
                const Text('Invalid, future-dated and duplicate readings are skipped when importing.'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: disabled ? null : _save,
                  child: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Import these readings'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
