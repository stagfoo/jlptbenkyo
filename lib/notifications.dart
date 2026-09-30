/// The daily reminder.
///
/// Local notifications only. The app has no server and never talks to a
/// network, so "push" here means the device's own alarm clock — which is
/// the right mechanism anyway: a study reminder depends on what is due on
/// *this* device, which no server would know.
///
/// Everything is best-effort. Android 13 can refuse the permission,
/// Android 14 can refuse exact alarms, and a user can turn the channel
/// off in system settings at any time. None of that is a reason for the
/// app to fail to open, so every call reports rather than throws.
library;

import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class Reminders {
  Reminders._();
  static final Reminders instance = Reminders._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const int _dailyId = 1;
  static const String _channelId = 'daily_review';

  bool _ready = false;

  /// Whether the device has agreed to show notifications at all. False
  /// until [requestPermission] has been granted, and after the user turns
  /// them off in system settings.
  bool granted = false;

  Future<void> init() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      // The device's own zone, resolved from its current offset. Without
      // this everything is scheduled in UTC, and "remind me at eight"
      // arrives at eight UTC — the middle of the night for most people,
      // and silently wrong rather than visibly broken.
      tz.setLocalLocation(tz.getLocation(await _deviceTimeZone()));

      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// Best-effort zone name. Falls back to UTC, which at least schedules
  /// consistently rather than not at all.
  Future<String> _deviceTimeZone() async {
    try {
      final offset = DateTime.now().timeZoneOffset;
      for (final name in tz.timeZoneDatabase.locations.keys) {
        final loc = tz.getLocation(name);
        if (tz.TZDateTime.now(loc).timeZoneOffset == offset) return name;
      }
    } catch (_) {
      // Fall through.
    }
    return 'UTC';
  }

  Future<bool> requestPermission() async {
    await init();
    if (!_ready) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      granted = await android?.requestNotificationsPermission() ?? false;
      return granted;
    } catch (_) {
      return false;
    }
  }

  /// Schedules a reminder at [hour]:[minute] every day.
  ///
  /// Repeating on a wall-clock time rather than a fixed interval, so it
  /// stays at the same time of day across a clock change instead of
  /// drifting an hour twice a year.
  Future<bool> scheduleDaily(int hour, int minute) async {
    await init();
    if (!_ready) return false;
    try {
      await cancel();
      await _plugin.zonedSchedule(
        id: _dailyId,
        title: 'Time to study',
        body: 'Your reviews are waiting.',
        scheduledDate: _nextOccurrence(hour, minute),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Daily review',
            channelDescription: 'A reminder that reviews are due.',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
        // Inexact on purpose. An exact alarm needs a special permission
        // on Android 14+, is refused by default, and buys nothing here —
        // a study reminder is no worse for arriving a few minutes late,
        // and asking for the stricter permission to gain that is a poor
        // trade for something that then fails on devices that say no.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  tz.TZDateTime _nextOccurrence(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var when =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    // Today's slot having already passed means the first one is
    // tomorrow. Scheduling it in the past fires it immediately, which
    // reads as the app nagging the moment you set a reminder.
    if (!when.isAfter(now)) {
      when = when.add(const Duration(days: 1));
    }
    return when;
  }

  Future<void> cancel() async {
    try {
      await _plugin.cancel(id: _dailyId);
    } catch (_) {
      // Cancelling something that was never scheduled is not an error.
    }
  }

  /// Whether the platform can do this at all. Only Android is shipped, but
  /// the check keeps a desktop debug run from throwing on a missing
  /// plugin implementation.
  bool get supported => Platform.isAndroid;
}
