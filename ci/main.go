// Dagger CI module for Phoneme Party (Flutter app).
//
// Flutter/Dart are not installed on the dev host. Everything runs inside
// containers on the Dagger engine:
//
//	dagger call -m ci check-fast          # format + analyze + unit tests
//	dagger call -m ci build-apk export --path build/pp-app.apk
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"regexp"
	"strconv"
	"strings"

	"dagger/ci/internal/dagger"
)

type Ci struct {
	Source         *dagger.Directory
	FlutterVersion string
}

func New(
	ctx context.Context,
	// +defaultPath=".."
	// +ignore=["build", ".dart_tool", "**/.gradle", "assets/models/*.onnx", "ci/internal"]
	source *dagger.Directory,
) (*Ci, error) {
	fvmrc, err := source.File(".fvmrc").Contents(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to read .fvmrc: %w", err)
	}
	var cfg struct {
		Flutter string `json:"flutter"`
	}
	if err := json.Unmarshal([]byte(fvmrc), &cfg); err != nil {
		return nil, fmt.Errorf("failed to parse .fvmrc: %w", err)
	}
	if cfg.Flutter == "" {
		return nil, fmt.Errorf(".fvmrc is missing the 'flutter' field")
	}
	return &Ci{Source: source, FlutterVersion: cfg.Flutter}, nil
}

const androidCmdlineToolsURL = "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"

const flutterArchiveURLTemplate = "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_%s-stable.tar.xz"

// ZIPA phone recognizer (int8 ONNX). Downloaded at build time, never committed.
// CC BY 4.0. The -ns-700k variant (CC BY-NC-SA, used by the web app
// guettli/pp) scored the same on real recordings and worse on synthesized
// speech (tool/tts_check), so the freely licensed one is used.
const (
	modelRepo = "anyspeech/zipa-small-crctc-500k"
	modelFile = "model.int8.onnx"
	// Pinned so an upstream change cannot silently change recognition.
	modelRevision = "dfe87c97662606fa6db90ad06f627d4363314744"
	modelSHA256   = "d0e28b68164e8b1fbd6105100c01798828aa0855000ce9bbbd1a2cec233adf13"
	tokensSHA256  = "f8e042a0c9130532b22d03ec7cae2f75a23fbec70c450c31a8efb51787b2b8fe"
)

// toolchain: Ubuntu + JDK 17 + Android SDK + Flutter (no cache mounts, so the
// layers are execution-cached by the engine).
func (m *Ci) toolchain() *dagger.Container {
	return dag.Container().
		From("ubuntu:24.04").
		WithEnvVariable("DEBIAN_FRONTEND", "noninteractive").
		WithEnvVariable("JAVA_HOME", "/usr/lib/jvm/java-17-openjdk-amd64").
		WithEnvVariable("ANDROID_HOME", "/opt/android-sdk").
		WithEnvVariable("PATH", "/opt/flutter/bin:/opt/android-sdk/cmdline-tools/latest/bin:${JAVA_HOME}/bin:${PATH}",
			dagger.ContainerWithEnvVariableOpts{Expand: true}).
		WithExec([]string{"/bin/sh", "-c",
			"apt-get -qq update && apt-get install -y -qq --no-install-recommends " +
				"ca-certificates curl git unzip xz-utils zip openjdk-17-jdk-headless python3"}).
		WithExec([]string{"useradd", "-m", "-s", "/bin/bash", "ci"}).
		WithExec([]string{"/bin/sh", "-c",
			`set -e; ` +
				`mkdir -p /opt/android-sdk/cmdline-tools; ` +
				`curl -fsSL -o /tmp/cmdline-tools.zip ` + androidCmdlineToolsURL + `; ` +
				`unzip -q /tmp/cmdline-tools.zip -d /opt/android-sdk/cmdline-tools; ` +
				`mv /opt/android-sdk/cmdline-tools/cmdline-tools /opt/android-sdk/cmdline-tools/latest; ` +
				`rm /tmp/cmdline-tools.zip; ` +
				`yes | sdkmanager --licenses >/dev/null; ` +
				`chown -R ci:ci /opt/android-sdk; ` +
				`mkdir -p /src && chown ci:ci /src`}).
		WithEnvVariable("PUB_CACHE", "/home/ci/.pub-cache").
		WithEnvVariable("HOME", "/home/ci").
		WithUser("ci").
		WithExec([]string{"/bin/sh", "-c",
			`tmp=$(mktemp); yes | sdkmanager "platform-tools" "build-tools;35.0.0" "platforms;android-35" "platforms;android-36" "ndk;28.2.13676358" "cmake;3.22.1" >"$tmp" 2>&1 || { cat "$tmp"; exit 1; }`}).
		WithUser("root").
		WithExec([]string{"/bin/sh", "-c",
			fmt.Sprintf(`set -e; curl -fsSL "`+flutterArchiveURLTemplate+`" | tar -xJ -C /opt; `+
				`git config --system --add safe.directory /opt/flutter; chown -R ci:ci /opt/flutter`, m.FlutterVersion)}).
		WithUser("ci").
		WithExec([]string{"flutter", "config", "--no-analytics"}).
		WithExec([]string{"flutter", "precache", "--android", "--no-ios", "--no-linux", "--no-web"})
}

