// Updates from Google Play (Play's "in-app updates"): at start the app
// asks Play whether a newer version is out. If so, Play asks whether to
// update now; "Update" shows Play's own full-screen progress, installs the
// new version and starts the app again ("immediate" update). It is asked
// at start only, so no game is cut off, and at most every [askEvery] (a
// child may tap "no thanks").
//
// It used to be a "flexible" update: Play downloaded in the background and
// the app installed it only at its next real start. Android mostly keeps
// the app alive and brings it back instead, so after "Update" nothing
// seemed to happen, often for days. An update downloaded that way is
// installed at the next start.
//
// Without Play (APK from GitHub, iOS, tests) or offline: nothing happens.
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class AppUpdater {
  /// Never throws.
  Future<void> run();
}

/// What the updater needs from Play (the in_app_update plugin; a fake in
/// tests).
abstract class PlayUpdates {
  Future<AppUpdateInfo> check();

  /// Play's full-screen update: download, install, restart.
  Future<AppUpdateResult> updateNow();

  /// Installs an update downloaded in the background; the app restarts.
  /// (The plugin never completes this future: on success the app is gone,
  /// on failure nothing is said.)
  Future<void> installDownloaded();
}

class PluginPlayUpdates implements PlayUpdates {
  @override
  Future<AppUpdateInfo> check() => InAppUpdate.checkForUpdate();
  @override
  Future<AppUpdateResult> updateNow() => InAppUpdate.performImmediateUpdate();
  @override
  Future<void> installDownloaded() => InAppUpdate.completeFlexibleUpdate();
}

class PlayAppUpdater implements AppUpdater {
  PlayAppUpdater(this.prefs, {PlayUpdates? play, this.android})
    : play = play ?? PluginPlayUpdates();

  final SharedPreferences prefs;
  final PlayUpdates play;

  /// Whether this is Android (Play); null: the platform's.
  final bool? android;

  static const askEvery = Duration(days: 3);

  /// An install of a downloaded update that has not restarted the app
  /// after this has failed.
  static const installWait = Duration(minutes: 1);
  static const _asked = 'update|asked';

  @override
  Future<void> run() async {
    if (!(android ?? (!kIsWeb && Platform.isAndroid))) return;
    try {
      final info = await play.check();
      debugPrint('app update: $info');
      if (info.installStatus == InstallStatus.downloaded) {
        // loaded in the background (the old flexible way): install now
        await play.installDownloaded().timeout(
          installWait,
          onTimeout: () => debugPrint(
            'app update: FAILED: the downloaded update was not installed '
            '(no restart after $installWait)',
          ),
        );
        return;
      }
      if (info.updateAvailability ==
          UpdateAvailability.developerTriggeredUpdateInProgress) {
        // an update was started and the app left meanwhile: go on with it
        if (!info.immediateUpdateAllowed) {
          // the plugin would never answer
          debugPrint('app update: FAILED: cannot go on with the update');
          return;
        }
        final result = await play.updateNow();
        debugPrint('app update: $result');
        return;
      }
      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        return;
      }
      if (!info.immediateUpdateAllowed) {
        debugPrint('app update: Play allows no immediate update');
        return;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final asked = prefs.getInt(_asked) ?? 0;
      if (now - asked < askEvery.inMilliseconds) return;
      await prefs.setInt(_asked, now);
      // after "Update" the app is replaced and restarts; it returns only
      // when declined or failed
      final result = await play.updateNow();
      if (result == AppUpdateResult.inAppUpdateFailed) {
        // not the child's "no": ask again at the next start
        await prefs.remove(_asked);
        debugPrint('app update: FAILED: Play could not update');
      } else {
        debugPrint('app update: $result');
      }
    } catch (e, st) {
      // not installed from Play, no Play services, offline; an update must
      // never stop the app
      debugPrint('app update: FAILED: $e\n$st');
    }
  }
}
