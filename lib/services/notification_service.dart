import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Schedules local notifications reminding the household about expiring items.
///
/// A single reminder is scheduled per item at 9am, [daysBefore] days before
/// its expiry date. Each item's notification id is derived from its Firestore
/// document id so we can update/cancel it deterministically.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  static const _channelId = 'expiry_reminders';
  static const _channelName = 'Expiry reminders';
  static const _channelDescription =
      'Reminds you when groceries are about to expire.';

  Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
      macOS: darwinInit,
    );

    await _plugin.initialize(settings: initSettings);
    _initialized = true;
  }

  /// Requests notification permission on platforms that need it. Safe to call
  /// multiple times. Returns true if granted (or not required).
  Future<bool> requestPermissions() async {
    await init();

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      final granted = await android.requestNotificationsPermission();
      return granted ?? true;
    }

    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      final granted = await ios.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }

    return true;
  }

  /// Stable notification id for a Firestore document id.
  int _idFor(String groceryId) => groceryId.hashCode & 0x7fffffff;

  /// Separate id for the "expires today" reminder so it can coexist with the
  /// "N days before" one.
  int _todayIdFor(String groceryId) =>
      (groceryId.hashCode ^ 0x5a5a5a5a) & 0x7fffffff;

  NotificationDetails get _details => const NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
  );

  /// Schedules (or reschedules) a reminder for an item. Cancels any existing
  /// one first. If the reminder time is in the past, nothing is scheduled.
  Future<void> scheduleExpiryReminder({
    required String groceryId,
    required String name,
    required DateTime expiryDate,
    required int daysBefore,
  }) async {
    await init();
    final id = _idFor(groceryId);
    final todayId = _todayIdFor(groceryId);
    await _plugin.cancel(id: id);
    await _plugin.cancel(id: todayId);

    // Fire at 9:00am, [daysBefore] days before expiry.
    final remindDay = expiryDate.subtract(Duration(days: daysBefore));
    final scheduled = DateTime(
      remindDay.year,
      remindDay.month,
      remindDay.day,
      9,
    );
    final now = DateTime.now();

    if (scheduled.isAfter(now)) {
      final tzTime = tz.TZDateTime.from(scheduled, tz.local);
      final days = daysBefore == 1 ? 'tomorrow' : 'in $daysBefore days';
      await _tryZonedSchedule(
        id: id,
        title: 'Expiring soon',
        body: '$name expires $days.',
        when: tzTime,
        label: name,
      );
    }

    // "Expires today" reminder at 9:00am on the expiry day itself.
    final todayReminder = DateTime(
      expiryDate.year,
      expiryDate.month,
      expiryDate.day,
      9,
    );
    if (todayReminder.isAfter(now)) {
      final tzTime = tz.TZDateTime.from(todayReminder, tz.local);
      await _tryZonedSchedule(
        id: todayId,
        title: 'Expires today',
        body: '$name expires today.',
        when: tzTime,
        label: name,
      );
    }
  }

  Future<void> _tryZonedSchedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
    required String label,
  }) async {
    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: when,
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('Failed to schedule reminder for $label: $e');
    }
  }

  Future<void> cancelReminder(String groceryId) async {
    await init();
    await _plugin.cancel(id: _idFor(groceryId));
    await _plugin.cancel(id: _todayIdFor(groceryId));
  }

  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }

  // Fixed id for the recurring daily digest so it can be updated/cancelled.
  static const int _digestId = 777001;

  /// Schedules (or replaces) a daily digest notification at 8am summarizing
  /// how many items are expiring soon. Pass [expiringCount] = 0 to cancel.
  Future<void> scheduleDailyDigest({required int expiringCount}) async {
    await init();
    await _plugin.cancel(id: _digestId);
    if (expiringCount <= 0) return;

    // Next 8:00am.
    final now = DateTime.now();
    var when = DateTime(now.year, now.month, now.day, 8);
    if (!when.isAfter(now)) {
      when = when.add(const Duration(days: 1));
    }
    final tzTime = tz.TZDateTime.from(when, tz.local);
    final body = expiringCount == 1
        ? '1 item is expiring soon. Tap to review.'
        : '$expiringCount items are expiring soon. Tap to review.';

    try {
      await _plugin.zonedSchedule(
        id: _digestId,
        title: 'StockHome daily check',
        body: body,
        scheduledDate: tzTime,
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        // Repeat every day at the same time.
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      debugPrint('Failed to schedule daily digest: $e');
    }
  }
}
