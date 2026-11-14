import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_state.dart';
import 'ui/emoji_image.dart';
import 'ui/home_screen.dart';
import 'ui/strings.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isIOS) {
    // audioplayers would switch the whole app to `playback`; the game also
    // records and speaks, so keep one session for all three, loud speaker.
    AudioPlayer.global.setAudioContext(
      AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playAndRecord,
          options: const {
            AVAudioSessionOptions.defaultToSpeaker,
            AVAudioSessionOptions.mixWithOthers,
          },
        ),
      ),
    );
  }
  runApp(const PhonemePartyApp());
}

class PhonemePartyApp extends StatelessWidget {
  const PhonemePartyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Phoneme Party',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF9100)),
        useMaterial3: true,
      ),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [
        Locale('en'),
        Locale('de'),
        Locale('fr'),
        Locale('it'),
        Locale('es'),
      ],
      home: const _Loader(),
    );
  }
}

class _Loader extends StatefulWidget {
  const _Loader();

  @override
  State<_Loader> createState() => _LoaderState();
}

class _LoaderState extends State<_Loader> {
  late final Future<AppState> _app = AppState.load();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppState>(
      future: _app,
      builder: (context, snap) {
        if (snap.hasData) return HomeScreen(app: snap.data!);
        return Scaffold(
          backgroundColor: const Color(0xFF14143A),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const EmojiImage('🚀', size: 96),
                const SizedBox(height: 24),
                if (snap.hasError)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '${snap.error}',
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  )
                else ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    S.of(context).loading,
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
