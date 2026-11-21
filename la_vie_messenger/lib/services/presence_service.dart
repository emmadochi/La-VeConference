import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class UserPresence {
  final bool isOnline;
  final String statusText;

  const UserPresence({
    required this.isOnline,
    required this.statusText,
  });
}

class PresenceService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static bool? _lastRecordedOnlineState;
  static DateTime? _lastWriteTime;
  static final Map<String, UserPresence> _presenceCache = {};

  /// Starts tracking presence for the signed-in user without burning continuous writes
  static void startTracking(String uid) {
    // Only refresh online state if changed or cooled down (180s cooldown cuts write bills by 66%)
    if (_lastRecordedOnlineState != true ||
        _lastWriteTime == null ||
        DateTime.now().difference(_lastWriteTime!).inSeconds > 180) {
      _setPresence(uid, true);
    }
  }

  /// Sets presence state in Firestore (rate-limited)
  static Future<void> _setPresence(String uid, bool isOnline) async {
    _lastRecordedOnlineState = isOnline;
    _lastWriteTime = DateTime.now();

    try {
      final Map<String, dynamic> updateData = {
        'isOnline': isOnline,
        'lastSeen': FieldValue.serverTimestamp(),
      };

      await _firestore.collection('users').doc(uid).set(
        updateData,
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint("Presence update error: $e");
    }
  }

  /// Sets the user as offline when the app is paused or closed
  static void setOffline(String uid) {
    if (_lastRecordedOnlineState != false) {
      _setPresence(uid, false);
    }
  }

  /// Returns cached presence if available for 0ms initial UI display
  static UserPresence? getCachedPresence(String uid) => _presenceCache[uid];

  /// Streams real-time presence of a specific user
  static Stream<UserPresence> streamUserPresence(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      if (!doc.exists) {
        const fallback = UserPresence(isOnline: false, statusText: 'Offline');
        _presenceCache[uid] = fallback;
        return fallback;
      }

      final data = doc.data() ?? {};
      final isOnlineField = data['isOnline'] == true;
      final lastSeenTimestamp = data['lastSeen'] as Timestamp?;

      if (lastSeenTimestamp == null) {
        final pres = UserPresence(
          isOnline: isOnlineField,
          statusText: isOnlineField ? 'Online' : 'Offline',
        );
        _presenceCache[uid] = pres;
        return pres;
      }

      final lastSeenDate = lastSeenTimestamp.toDate();
      final diff = DateTime.now().difference(lastSeenDate);

      // The user is online if isOnline is true and last write was within 24 hours (sanity check)
      final isActuallyOnline = isOnlineField && diff.inHours < 24;

      String statusText;
      if (isActuallyOnline) {
        statusText = 'Online';
      } else if (diff.inMinutes < 1) {
        statusText = 'Last seen just now';
      } else if (diff.inMinutes < 60) {
        statusText = 'Last seen ${diff.inMinutes}m ago';
      } else if (diff.inHours < 24) {
        statusText = 'Last seen ${diff.inHours}h ago';
      } else {
        statusText = 'Offline';
      }

      final result = UserPresence(
        isOnline: isActuallyOnline,
        statusText: statusText,
      );
      _presenceCache[uid] = result;
      return result;
    });
  }

  /// Checks if a user is currently online (one-shot)
  static Future<bool> isUserOnline(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (!doc.exists) return false;
      final data = doc.data() ?? {};
      final isOnline = data['isOnline'] == true;
      final lastSeen = data['lastSeen'] as Timestamp?;
      if (!isOnline) return false;
      if (lastSeen == null) return true;
      final diff = DateTime.now().difference(lastSeen.toDate());
      return diff.inHours < 24;
    } catch (_) {
      return false;
    }
  }
}
