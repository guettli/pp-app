// Updates from Google Play while the app runs (Play's "in-app updates",
// flexible mode): at start the app asks Play whether a newer version is
// out. If so, Play asks once whether to download it and loads it in the
// background while the child plays; on the next start the app installs it
// and restarts. Play's question comes at most every [askEvery] (a child
// may tap "no"). Without Play (APK from GitHub, iOS, tests) or offline:
// nothing happens.
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class AppUpdater {
  /// Never throws.
  Future<void> run();
}

class PlayAppUpdater implements AppUpdater {
  PlayAppUpdater(this.prefs);

  final SharedPreferences prefs;
  static const askEvery = Duration(days: 3);
  static const _asked = 'update|asked';

  @override
  Future<void> run() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.installStatus == InstallStatus.downloaded) {
        // loaded last time: install now, the app restarts
        await InAppUpdate.completeFlexibleUpdate();
        return;
      }
      if (info.updateAvailability == UpdateAvailability.updateAvailable &&
          info.flexibleUpdateAllowed) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final asked = prefs.getInt(_asked) ?? 0;
        if (now - asked < askEvery.inMilliseconds) return;
        await prefs.setInt(_asked, now);
        // completes once downloaded; throws if declined
        await InAppUpdate.startFlexibleUpdate();
      }
    } catch (e) {
      // not installed from Play, no Play services, offline
      debugPrint('app update: $e');
    }
  }
}