// base: toolchain + project source + `flutter pub get`.
func (m *Ci) base() *dagger.Container {
	pubspec := m.Source.Filter(dagger.DirectoryFilterOpts{Include: []string{"pubspec.yaml", "pubspec.lock"}})
	return m.toolchain().
		WithDirectory("/src", pubspec, dagger.ContainerWithDirectoryOpts{Owner: "ci"}).
		WithWorkdir("/src").
		WithExec([]string{"flutter", "pub", "get"}).
		WithDirectory("/src", m.Source, dagger.ContainerWithDirectoryOpts{Owner: "ci"}).
		WithExec([]string{"flutter", "pub", "get", "--offline"})
}

// Shell returns the build container, e.g. `dagger call -m ci shell terminal`.
func (m *Ci) Shell() *dagger.Container {
	return m.base()
}

// Format fails if `dart format` would change anything.
func (m *Ci) Format(ctx context.Context) (string, error) {
	return m.base().
		WithExec([]string{"dart", "format", "--output=none", "--set-exit-if-changed", "lib", "test"}).
		Stdout(ctx)
}

// FormatWrite returns the source tree after `dart format` (export it over the repo).
func (m *Ci) FormatWrite() *dagger.Directory {
	return m.base().
		WithExec([]string{"dart", "format", "lib", "test"}).
		Directory("/src").
		Filter(dagger.DirectoryFilterOpts{Include: []string{"lib/", "test/"}})
}

// Analyze runs `flutter analyze --fatal-infos`.
func (m *Ci) Analyze(ctx context.Context) (string, error) {
	return m.base().
		WithExec([]string{"flutter", "analyze", "--fatal-infos"}).
		Stdout(ctx)
}

// Test runs the unit/widget tests.
func (m *Ci) Test(ctx context.Context) (string, error) {
	return m.base().
		WithExec([]string{"flutter", "test", "--reporter", "expanded"}).
		Stdout(ctx)
}

// CheckFast: format + analyze + test. Run this before every push.
func (m *Ci) CheckFast(ctx context.Context) (string, error) {
	out := ""
	for _, step := range []func(context.Context) (string, error){m.Format, m.Analyze, m.Test} {
		s, err := step(ctx)
		if err != nil {
			return out, err
		}
		out += s
	}
	return out, nil
}

