import 'dart:async';
import 'dart:ui';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Crash reporting for Seaty.
///
/// Crashlytics is not available until Firebase finishes initialising - which
/// is exactly when the nastiest crashes happen, and Firebase may fail to
/// initialise at all. Handlers are therefore installed immediately and errors
/// raised before Firebase is up are buffered, then flushed once
/// [enableCrashReporting] is called.
///
/// This only *observes* errors. It never swallows one or alters control flow:
/// every error is still passed to Flutter's normal presentation path.
class CrashReporting {
  CrashReporting._();

  static bool _installed = false;
  static bool _ready = false;

  /// Errors captured before Firebase finished initialising. Bounded so a crash
  /// loop before startup can't grow this without limit.
  static final List<_PendingError> _pending = <_PendingError>[];
  static const int _maxPending = 20;

  /// Installs the global handlers. Safe to call more than once.
  ///
  /// Call as early as possible in `main()`, before `runApp`.
  static void installHandlers() {
    if (_installed) return;
    _installed = true;

    // Errors thrown inside the widget/build/layout pipeline.
    final FlutterExceptionHandler? previousOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      _record(details.exception, details.stack, fatal: false, details: details);
      // Preserve whatever Flutter (or a previously installed handler) would
      // have done - in debug this keeps the red screen and console output.
      if (previousOnError != null) {
        previousOnError(details);
      } else {
        FlutterError.presentError(details);
      }
    };

    // Uncaught asynchronous errors that escape to the platform. Preferred over
    // wrapping runApp in runZonedGuarded, which would mean restructuring main().
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      _record(error, stack, fatal: true);
      return true; // handled - do not tear the isolate down
    };
  }

  /// Turns on delivery to Crashlytics and flushes anything buffered during
  /// startup. Call once Firebase has initialised.
  static Future<void> enableCrashReporting() async {
    if (_ready) return;
    try {
      // Nothing is uploaded from debug builds - local runs would otherwise
      // pollute the dashboard and hide real user crashes.
      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(!kDebugMode);
      _ready = true;

      for (final _PendingError pending in _pending) {
        await _send(pending.error, pending.stack, pending.fatal);
      }
      _pending.clear();
    } catch (e) {
      // Crash reporting must never itself break the app.
      debugPrint('Crashlytics enable notice: $e');
    }
  }

  /// Records a handled (non-fatal) problem - useful for caught exceptions that
  /// the user never sees but that still indicate a defect.
  static void recordHandled(Object error, StackTrace? stack, {String? reason}) {
    _record(error, stack, fatal: false, reason: reason);
  }

  /// Tags reports with the signed-in user so crashes can be correlated.
  static Future<void> setUser({String? id, String? role}) async {
    if (!_ready) return;
    try {
      if (id != null) await FirebaseCrashlytics.instance.setUserIdentifier(id);
      if (role != null) {
        await FirebaseCrashlytics.instance.setCustomKey('role', role);
      }
    } catch (e) {
      debugPrint('Crashlytics setUser notice: $e');
    }
  }

  /// Breadcrumb attached to any later crash report.
  static void log(String message) {
    if (!_ready) return;
    try {
      FirebaseCrashlytics.instance.log(message);
    } catch (_) {
      // ignored - breadcrumbs are best-effort
    }
  }

  static void _record(
    Object error,
    StackTrace? stack, {
    required bool fatal,
    String? reason,
    FlutterErrorDetails? details,
  }) {
    if (!_ready) {
      if (_pending.length < _maxPending) {
        _pending.add(_PendingError(error, stack, fatal));
      }
      return;
    }
    unawaited(_send(error, stack, fatal, reason: reason, details: details));
  }

  static Future<void> _send(
    Object error,
    StackTrace? stack,
    bool fatal, {
    String? reason,
    FlutterErrorDetails? details,
  }) async {
    try {
      if (details != null) {
        await FirebaseCrashlytics.instance.recordFlutterError(details);
      } else {
        await FirebaseCrashlytics.instance.recordError(
          error,
          stack,
          reason: reason,
          fatal: fatal,
        );
      }
    } catch (e) {
      debugPrint('Crashlytics record notice: $e');
    }
  }
}

class _PendingError {
  const _PendingError(this.error, this.stack, this.fatal);

  final Object error;
  final StackTrace? stack;
  final bool fatal;
}
