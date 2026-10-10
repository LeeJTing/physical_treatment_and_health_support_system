import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/view/common/status_bar_strip.dart';
import 'package:physical_treatment_and_health_support_system/view/login_view/widgets/auth_widgets.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/auth_view_model/auth_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';

/// Terms of Use and Privacy Notice in English or Malay (PDPA 2010 s.7(3)),
/// from assets/legal/terms.json (11 Oct). Shown after registration and at a
/// sign-in when the version changed or a guardian must agree; the patient
/// chooses an age group, a user aged 13 to 17 has a parent or guardian agree,
/// and the health-data consent is separate (s.40). [readOnly] only shows the
/// text (the link on the registration form).
class TermsView extends StatefulWidget {
  final bool readOnly;
  const TermsView({super.key, this.readOnly = false});

  @override
  State<TermsView> createState() => _TermsViewState();
}

class _TermsViewState extends State<TermsView> {
  Map<String, dynamic>? _doc;
  String _lang = 'en';
  bool? _minor;
  String? _relationship; // PARENT | GUARDIAN
  bool _guardianAgreed = false;
  bool _agreeTerms = false;
  bool _consentHealth = false;
  final _guardianName = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_doc == null) _load();
  }

  Future<void> _load() async {
    final text = await DefaultAssetBundle.of(
      context,
    ).loadString('assets/legal/terms.json');
    if (!mounted) return;
    setState(() => _doc = jsonDecode(text) as Map<String, dynamic>);
  }

  @override
  void dispose() {
    _guardianName.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _l => _doc![_lang] as Map<String, dynamic>;
  String _ui(String key) => (_l['ui'] as Map<String, dynamic>)[key] as String;

  /// The profile says under 18 (or the gate asked for a guardian): no adult option.
  bool _mustBeMinor(AuthViewModel? vm) =>
      vm != null &&
      (vm.termsReason == TermsReason.guardianNeeded ||
          (vm.termsProfileAge ?? AppConstants.adultAge) < AppConstants.adultAge);

  bool _canAccept(bool minor) =>
      _agreeTerms &&
      _consentHealth &&
      (!minor ||
          (_guardianName.text.trim().length >= 2 &&
              _relationship != null &&
              _guardianAgreed));

  Future<void> _accept(AuthViewModel vm, bool minor) async {
    final ok = await vm.acceptTerms(
      language: _lang,
      minor: minor,
      guardianName: _guardianName.text,
      guardianRelationship: _relationship,
    );
    if (ok && mounted) {
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(vm.nextRoute ?? Routes.home, (_) => false);
    }
  }

  Future<void> _decline(AuthViewModel vm) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(_ui('decline_message'), style: const TextStyle(fontSize: 17)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(_ui('decline_back')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(
              _ui('decline_confirm'),
              style: const TextStyle(color: AppTokens.cta),
            ),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await vm.declineTerms();
    if (mounted) {
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(Routes.loginScreen, (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.readOnly ? null : context.watch<AuthViewModel>();
    final doc = _doc;
    return PopScope(
      canPop: widget.readOnly, // the terms are accepted or declined, not skipped
      child: Scaffold(
        appBar: const StatusBarStrip(),
        backgroundColor: AppTokens.screenBackground,
        body: doc == null
            ? const Center(child: CircularProgressIndicator())
            : _body(doc, vm),
      ),
    );
  }

  Widget _body(Map<String, dynamic> doc, AuthViewModel? vm) {
    final mustBeMinor = _mustBeMinor(vm);
    final minor = mustBeMinor ? true : _minor;
    final reason = switch (vm?.termsReason) {
      TermsReason.updated => _ui('updated'),
      TermsReason.guardianNeeded => _ui('guardian_needed'),
      _ => _ui('first_time'),
    };
    final contact = doc['contact'] as String;
    final version = (_l['version_line'] as String)
        .replaceAll('{version}', doc['version'] as String)
        .replaceAll('{date}', (doc['effective'] as Map)[_lang] as String);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _l['title'] as String,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppTokens.ink,
                ),
              ),
            ),
            if (widget.readOnly)
              IconButton(
                tooltip: _ui('close'),
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close, color: AppTokens.ink),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(version, style: const TextStyle(color: AppTokens.inkMuted)),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'en', label: Text('English')),
            ButtonSegment(value: 'ms', label: Text('Bahasa Melayu')),
          ],
          selected: {_lang},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _lang = s.first),
        ),
        if (!widget.readOnly) ...[
          const SizedBox(height: 14),
          _Banner(reason),
        ],
        for (final s in (_l['sections'] as List).cast<Map<String, dynamic>>()) ...[
          const SizedBox(height: 18),
          Text(
            s['heading'] as String,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppTokens.ink,
            ),
          ),
          for (final p in (s['paragraphs'] as List).cast<String>()) ...[
            const SizedBox(height: 8),
            Text(
              p.replaceAll('{contact}', contact),
              style: const TextStyle(
                fontSize: 15,
                height: 1.45,
                color: AppTokens.textBody,
              ),
            ),
          ],
        ],
        if (vm != null) ..._acceptance(vm, mustBeMinor, minor),
        if (widget.readOnly) ...[
          const SizedBox(height: 24),
          PillButton(
            label: _ui('close'),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ],
    );
  }

  List<Widget> _acceptance(AuthViewModel vm, bool mustBeMinor, bool? minor) {
    final error = switch (vm.termsState) {
      UiError(:final message) => message,
      _ => null,
    };
    return [
      const SizedBox(height: 24),
      const Divider(),
      const SizedBox(height: 12),
      Text(
        _ui('age_question'),
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppTokens.ink,
        ),
      ),
      const SizedBox(height: 8),
      SegmentedButton<bool>(
        key: const Key('age_group'),
        segments: [
          ButtonSegment(
            value: false,
            enabled: !mustBeMinor,
            label: Text(_ui('age_adult')),
          ),
          ButtonSegment(value: true, label: Text(_ui('age_minor'))),
        ],
        selected: {?minor},
        emptySelectionAllowed: true,
        showSelectedIcon: false,
        onSelectionChanged: (s) => setState(() => _minor = s.firstOrNull),
      ),
      const SizedBox(height: 6),
      Text(_ui('age_note'), style: const TextStyle(color: AppTokens.inkMuted)),
      if (minor == true) ...[
        const SizedBox(height: 16),
        Text(
          _ui('guardian_heading'),
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppTokens.ink,
          ),
        ),
        const SizedBox(height: 10),
        LabeledField(
          label: _ui('guardian_name'),
          controller: _guardianName,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        Text(
          _ui('guardian_relationship'),
          style: const TextStyle(color: AppTokens.inkMuted),
        ),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          key: const Key('guardian_relationship'),
          segments: [
            ButtonSegment(
              value: 'PARENT',
              label: Text(_ui('relationship_parent')),
            ),
            ButtonSegment(
              value: 'GUARDIAN',
              label: Text(_ui('relationship_guardian')),
            ),
          ],
          selected: {?_relationship},
          emptySelectionAllowed: true,
          showSelectedIcon: false,
          onSelectionChanged: (s) =>
              setState(() => _relationship = s.firstOrNull),
        ),
        const SizedBox(height: 6),
        _Tick(
          key: const Key('guardian_declaration'),
          value: _guardianAgreed,
          text: _ui('guardian_declaration'),
          onChanged: (v) => setState(() => _guardianAgreed = v),
        ),
      ],
      const SizedBox(height: 8),
      _Tick(
        key: const Key('agree_terms'),
        value: _agreeTerms,
        text: _ui('agree_terms'),
        onChanged: (v) => setState(() => _agreeTerms = v),
      ),
      _Tick(
        key: const Key('consent_health'),
        value: _consentHealth,
        text: _ui('consent_health'),
        onChanged: (v) => setState(() => _consentHealth = v),
      ),
      if (error != null) ...[
        const SizedBox(height: 8),
        AuthErrorBanner(error),
      ],
      const SizedBox(height: 16),
      PillButton(
        label: _ui('accept'),
        busy: vm.termsState is Loading,
        onPressed: minor != null && _canAccept(minor)
            ? () => _accept(vm, minor)
            : null,
      ),
      const SizedBox(height: 8),
      Center(
        child: TextButton(
          onPressed: vm.termsState is Loading ? null : () => _decline(vm),
          child: Text(
            _ui('decline'),
            style: const TextStyle(color: AppTokens.inkMuted, fontSize: 16),
          ),
        ),
      ),
    ];
  }
}

class _Banner extends StatelessWidget {
  final String text;
  const _Banner(this.text);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppTokens.warnContainer,
      borderRadius: BorderRadius.circular(AppTokens.radiusCard),
    ),
    child: Text(
      text,
      style: const TextStyle(color: AppTokens.onWarn, fontSize: 15),
    ),
  );
}

/// A tick box with a long label that can be tapped too.
class _Tick extends StatelessWidget {
  final bool value;
  final String text;
  final ValueChanged<bool> onChanged;
  const _Tick({
    super.key,
    required this.value,
    required this.text,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => onChanged(!value),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
          const SizedBox(width: 4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: AppTokens.ink,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
