import 'dart:convert';
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

enum CalendarSyncStatus {
  addedViaApi,
  openedTemplateIntent,
  failed,
}

class CalendarHelper {
  static const String baseJoinDomain = 'https://la-vie.lifechangerstouch.org/join';

  /// Builds the canonical shareable invite link that works for both Web and Mobile App Links.
  static String buildInviteLink(String roomId, {String? e2eeKey}) {
    final cleanId = roomId.split('#').first.trim();
    final key = (e2eeKey != null && e2eeKey.trim().isNotEmpty)
        ? e2eeKey.trim()
        : (roomId.contains('#') ? roomId.split('#').last.trim() : '');
    if (key.isNotEmpty) {
      return '$baseJoinDomain?room=${Uri.encodeComponent(cleanId)}#$key';
    }
    return '$baseJoinDomain?room=${Uri.encodeComponent(cleanId)}';
  }

  /// Formats a DateTime into Google Calendar UTC template format (yyyyMMddTHHmmssZ).
  static String _formatGCalUtc(DateTime dt) {
    final u = dt.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${u.year}${two(u.month)}${two(u.day)}T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
  }

  /// Builds a universal Google Calendar event creation URL that works for any user/account.
  static String buildGoogleCalendarTemplateUrl({
    required String title,
    required DateTime startTime,
    required String roomId,
    String? e2eeKey,
    String? hostName,
    int durationMinutes = 60,
  }) {
    final endTime = startTime.add(Duration(minutes: durationMinutes));
    final meetingLink = buildInviteLink(roomId, e2eeKey: e2eeKey);
    final hostLine = (hostName != null && hostName.trim().isNotEmpty)
        ? 'Host: ${hostName.trim()}\n'
        : '';
    final details =
        '${hostLine}Join La-Vie Conference:\n$meetingLink\n\nRoom Code: ${roomId.split('#').first}\nThis meeting is End-to-End Encrypted.';

    final uri = Uri.https('calendar.google.com', '/calendar/render', {
      'action': 'TEMPLATE',
      'text': title,
      'dates': '${_formatGCalUtc(startTime)}/${_formatGCalUtc(endTime)}',
      'details': details,
      'location': meetingLink,
    });
    return uri.toString();
  }

  /// Attempts silent/direct creation via Google Calendar REST API (for Google-signed-in users).
  static Future<bool> tryCreateGoogleCalendarApiEvent({
    required String title,
    required DateTime startTime,
    required String roomId,
    String? e2eeKey,
    String? hostName,
    int reminderMinutes = 15,
  }) async {
    try {
      final account = await GoogleSignIn.instance.attemptLightweightAuthentication();
      if (account == null) return false;

      final authClient = await account.authorizationClient.authorizationForScopes([
        'https://www.googleapis.com/auth/calendar.events',
      ]);
      final token = authClient?.accessToken;
      if (token == null || token.isEmpty) return false;

      final endTime = startTime.add(const Duration(hours: 1));
      final meetingLink = buildInviteLink(roomId, e2eeKey: e2eeKey);
      final hostLine = (hostName != null && hostName.trim().isNotEmpty)
          ? 'Host: ${hostName.trim()}\n'
          : '';

      final response = await http.post(
        Uri.parse('https://www.googleapis.com/calendar/v3/calendars/primary/events'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'summary': title,
          'location': meetingLink,
          'description':
              '${hostLine}Join La-Vie Conference:\n$meetingLink\n\nThis meeting is End-to-End Encrypted.',
          'start': {
            'dateTime': startTime.toUtc().toIso8601String(),
          },
          'end': {
            'dateTime': endTime.toUtc().toIso8601String(),
          },
          'reminders': {
            'useDefault': false,
            'overrides': [
              if (reminderMinutes > 0) {'method': 'popup', 'minutes': reminderMinutes},
              {'method': 'popup', 'minutes': 5},
            ],
          },
        }),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('Google Calendar API sync error: $e');
      return false;
    }
  }

  /// Launches Google Calendar App or Browser directly with pre-filled event fields.
  static Future<bool> openGoogleCalendarTemplate({
    required String title,
    required DateTime startTime,
    required String roomId,
    String? e2eeKey,
    String? hostName,
  }) async {
    try {
      final url = buildGoogleCalendarTemplateUrl(
        title: title,
        startTime: startTime,
        roomId: roomId,
        e2eeKey: e2eeKey,
        hostName: hostName,
      );

      if (defaultTargetPlatform == TargetPlatform.android) {
        final intent = AndroidIntent(
          action: 'action_view',
          data: url,
        );
        await intent.launch();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Failed to launch Google Calendar intent: $e');
      return false;
    }
  }

  /// Tries silent Google Calendar API first; if unavailable or user prefers interactive fallback,
  /// launches Google Calendar Template intent so 100% of users (including email-login users) succeed.
  static Future<CalendarSyncStatus> addMeetingToGoogleCalendar({
    required String title,
    required DateTime startTime,
    required String roomId,
    String? e2eeKey,
    String? hostName,
    int reminderMinutes = 15,
    bool allowInteractiveFallback = true,
  }) async {
    final apiSuccess = await tryCreateGoogleCalendarApiEvent(
      title: title,
      startTime: startTime,
      roomId: roomId,
      e2eeKey: e2eeKey,
      hostName: hostName,
      reminderMinutes: reminderMinutes,
    );
    if (apiSuccess) {
      return CalendarSyncStatus.addedViaApi;
    }

    if (allowInteractiveFallback) {
      final launched = await openGoogleCalendarTemplate(
        title: title,
        startTime: startTime,
        roomId: roomId,
        e2eeKey: e2eeKey,
        hostName: hostName,
      );
      if (launched) {
        return CalendarSyncStatus.openedTemplateIntent;
      }
    }

    return CalendarSyncStatus.failed;
  }
}

