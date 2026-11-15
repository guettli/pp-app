// Feedback and bug reports, for grown-ups: behind a small sum (children
// should not send reports by accident; the Play Store asks for such a gate
// in apps for children). The screen shows everything that is sent.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../net/device_info.dart';
import '../net/feedback.dart';
import 'strings.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key, required this.app, this.info = deviceInfo});

  final AppState app;

  /// App version, phone and Android version (replaced in tests).
  final Future<Map<String, String>> Function() info;

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  late final math.Random _rng = widget.app.io.random();
  late final int _a = 3 + _rng.nextInt(7), _b = 3 + _rng.nextInt(7);
  final _answer = TextEditingController();
  final _text = TextEditingController();
  bool _unlocked = false;
  FeedbackKind _kind = FeedbackKind.bug;
  Map<String, String> _device = const {};
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    widget.info().then((d) {
      if (mounted) setState(() => _device = d);
    });
  }

  @override
  void dispose() {
    _answer.dispose();
    _text.dispose();
    super.dispose();
  }

  /// Everything that is sent besides the text.
  Map<String, String> _info(BuildContext context) => {
    ..._device,
    'studyLang': widget.app.book.lang,
    'uiLang': Localizations.maybeLocaleOf(context)?.languageCode ?? '',
  };

  Future<void> _send() async {
    final outbox = widget.app.feedback;
    final text = _text.text.trim();
    if (outbox == null || text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final s = S.of(context);
    final report = FeedbackReport(
      id: FeedbackReport.newId(math.Random.secure()),
      kind: _kind,
      text: text,
      info: _info(context),
      created: DateTime.now(),
    );
    final messenger = ScaffoldMessenger.of(context);
    final state = await outbox.add(report);
    final message = switch (state) {
      ReportState.sent => s.feedbackSent,
      ReportState.waiting => s.feedbackQueued,
      ReportState.rejected => s.tryAgain,
    };
    messenger.showSnackBar(SnackBar(content: Text(message)));
    if (!mounted) return;
    if (state == ReportState.rejected) {
      setState(() => _sending = false); // the text is still there
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.feedbackTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: _unlocked ? _form(s) : _gate(s),
        ),
      ),
    );
  }

  List<Widget> _gate(S s) => [
    Text(s.parentGate(_a, _b), style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 16),
    TextField(
      key: const Key('gate'),
      controller: _answer,
      keyboardType: TextInputType.number,
      autofocus: true,
      onChanged: (v) {
        if (int.tryParse(v.trim()) == _a + _b) {
          setState(() => _unlocked = true);
        }
      },
    ),
  ];

  List<Widget> _form(S s) {
    final info = _info(context);
    final kinds = {
      FeedbackKind.bug: s.kindBug,
      FeedbackKind.idea: s.kindIdea,
      FeedbackKind.word: s.kindWord,
      FeedbackKind.other: s.kindOther,
    };
    return [
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final MapEntry(key: k, value: label) in kinds.entries)
            ChoiceChip(
              label: Text(label),
              selected: _kind == k,
              onSelected: (_) => setState(() => _kind = k),
            ),
        ],
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('text'),
        controller: _text,
        minLines: 4,
        maxLines: 10,
        maxLength: FeedbackReport.maxText,
        decoration: InputDecoration(
          hintText: s.feedbackHint,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 8),
      Text(s.feedbackSends),
      for (final e in info.entries)
        Text(
          '${e.key}: ${e.value}',
          style: const TextStyle(color: Colors.black54),
        ),
      const SizedBox(height: 8),
      Text(s.feedbackPublic, style: const TextStyle(color: Colors.black54)),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _text.text.trim().isEmpty || _sending ? null : _send,
        child: _sending
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(s.send),
      ),
    ];
  }
}
