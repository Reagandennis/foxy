import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class TaskNotificationService {
  TaskNotificationService._();

  static const String _channelId = 'foxy_task_reminders';
  static const String _channelName = 'Task reminders';
  static const String _channelDescription =
      'Task reminder notifications from Foxy';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static String? _lastError;

  static String? get lastError => _lastError;

  static Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    tz.initializeTimeZones();

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings darwinSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _plugin.initialize(settings: initSettings);

    final AndroidFlutterLocalNotificationsPlugin? androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    try {
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.max,
        ),
      );
    } catch (_) {
      // Channel creation can fail on unsupported targets; plugin still works.
    }

    _initialized = true;
  }

  static Future<bool> requestPermissions() async {
    _lastError = null;
    try {
      await initialize();
    } catch (error) {
      _lastError = error.toString();
      return false;
    }
    bool granted = true;

    final AndroidFlutterLocalNotificationsPlugin? androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    try {
      final bool? androidGranted = await androidPlugin
          ?.requestNotificationsPermission();
      if (androidGranted != null) {
        granted = granted && androidGranted;
      }
    } catch (error) {
      _lastError = error.toString();
      granted = false;
    }
    try {
      await androidPlugin?.requestExactAlarmsPermission();
    } catch (_) {
      // Exact alarms are optional for current scheduling mode.
    }

    final IOSFlutterLocalNotificationsPlugin? iosPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    try {
      final bool? iosGranted = await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      if (iosGranted != null) {
        granted = granted && iosGranted;
      }
    } catch (error) {
      _lastError = error.toString();
      granted = false;
    }

    return granted;
  }

  static Future<bool?> areNotificationsEnabled() async {
    try {
      await initialize();
      final AndroidFlutterLocalNotificationsPlugin? androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (androidPlugin != null) {
        return await androidPlugin.areNotificationsEnabled();
      }

      final IOSFlutterLocalNotificationsPlugin? iosPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (iosPlugin != null) {
        final NotificationsEnabledOptions? options = await iosPlugin
            .checkPermissions();
        if (options == null) {
          return null;
        }
        return options.isEnabled;
      }
      return null;
    } catch (error) {
      _lastError = error.toString();
      return null;
    }
  }

  static int _notificationIdForTask(String taskId) {
    return taskId.hashCode & 0x7fffffff;
  }

  static Future<void> cancelReminder(String taskId) async {
    await initialize();
    await _plugin.cancel(id: _notificationIdForTask(taskId));
  }

  static Future<void> scheduleReminder({
    required String taskId,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    await initialize();

    final tz.TZDateTime scheduledAt = tz.TZDateTime.from(when.toUtc(), tz.UTC);
    if (scheduledAt.isBefore(tz.TZDateTime.now(tz.UTC))) {
      await cancelReminder(taskId);
      return;
    }

    final NotificationDetails details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        color: const Color(0xFFE95E4A),
        styleInformation: BigTextStyleInformation(body),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _plugin.zonedSchedule(
      id: _notificationIdForTask(taskId),
      title: title,
      body: body,
      scheduledDate: scheduledAt,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: taskId,
    );
  }

  static Future<void> showTestNotification() async {
    await initialize();
    const NotificationDetails details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.max,
        priority: Priority.high,
        color: Color(0xFFE95E4A),
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _plugin.show(
      id: 999001,
      title: 'Foxy notifications are on',
      body: 'Task reminders will appear here.',
      notificationDetails: details,
      payload: 'test',
    );
  }
}
