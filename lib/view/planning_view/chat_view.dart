import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/chatbot_service/chat_reply.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/chat_view_model/chat_view_model.dart';
import 'package:physical_treatment_and_health_support_system/view/planning_view/widgets/planning_widgets.dart';

/// Chatbot interface within the AI-assisted planning module (FR500_17 to FR500_23).
/// No Figma frame exists for it, so it uses the planning screens' tokens.
class ChatView extends StatefulWidget {
  /// Route of the screen that opened the chat (the planning page or Home). A
  /// button for that screen goes back to it instead of stacking a second copy.
  final String? openedFrom;

  const ChatView({super.key, this.openedFrom});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  int _shown = 0;

  /// Screens a chatbot button can open (ChatAction.key -> route).
  static const _actionRoutes = {
    'open_reset_password': Routes.resetPassword,
    'open_planning': Routes.treatmentPlanning,
    'open_profile': Routes.healthProfile,
    'open_treatment': Routes.physicalTreatment,
    'open_reminders': Routes.reminders,
    'open_history': Routes.sessionHistory,
    'open_age_limit': Routes.ageLimit, // chat-rules-3.49
  };

  /// Opens the screen behind a chatbot button, on top of the chat so Back
  /// returns to it. If the button is for the screen the chat was opened from,
  /// go back to that screen instead of stacking a second copy.
  ///
  /// Before, it popped every route down to Home first, so after "Open
  /// Profile" Back skipped the chat (Android 15 emulator, 10 Oct).
  void _openAction(ChatAction action) {
    final route = _actionRoutes[action.key];
    if (route == null) return;
    final nav = Navigator.of(context);
    if (route == widget.openedFrom && nav.canPop()) {
      nav.pop();
    } else {
      nav.pushNamed(
        route,
        arguments: route == Routes.ageLimit
            ? context.read<ChatViewModel>().age
            : null,
      );
    }
  }

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

  /// "Report this answer" (Elwin, 11 Oct): what the patient expected and the
  /// topic they meant, both optional, saved for review.
  Future<void> _report(ChatEntry answer) async {
    final vm = context.read<ChatViewModel>();
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTokens.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ChangeNotifierProvider.value(
        value: vm,
        child: _ReportSheet(answer: answer),
      ),
    );
    if (sent == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(Messages.chatReportSent)));
    }
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
                            _MessageTile(
                              entry: e,
                              onChoose: vm.choose,
                              onAction: _openAction,
                              onReport: vm.canReport(e)
                                  ? () => _report(e)
                                  : null,
                              reported: vm.isReported(e),
                            ),
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

  final void Function(ChatAction) onAction;

  /// Null when the answer cannot be reported (the welcome, an error, or
  /// already reported).
  final VoidCallback? onReport;
  final bool reported;

  const _MessageTile({
    required this.entry,
    required this.onChoose,
    required this.onAction,
    this.onReport,
    this.reported = false,
  });

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
              // One note per line, so several are not run together into one paragraph.
              child: NoticeBanner(
                reply.notes.length == 1
                    ? reply.notes.single
                    : reply.notes.map((n) => '• $n').join('\n'),
                warning: true,
              ),
            ),
          ],
          // Buttons to the screens the answer names: the first filled, a second outlined. An
          // arrow, not "open in new": they open a screen in the app, and Back returns here.
          if (reply != null && reply.actions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: mine ? WrapAlignment.end : WrapAlignment.start,
              children: [
                for (final (i, action) in reply.actions.indexed)
                  i == 0
                      ? FilledButton.icon(
                          onPressed: () => onAction(action),
                          icon: const Icon(Icons.arrow_forward, size: 18),
                          label: Text(action.label),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTokens.primary,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(48, AppTokens.minTarget),
                            shape: const StadiumBorder(),
                            textStyle: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      : OutlinedButton.icon(
                          onPressed: () => onAction(action),
                          icon: const Icon(Icons.arrow_forward, size: 18),
                          label: Text(action.label),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTokens.primary,
                            side: const BorderSide(color: AppTokens.primary),
                            minimumSize: const Size(48, AppTokens.minTarget),
                            shape: const StadiumBorder(),
                            textStyle: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
              ],
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
          if (reported)
            const Padding(
              padding: EdgeInsets.only(top: 4, left: 4),
              child: Text(
                'Reported, thank you',
                style: TextStyle(fontSize: 14, color: AppTokens.textMuted),
              ),
            )
          else if (onReport != null)
            TextButton.icon(
              onPressed: onReport,
              icon: const Icon(Icons.flag_outlined, size: 18),
              label: const Text('Report this answer'),
              style: TextButton.styleFrom(
                foregroundColor: AppTokens.textMuted,
                minimumSize: const Size(48, AppTokens.minTarget),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                textStyle: const TextStyle(fontSize: 14),
              ),
            ),
        ],
      ),
    );
  }
}

/// The report sheet: the question the patient asked, what they expected
/// (optional) and the topic they meant (optional).
class _ReportSheet extends StatefulWidget {
  final ChatEntry answer;
  const _ReportSheet({required this.answer});

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _expected = TextEditingController();
  String? _topic;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _expected.dispose();
    super.dispose();
  }

  Future<void> _sendReport() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await context.read<ChatViewModel>().report(
      widget.answer,
      expected: _expected.text,
      wantedCategory: _topic,
    );
    if (!mounted) return;
    if (res.isSuccess) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error = Messages.chatReportFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ChatViewModel>();
    final question = vm.questionFor(widget.answer)?.message.messageText ?? '';
    final topics = switch (vm.categories) {
      UiSuccess(:final data) => data,
      _ => const <ChatCategory>[],
    };
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.gutter,
            16,
            AppTokens.gutter,
            AppTokens.gutter,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Report this answer',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.text,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'We check every report before the chatbot is changed.',
                style: TextStyle(fontSize: 14, color: AppTokens.textMuted),
              ),
              const SizedBox(height: 16),
              Text(
                'You asked: \u201c$question\u201d',
                style: const TextStyle(fontSize: 15, color: AppTokens.text),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _expected,
                maxLength: 500,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'What did you expect? (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              if (topics.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'Which topic did you mean? (optional)',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in topics)
                      ChoiceChip(
                        label: Text(c.title),
                        selected: _topic == c.key,
                        selectedColor: AppTokens.accentContainer,
                        onSelected: (on) =>
                            setState(() => _topic = on ? c.key : null),
                      ),
                  ],
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                NoticeBanner(_error!, warning: true),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTokens.primary,
                        minimumSize: const Size(48, AppTokens.minTarget),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : _sendReport,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTokens.primary,
                        minimumSize: const Size(48, AppTokens.minTarget),
                      ),
                      child: const Text('Send report'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
