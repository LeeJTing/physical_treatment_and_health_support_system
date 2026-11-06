import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/server_connection_service/server_status.dart';
import 'package:physical_treatment_and_health_support_system/view/common/primary_button.dart';
import 'package:physical_treatment_and_health_support_system/view/profile_view/widgets/profile_widgets.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/server_settings_view_model/server_settings_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';

/// Profile > AI server. The AI server runs on the team's laptop; its address is typed here and
/// checked with Test connection, so a new Wi-Fi network or tunnel address needs no new build.
class ServerSettingsView extends StatefulWidget {
  const ServerSettingsView({super.key});

  @override
  State<ServerSettingsView> createState() => _ServerSettingsViewState();
}

class _ServerSettingsViewState extends State<ServerSettingsView> {
  late final TextEditingController _address;

  @override
  void initState() {
    super.initState();
    final vm = context.read<ServerSettingsViewModel>();
    _address = TextEditingController(text: vm.address);
    WidgetsBinding.instance.addPostFrameCallback((_) => vm.test());
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ServerSettingsViewModel>();
    final busy = vm.status is Loading;
    return Scaffold(
      backgroundColor: AppTokens.screenBackground,
      appBar: AppBar(title: const Text('AI server')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            const Text(
              'Food recognition, diet plans, health analysis, treatment plans, the chatbot and the '
              'posture check run on the AI server on the laptop.',
              style: TextStyle(fontSize: 16, color: AppTokens.inkMuted),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _address,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Server address',
                hintText: 'http://192.168.1.20:8000',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Built-in address: ${vm.defaultAddress}${vm.usingDefault ? ' (in use)' : ''}',
              style: const TextStyle(fontSize: 13, color: AppTokens.inkMuted),
            ),
            const SizedBox(height: 16),
            _StatusCard(vm.status),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Save and use this address',
              busy: busy,
              onPressed: () => vm.save(_address.text),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : () => vm.test(_address.text),
                    child: const Text('Test connection'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy
                        ? null
                        : () async {
                            await vm.useDefault();
                            _address.text = vm.address;
                          },
                    child: const Text('Use built-in'),
                  ),
                ),
              ],
            ),
            if (vm.notice != null) ...[
              const SizedBox(height: 14),
              InfoBanner(vm.notice!, icon: Icons.info_outline, tone: BannerTone.info),
            ],
            const SizedBox(height: 24),
            const SectionTitle('Which address?'),
            const SizedBox(height: 8),
            const Text(
              'Same Wi-Fi as the laptop: the address run_server.ps1 -Lan prints, for example '
              'http://192.168.1.20:8000 (test builds only).\n\n'
              'Anywhere, also on mobile data: the https://….trycloudflare.com address run_tunnel.ps1 '
              'prints. It changes each time the tunnel starts, so save the new one here.',
              style: TextStyle(fontSize: 15, color: AppTokens.ink),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final UiState<ServerStatus> state;
  const _StatusCard(this.state);

  @override
  Widget build(BuildContext context) => switch (state) {
    Idle() => const SizedBox.shrink(),
    Loading() => const Row(
      children: [
        SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 12),
        Text('Checking the AI server...', style: TextStyle(fontSize: 15)),
      ],
    ),
    UiError(:final message) => InfoBanner(message, icon: Icons.cloud_off_outlined),
    UiSuccess(:final data) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTokens.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Connected',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTokens.ink),
                ),
              ),
              StatusPill('${data.latencyMs} ms', good: data.latencyMs < 1500),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${data.address} · version ${data.version}',
            style: const TextStyle(fontSize: 13, color: AppTokens.inkMuted),
          ),
          for (final e in data.modules.entries) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  e.value == 'ready' ? Icons.check_circle_outline : Icons.hourglass_empty,
                  size: 20,
                  color: e.value == 'ready' ? AppTokens.good : AppTokens.caution,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(ServerStatus.labels[e.key] ?? e.key)),
                Text(
                  switch (e.value) {
                    'ready' => 'Ready',
                    'loading' => 'Starting up',
                    _ => 'Not available',
                  },
                  style: const TextStyle(color: AppTokens.inkMuted),
                ),
              ],
            ),
          ],
        ],
      ),
    ),
  };
}
