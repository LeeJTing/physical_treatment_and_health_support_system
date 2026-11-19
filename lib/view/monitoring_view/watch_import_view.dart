import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/device_platform/wearable/veepoo_watch_source.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/monitoring_view_model/monitoring_view_model.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';

class WatchImportView extends StatefulWidget {
  final MonitoringViewModel viewModel;
  final VeepooWatchSource? source;
  const WatchImportView({super.key, required this.viewModel, this.source});

  @override
  State<WatchImportView> createState() => _WatchImportViewState();
}

class _WatchImportViewState extends State<WatchImportView> {
  late final _source = widget.source ?? widget.viewModel.watchSource;
  final _pin = TextEditingController(text: '0000');
  List<WatchDevice> _devices = const [];
  WatchHistory? _history;
  String? _status;
  String? _error;
  bool _busy = false;
  bool _saving = false;
  bool _automatic = true;
  WatchDevice? _selectedDevice;

  @override
  void initState() {
    super.initState();
    widget.viewModel.watchSetupOpen = true;
  }

  @override
  void dispose() {
    unawaited(_source.cancel());
    widget.viewModel.watchSetupOpen = false;
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
      if (mounted) {
        setState(
          () => _error =
              'Unable to read the watch. Disconnect it from its companion app first, then try Bluetooth again.',
        );
      }
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
        _error =
            'No compatible watch found. Disconnect your watch from its companion app, keep it nearby and scan again. '
            'For other wearables, use Health Connect in Tracking.';
      }
    });
  });

  Future<void> _read(WatchDevice device) async {
    if (!RegExp(r'^\d{4}$').hasMatch(_pin.text)) {
      setState(() => _error = 'Enter the watch’s four-digit PIN.');
      return;
    }
    await _run('Reading saved health records. Confirm on your watch if asked...', () async {
      final history = await _source.read(device, pin: _pin.text);
      if (mounted) {
        setState(() {
          _history = history;
          _selectedDevice = device;
        });
      }
    });
  }

  Future<void> _save() async {
    final history = _history;
    if (history == null || _busy || _saving) return;
    setState(() => _saving = true);
    try {
      final count = _automatic
          ? await widget.viewModel.enableWatchSync(_selectedDevice!, _pin.text, history)
          : await widget.viewModel.importWatchHistory(history);
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
        bottomNavigationBar: history != null && (history.readings.isNotEmpty || _automatic)
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: disabled ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_automatic ? 'Connect and sync automatically' : 'Import these readings'),
                  ),
                ),
              )
            : null,
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('Connect a wearable watch', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            const Text(
              'Disconnect your watch from its companion app first. Then turn on Bluetooth and tap Find my watch '
              'to connect here. Keep your watch near this phone.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Direct Bluetooth works with compatible watches. If your watch does not appear, use Health Connect '
              'in Tracking to import readings shared by its companion app.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Watch blood pressure and glucose values are estimates. Review the dates and values before importing. '
              'Use clinical devices for medical decisions.',
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
                    subtitle: const Text('Read supported health records'),
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
              const SizedBox(height: 12),
              for (final metric in [MetricType.bloodPressure, MetricType.bloodGlucose])
                Text(
                  '${metric.label} · ${history.supportedTypes.contains(metric.db) ? 'Supported by this watch' : 'Use Health Connect or manual entry'}',
                ),
              const Text('Weight · Use Health Connect with a scale, or add a weight reading manually.'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Automatically sync this watch'),
                subtitle: const Text('Checks every 15 seconds while HealthGuide is open and when you return to the app. '
                    'New readings are saved as soon as a check returns them.'),
                value: _automatic,
                onChanged: disabled ? null : (value) => setState(() => _automatic = value),
              ),
              if (history.readings.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'The watch returned no saved health records. Record a supported reading on the watch, '
                    'then try again. The watch may keep only a few days of history.',
                  ),
                ),
              for (final row in history.readings)
                Semantics(
                  container: true,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      row.metric == 'BLOOD_PRESSURE'
                          ? 'Blood pressure · ${row.value.round()}/${row.secondary?.round()} mmHg'
                          : 'Blood glucose · ${row.value.toStringAsFixed(1)} mmol/L',
                    ),
                    subtitle: Text('${DateFormat('d MMM yyyy, HH:mm').format(row.at)} · Watch estimate'),
                  ),
                ),
              if (history.readings.isNotEmpty || _automatic) ...[
                const Text('Invalid, future-dated and duplicate readings are skipped when importing.'),
                const SizedBox(height: 12),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
