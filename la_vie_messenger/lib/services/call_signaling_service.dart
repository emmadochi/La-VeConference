import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'presence_service.dart';

class _TokenCacheEntry {
  final Map<String, String> data;
  final DateTime timestamp;
  _TokenCacheEntry(this.data, this.timestamp);
}

class CallSignalingService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _backendUrl = 'https://la-vie.lifechangerstouch.org';

  /// Creates an outgoing call record and begins contacting the receiver
  static Future<String> initiateCall({
    required String callerId,
    required String callerName,
    String? callerAvatar,
    required String receiverId,
    required String receiverName,
    String? receiverAvatar,
    bool isVideo = true,
  }) async {
    final docRef = _firestore.collection('calls').doc();
    final callId = docRef.id;

    await docRef.set({
      'callId': callId,
      'callerId': callerId,
      'callerName': callerName,
      'callerAvatar': callerAvatar ?? '',
      'receiverId': receiverId,
      'receiverName': receiverName,
      'receiverAvatar': receiverAvatar ?? '',
      'isVideo': isVideo,
      'status': 'calling', // Starts as 'calling', transitions to 'ringing' when receiver phone wakes up
      'roomName': 'call_$callId',
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Send high-priority wake-up push notification via backend
    try {
      final res = await http.post(
        Uri.parse('$_backendUrl/api/call/notify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'call_id': callId,
          'caller_id': callerId,
          'caller_name': callerName,
          'caller_avatar': callerAvatar ?? '',
          'receiver_id': receiverId,
          'is_video': isVideo,
          'room_name': 'call_$callId',
        }),
      ).timeout(const Duration(seconds: 6));

      debugPrint("Call push response: ${res.statusCode} ${res.body}");
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['status'] == 'no_token' || body['status'] == 'skipped') {
          // Check if user is online in Firestore
          final isOnline = await PresenceService.isUserOnline(receiverId);
          if (!isOnline) {
            await markOffline(callId);
          }
        }
      }
    } catch (e) {
      debugPrint("Could not deliver push notification for call: $e");
    }

    return callId;
  }

  /// Initiates a multi-party group call ringing all group participants
  static Future<String> initiateGroupCall({
    required String callerId,
    required String callerName,
    String? callerAvatar,
    required String groupId,
    required String groupName,
    required List<String> memberUids,
    bool isVideo = true,
  }) async {
    final roomName = 'group_call_${groupId}_${DateTime.now().millisecondsSinceEpoch}';

    // Ring each member in the group concurrently
    for (final memberUid in memberUids) {
      if (memberUid == callerId) continue;
      inviteToActiveCall(
        roomName: roomName,
        inviterId: callerId,
        inviterName: callerName,
        inviterAvatar: callerAvatar,
        contactUid: memberUid,
        contactName: groupName,
        isVideo: isVideo,
        isGroup: true,
        groupName: groupName,
      );
    }

    return roomName;
  }

  /// Invites an additional participant into an active LiveKit room
  static Future<String> inviteToActiveCall({
    required String roomName,
    required String inviterId,
    required String inviterName,
    String? inviterAvatar,
    required String contactUid,
    required String contactName,
    String? contactAvatar,
    bool isVideo = true,
    bool isGroup = false,
    String? groupName,
  }) async {
    final docRef = _firestore.collection('calls').doc();
    final callId = docRef.id;

    await docRef.set({
      'callId': callId,
      'callerId': inviterId,
      'callerName': inviterName,
      'callerAvatar': inviterAvatar ?? '',
      'receiverId': contactUid,
      'receiverName': contactName,
      'receiverAvatar': contactAvatar ?? '',
      'isVideo': isVideo,
      'isGroup': isGroup,
      'groupName': groupName ?? '',
      'status': 'calling',
      'roomName': roomName,
      'createdAt': FieldValue.serverTimestamp(),
    });

    try {
      final res = await http.post(
        Uri.parse('$_backendUrl/api/call/notify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'call_id': callId,
          'caller_id': inviterId,
          'caller_name': inviterName,
          'caller_avatar': inviterAvatar ?? '',
          'receiver_id': contactUid,
          'is_video': isVideo,
          'room_name': roomName,
          'is_group': isGroup,
          'group_name': groupName ?? '',
        }),
      ).timeout(const Duration(seconds: 6));

      debugPrint("Invite to active call push response: ${res.statusCode} ${res.body}");
    } catch (e) {
      debugPrint("Could not deliver push notification for invite: $e");
    }

    return callId;
  }

  /// Receiver acknowledges the call and starts physically ringing
  static Future<void> markRinging(String callId) async {
    try {
      await _firestore.collection('calls').doc(callId).update({
        'status': 'ringing',
        'ringingAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  /// Receiver is verified offline or unreachable
  static Future<void> markOffline(String callId) async {
    try {
      await _firestore.collection('calls').doc(callId).update({
        'status': 'offline',
        'endedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  /// Receiver answers the call
  static Future<void> acceptCall(String callId) async {
    await _firestore.collection('calls').doc(callId).update({
      'status': 'accepted',
      'acceptedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Receiver declines the call
  static Future<void> declineCall(String callId) async {
    await _firestore.collection('calls').doc(callId).update({
      'status': 'declined',
      'endedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Either party hangs up
  static Future<void> endCall(String callId, {int? durationSeconds}) async {
    final updateData = <String, dynamic>{
      'status': 'ended',
      'endedAt': FieldValue.serverTimestamp(),
    };
    if (durationSeconds != null && durationSeconds > 0) {
      updateData['duration'] = durationSeconds;
    }
    await _firestore.collection('calls').doc(callId).update(updateData);
  }

  /// Remove a call from history
  static Future<void> deleteCallHistoryItem(String callId) async {
    try {
      await _firestore.collection('calls').doc(callId).delete();
    } catch (e) {
      debugPrint("Error deleting call history item: $e");
    }
  }

  /// Timeout when receiver didn't pick up
  static Future<void> markMissed(String callId) async {
    try {
      await _firestore.collection('calls').doc(callId).update({
        'status': 'missed',
        'seen': false,
        'endedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  /// Real-time stream of a call's status
  static Stream<DocumentSnapshot<Map<String, dynamic>>> streamCall(String callId) {
    return _firestore.collection('calls').doc(callId).snapshots();
  }

  /// Stream of incoming calls for a user (listens to both calling and ringing states)
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamIncomingCalls(String myUid) {
    return _firestore
        .collection('calls')
        .where('receiverId', isEqualTo: myUid)
        .where('status', whereIn: ['calling', 'ringing'])
        .limit(1)
        .snapshots();
  }

  /// Stream of call history (All / Missed) - no composite index required
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamCallHistory(String myUid) {
    return _firestore
        .collection('calls')
        .where(Filter.or(
          Filter('callerId', isEqualTo: myUid),
          Filter('receiverId', isEqualTo: myUid),
        ))
        .snapshots();
  }

  static final Map<String, _TokenCacheEntry> _tokenCache = {};

  /// Pre-warms or fetches a LiveKit token for zero-latency call connection
  static Future<Map<String, String>?> getOrFetchToken({
    required String roomName,
    required String userId,
    required String userName,
  }) async {
    final cacheKey = '$roomName:$userId';
    final cached = _tokenCache[cacheKey];
    if (cached != null && DateTime.now().difference(cached.timestamp).inMinutes < 5) {
      return cached.data;
    }

    try {
      final res = await http.post(
        Uri.parse('$_backendUrl/api/call/token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'room_name': roomName,
          'user_id': userId,
          'user_name': userName,
        }),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final result = {
          'token': data['token'] as String,
          'url': data['url'] as String,
        };
        _tokenCache[cacheKey] = _TokenCacheEntry(result, DateTime.now());
        return result;
      }
    } catch (e) {
      debugPrint("Pre-warming LiveKit token error: $e");
    }
    return null;
  }

  /// Removes cached tokens for a room so the next connect attempt fetches fresh credentials.
  static void evictTokenCache(String roomName) {
    _tokenCache.removeWhere((key, _) => key.startsWith('$roomName:'));
  }

  /// Starts server-side LiveKit Egress recording for this call
  static Future<Map<String, dynamic>?> startCallRecording({
    required String callId,
    required String roomName,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_backendUrl/api/call/record/start'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'call_id': callId,
          'room_name': roomName,
        }),
      ).timeout(const Duration(seconds: 12));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint("Error starting call recording: $e");
    }
    return null;
  }

  /// Stops server-side LiveKit Egress recording for this call
  static Future<Map<String, dynamic>?> stopCallRecording({
    required String callId,
    String? egressId,
    String? fileName,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_backendUrl/api/call/record/stop'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'call_id': callId,
          if (egressId != null) 'egress_id': egressId,
          if (fileName != null) 'file_name': fileName,
        }),
      ).timeout(const Duration(seconds: 12));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint("Error stopping call recording: $e");
    }
    return null;
  }

  /// Informs the server to immediately delete the recording after local download
  static Future<bool> purgeServerRecording({
    required String fileName,
    String? callId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_backendUrl/api/call/record/delete'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'file_name': fileName,
          if (callId != null) 'call_id': callId,
        }),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['deleted'] == true;
      }
    } catch (e) {
      debugPrint("Error purging server recording: $e");
    }
    return false;
  }

  /// Requests remote peer to switch/upgrade current audio call to video
  static Future<void> requestVideoUpgrade({
    required String callId,
    required String requesterId,
    required String requesterName,
  }) async {
    try {
      await _firestore.collection('calls').doc(callId).update({
        'videoUpgrade': {
          'requesterId': requesterId,
          'requesterName': requesterName,
          'status': 'pending',
          'requestedAt': FieldValue.serverTimestamp(),
        },
      });
    } catch (e) {
      debugPrint("Error requesting video upgrade: $e");
    }
  }

  /// Responds to a video upgrade request (accept or decline)
  static Future<void> respondVideoUpgrade({
    required String callId,
    required bool accept,
  }) async {
    try {
      await _firestore.collection('calls').doc(callId).update({
        'videoUpgrade.status': accept ? 'accepted' : 'declined',
        'videoUpgrade.respondedAt': FieldValue.serverTimestamp(),
        if (accept) 'isVideo': true,
      });
    } catch (e) {
      debugPrint("Error responding to video upgrade: $e");
    }
  }

  /// Clears video upgrade state after handling
  static Future<void> clearVideoUpgrade(String callId) async {
    try {
      await _firestore.collection('calls').doc(callId).update({
        'videoUpgrade': FieldValue.delete(),
      });
    } catch (e) {
      debugPrint("Error clearing video upgrade: $e");
    }
  }
}