// Model downloads the ZIPA ONNX model and its token table (pinned revision,
// checked against sha256).
func (m *Ci) Model() *dagger.Directory {
	base := "https://huggingface.co/" + modelRepo + "/resolve/" + modelRevision + "/"
	sums := modelSHA256 + "  model.onnx\n" + tokensSHA256 + "  tokens.txt\n"
	return dag.Container().
		From("alpine:3.21").
		WithExec([]string{"apk", "add", "--no-cache", "curl"}).
		WithWorkdir("/out").
		WithExec([]string{"curl", "-fsSL", "-o", "model.onnx", base + modelFile}).
		WithExec([]string{"curl", "-fsSL", "-o", "tokens.txt", base + "tokens.txt"}).
		WithNewFile("/sha256sums", sums).
		WithExec([]string{"sha256sum", "-c", "/sha256sums"}).
		Directory("/out")
}

// BuildApk builds a release APK for one ABI. One APK per ABI keeps the size
// down: ONNX Runtime alone is 20-35 MB per architecture. Play Store builds
// should use an app bundle.
//
// Without a keystore the APK is signed with a throw-away debug key, so it
// cannot be installed as an update over an APK from another build.
func (m *Ci) BuildApk(
	ctx context.Context,
	// +default="arm64-v8a"
	abi string,
	// Release keystore (PKCS12/JKS, base64-encoded), key alias "upload".
	// +optional
	keystoreBase64 *dagger.Secret,
	// Password of the keystore and the key.
	// +optional
	keystorePassword *dagger.Secret,
	// Build number (Android versionCode); must grow with every release so
	// phones accept the update. The version name becomes
	// <major>.<minor>.<buildNumber> from pubspec.yaml. 0 keeps pubspec's.
	// +default=0
	buildNumber int,
) (*dagger.File, error) {
	c := m.base().
		WithDirectory("/src/assets/models", m.Model(), dagger.ContainerWithDirectoryOpts{Owner: "ci"}).
		WithMountedCache("/home/ci/.gradle", dag.CacheVolume("pp-app-gradle"), dagger.ContainerWithMountedCacheOpts{Owner: "ci"}).
		WithEnvVariable("GRADLE_OPTS", "-Dorg.gradle.daemon=false")
	if keystoreBase64 != nil && keystorePassword != nil {
		c = c.
			WithSecretVariable("KS_B64", keystoreBase64).
			WithSecretVariable("KS_PASS", keystorePassword).
			WithExec([]string{"sh", "-euc", `echo "$KS_B64" | base64 -d > /home/ci/upload.jks
printf 'storeFile=/home/ci/upload.jks\nstorePassword=%s\nkeyAlias=upload\nkeyPassword=%s\n' "$KS_PASS" "$KS_PASS" > android/key.properties`})
	}
	args := []string{"flutter", "build", "apk", "--release", "--split-per-abi", "--target-platform", "android-arm64,android-arm"}
	if buildNumber > 0 {
		name, err := m.releaseVersion(ctx, buildNumber)
		if err != nil {
			return nil, err
		}
		args = append(args, "--build-name", name, "--build-number", strconv.Itoa(buildNumber))
	}
	return c.
		WithExec(args).
		File("/src/build/app/outputs/flutter-apk/app-" + abi + "-release.apk"), nil
}

// ReleaseVersion returns the version name for a build number:
// <major>.<minor> from pubspec.yaml plus the build number as patch.
func (m *Ci) ReleaseVersion(
	ctx context.Context,
	buildNumber int,
) (string, error) {
	return m.releaseVersion(ctx, buildNumber)
}

func (m *Ci) releaseVersion(ctx context.Context, buildNumber int) (string, error) {
	pubspec, err := m.Source.File("pubspec.yaml").Contents(ctx)
	if err != nil {
		return "", err
	}
	match := regexp.MustCompile(`(?m)^version:\s*(\d+)\.(\d+)\.`).FindStringSubmatch(pubspec)
	if match == nil {
		return "", fmt.Errorf("no version: <major>.<minor>.<patch> in pubspec.yaml")
	}
	return fmt.Sprintf("%s.%s.%d", match[1], match[2], buildNumber), nil
}

