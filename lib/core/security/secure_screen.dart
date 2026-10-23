import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Blocks screenshots, screen recording and the recent-apps preview.
/// Android only: iOS does not let apps prevent screenshots, so there the
/// privacy shield covers the app switcher instead.
abstract final class SecureScreen {
  static const _channel = MethodChannel('app.duedesk/security');

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> set(bool enabled) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('setSecure', {'enabled': enabled});
    } on PlatformException {
      // Optional hardening; never block the app over it.
    } on MissingPluginException {
      // Not available in this embedding.
    }
  }
}
