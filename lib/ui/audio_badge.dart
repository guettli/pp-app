// What a game does with sound, shown on its home tile so grown-ups see
// at a glance whether the phone talks (🔊) and whether it listens (🎤).
// Both symbols are always there; the one a game does not use is crossed
// out, so "no sound at all" is as clear as "both".
import 'package:flutter/material.dart';

import 'strings.dart';

/// The four ways a game uses sound: does the phone talk (output), does it
/// listen to the child (input)?
enum Audio {
  none(talks: false, listens: false),
  input(talks: false, listens: true),
  output(talks: true, listens: false),
  both(talks: true, listens: true);

  const Audio({required this.talks, required this.listens});

  final bool talks;
  final bool listens;
}

class AudioBadge extends StatelessWidget {
  const AudioBadge(this.audio, {super.key, this.size = 18});

  final Audio audio;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    Widget one(
      bool on,
      IconData yes,
      IconData no,
      String sayOn,
      String sayOff,
    ) {
      return Tooltip(
        message: on ? sayOn : sayOff,
        child: Icon(
          on ? yes : no,
          size: size,
          color: on ? const Color(0xFFFFD54F) : Colors.white38,
        ),
      );
    }

    return Container(
      key: ValueKey('audio-${audio.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          one(
            audio.talks,
            Icons.volume_up,
            Icons.volume_off,
            s.phoneTalks,
            s.phoneSilent,
          ),
          SizedBox(width: size / 3),
          one(
            audio.listens,
            Icons.mic,
            Icons.mic_off,
            s.phoneListens,
            s.phoneDeaf,
          ),
        ],
      ),
    );
  }
}
