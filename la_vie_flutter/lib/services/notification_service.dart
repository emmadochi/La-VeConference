import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main.dart';
import '../screens/notifications_screen.dart';
import '../screens/video_room_screen.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  NotificationService._internal();

  Future<void> init() async {
    tz.initializeTimeZones();

    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/launcher_icon');
    
    // We request permissions manually, so set request functions to false here
    final DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const LinuxInitializationSettings initializationSettingsLinux = LinuxInitializationSettings(
      defaultActionName: 'Open notification',
    );
    
    final InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
      macOS: initializationSettingsIOS,
      linux: initializationSettingsLinux,
    );

    try {
      await flutterLocalNotificationsPlugin.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          final payload = response.payload;
          if (payload != null && (payload == 'open_notes' || payload.contains('open_notes'))) {
            navigatorKey.currentState?.push(
              MaterialPageRoute(builder: (context) => const NotificationsScreen()),
            );
          } else if (payload != null && payload.startsWith('open_room:')) {
            final roomId = payload.substring('open_room:'.length).trim();
            if (roomId.isNotEmpty) {
              final userName = FirebaseAuth.instance.currentUser?.displayName ?? 'Participant';
              navigatorKey.currentState?.push(
                MaterialPageRoute(
                  builder: (context) => VideoRoomScreen(
                    roomName: roomId,
                    participantName: userName,
                  ),
                ),
              );
            }
          }
        },
      );
    } catch (e) {
      debugPrint('NotificationService initialization skipped or unsupported on this platform: $e');
    }
  }

  Future<void> requestPermissions() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        await androidImplementation.requestNotificationsPermission();
      }
    }
  }

  Future<void> showImmediateNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'la_vie_meetings',
      'Meetings',
      channelDescription: 'Notifications for meetings',
      importance: Importance.max,
      priority: Priority.high,
    );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: DarwinNotificationDetails(),
    );
    
    await flutterLocalNotificationsPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: platformChannelSpecifics,
      payload: payload,
    );
  }

  Future<void> scheduleMeetingReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
  }) async {
    final localTarget = scheduledDate.isUtc ? scheduledDate.toLocal() : scheduledDate;
    if (localTarget.isBefore(DateTime.now())) return; // Don't schedule in the past

    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'la_vie_meeting_reminders',
      'Meeting Reminders',
      channelDescription: 'Reminders for upcoming meetings',
      importance: Importance.max,
      priority: Priority.high,
    );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: DarwinNotificationDetails(),
    );

    final tzTarget = tz.TZDateTime.from(localTarget, tz.local);

    try {
      bool useExact = true;
      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidImpl = flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        if (androidImpl != null) {
          useExact = await androidImpl.canScheduleExactNotifications() ?? false;
        }
      }

      await flutterLocalNotificationsPlugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tzTarget,
        notificationDetails: platformChannelSpecifics,
        androidScheduleMode: useExact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
      );
    } catch (e) {
      debugPrint('Exact alarm scheduling unavailable ($e), falling back to inexact reminder');
      try {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          id: id,
          title: title,
          body: body,
          scheduledDate: tzTarget,
          notificationDetails: platformChannelSpecifics,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: payload,
        );
      } catch (fallbackErr) {
        debugPrint('Local reminder fallback failed: $fallbackErr');
      }
    }
  }

  Future<void> cancelNotification(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id: id);
  }
}