// Scaffold runs `flutter create` and returns the generated platform folders.
// Only used once to bootstrap android/; kept for regenerating.
func (m *Ci) Scaffold() *dagger.Directory {
	return m.toolchain().
		WithWorkdir("/src").
		WithExec([]string{"flutter", "create", "--org", "de.relaxandplay", "--project-name", "phoneme_party",
			"--platforms", "android,ios", "--empty", "."}).
		Directory("/src")
}

// PanphonFeatures exports PanPhon's articulatory feature table as JSON
// (phoneme -> 24 values in {-1,0,1}).
func (m *Ci) PanphonFeatures() *dagger.File {
	script := `
import json, panphon
ft = panphon.FeatureTable()
names = ft.names
out = {}
for sym in ft.seg_dict.keys():
    vec = ft.word_to_vector_list(sym, numeric=True)
    if len(vec) == 1:
        out[sym] = vec[0]
json.dump({"names": names, "features": out}, open("/out/panphon_features.json", "w"), ensure_ascii=False, separators=(",", ":"))
print(len(out), "phonemes,", len(names), "features")
`
	return dag.Container().
		From("python:3.12-slim").
		WithExec([]string{"pip", "install", "--quiet", "panphon==0.22.2"}).
		WithNewFile("/gen.py", script).
		WithExec([]string{"mkdir", "-p", "/out"}).
		WithExec([]string{"python", "/gen.py"}).
		File("/out/panphon_features.json")
}

// FlacToWav converts a test recording to 16 kHz mono 16-bit WAV (test fixtures).
func (m *Ci) FlacToWav(flac *dagger.File) *dagger.File {
	return dag.Container().
		From("alpine:3.21").
		WithExec([]string{"apk", "add", "--no-cache", "ffmpeg"}).
		WithFile("/in.flac", flac).
		WithExec([]string{"ffmpeg", "-loglevel", "error", "-i", "/in.flac", "-ac", "1", "-ar", "16000", "-sample_fmt", "s16", "/out.wav"}).
		File("/out.wav")
}

// FbankReference computes reference log-mel features with Lhotse (the feature
// extractor ZIPA was trained with) for a 16 kHz WAV. Output: JSON
// {"frames": N, "bins": 80, "data": [...]} used by test/fbank_test.dart.
func (m *Ci) FbankReference(wav *dagger.File) *dagger.File {
	script := `
import json, numpy as np, soundfile as sf
from lhotse.features.kaldi.extractors import Fbank, FbankConfig
audio, sr = sf.read("/in.wav", dtype="float32")
assert sr == 16000, sr
feats = Fbank(FbankConfig(num_mel_bins=80)).extract(audio, sr)
json.dump({"frames": int(feats.shape[0]), "bins": int(feats.shape[1]),
           "data": [round(float(x), 5) for x in feats.reshape(-1)]}, open("/out.json", "w"))
print(feats.shape)
`
	return dag.Container().
		From("python:3.12-slim").
		WithExec([]string{"pip", "install", "--quiet", "--index-url", "https://download.pytorch.org/whl/cpu", "torch==2.5.1", "torchaudio==2.5.1"}).
		WithExec([]string{"pip", "install", "--quiet", "lhotse==1.30.3", "soundfile"}).
		WithFile("/in.wav", wav).
		WithNewFile("/gen.py", script).
		WithExec([]string{"python", "/gen.py"}).
		File("/out.json")
}

// PubspecLock returns the lock file resolved by `flutter pub get`.
func (m *Ci) PubspecLock() *dagger.File {
	return m.base().File("/src/pubspec.lock")
}

// Piper voices for the automatic pronunciation check (two per language).
var ttsVoices = []string{
	"de/de_DE/thorsten/medium", "de/de_DE/kerstin/low",
	"en/en_GB/alba/medium", "en/en_GB/southern_english_female/low",
	"fr/fr_FR/siwis/medium", "fr/fr_FR/tom/medium",
	"it/it_IT/paola/medium", "it/it_IT/riccardo/x_low",
	"es/es_ES/davefx/medium", "es/es_ES/sharvard/medium",
}

