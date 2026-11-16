// What a bug report says about the phone; read from Android
// (MainActivity.kt, channel "de.sharedinbox.pp2/device").
import 'package:flutter/services.dart';

const _channel = MethodChannel('de.sharedinbox.pp2/device');

/// App version, phone model and system version; empty where unknown.
Future<Map<String, String>> deviceInfo() async {
  try {
    final m = await _channel.invokeMapMethod<String, String>('info');
    return m ?? const {};
  } catch (_) {
    return const {};
  }
}
