import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The iOS app-icon badge.
///
/// The badge is push-driven: APNs writes whatever number the payload carries
/// and iOS keeps it until the app sets it to something else. Reading a
/// notification in-app, signing out, or signing in as somebody else does none
/// of that - so without this the count from one user's push survives logout and
/// shows on the next user's home screen.
///
/// No-op on Android, where launchers derive their own badge from the
/// notification shade, and on any platform with no handler registered.
class AppBadge {
  AppBadge._();

  static const MethodChannel _channel = MethodChannel('lk.seaty.app/badge');

  /// Sets the badge to [count]. Zero removes it.
  static Future<void> set(int count) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('setBadge', <String, dynamic>{
        'count': count < 0 ? 0 : count,
      });
    } on MissingPluginException {
      // Platform without a handler - Android, tests. Nothing to set.
    } catch (e) {
      debugPrint('Could not set app badge: $e');
    }
  }

  /// Removes the badge. Call on sign-out, before the next user arrives.
  static Future<void> clear() => set(0);
}
