// Two phones play together: one child opens a match and shows four
// pictures, the other taps them in. The host's child sees the guest's
// animal and says yes (or no); then the phones are linked (lib/net/) and
// the game starts.
import 'dart:async';

import 'package:flutter/material.dart';

import '../net/match.dart';
import '../net/peer_link.dart';
import '../net/together.dart';
import '../ui/emoji_image.dart';
import '../ui/round_button.dart';
import '../ui/strings.dart';
import 'codes.dart';
import 'wave_game.dart';

enum _Step {
  choose,
  opening,
  showCode,
  ask,
  typeCode,
  joining,
  waitHost,
  connecting,
  play,
  failed,
}

/// Why the screen shows [_Step.failed].
enum _Why { taken, notAccepted, expired, offline, noLink }

class TogetherScreen extends StatefulWidget {
  const TogetherScreen({super.key, required this.together});

  final Together together;

  @override
  State<TogetherScreen> createState() => _TogetherScreenState();
}

class _TogetherScreenState extends State<TogetherScreen> {
  var _step = _Step.choose;
  HostMatch? _host;
  GuestMatch? _guest;
  PeerLink? _link;
  StreamSubscription<HostEvent>? _events;
  late final AppLifecycleListener _lifecycle;
  List<String> _code = const [];
  final _typed = <int>[];
  int? _animal; // the guest's
  bool _isHost = false;
  _Why _why = _Why.noLink;
  String? _note; // a wrong code, shown above the pictures
  var _gen = 0; // bumped on every new attempt; stale futures check it

  @override
  void initState() {
    super.initState();
    // Leaving the app while looking for a friend ends the search: nobody
    // waits for a phone in a pocket, and a code is not left open.
    _lifecycle = AppLifecycleListener(onHide: _hidden);
  }

