import 'dart:async';
import 'package:flutter/services.dart';

// Optional device feedback must never block a saved action or fail on web.
abstract final class DueHaptics {
  static void confirm() =>
      unawaited(HapticFeedback.mediumImpact().catchError((Object _) {}));
  static void light() =>
      unawaited(HapticFeedback.lightImpact().catchError((Object _) {}));
  static void selection() =>
      unawaited(HapticFeedback.selectionClick().catchError((Object _) {}));
  static void warning() =>
      unawaited(HapticFeedback.heavyImpact().catchError((Object _) {}));
}
