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

- **Offline, no AI token.** Speech recognition runs on the phone. The
  recording stays on the device, unless a grown-up switches on quiz reports
  (then 🐞 in the quiz sends that question with its recording, after
  asking; the dialog can play the recording first; see PRIVACY.md). Feedback and quiz reports go to `server/feedback`.
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

Above the worlds, the games are sorted into four groups, two big tiles a
row, by what the child practises: 👂 listening (listen closely, sound
detective), 📖 reading (word to picture, letter puzzle, read aloud),
🎤 speaking (hold it long, low and high) and 🤔 thinking (what do I
need, who am I, odd one out, who lives here, quiz). A group opens a screen with its games
(`lib/ui/game_tile.dart`).

Each game first says what to do, in the study language ("Hör gut zu und
sag das richtige Wort!", "… tippe auf das richtige Bild!", …,
`lib/ui/intros.dart`): a child who cannot read must know whether to tap
or to speak.

Every game tile shows what the game does with sound, for the
grown-ups: 🔊 the phone talks, 🎤 it listens; the one a game does not
use is crossed out (`lib/ui/audio_badge.dart`). Every game talks while
playing; the quiz, sound detective, read aloud, hold it long and low
and high also listen (and so do the worlds).

- **🦉 Quiz:** the phone asks "Was kann fliegen? Baum, Vogel oder Haus?",
  shows the three pictures, and the child answers by saying the word.
  Eight questions a round about the words of the open worlds: what flies,
  swims, can be eaten, has wheels, … and what is biggest, smallest,
  heaviest, lightest. The facts are in `assets/facts/facts.tsv` (one line
  per picture, the same for every language): every property is yes, no or
  unclear, and only clear "no"s are offered as wrong answers. A word the
  phone did not understand is asked once more instead of being marked wrong.
- **👂 Listen closely:** the phone says a word, the child taps its
  picture among four (no microphone, no reading). Eight words a round from
  the open worlds; in the second half one wrong picture sounds like the
  answer (Maus / Haus). A wrong tap: the phone says what that picture is
  and the word again; only the first tap counts for the stars.
- **📖 Word to picture:** like Listen closely, but the word is written
  and not said (silent reading). Later in the round one wrong picture is
  written alike (Hase / Hose). 🔊 says the word as a help; that word then
  gets no star.
- **📖🎤 Read aloud:** a word is written, nothing is said and no
  picture shown; the child reads it aloud. The phone listens by itself and
  scores it like the word game, then shows the picture and says the word.
  0 stars: once more. Six words a round, short ones first; the round's
  stars are the average.
- **🔔 Sound detective:** "What starts like Maus?" with the picture of
  the mouse; three pictures, one starts the same way (Mond), the child
  says it (the quiz with other questions, `lib/quiz/sound_rules.dart`).
  "The same way" is every consonant before the first vowel: Stuhl /ʃt/
  starts like Stern, not like Spinne /ʃp/ or Schuh /ʃ/. Words starting
  with a vowel are left out; the wrong ones start with a clearly
  different sound (PanPhon cost ≥ 0.2 for every part: never b against p,
  ts against t, Schuh against Stuhl).
- **✏️ Letters:** the picture, the phone says the word, and the child
  spells it by tapping letter tiles in order (the tiles as written in the
  word: H a i for Hai, a child need not match h to H; the tile must
  match exactly, the e of Ente is not its E). Six words a round, short ones first; later
  words get one or two extra tiles. A wrong tile shakes; after two wrong
  tiles for the same place the right one glows. A word without a wrong
  tile is a star. Multi-word phrases and words with hyphens are left out.
- **🧤☂️ What do I need?** (thinking, no letters, no numbers): the phone
  tells a small problem ("Meine Hände sind kalt. Was brauche ich?"), the
  child taps the picture that helps among three (🧤). Six problems a
  round. Anything that might help too if a child thinks around a corner
  (a hammer for a locked door) is never offered as a wrong picture. The
  texts in all languages are in `lib/think/think_data.dart`.
- **🐮🔊 Who am I?** a thing tells about itself, three clues from vague
  to clear ("Ich lebe auf dem Bauernhof." "Ich fresse Gras." "Ich sage
  Muh!"); the child taps one of four pictures when sure. 💡 gives the next
  clue at any time, waiting costs nothing; a wrong tap brings the next
  clue and costs the star. The last clue fits only the answer among all
  riddles.
- **🐶🐱🚗 Odd one out:** four pictures, three of one kind (animals,
  food, clothes, plants, things with wheels, instruments, body parts,
  things that shine; from `assets/facts/facts.tsv`) and one of another
  kind. After the right tap the phone says why ("Nase! Die anderen kann
  man anziehen."). Only pictures of exactly one kind take part (a fish is
  an animal and food); the odd one is clearly not of the three's kind and
  the three clearly not of its kind (a cow might be food: never three
  animals and a pizza); plants are never mixed with food (a carrot is
  both).
- **🌊🐟 Who lives here?** a place, shown big (🌊 sea, 🚜 farm, 🌳 forest,
  🌴 jungle, ❄️ ice, 🏜️ desert, 🏠 at home), and three animals; one lives
  there. Animals that might live there too (a penguin in the sea, a mouse
  in a house) are never offered as wrong pictures.
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

Installed from Play, the app updates itself (`lib/net/app_update.dart`,
Play in-app updates, flexible): at start it asks Play for a newer
version; Play asks once and downloads it in the background; the next
start installs it. Installed from an APK: no update check.

CI uploads each release's bundle to the **internal testing** track
(`dagger call -m ci upload-to-play`, `tool/play_upload.py`) when the
repository secret `PLAY_STORE_CONFIG_JSON` is set. It is the JSON key of
the Play service account of guettli/sharedinbox
(`playstore@sharedinbox-496103.iam.gserviceaccount.com`), which the Play
Console allows to release this app too. A copy is in
`secrets/play-store.enc.yaml` (SOPS, like the upload key):

```sh
sops decrypt --extract '["play_store_config_json"]' secrets/play-store.enc.yaml \
  | gh secret set PLAY_STORE_CONFIG_JSON -R guettli/pp-app
```

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
Android versionCode) with both APKs. `gh workflow run CI --ref main`
releases main again without a code change. Pull requests get the APK as a workflow
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
