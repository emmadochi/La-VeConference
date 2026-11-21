import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/status_model.dart';
import 'media_storage_service.dart';

class StatusService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Post a new Text Status
  static Future<void> postTextStatus({
    required String uid,
    required String userName,
    String? userAvatar,
    required String text,
    required List<int> gradientColors,
    String fontStyle = 'default',
    String privacy = 'all',
    List<String> privacyUids = const [],
    int durationHours = 24,
  }) async {
    try {
      final docRef = _firestore.collection('statuses').doc();
      final now = DateTime.now();
      final safeHours = (durationHours >= 1 && durationHours <= 48) ? durationHours : 24;
      final expiresAt = now.add(Duration(hours: safeHours));

      await docRef.set({
        'id': docRef.id,
        'uid': uid,
        'userName': userName,
        'userAvatar': userAvatar ?? '',
        'type': 'text',
        'content': text.trim(),
        'caption': null,
        'gradientColors': gradientColors,
        'fontStyle': fontStyle,
        'durationHours': safeHours,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expiresAt),
        'viewers': [],
        'viewerInfo': {},
        'privacy': privacy,
        'privacyUids': privacyUids,
      });

      // Update user doc with last status activity timestamp
      await _firestore.collection('users').doc(uid).set({
        'lastStatusTime': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Error posting text status: $e");
      rethrow;
    }
  }

  /// Post a new Image or Media Status
  static Future<void> postMediaStatus({
    required String uid,
    required String userName,
    String? userAvatar,
    required File mediaFile,
    String type = 'image',
    String? caption,
    String privacy = 'all',
    List<String> privacyUids = const [],
    int durationHours = 24,
    void Function(int bytesSent, int totalBytes)? onProgress,
  }) async {
    try {
      String ext = mediaFile.path.contains('.')
          ? mediaFile.path.split('.').last.toLowerCase()
          : (type == 'video' ? 'mp4' : 'jpg');
      if (ext.length > 5 || ext.isEmpty) {
        ext = type == 'video' ? 'mp4' : 'jpg';
      }

      String contentType;
      if (type == 'image') {
        contentType = ext == 'png' ? 'image/png' : 'image/jpeg';
      } else {
        if (ext == 'mov') {
          contentType = 'video/quicktime';
        } else if (ext == '3gp') {
          contentType = 'video/3gpp';
        } else if (ext == 'webm') {
          contentType = 'video/webm';
        } else {
          contentType = 'video/mp4';
        }
      }

      final fileName = 'status_${type}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final mediaUrl = await MediaStorageService.uploadEphemeralMedia(
        file: mediaFile,
        chatId: 'status_$uid',
        fileName: fileName,
        contentType: contentType,
        onProgress: onProgress,
      );

      final docRef = _firestore.collection('statuses').doc();
      final now = DateTime.now();
      final safeHours = (durationHours >= 1 && durationHours <= 48) ? durationHours : 24;
      final expiresAt = now.add(Duration(hours: safeHours));

      await docRef.set({
        'id': docRef.id,
        'uid': uid,
        'userName': userName,
        'userAvatar': userAvatar ?? '',
        'type': type,
        'content': mediaUrl,
        'caption': caption?.trim(),
        'gradientColors': [0xFF7C3AED, 0xFF9333EA],
        'fontStyle': 'default',
        'durationHours': safeHours,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expiresAt),
        'viewers': [],
        'viewerInfo': {},
        'privacy': privacy,
        'privacyUids': privacyUids,
      });

      // Save a local copy so the uploader experiences 0ms instant playback
      try {
        await MediaStorageService.saveOutgoingFile(
          sourceFile: mediaFile,
          category: 'StatusDownloads',
          targetFileName: 'status_${docRef.id}.$ext',
        );
      } catch (_) {}

      // Update user doc with last status activity timestamp
      await _firestore.collection('users').doc(uid).set({
        'lastStatusTime': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Error posting media status: $e");
      rethrow;
    }
  }

  /// Post a new Voice Note / Audio Status
  static Future<void> postAudioStatus({
    required String uid,
    required String userName,
    String? userAvatar,
    required File audioFile,
    required int durationSeconds,
    required List<int> gradientColors,
    String? caption,
    String privacy = 'all',
    List<String> privacyUids = const [],
    int durationHours = 24,
  }) async {
    try {
      final fileName = 'status_audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final mediaUrl = await MediaStorageService.uploadEphemeralMedia(
        file: audioFile,
        chatId: 'status_$uid',
        fileName: fileName,
        contentType: 'audio/m4a',
      );

      final docRef = _firestore.collection('statuses').doc();
      final now = DateTime.now();
      final safeHours = (durationHours >= 1 && durationHours <= 48) ? durationHours : 24;
      final expiresAt = now.add(Duration(hours: safeHours));

      await docRef.set({
        'id': docRef.id,
        'uid': uid,
        'userName': userName,
        'userAvatar': userAvatar ?? '',
        'type': 'audio',
        'content': mediaUrl,
        'caption': caption?.trim(),
        'gradientColors': gradientColors,
        'fontStyle': 'default',
        'duration': durationSeconds,
        'durationHours': safeHours,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expiresAt),
        'viewers': [],
        'viewerInfo': {},
        'privacy': privacy,
        'privacyUids': privacyUids,
      });

      // Save a local copy so the uploader experiences 0ms instant playback
      try {
        await MediaStorageService.saveOutgoingFile(
          sourceFile: audioFile,
          category: 'StatusDownloads',
          targetFileName: 'status_${docRef.id}.m4a',
        );
      } catch (_) {}

      // Update user doc with last status activity timestamp
      await _firestore.collection('users').doc(uid).set({
        'lastStatusTime': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Error posting audio status: $e");
      rethrow;
    }
  }

  /// Stream all active (non-expired) statuses grouped by user.
  /// Enforces strict privacy: statuses are ONLY shown between users who are verified mutual contacts.
  static Stream<List<UserStatusGroup>> streamActiveStatusGroups({
    required String myUid,
    List<String>? contactUids,
  }) {
    // Up to 48 hours window for custom longevity statuses
    final cutoff = DateTime.now().subtract(const Duration(hours: 48));

    final Stream<Set<String>> contactsStream = contactUids != null
        ? Stream.value(contactUids.toSet())
        : _firestore
            .collection('users')
            .doc(myUid)
            .collection('contacts')
            .snapshots()
            .map((snap) => snap.docs.map((d) => d.id).toSet());

    return contactsStream.asyncExpand((verifiedUids) {
      return _firestore
          .collection('statuses')
          .where('createdAt', isGreaterThan: Timestamp.fromDate(cutoff))
          .orderBy('createdAt', descending: false)
          .snapshots()
          .map((snapshot) {
        final Map<String, List<StatusItem>> userItems = {};
        final Map<String, Map<String, dynamic>> userMeta = {};

        for (final doc in snapshot.docs) {
          final item = StatusItem.fromFirestore(doc);
          if (item.isExpired) continue;

          // STRICT PRIVACY: User status is only visible between users that have each other's contact
          if (item.uid != myUid && !verifiedUids.contains(item.uid)) {
            continue;
          }

          if (!item.canBeViewedBy(myUid)) continue;

          userItems.putIfAbsent(item.uid, () => []).add(item);
          userMeta[item.uid] = {
            'name': item.userName,
            'avatar': item.userAvatar,
          };
        }

        final List<UserStatusGroup> groups = [];
        userItems.forEach((uid, items) {
          groups.add(UserStatusGroup(
            uid: uid,
            userName: userMeta[uid]?['name'] ?? 'User',
            userAvatar: userMeta[uid]?['avatar'],
            items: items,
          ));
        });

        // Sort: My status first, then by most recent status update
        groups.sort((a, b) {
          if (a.uid == myUid) return -1;
          if (b.uid == myUid) return 1;
          return b.lastUpdated.compareTo(a.lastUpdated);
        });

        return groups;
      });
    });
  }

  /// Record a viewer on a status item
  static Future<void> markStatusViewed({
    required String statusId,
    required String viewerUid,
    required String viewerName,
    String? viewerAvatar,
  }) async {
    try {
      final docRef = _firestore.collection('statuses').doc(statusId);
      final keyName = 'viewerInfo.$viewerUid';

      await docRef.update({
        'viewers': FieldValue.arrayUnion([viewerUid]),
        keyName: {
          'name': viewerName,
          'avatar': viewerAvatar ?? '',
          'viewedAt': Timestamp.now(),
        },
      });
    } catch (e) {
      debugPrint("Error marking status viewed: $e");
    }
  }

  /// Delete a status item
  static Future<void> deleteStatus(String statusId) async {
    try {
      await _firestore.collection('statuses').doc(statusId).delete();
    } catch (e) {
      debugPrint("Error deleting status: $e");
    }
  }
}