  void _hidden() {
    if (const {
      _Step.opening,
      _Step.showCode,
      _Step.ask,
      _Step.joining,
      _Step.waitHost,
      _Step.connecting,
    }.contains(_step)) {
      _restart();
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _gen++;
    _closeAll();
    super.dispose();
  }

  void _closeAll() {
    unawaited(_events?.cancel());
    _events = null;
    unawaited(_host?.close());
    unawaited(_guest?.close());
    unawaited(_link?.close());
    _host = null;
    _guest = null;
    _link = null;
  }

  void _fail(_Why why) {
    if (!mounted) return;
    _closeAll();
    setState(() {
      _why = why;
      _step = _Step.failed;
    });
  }

  _Why _whyOf(Object e) => switch (e) {
    MatchError(failure: MatchFailure.offline) => _Why.offline,
    MatchError(failure: MatchFailure.taken) => _Why.taken,
    MatchError() => _isHost ? _Why.expired : _Why.notAccepted,
    _ => _Why.noLink,
  };

  Future<void> _open() async {
    final gen = ++_gen;
    setState(() {
      _isHost = true;
      _step = _Step.opening;
    });
    final host = _host = HostMatch(widget.together);
    try {
      final code = await host.open();
      if (!mounted || gen != _gen) return;
      _events = host.events.listen((e) {
        if (!mounted || gen != _gen) return;
        switch (e) {
          case Joined(:final animal):
            if (_step == _Step.showCode) {
              setState(() {
                _animal = animal;
                _step = _Step.ask;
              });
            }
          case GuestLeft():
            if (_step == _Step.ask) setState(() => _step = _Step.showCode);
          case MatchOver(:final error):
            _fail(_whyOf(error));
        }
      });
      setState(() {
        _code = codeToPictures(code);
        _step = _Step.showCode;
      });
    } catch (e) {
      if (gen == _gen) _fail(_whyOf(e));
    }
  }

  /// Back to the code, or straight to the next guest's animal.
  void _waitAgain(HostMatch host) {
    final next = host.waiting;
    setState(() {
      _animal = next;
      _step = next == null ? _Step.showCode : _Step.ask;
    });
  }

  Future<void> _answer(bool yes) async {
    final host = _host;
    if (host == null) return;
    final gen = _gen;
    if (!yes) {
      setState(() => _step = _Step.showCode);
      try {
        await host.reject();
      } catch (e) {
        if (gen == _gen) _fail(_whyOf(e));
      }
      return;
    }
    setState(() => _step = _Step.connecting);
    try {
      final link = await host.accept();
      if (!mounted || gen != _gen) {
        unawaited(link.close());
        return;
      }
      _play(link);
    } on MatchError catch (e) {
      if (!mounted || gen != _gen) return;
      // that guest went (or another came): the code is still open
      if (e.failure == MatchFailure.gone && e.detail != 'closed' ||
          e.failure == MatchFailure.taken) {
        _waitAgain(host);
      } else {
        _fail(_whyOf(e));
      }
    } catch (e) {
      if (gen == _gen) _fail(_whyOf(e));
    }
  }

  void _startTyping() {
    _gen++;
    setState(() {
      _isHost = false;
      _typed.clear();
      _note = null;
      _step = _Step.typeCode;
    });
  }

  Future<void> _type(int picture) async {
    if (_step != _Step.typeCode || _typed.length >= codeLength) return;
    setState(() {
      _note = null;
      _typed.add(picture);
    });
    if (_typed.length < codeLength) return;
    final gen = ++_gen;
    final code = picturesToCode(_typed);
    final guest = _guest = GuestMatch(widget.together);
    setState(() => _step = _Step.joining);
    try {
      final animal = await guest.join(code);
      if (!mounted || gen != _gen) return;
      setState(() {
        _animal = animal;
        _step = _Step.waitHost;
      });
      final link = await guest.connect();
      if (!mounted || gen != _gen) {
        unawaited(link.close());
        return;
      }
      _play(link);
    } on MatchError catch (e) {
      if (!mounted || gen != _gen) return;
      if (e.failure == MatchFailure.noSuchCode) {
        // mistyped: try again right here
        final s = S.of(context);
        _guest = null;
        setState(() {
          _typed.clear();
          _note = s.codeWrong;
          _step = _Step.typeCode;
        });
      } else {
        _fail(_whyOf(e));
      }
    } catch (e) {
      if (gen == _gen) _fail(_whyOf(e));
    }
  }

  void _play(PeerLink link) {
    unawaited(_events?.cancel());
    _events = null;
    setState(() {
      _link = link;
      _step = _Step.play;
    });
  }

  void _restart() {
    _gen++;
    _closeAll();
    setState(() {
      _animal = null;
      _step = _Step.choose;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF14143A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(s.togetherTitle),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: switch (_step) {
            _Step.choose => _choose(s),
            _Step.opening || _Step.joining => _busy(null),
            _Step.connecting => _busy(s.connecting),
            _Step.showCode => _showCode(s),
            _Step.ask => _ask(s),
            _Step.typeCode => _typeCode(s),
            _Step.waitHost => _waitHost(s),
            _Step.play => WaveGame(
              key: const ValueKey('together-play'),
              link: _link!,
              me: _isHost ? '🏠' : animalFor(_animal ?? 0),
              friend: _isHost ? animalFor(_animal ?? 0) : '🏠',
              onGone: _restart,
            ),
            _Step.failed => _failed(s),
          },
        ),
      ),
    );
  }

  Widget _text(String t, {double size = 22}) => Text(
    t,
    textAlign: TextAlign.center,
    style: TextStyle(color: Colors.white, fontSize: size),
  );

