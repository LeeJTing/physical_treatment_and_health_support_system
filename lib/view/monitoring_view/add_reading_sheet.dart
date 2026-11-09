import 'package:flutter/material.dart';

import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/view/common/tidy_text.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/monitoring_view_model/monitoring_view_model.dart';

/// Entry form for one reading (UC700 BF-6 to BF-20; C4 to C6). The date and time start at the
/// device time (BF-8); Save stays disabled until every required field is valid (BF-9 to BF-14);
/// a rejected save keeps the values (FR200_008). Returns true when a reading was saved.
class AddReadingSheet extends StatefulWidget {
  final MonitoringViewModel vm;
  final MetricType initial;
  const AddReadingSheet({super.key, required this.vm, this.initial = MetricType.bloodPressure});

  static Future<bool?> show(BuildContext context, MonitoringViewModel vm, [MetricType m = MetricType.bloodPressure]) =>
      showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: AppTokens.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => AddReadingSheet(vm: vm, initial: m),
      );

  @override
  State<AddReadingSheet> createState() => _AddReadingSheetState();
}

class _AddReadingSheetState extends State<AddReadingSheet> {
  late MetricType _metric = widget.initial;
  final _primary = TextEditingController();
  final _secondary = TextEditingController();
  MeasurementContext? _context;
  DateTime _at = DateTime.now();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _primary.dispose();
    _secondary.dispose();
    super.dispose();
  }

  double? get _p => double.tryParse(_primary.text.trim());
  double? get _s => double.tryParse(_secondary.text.trim());

  String? get _problem => widget.vm.validate(
    metric: _metric,
    primary: _p,
    secondary: _s,
    context: _context,
    recordedAt: _at,
  );

  Future<void> _pickTime() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_at));
    if (t == null) return;
    setState(() => _at = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final msg = await widget.vm.addReading(
      metric: _metric,
      primary: _p,
      secondary: _s,
      context: _context,
      recordedAt: _at,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = msg;
    });
    if (msg == null) Navigator.of(context).pop(true);
  }

  Widget _field(String label, TextEditingController c, String unit) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => setState(() => _error = null),
      style: const TextStyle(fontSize: 20),
      decoration: InputDecoration(
        labelText: label,
        suffixText: unit,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTokens.radiusField)),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final at = '${_at.day}/${_at.month}/${_at.year}  '
        '${_at.hour.toString().padLeft(2, '0')}:${_at.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Add Reading',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppTokens.ink),
            ),
            const SizedBox(height: 14),
            // No tick on the chosen one, and each name on one line (phone, 9 Nov).
            SegmentedButton<MetricType>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: MetricType.bloodPressure,
                  label: OneLineText('Blood pressure', alignment: Alignment.center),
                ),
                ButtonSegment(value: MetricType.bloodGlucose, label: OneLineText('Glucose', alignment: Alignment.center)),
                ButtonSegment(value: MetricType.bodyWeight, label: OneLineText('Weight', alignment: Alignment.center)),
              ],
              selected: {_metric},
              onSelectionChanged: (s) => setState(() {
                _metric = s.first;
                _primary.clear();
                _secondary.clear();
                _context = null;
                _error = null;
              }),
            ),
            const SizedBox(height: 12),
            _Tip(switch (_metric) {
              MetricType.bloodPressure =>
                'Sit quietly for 5 minutes with your arm resting at heart level, then measure.',
              MetricType.bloodGlucose => 'Say when you measured: it changes what counts as usual for you.',
              MetricType.bodyWeight => 'Weigh yourself at the same time each day, ideally before breakfast.',
            }),
            const SizedBox(height: 14),
            ...switch (_metric) {
              MetricType.bloodPressure => [
                _field('Systolic (top number)', _primary, 'mmHg'),
                _field('Diastolic (bottom number)', _secondary, 'mmHg'),
              ],
              MetricType.bloodGlucose => [
                _field('Glucose level', _primary, 'mmol/L'),
                const Text('When was it measured?', style: TextStyle(fontSize: 16, color: AppTokens.inkMuted)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in MeasurementContext.values)
                      ChoiceChip(
                        label: Text(c.label, style: const TextStyle(fontSize: 16)),
                        selected: _context == c,
                        onSelected: (_) => setState(() => _context = c),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              MetricType.bodyWeight => [_field('Weight', _primary, 'kg')],
            },
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: const Text('Date and time'),
              subtitle: Text(at, style: const TextStyle(fontSize: 17, color: AppTokens.ink)),
              trailing: const Icon(Icons.edit_calendar),
              onTap: _pickTime,
            ),
            if (_error != null || (problem != null && (_p != null || _primary.text.isNotEmpty)))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  _error ?? problem!,
                  style: const TextStyle(color: AppTokens.danger, fontSize: 15),
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              height: 56,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTokens.brandDeep,
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                onPressed: problem == null && !_saving ? _save : null,
                child: _saving
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A one-line measuring tip with a light-bulb picture, under the reading type.
class _Tip extends StatelessWidget {
  final String text;
  const _Tip(this.text);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: AppTokens.tint, borderRadius: BorderRadius.circular(14)),
    child: Row(
      children: [
        const Icon(Icons.lightbulb_outline, color: AppTokens.brandDeep),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 15, height: 1.3, color: AppTokens.ink))),
      ],
    ),
  );
}
