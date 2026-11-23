// Updates from Play at start: what the app asks Play to do.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:phoneme_party/net/app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakePlay implements PlayUpdates {
  FakePlay(this.info);
  AppUpdateInfo info;
  final calls = <String>[];
  AppUpdateResult result = AppUpdateResult.userDeniedUpdate;
  Object? throws;

  /// Like the plugin: never completes (the app restarts).
  bool installHangs = false;

  @override
  Future<AppUpdateInfo> check() async {
    calls.add('check');
    return info;
  }

  @override
  Future<AppUpdateResult> updateNow() async {
    calls.add('updateNow');
    if (throws case final e?) throw e;
    return result;
  }

  @override
  Future<void> installDownloaded() {
    calls.add('installDownloaded');
    return installHangs ? Completer<void>().future : Future.value();
  }
}

AppUpdateInfo info({
  UpdateAvailability availability = UpdateAvailability.updateAvailable,
  bool immediate = true,
  InstallStatus status = InstallStatus.unknown,
}) => AppUpdateInfo(
  updateAvailability: availability,
  immediateUpdateAllowed: immediate,
  immediateAllowedPreconditions: null,
  flexibleUpdateAllowed: true,
  flexibleAllowedPreconditions: null,
  availableVersionCode: 200,
  installStatus: status,
  packageName: 'de.sharedinbox.pp2',
  clientVersionStalenessDays: 1,
  updatePriority: 0,
);

void main() {
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  PlayAppUpdater updater(FakePlay play) =>
      PlayAppUpdater(prefs, play: play, android: true);

  test('a new version: Play updates now (full screen, restarts)', () async {
    final play = FakePlay(info());
    await updater(play).run();
    expect(play.calls, ['check', 'updateNow']);
  });

  test('declined: not asked again for three days', () async {
    final play = FakePlay(info());
    await updater(play).run();
    await updater(play).run();
    expect(play.calls, ['check', 'updateNow', 'check']);
    // three days later
    await prefs.setInt(
      'update|asked',
      DateTime.now()
          .subtract(PlayAppUpdater.askEvery + const Duration(minutes: 1))
          .millisecondsSinceEpoch,
    );
    await updater(play).run();
    expect(play.calls.last, 'updateNow');
  });

  test('downloaded in the background before: installed at start', () async {
    final play = FakePlay(info(status: InstallStatus.downloaded));
    await updater(play).run();
    expect(play.calls, ['check', 'installDownloaded']);
  });

  test('Play could not update: asked again at the next start', () async {
    final play = FakePlay(info())..result = AppUpdateResult.inAppUpdateFailed;
    await updater(play).run();
    expect(prefs.getInt('update|asked'), isNull);
    await updater(play).run();
    expect(play.calls, ['check', 'updateNow', 'check', 'updateNow']);
  });

  test('the update throws: no error, the app goes on', () async {
    final play = FakePlay(info())..throws = StateError('broken');
    await updater(play).run();
    expect(play.calls, ['check', 'updateNow']);
  });

  test('install of a downloaded update never answers: run ends', () {
    fakeAsync((time) {
      final play = FakePlay(info(status: InstallStatus.downloaded))
        ..installHangs = true;
      var done = false;
      updater(play).run().then((_) => done = true);
      time.elapse(PlayAppUpdater.installWait);
      time.flushMicrotasks();
      expect(done, isTrue);
    });
  });

  test('an update in progress (the app was left): it goes on', () async {
    final play = FakePlay(
      info(availability: UpdateAvailability.developerTriggeredUpdateInProgress),
    );
    // even right after asking
    await prefs.setInt('update|asked', DateTime.now().millisecondsSinceEpoch);
    await updater(play).run();
    expect(play.calls, ['check', 'updateNow']);
  });

  test('up to date, or no immediate update allowed: nothing', () async {
    for (final i in [
      info(availability: UpdateAvailability.updateNotAvailable),
      info(immediate: false),
    ]) {
      final play = FakePlay(i);
      await updater(play).run();
      expect(play.calls, ['check']);
      expect(prefs.getInt('update|asked'), isNull);
    }
  });

  test('in progress, but Play allows no immediate update: nothing', () async {
    final play = FakePlay(
      info(
        availability: UpdateAvailability.developerTriggeredUpdateInProgress,
        immediate: false,
      ),
    );
    await updater(play).run();
    expect(play.calls, ['check']);
  });

  test('without Play (not Android): Play is not asked', () async {
    final play = FakePlay(info());
    await PlayAppUpdater(prefs, play: play, android: false).run();
    expect(play.calls, isEmpty);
  });

  test('Play fails (APK from GitHub, offline): no error', () async {
    final play = _FailingPlay();
    await PlayAppUpdater(prefs, play: play, android: true).run();
    expect(prefs.getInt('update|asked'), isNull);
  });
}

class _FailingPlay extends FakePlay {
  _FailingPlay() : super(info());
  @override
  Future<AppUpdateInfo> check() async => throw StateError('no Play');
}
