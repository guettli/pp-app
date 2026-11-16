# Der Hase lacht (App)

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
  (fr-FR), Italian (it-IT), Spanish (es-ES), about 170 words each.
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

## More games (above the worlds)

- **🦉 Quiz:** the phone asks "Was kann fliegen? Baum, Vogel oder Haus?",
  shows the three pictures, and the child answers by saying the word.
  Eight questions a round about the words of the open worlds: what flies,
  swims, can be eaten, has wheels, … and what is biggest, smallest,
  heaviest, lightest. The facts are in `assets/facts/facts.tsv` (one line
  per picture, the same for every language): every property is yes, no or
  unclear, and only clear "no"s are offered as wrong answers. A word the
  phone did not understand is asked once more instead of being marked wrong.
- **🎈 Hold it long** and **🐻🐭 Low and high:** voice games without words
  (`lib/voice/`); the sound is only measured, never recorded.
- **📖 Word list:** every word with picture, rough size and weight and its
  properties; tapping a word says it.

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

## Google Play

Every release also carries `phoneme-party-google-play.aab`, the App Bundle
signed with the upload key (`dagger call -m ci build-aab ...`; Play App
Signing re-signs what phones get). It is checked like the APK: package id,
name, permissions, versionCode = build number, not a debug key.

- Listing texts: `fastlane/metadata/android/<locale>/` (title,
  short and full description; `test/store_listing_test.dart` checks
  Google's length limits). Default language en-US.
- Privacy policy: [PRIVACY.md](PRIVACY.md) (English and German); URL for
  the Play Console: <https://github.com/guettli/pp-app/blob/main/PRIVACY.md>.
- Renaming the app: the shown name is in `android/app/build.gradle.kts`
  (`appLabel`), `lib/main.dart`, `lib/ui/strings.dart` (title and the
  feedback texts), `ios/Runner/Info.plist`, `fastlane/metadata/android/*/`
  (title ≤ 30 characters, descriptions) and `PRIVACY.md`. The package id
  `de.sharedinbox.pp2` stays: Google Play never lets it change.
- Up to v0.1.52 the app was "Phoneme Party" with id
  `de.relaxandplay.phoneme_party`; that one does not update to the new
  id, it stays installed beside it (uninstall it by hand).
- Phones that installed the GitHub APK cannot update to the Play version
  (other signature, unless Play App Signing uses our upload key as app
  signing key); switching means uninstalling, which deletes the stars.

Answers for the Play Console:

- **Target audience:** children (5 and under, 6–8, 9–12) → Families
  policy. **Ads:** no. **In-app purchases:** no.
- **Data safety:** data is collected (only the optional feedback report):
  - *App activity → Other user-generated content* (the typed text) and
    *App info and performance → Diagnostics* (app version, phone model,
    Android version, languages).
  - Optional (the user chooses to send it), purpose *App functionality*,
    not shared, encrypted in transit, deletion on request (the screen
    shows the report id; `kubectl -n pp-app exec deploy/feedback --
    /feedback delete <id>`), deleted automatically after 12 months.
  - *Audio → Voice or sound recordings*: only quiz reports (off until a
    grown-up switches them on behind the parent gate; each one sent by a
    tap on 🐞). Optional, purpose *App functionality* (improving the
    speech recognition), not shared, encrypted in transit, deleted after
    90 days (`server/feedback/quiz.go`), deletion on request
    (`/feedback delete <id>`; `/feedback quiz-list`, `/feedback cat
    <file>.wav` to listen). Otherwise audio is processed only on the
    device. Nothing else is collected (no ids, no location).
- **Permissions:** `RECORD_AUDIO` (the game), `INTERNET` (feedback).

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

### Pronunciation check

`tool/tts_check` speaks every word with two [Piper](https://github.com/rhasspy/piper)
voices per language, runs the app's own recognition pipeline (silence
trimming, level normalisation, fbank, ZIPA, CTC decoding, scoring) on it and
reports the stars per word:

```sh
dagger call -m ci tts-check export --path report.json        # ~20 min
python3 tool/tts_check/summary.py report.json
# variants: --voice thorsten, --options "gain=0.15 noise=0",
#   --model anyspeech/zipa-small-crctc-ns-700k,
#   --recordings <dir with recordings.json> (real recordings)
dagger call -m ci tts-rescore --report report.json export --path new.json
```

A word that gets few stars from every voice although it was pronounced
correctly points to a wrong IPA in the word list or a weakness of the
scoring. Synthesized adult speech is not a child, so the numbers are a
relative measure (model A vs. B, scoring before/after a change), not the
stars a child will get. Piper varies slightly between runs (±0.1 stars).

### Signing

Android only installs an update if it is signed with the same key as the
installed app. Without a keystore every build gets a fresh debug key, so a
new APK cannot replace an old one (and uninstalling deletes the child's
stars). Release builds therefore use an upload key:

```sh
dagger call -m ci build-apk \
  --keystore-base-64 file://upload.jks.b64 --keystore-password file://password \
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
