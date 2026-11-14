# Phoneme Party (App)

**📲 [Download for Android (APK)](https://github.com/guettli/pp-app/releases/latest/download/phoneme-party.apk)**
· older 32-bit phones: [armv7 APK](https://github.com/guettli/pp-app/releases/latest/download/phoneme-party-armv7.apk)
· [all releases](https://github.com/guettli/pp-app/releases)

Open the link on the phone, tap the downloaded file and allow "install
unknown apps" once. Updates install the same way, over the old version; the
stars are kept.

Speaking clearly should be fun. A free, offline pronunciation game for kids,
built with Flutter. Native successor of the web app
[guettli/pp](https://github.com/guettli/pp).

- **Offline, no server, no AI token.** Speech recognition runs on the phone.
  The recording never leaves the device.
- Five study languages: German (de-DE), British English (en-GB), French
  (fr-FR), Italian (it-IT), Spanish (es-ES), about 165 words each.
- Only concrete things kids know (animals, food, body, toys, vehicles,
  numbers …) with a picture that makes everybody think of the same word.
  The list is curated in `tool/words.tsv`.
- Android first (the target group: kids in developing countries on cheap
  phones). iOS is scaffolded but not built or tested yet.

## How the game works

1. Worlds of 8 phrases, easy first. A world opens once the previous one has
   on average one star per phrase.
2. The child sees a picture, the phone says the phrase (device TTS, 👂), then
   listens by itself (🎤 red, "your turn"). No button is needed: recording
   stops after 1 s of silence once the child has spoken
   (`lib/phonetics/endpointer.dart`), after 5 s without speech, or at the
   time limit (6–12 s, by phrase length). Tapping 🎤 stops early.
3. The rocket flies as high as the pronunciation was clear. 3 stars = the
   planet is reached. 🎤 repeats the round (hear, then speak), 🔊 or the
   picture only repeats the phrase, ➡ goes to the next phrase, which starts
   by itself.
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
# assets/phrases/*.json from tool/words.tsv; IPA from English Wiktionary,
# corrections in tool/ipa_overrides.tsv (cache dir avoids re-fetching)
python3 tool/build_words.py ~/.cache/pp-app-wiktionary
python3 tool/fetch_emoji.py <fluentui-emoji clone> emojis.txt   # assets/emoji/
dagger call -m ci panphon-features export --path assets/panphon/panphon_features.json
```

Word list rules (`tool/words.tsv`): one concept per line, a concrete thing a
3–8 year old knows, and an emoji that makes everybody think of the same
thing. If a picture has two common words in one language, both are listed as
`Karotte|Möhre`: the app says the first one, and the others are accepted too
(the child may know only the other word). A cell `-` leaves the word out in
that language.
Every picture was also checked as the Fluent 3D image itself (🧽 looks
like cheese, so it is not in the list). Plural
when the picture shows several (🍒 Kirschen).

Every merge to `main` publishes a GitHub release `v<major>.<minor>.<run>`
(major/minor from `pubspec.yaml`, the workflow run number is also the
Android versionCode) with both APKs. Pull requests get the APK as a workflow
artifact.

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

The key itself is kept in git, encrypted with [SOPS](https://getsops.io) and
age (`secrets/android-upload.enc.yaml`, recipient in `.sops.yaml`: the master
key of guettli/gitops). Losing it means no more updates for installed apps.
With `SOPS_AGE_KEY` set:

```sh
f=secrets/android-upload.enc.yaml
sops decrypt --extract '["keystore_base64"]' $f > upload.jks.b64
sops decrypt --extract '["keystore_password"]' $f > password
# restore the GitHub secrets
gh secret set KEYSTORE_BASE64 < upload.jks.b64
gh secret set KEYSTORE_PASSWORD < password
```

Do not commit the decrypted files (`*.jks`, `*.b64`, `password` are
ignored).

## Licenses

- Code: MIT (see `LICENSE`).
- Word list: own (MIT). IPA: [Wiktionary](https://en.wiktionary.org)
  (CC BY-SA 4.0), a few entries corrected by hand (`tool/ipa_overrides.tsv`).
- Pictures: [Microsoft Fluent Emoji](https://github.com/microsoft/fluentui-emoji)
  3D (MIT), converted to WebP; 🇮🇹 from Noto Emoji region flags (public domain).
- Phonetic features: [PanPhon](https://github.com/dmort27/panphon) (MIT).
- Model: [ZIPA](https://github.com/lingjzhu/zipa)
  `anyspeech/zipa-small-crctc-500k`, CC BY 4.0. (The noisy-student variant
  `-ns-700k` is CC BY-NC-SA; it scored the same on real recordings and worse
  on synthesized speech, see "Pronunciation check".)
