// Feedback: the outbox keeps reports until the service took them, and the
// screen sends only after the grown-ups' sum, showing what goes out.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/app_state.dart';
import 'package:phoneme_party/data/phrases.dart';
import 'package:phoneme_party/data/progress.dart';
import 'package:phoneme_party/net/feedback.dart';
import 'package:phoneme_party/phonetics/phoneme_distance.dart';
import 'package:phoneme_party/ui/feedback_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

class FakeTransport implements FeedbackTransport {
  final sent = <Map<String, dynamic>>[];
  SendResult Function() answer = () => SendResult.done;

  @override
  Future<SendResult> send(Map<String, dynamic> json) async {
    final r = answer();
    if (r == SendResult.done) sent.add(json);
    return r;
  }
}

FeedbackReport report(String text, {DateTime? created}) => FeedbackReport(
  id: FeedbackReport.newId(math.Random()),
  kind: FeedbackKind.bug,
  text: text,
  info: const {'app': '0.1.40'},
  created: created ?? DateTime.now(),
);

void main() {
  late SharedPreferences prefs;
  late FakeTransport net;
  late FeedbackOutbox outbox;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    net = FakeTransport();
    outbox = FeedbackOutbox(prefs, net);
  });

  test('sent at once when there is internet', () async {
    expect(await outbox.add(report('a')), isTrue);
    expect(net.sent.single['text'], 'a');
    expect(outbox.waiting, isEmpty);
  });

  test('kept without internet, sent later in order', () async {
    net.answer = () => SendResult.later;
    expect(await outbox.add(report('a')), isFalse);
    expect(await outbox.add(report('b')), isFalse);
    expect(outbox.waiting.map((r) => r.text), ['a', 'b']);
    // survives a restart
    final again = FeedbackOutbox(prefs, net);
    net.answer = () => SendResult.done;
    await again.flush();
    expect(net.sent.map((j) => j['text']), ['a', 'b']);
    expect(again.waiting, isEmpty);
  });

  test('a report the service rejects is dropped, the rest goes on', () async {
    net.answer = () => SendResult.later;
    await outbox.add(report('bad'));
    await outbox.add(report('good'));
    var n = 0;
    net.answer = () => n++ == 0 ? SendResult.rejected : SendResult.done;
    await outbox.flush();
    expect(net.sent.map((j) => j['text']), ['good']);
    expect(outbox.waiting, isEmpty);
  });

  test('old reports are given up, at most 20 wait', () async {
    net.answer = () => SendResult.later;
    await outbox.add(
      report('old', created: DateTime.now().subtract(const Duration(days: 40))),
    );
    for (var i = 0; i < 25; i++) {
      await outbox.add(report('$i'));
    }
    expect(outbox.waiting, hasLength(FeedbackOutbox.maxWaiting));
    expect(outbox.waiting.first.text, '5');
    net.answer = () => SendResult.done;
    await outbox.flush();
    expect(net.sent, hasLength(20));
  });

  test('two flushes at once send every report once', () async {
    net.answer = () => SendResult.later;
    await outbox.add(report('a'));
    net.answer = () => SendResult.done;
    await Future.wait([outbox.flush(), outbox.flush()]);
    expect(net.sent, hasLength(1));
  });

  test('a report survives a round trip through JSON', () {
    final r = report('ä ✓');
    final back = FeedbackReport.fromJson(
      jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>,
    );
    expect(back.text, r.text);
    expect(back.id, r.id);
    expect(back.info, r.info);
  });

  testWidgets('the screen: sum first, shows what is sent, sends', (t) async {
    final progress = await Progress.load();
    final raw = File('assets/phrases/de-DE.json').readAsStringSync();
    final book = PhraseBook('de-DE', [
      for (final j in (jsonDecode(raw) as List).cast<Map<String, dynamic>>())
        Phrase.fromJson(j),
    ]);
    final comparer = PhonemeComparer.fromJson(
      File('assets/panphon/panphon_features.json').readAsStringSync(),
    );
    final t0 = t.binding.clock.now();
    final dev = FakeDevices(IoLog(() => t.binding.clock.now().difference(t0)));
    final app = AppState(
      FakeRecognizer(() => ''),
      comparer,
      progress,
      book,
      io: dev.io,
      feedback: outbox,
    );
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => FeedbackScreen(
                    app: app,
                    info: () async => {'app': '0.1.40', 'phone': 'Test Phone'},
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('text')), findsNothing);
    // the sum: math.Random(1) of FakeDevices
    final q = find.textContaining('what is').evaluate().single.widget as Text;
    final m = RegExp(r'(\d+) \+ (\d+)').firstMatch(q.data!)!;
    await t.enterText(find.byKey(const Key('gate')), '99');
    await t.pump();
    expect(find.byKey(const Key('text')), findsNothing);
    await t.enterText(
      find.byKey(const Key('gate')),
      '${int.parse(m[1]!) + int.parse(m[2]!)}',
    );
    await t.pump();
    expect(find.text('phone: Test Phone'), findsOneWidget);
    expect(find.text('studyLang: de-DE'), findsOneWidget);
    await t.tap(find.text('Idea'));
    await t.enterText(find.byKey(const Key('text')), 'Mehr Tiere bitte');
    await t.pump();
    await t.tap(find.text('Send'));
    await t.pumpAndSettle();
    expect(net.sent.single['text'], 'Mehr Tiere bitte');
    expect(net.sent.single['kind'], 'idea');
    expect((net.sent.single['info'] as Map)['phone'], 'Test Phone');
    expect(find.text('Thank you! Sent.'), findsOneWidget);
  });
}