  Widget _choose(S s) => Center(
    child: SingleChildScrollView(
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 24,
        runSpacing: 24,
        children: [
          _bigChoice('together-open', '🏠', s.openMatch, _open),
          _bigChoice('together-join', '🚪', s.joinMatch, _startTyping),
        ],
      ),
    ),
  );

  Widget _bigChoice(
    String key,
    String emoji,
    String label,
    VoidCallback onTap,
  ) => SizedBox(
    width: 160,
    child: Material(
      color: const Color(0xFF2B2B6B),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        key: ValueKey(key),
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              EmojiImage(emoji, size: 80),
              const SizedBox(height: 8),
              _text(label, size: 18),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _busy(String? label) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(color: Colors.white),
        if (label != null) ...[const SizedBox(height: 16), _text(label)],
      ],
    ),
  );

  Widget _pictures(List<String> pics, {String keyPrefix = 'code'}) => FittedBox(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < codeLength; i++)
          Container(
            key: ValueKey('$keyPrefix-$i'),
            margin: const EdgeInsets.all(6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3D6),
              borderRadius: BorderRadius.circular(16),
            ),
            child: i < pics.length
                ? EmojiImage(pics[i], size: 64)
                : const SizedBox(width: 64, height: 64),
          ),
      ],
    ),
  );

  Widget _showCode(S s) => Center(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _text(s.showCode),
          const SizedBox(height: 16),
          _pictures(_code),
          const SizedBox(height: 24),
          const CircularProgressIndicator(color: Colors.white54),
        ],
      ),
    ),
  );

  Widget _ask(S s) => Center(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          EmojiImage(animalFor(_animal ?? 0), size: 120),
          const SizedBox(height: 8),
          _text(s.wantsToPlay, size: 26),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              RoundButton(
                key: const ValueKey('together-no'),
                tooltip: s.no,
                color: const Color(0xFFE57373),
                size: 96,
                onTap: () => _answer(false),
                child: const Icon(Icons.close, color: Colors.white, size: 56),
              ),
              const SizedBox(width: 40),
              RoundButton(
                key: const ValueKey('together-yes'),
                tooltip: s.yes,
                color: const Color(0xFF66BB6A),
                size: 96,
                onTap: () => _answer(true),
                child: const Icon(Icons.check, color: Colors.white, size: 56),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _typeCode(S s) => LayoutBuilder(
    builder: (context, c) {
      final wide = c.maxWidth > c.maxHeight;
      final cell = ((wide ? c.maxWidth / 2 : c.maxWidth) / 4 - 12).clamp(
        40.0,
        96.0,
      );
      final grid = Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < codePictures.length; i++)
            Material(
              color: const Color(0xFF2B2B6B),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                key: ValueKey('together-pic-$i'),
                borderRadius: BorderRadius.circular(14),
                onTap: () => _type(i),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: EmojiImage(codePictures[i], size: cell - 12),
                ),
              ),
            ),
        ],
      );
      final top = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _text(_note ?? s.typeCode, size: 20),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: _pictures([
                  for (final i in _typed) codePictures[i],
                ], keyPrefix: 'typed'),
              ),
              IconButton(
                key: const ValueKey('together-back'),
                tooltip: s.undo,
                onPressed: _typed.isEmpty
                    ? null
                    : () => setState(() => _typed.removeLast()),
                icon: const Icon(
                  Icons.backspace_outlined,
                  color: Colors.white,
                  size: 36,
                ),
              ),
            ],
          ),
        ],
      );
      return SingleChildScrollView(
        child: wide
            ? Row(
                children: [
                  Expanded(child: top),
                  Expanded(child: grid),
                ],
              )
            : Column(children: [top, const SizedBox(height: 16), grid]),
      );
    },
  );

  Widget _waitHost(S s) => Center(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _text(s.youAre),
          const SizedBox(height: 8),
          EmojiImage(animalFor(_animal ?? 0), size: 120),
          const SizedBox(height: 16),
          _text(s.waitForYes),
          const SizedBox(height: 24),
          const CircularProgressIndicator(color: Colors.white54),
        ],
      ),
    ),
  );

  Widget _failed(S s) => Center(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const EmojiImage('😕', size: 96),
          const SizedBox(height: 16),
          _text(switch (_why) {
            _Why.taken => s.codeTaken,
            _Why.notAccepted => s.notAccepted,
            _Why.expired => s.codeExpired,
            _Why.offline => s.offline,
            _Why.noLink => s.linkFailed,
          }),
          const SizedBox(height: 24),
          RoundButton(
            key: const ValueKey('together-again'),
            tooltip: s.tryAgain,
            color: const Color(0xFF5C6BC0),
            size: 96,
            onTap: _restart,
            child: const Icon(Icons.refresh, color: Colors.white, size: 56),
          ),
        ],
      ),
    ),
  );
}
