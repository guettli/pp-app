# Phoneme Party (App)

Speaking clearly should be fun. A free, offline pronunciation game for kids,
built with Flutter. Native successor of the web app
[guettli/pp](https://github.com/guettli/pp).

- **Offline, no server, no AI token.** Speech recognition runs on the phone.
  The recording never leaves the device.
- Five study languages: German (de-DE), British English (en-GB), French
  (fr-FR), Italian (it-IT), Spanish (es-ES), 816 phrases each (from pp).
- Android first (the target group: kids in developing countries on cheap
  phones). iOS is scaffolded but not built or tested yet.

## How the game works

1. Worlds of 8 phrases, easy first. A world opens once the previous one has
   on average one star per phrase.
2. The child sees a picture, taps it (or 🔊) to hear the phrase (device TTS),
   then taps 🎤 and speaks.
3. The rocket flies as high as the pronunciation was clear. 3 stars = the
   planet is reached. Recording stops by tap or after 4–10 s, depending on
   the phrase length.
4. Every expected sound is shown as a chip: green = right, orange = close,
   red = missing / wrong.

## How recognition works

```
mic (16 kHz PCM) -> silence trim -> Kaldi fbank (80 mel, Dart)
  -> ZIPA small CR-CTC (ONNX Runtime, int8, 71 MB) -> greedy CTC decode -> IPA
  -> alignment with the phrase IPA (PanPhon features) -> score / stars
```

- `lib/phonetics/fbank.dart` is a port of pp's Zig/WASM fbank and is tested
  against features computed by Lhotse itself on a real recording.
- `lib/phonetics/ctc_decoder.dart` ports pp's decoder heuristics.
- `lib/phonetics/phoneme_distance.dart` ports pp's PanPhon alignment, with
  fixes (see the header comment and the tests):
  - the zero-width joiner in en-GB IPA (`t‍ʃ`) is ignored,
  - `g` is mapped to IPA `ɡ` (pp did the reverse, so PanPhon did not know `g`),
  - word boundaries survive insertions,
  - silence scores 0 (pp: 0.5),
  - stars use the phoneme hit rate, not the feature similarity: a completely
    different phrase got ~0.7–0.8 in pp, i.e. 2–3 stars.

## Development

Flutter is **not** installed on the dev host. Everything runs in containers
via [Dagger](https://dagger.io) (`ci/main.go`):

```sh
dagger call -m ci check-fast                     # format + analyze + tests
dagger call -m ci format-write export --path .   # apply dart format
dagger call -m ci build-apk export --path build/phoneme-party.apk
```

Data generation (only needed when the source data changes):

```sh
python3 tool/build_phrases.py ../pp > emojis.txt      # assets/phrases/*.json
python3 tool/fetch_emoji.py <fluentui-emoji clone> emojis.txt   # assets/emoji/
dagger call -m ci panphon-features export --path assets/panphon/panphon_features.json
```

The ONNX model is downloaded during `build-apk` (pinned Hugging Face revision,
checked by sha256) and never committed.

### Signing

Android only installs an update if it is signed with the same key as the
installed app. Without a keystore every build gets a fresh debug key, so a
new APK cannot replace an old one (and uninstalling deletes the child's
stars). Release builds therefore use an upload key:

```sh
dagger call -m ci build-apk \
  --keystore-base-64 file:upload.jks.b64 --keystore-password file:password \
  export --path build/phoneme-party.apk
```

In GitHub Actions the repository secrets `KEYSTORE_BASE64` (base64 of the
PKCS12 keystore, alias `upload`) and `KEYSTORE_PASSWORD` are used when set;
otherwise CI falls back to a debug key.

## Licenses

- Code: MIT (see `LICENSE`).
- Phrases and IPA: from [guettli/pp](https://github.com/guettli/pp) (MIT).
- Pictures: [Microsoft Fluent Emoji](https://github.com/microsoft/fluentui-emoji)
  3D (MIT); 🇮🇹 from Noto Emoji region flags (public domain).
- Phonetic features: [PanPhon](https://github.com/dmort27/panphon) (MIT).
- Model: [ZIPA](https://github.com/lingjzhu/zipa)
  `anyspeech/zipa-small-crctc-ns-700k`, **CC BY-NC-SA 4.0** (non-commercial).
  A CC BY 4.0 alternative with slightly lower accuracy is
  `anyspeech/zipa-small-crctc-500k` (switch in `ci/main.go`).