// TtsCheck speaks every word of the word list with Piper voices, runs the
// app's recognition and scoring on it and returns one JSON row per word and
// voice (tool/tts_check). Words that get few stars although they were
// pronounced correctly point to a wrong IPA in the word list.
func (m *Ci) TtsCheck(
	// Hugging Face repo of another ZIPA model to compare (default: the app's).
	// +optional
	model string,
	// Synthesis options for experiments, e.g. "gain=1 lead=0.4 tail=0.8 noise=0.002".
	// +optional
	options string,
	// Only voices whose name contains this (e.g. "thorsten"), for quick experiments.
	// +optional
	voice string,
	// Real recordings instead of synthesized speech (see
	// tool/tts_check/load_recordings.py).
	// +optional
	recordings *dagger.Directory,
) *dagger.File {
	if recordings == nil {
		recordings = dag.Directory()
	}
	modelDir := m.Model()
	if model != "" {
		modelDir = dag.Container().
			From("alpine:3.21").
			WithExec([]string{"apk", "add", "--no-cache", "curl"}).
			WithWorkdir("/out").
			WithExec([]string{"curl", "-fsSL", "-o", "model.onnx", "https://huggingface.co/" + model + "/resolve/main/" + modelFile}).
			WithExec([]string{"curl", "-fsSL", "-o", "tokens.txt", "https://huggingface.co/" + model + "/resolve/main/tokens.txt"}).
			Directory("/out")
	}
	voices := dag.Container().
		From("alpine:3.21").
		WithExec([]string{"apk", "add", "--no-cache", "curl"}).
		WithExec([]string{"mkdir", "/voices"}).
		WithWorkdir("/voices")
	for _, v := range ttsVoices {
		if voice != "" && !strings.Contains(v, voice) {
			continue
		}
		parts := regexp.MustCompile("/").Split(v, -1)
		name := parts[1] + "-" + parts[2] + "-" + parts[3]
		url := "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/" + v + "/" + name
		voices = voices.WithExec([]string{"sh", "-c",
			"curl -fsSL -o " + name + ".onnx " + url + ".onnx && curl -fsSL -o " + name + ".onnx.json " + url + ".onnx.json"})
	}
	run := `set -e
. /opt/venv/bin/activate
if [ -f /rec/recordings.json ]; then python tool/tts_check/load_recordings.py /rec /work
else python tool/tts_check/synth.py assets/phrases /voices /work; fi
dart run tool/tts_check/check.dart features /work
python tool/tts_check/infer.py /work /model/model.onnx
dart run tool/tts_check/check.dart score /work /model/tokens.txt /work/report.json`
	return m.base().
		WithUser("root").
		WithExec([]string{"sh", "-c", "apt-get -qq update && apt-get install -y -qq --no-install-recommends python3-venv && " +
			"python3 -m venv /opt/venv && /opt/venv/bin/pip install --quiet piper-tts==1.3.0 onnxruntime==1.20.1 scipy==1.14.1 numpy==2.1.3 soundfile==0.12.1 && " +
			"mkdir /work && chown ci /work"}).
		WithUser("ci").
		WithDirectory("/voices", voices.Directory("/voices")).
		WithDirectory("/model", modelDir).
		WithDirectory("/rec", recordings).
		WithEnvVariable("TTS_OPTIONS", options).
		WithExec([]string{"sh", "-c", run}).
		File("/work/report.json")
}

// TtsRescore scores the recognitions of a TtsCheck report again with the
// current scoring code (quick check of a scoring change).
func (m *Ci) TtsRescore(report *dagger.File) *dagger.File {
	return m.base().
		WithFile("/tmp/in.json", report).
		WithExec([]string{"dart", "run", "tool/tts_check/check.dart", "rescore", "/tmp/in.json", "/tmp/out.json"}).
		File("/tmp/out.json")
}
