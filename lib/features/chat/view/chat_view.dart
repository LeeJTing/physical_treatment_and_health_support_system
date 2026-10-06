import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/base/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/features/chat/model/chat_reply.dart';
import 'package:physical_treatment_and_health_support_system/features/chat/viewmodel/chat_view_model.dart';
import 'package:physical_treatment_and_health_support_system/features/planning/widgets/planning_widgets.dart';

/// Chatbot interface within the AI-assisted planning module (FR500_17 to FR500_23).
/// No Figma frame exists for it, so it uses the planning screens' tokens.
class ChatView extends StatefulWidget {
  const ChatView({super.key});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  int _shown = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<ChatViewModel>().loadCategories(),
    );
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  });

  void _exit() {
    context.read<ChatViewModel>().close();
    Navigator.of(
      context,
    ).pop(); // FR500_23: back to the AI-assisted planning page
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    await context.read<ChatViewModel>().ask(text);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ChatViewModel>();
    if (vm.messages.length != _shown) {
      _shown = vm.messages.length;
      _scrollToEnd();
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit();
      },
      child: Scaffold(
        backgroundColor: AppTokens.background,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, AppTokens.gutter, 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: PlanningHeader(
                        title: 'Chat bot',
                        subtitle: 'Ask about your rehabilitation',
                        onBack: _exit,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: OutlinedButton(
                        onPressed: _exit,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTokens.primary,
                          side: const BorderSide(
                            color: AppTokens.primary,
                            width: 1.5,
                          ),
                          minimumSize: const Size(0, 40),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppTokens.radiusButton,
                            ),
                          ),
                        ),
                        child: const Text(
                          'Exit chatbot',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: vm.categoriesFailed && vm.messages.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(AppTokens.gutter),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            NoticeBanner(vm.categoriesError, warning: true),
                            const SizedBox(height: AppTokens.gutter),
                            TokenButton(
                              label: 'Try again',
                              color: AppTokens.primary,
                              onPressed: vm.retry,
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(
                          AppTokens.gutter,
                          8,
                          AppTokens.gutter,
                          8,
                        ),
                        children: [
                          if (vm.categories is Loading && vm.messages.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 40),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: AppTokens.primary,
                                ),
                              ),
                            ),
                          for (final e in vm.messages)
                            _MessageTile(entry: e, onChoose: vm.choose),
                          if (vm.sending) const _Typing(),
                        ],
                      ),
              ),
              _Topics(
                state: vm.categories,
                onChoose: vm.choose,
                enabled: !vm.sending,
              ),
              _InputBar(
                controller: _input,
                onSend: _send,
                enabled: !vm.sending,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  final ChatEntry entry;
  final void Function(ChatCategory) onChoose;

  const _MessageTile({required this.entry, required this.onChoose});

  @override
  Widget build(BuildContext context) {
    final mine = entry.fromPatient;
    final reply = entry.reply;
    final urgent = reply?.isUrgent ?? false;
    final notRecognised = !mine && !entry.message.isMatched;
    final text = reply?.mainAnswer ?? entry.message.messageText;

    final Color bg = mine
        ? AppTokens.primary
        : urgent
        ? AppTokens.dangerContainer
        : notRecognised
        ? AppTokens.cautionContainer
        : AppTokens.surface;
    final Color fg = mine
        ? Colors.white
        : urgent
        ? AppTokens.onDanger
        : notRecognised
        ? AppTokens.caution
        : AppTokens.text;

    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.8,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        border: mine
            ? null
            : Border.all(
                color: urgent ? AppTokens.danger : AppTokens.border,
                width: urgent ? 1.5 : 1,
              ),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(mine ? 16 : 4),
          bottomRight: Radius.circular(mine ? 4 : 16),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (urgent) ...[
            const Icon(
              Icons.warning_amber_rounded,
              color: AppTokens.danger,
              size: 22,
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              text,
              style: TextStyle(fontSize: 16, height: 1.4, color: fg),
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          bubble,
          if (reply != null && reply.notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.8,
              ),
              child: NoticeBanner(reply.notes.join(' '), warning: true),
            ),
          ],
          if (reply != null && reply.followUps.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in reply.followUps)
                  _Choice(category: c, onTap: () => onChoose(c)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  final ChatCategory category;
  final VoidCallback? onTap;

  const _Choice({required this.category, this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: AppTokens.accentContainer,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            category.title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTokens.accent,
            ),
          ),
        ),
      ),
    ),
  );
}

class _Topics extends StatelessWidget {
  final UiState<List<ChatCategory>> state;
  final void Function(ChatCategory) onChoose;
  final bool enabled;

  const _Topics({
    required this.state,
    required this.onChoose,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final cats = switch (state) {
      UiSuccess(:final data) => data,
      _ => const <ChatCategory>[],
    };
    if (cats.isEmpty) return const SizedBox.shrink();
    return Container(
      color: AppTokens.background,
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.gutter),
          itemCount: cats.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) => _Choice(
            category: cats[i],
            onTap: enabled ? () => onChoose(cats[i]) : null,
          ),
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool enabled;

  const _InputBar({
    required this.controller,
    required this.onSend,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(AppTokens.gutter, 8, 8, 8),
    decoration: const BoxDecoration(
      color: AppTokens.surface,
      border: Border(top: BorderSide(color: AppTokens.border)),
    ),
    child: SafeArea(
      top: false,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              maxLength: 500,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              style: const TextStyle(fontSize: 16, color: AppTokens.text),
              decoration: InputDecoration(
                hintText: 'Type your question',
                counterText: '',
                filled: true,
                fillColor: AppTokens.background,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filled(
            onPressed: enabled ? onSend : null,
            tooltip: 'Send',
            style: IconButton.styleFrom(
              backgroundColor: AppTokens.primary,
              minimumSize: const Size(48, 48),
            ),
            icon: const Icon(Icons.send_rounded, color: Colors.white),
          ),
        ],
      ),
    ),
  );
}

class _Typing extends StatelessWidget {
  const _Typing();

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        border: Border.all(color: AppTokens.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppTokens.accent,
        ),
      ),
    ),
  );
}
