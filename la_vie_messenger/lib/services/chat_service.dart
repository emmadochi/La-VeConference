import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'contact_service.dart';
import 'local_db_service.dart';
import 'sound_service.dart';

class ChatService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _backendUrl = 'https://la-vie.lifechangerstouch.org';

  /// Deterministic chat ID between two users
  static String getConversationId(String uid1, String uid2) {
    final list = [uid1, uid2]..sort();
    return '${list[0]}_${list[1]}';
  }

  /// Sends a text or media message (supports both 1-on-1 and Group chats)
  static Future<String> sendMessage({
    required String chatId,
    required String senderId,
    required String senderName,
    required String receiverId,
    required String text,
    String type = 'text', // 'text', 'image', 'audio', 'file'
    String? mediaUrl,
    String? fileName,
    int? fileSize,
    int? duration,
    String? localPath,
    Map<String, dynamic>? replyTo,
    Map<String, dynamic>? poll,
    bool isGroup = false,
    String? groupName,
    List<String>? groupParticipants,
    String? clientTempId,
  }) async {
    // 1. Strict Gatekeeping using instant in-memory cached verification
    if (!isGroup) {
      final isVerified = await ContactService.isContactVerified(senderId, receiverId);
      if (!isVerified) {
        throw StateError('Cannot send message: Contact connection not verified. You must be mutual contacts to chat on LiChat.');
      }
    }

    final messageRef = _firestore.collection('chats').doc(chatId).collection('messages').doc();
    SoundService.instance.playMessageSent();

    // Standard WhatsApp-style protocol:
    // Outgoing messages start with status 'sent' (single checkmark).
    // The recipient's device immediately marks it 'delivered' (double checkmark) when received.
    const String initialStatus = 'sent';

    final messageData = {
      'id': messageRef.id,
      'clientTempId': clientTempId,
      'senderId': senderId,
      'senderName': senderName,
      'receiverId': receiverId,
      'text': text,
      'type': type,
      'mediaUrl': mediaUrl,
      'fileName': fileName,
      'fileSize': fileSize,
      'duration': duration,
      'localPath': localPath,
      'replyTo': replyTo,
      'poll': poll,
      'timestamp': FieldValue.serverTimestamp(),
      'status': initialStatus, // 'sent', 'delivered', 'read'
      'reaction': null,
      'isGroup': isGroup,
      'readBy': {
        senderId: FieldValue.serverTimestamp(),
      },
      'deliveredTo': {
        senderId: FieldValue.serverTimestamp(),
      },
    };

    final Map<String, dynamic> unreadUpdates = {};
    if (isGroup && groupParticipants != null) {
      for (final uid in groupParticipants) {
        if (uid != senderId) {
          unreadUpdates[uid] = FieldValue.increment(1);
        } else {
          unreadUpdates[uid] = 0;
        }
      }
    } else {
      unreadUpdates[receiverId] = FieldValue.increment(1);
      unreadUpdates[senderId] = 0;
    }

    String previewText = text;
    if (type == 'audio') {
      previewText = '🎤 Voice note${duration != null ? ' (${duration ~/ 60}:${(duration % 60).toString().padLeft(2, '0')})' : ''}';
    } else if (type == 'image') {
      previewText = '📷 Photo';
    } else if (type == 'file') {
      previewText = '📄 ${fileName ?? 'Document'}';
    } else if (type == 'poll') {
      previewText = '📊 Poll: ${poll?['question'] ?? 'Poll'}';
    }

    final participantsList = isGroup
        ? (groupParticipants ?? [senderId, receiverId])
        : [senderId, receiverId];

    final chatMeta = {
      'chatId': chatId,
      'isGroup': isGroup,
      'participants': participantsList,
      'lastMessage': previewText,
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastSenderId': senderId,
      'lastSenderName': senderName,
      'participantNames.$senderId': senderName,
      'lastMessageStatus': initialStatus, // 'sent', 'delivered', 'read'
      'unreadCounts': unreadUpdates,
    };

    final batch = _firestore.batch();
    batch.set(messageRef, messageData);
    batch.set(_firestore.collection('chats').doc(chatId), chatMeta, SetOptions(merge: true));
    await batch.commit();

    // Mark previous incoming messages in this chat as read since sender is actively communicating
    unawaited(markAsRead(chatId, senderId));

    // Save outgoing message to local SQLite immediately (WhatsApp-style local-first)
    unawaited(LocalDbService.upsertMessage({
      'id': messageRef.id,
      'chatId': chatId,
      'senderId': senderId,
      'senderName': senderName,
      'receiverId': receiverId,
      'text': text,
      'type': type,
      'mediaUrl': mediaUrl,
      'localPath': localPath,
      'fileName': fileName,
      'fileSize': fileSize,
      'duration': duration,
      'status': 'sent',
      'isRead': true, // sender has read their own message
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'replyToId': replyTo?['id'],
      'replyToText': replyTo?['text'],
      'isGroup': isGroup,
    }));

    // Update conversation list cache in SQLite
    unawaited(LocalDbService.upsertConversation({
      'chatId': chatId,
      'peerUid': receiverId,
      'lastMessage': previewText,
      'lastMessageType': type,
      'lastTimestamp': DateTime.now().millisecondsSinceEpoch,
      'unreadCount': 0,
      'isGroup': isGroup,
    }));

    // Dispatch background push notification to recipient(s) in a single high-scale multicast request
    unawaited(() async {
      try {
        final recipients = (isGroup && groupParticipants != null)
            ? groupParticipants.where((id) => id != senderId).toList()
            : [receiverId];

        if (recipients.isEmpty) return;

        String resolvedGroupName = groupName ?? '';
        if (isGroup && resolvedGroupName.isEmpty) {
          try {
            final chatDoc = await _firestore.collection('chats').doc(chatId).get();
            resolvedGroupName = (chatDoc.data()?['groupName'] ?? chatDoc.data()?['name'] ?? 'Group') as String;
          } catch (_) {}
        }

        await http.post(
          Uri.parse('$_backendUrl/api/chat/notify'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'chat_id': chatId,
            'message_id': messageRef.id,
            'sender_id': senderId,
            'sender_name': senderName,
            'receiver_ids': recipients,
            'receiver_id': recipients.length == 1 ? recipients.first : null,
            'text': previewText,
            'is_group': isGroup,
            'group_name': resolvedGroupName,
          }),
        ).timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint("Error dispatching chat notification: $e");
      }
    }());

    return messageRef.id;
  }

  /// Triggers server-side purge of delivered messages older than [olderThanDays]
  static Future<void> purgeDeliveredMessages(String chatId, {int olderThanDays = 7}) async {
    try {
      await http.post(
        Uri.parse('$_backendUrl/api/chat/purge_delivered'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chat_id': chatId,
          'older_than_days': olderThanDays,
        }),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  /// Creates a new Group Chat
  static Future<String> createGroupChat({
    required String groupName,
    required List<String> memberUids,
    required String myUid,
    required String myName,
    String? groupAvatar,
    bool isChannel = false,
  }) async {
    final docRef = _firestore.collection('chats').doc();
    final chatId = docRef.id;
    final allMembers = [myUid, ...memberUids.where((id) => id != myUid)];

    final Map<String, dynamic> unreadCounts = {};
    for (final uid in allMembers) {
      unreadCounts[uid] = 0;
    }

    final entityType = isChannel ? 'channel' : 'group';

    await docRef.set({
      'chatId': chatId,
      'isGroup': true,
      'isChannel': isChannel,
      'onlyAdminsCanPost': isChannel,
      'name': groupName.trim(),
      'groupName': groupName.trim(),
      'avatar': groupAvatar ?? '',
      'groupAvatar': groupAvatar ?? '',
      'participants': allMembers,
      'admins': [myUid],
      'creatorId': myUid,
      'createdAt': FieldValue.serverTimestamp(),
      'lastMessage': '$myName created $entityType "${groupName.trim()}"',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastSenderId': myUid,
      'lastSenderName': myName,
      'unreadCounts': unreadCounts,
    });

    // Add initial system message
    final msgRef = docRef.collection('messages').doc();
    await msgRef.set({
      'id': msgRef.id,
      'senderId': myUid,
      'senderName': myName,
      'receiverId': '',
      'text': '$myName created $entityType "${groupName.trim()}"',
      'type': 'system',
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'read',
      'isGroup': true,
    });

    return chatId;
  }

  /// Renames a group chat and writes an event system message
  static Future<void> updateGroupName({
    required String chatId,
    required String newName,
    required String updaterUid,
    required String updaterName,
  }) async {
    final cleanName = newName.trim();
    if (cleanName.isEmpty) return;

    await _firestore.collection('chats').doc(chatId).update({
      'name': cleanName,
      'groupName': cleanName,
      'lastMessage': '$updaterName changed group name to "$cleanName"',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastSenderId': updaterUid,
      'lastSenderName': updaterName,
    });

    final msgRef = _firestore.collection('chats').doc(chatId).collection('messages').doc();
    await msgRef.set({
      'id': msgRef.id,
      'senderId': updaterUid,
      'senderName': updaterName,
      'receiverId': '',
      'text': '$updaterName changed group name to "$cleanName"',
      'type': 'system',
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'read',
      'isGroup': true,
    });
  }

  /// Adds new participants to an existing group without duplicates
  static Future<void> addParticipantsToGroup({
    required String chatId,
    required List<String> newMemberUids,
    required List<String> newMemberNames,
    required String adderUid,
    required String adderName,
  }) async {
    if (newMemberUids.isEmpty) return;

    final docRef = _firestore.collection('chats').doc(chatId);

    final Map<String, dynamic> unreadUpdates = {};
    for (final uid in newMemberUids) {
      unreadUpdates['unreadCounts.$uid'] = 0;
    }

    final namesText = newMemberNames.join(', ');
    final systemText = '$adderName added $namesText to the group';

    await docRef.update({
      'participants': FieldValue.arrayUnion(newMemberUids),
      'lastMessage': systemText,
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastSenderId': adderUid,
      'lastSenderName': adderName,
      ...unreadUpdates,
    });

    final msgRef = docRef.collection('messages').doc();
    await msgRef.set({
      'id': msgRef.id,
      'senderId': adderUid,
      'senderName': adderName,
      'receiverId': '',
      'text': systemText,
      'type': 'system',
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'read',
      'isGroup': true,
    });
  }

  /// Reacts to a message with an emoji (WhatsApp-style per-user reactions and toggle)
  static Future<void> setReaction(String chatId, String messageId, String? emoji, {String? myUid}) async {
    try {
      final docRef = _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId);
      final doc = await docRef.get();
      if (doc.exists) {
        final data = doc.data() ?? {};
        final Map<String, dynamic> reactions = Map<String, dynamic>.from(data['reactions'] ?? {});
        final uid = myUid ?? FirebaseAuth.instance.currentUser?.uid;

        if (uid != null) {
          if (reactions[uid] == emoji || emoji == null) {
            reactions.remove(uid);
          } else {
            reactions[uid] = emoji;
          }
        }

        final current = data['reaction'];
        final newReaction = current == emoji ? null : emoji;

        await docRef.update({
          'reaction': newReaction,
          if (uid != null) 'reactions': reactions,
        });
      }
    } catch (e) {
      debugPrint("Error setting reaction: $e");
    }
  }

  /// Real-time stream of messages in a conversation
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamMessages(String chatId) {
    if (chatId.isEmpty) return const Stream.empty();
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots();
  }

  /// Real-time stream of recent conversations (no composite index required)
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamConversations(String myUid) {
    if (myUid.isEmpty) return const Stream.empty();
    return _firestore
        .collection('chats')
        .where('participants', arrayContains: myUid)
        .snapshots();
  }

  /// Mark conversation and all incoming unread messages as read
  static Future<void> markAsRead(String chatId, String myUid) async {
    try {
      // 1. Reset unread counter on chat document
      await _firestore.collection('chats').doc(chatId).set({
        'unreadCounts': {myUid: 0},
      }, SetOptions(merge: true));

      // 2. Query recent messages in chat and update those sent to me that are not yet marked 'read'
      final recentDocs = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(50)
          .get();

      if (recentDocs.docs.isNotEmpty) {
        final batch = _firestore.batch();
        bool hasUpdates = false;
        for (final doc in recentDocs.docs) {
          final data = doc.data();
          final rawReadBy = data['readBy'];
          final readBy = rawReadBy is Map ? Map<String, dynamic>.from(rawReadBy) : <String, dynamic>{};
          final alreadyReadByMe = readBy.containsKey(myUid);

          if (data['senderId'] != myUid && !alreadyReadByMe) {
            batch.set(
              doc.reference,
              {
                'status': 'read',
                'readAt': FieldValue.serverTimestamp(),
                'readBy': {myUid: FieldValue.serverTimestamp()},
                'deliveredTo': {myUid: FieldValue.serverTimestamp()},
              },
              SetOptions(merge: true),
            );
            hasUpdates = true;
          }
        }
        if (hasUpdates) {
          batch.set(
            _firestore.collection('chats').doc(chatId),
            {'lastMessageStatus': 'read'},
            SetOptions(merge: true),
          );
        }
        await batch.commit();
      }
      unawaited(LocalDbService.markChatRead(chatId));
    } catch (e) {
      debugPrint("Error in markAsRead: $e");
    }
  }

  /// Mark specific message document references directly as read (0ms from active message stream)
  static Future<void> markMessagesAsReadDirectly(
    String chatId,
    String myUid,
    List<DocumentReference<Map<String, dynamic>>> docRefs,
  ) async {
    if (docRefs.isEmpty) return;
    try {
      final batch = _firestore.batch();
      for (final ref in docRefs) {
        batch.set(
          ref,
          {
            'status': 'read',
            'readAt': FieldValue.serverTimestamp(),
            'readBy': {myUid: FieldValue.serverTimestamp()},
            'deliveredTo': {myUid: FieldValue.serverTimestamp()},
          },
          SetOptions(merge: true),
        );
      }
      batch.set(
        _firestore.collection('chats').doc(chatId),
        {
          'unreadCounts': {myUid: 0},
          'lastMessageStatus': 'read',
        },
        SetOptions(merge: true),
      );
      await batch.commit();
      unawaited(LocalDbService.markChatRead(chatId));
    } catch (e) {
      debugPrint("Error in markMessagesAsReadDirectly: $e");
    }
  }

  /// Bulk caches incoming Firestore messages to local SQLite database asynchronously
  static void syncMessagesToLocalDb(String chatId, List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    unawaited(() async {
      try {
        for (final doc in docs) {
          final data = doc.data();
          final ts = data['timestamp'];
          int epochMs = DateTime.now().millisecondsSinceEpoch;
          if (ts is Timestamp) {
            epochMs = ts.millisecondsSinceEpoch;
          } else if (ts is int) {
            epochMs = ts;
          }
          final replyTo = data['replyTo'] is Map ? data['replyTo'] as Map : null;
          await LocalDbService.upsertMessage({
            'id': doc.id,
            'chatId': chatId,
            'senderId': data['senderId'] ?? '',
            'senderName': data['senderName'],
            'receiverId': data['receiverId'],
            'text': data['text'],
            'type': data['type'] ?? 'text',
            'mediaUrl': data['mediaUrl'],
            'localPath': data['localPath'],
            'fileName': data['fileName'],
            'fileSize': data['fileSize'],
            'duration': data['duration'],
            'status': data['status'] ?? 'sent',
            'isRead': data['status'] == 'read',
            'timestamp': epochMs,
            'replyToId': replyTo?['id'],
            'replyToText': replyTo?['text'],
            'isGroup': data['isGroup'] == true,
          });
        }
      } catch (e) {
        debugPrint('[LocalDB] syncMessagesToLocalDb error: $e');
      }
    }());
  }

  /// Mark messages as delivered when recipient app is active or list loads
  static Future<void> markAsDelivered(String chatId, String myUid) async {
    try {
      final recentDocs = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(30)
          .get();

      if (recentDocs.docs.isNotEmpty) {
        final batch = _firestore.batch();
        bool hasUpdates = false;
        for (final doc in recentDocs.docs) {
          final data = doc.data();
          final rawDeliveredTo = data['deliveredTo'];
          final deliveredTo = rawDeliveredTo is Map ? Map<String, dynamic>.from(rawDeliveredTo) : <String, dynamic>{};
          final alreadyDeliveredToMe = deliveredTo.containsKey(myUid);

          if (data['senderId'] != myUid && !alreadyDeliveredToMe) {
            batch.set(
              doc.reference,
              {
                if (data['status'] == 'sent') 'status': 'delivered',
                'deliveredAt': FieldValue.serverTimestamp(),
                'deliveredTo': {myUid: FieldValue.serverTimestamp()},
              },
              SetOptions(merge: true),
            );
            hasUpdates = true;
          }
        }
        if (hasUpdates) {
          final firstDoc = recentDocs.docs.first;
          if (firstDoc.data()['senderId'] != myUid && firstDoc.data()['status'] != 'read') {
            batch.set(
              _firestore.collection('chats').doc(chatId),
              {'lastMessageStatus': 'delivered'},
              SetOptions(merge: true),
            );
          }
          await batch.commit();
        }
      }
    } catch (e) {
      debugPrint("Error in markAsDelivered: $e");
    }
  }

  /// Stream a single message's updates (for Message Info screen / live read receipts)
  static Stream<DocumentSnapshot<Map<String, dynamic>>> streamMessage({
    required String chatId,
    required String messageId,
  }) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .snapshots();
  }

  /// Updates typing status of a user
  static Future<void> setTypingStatus(String chatId, String uid, bool isTyping) async {
    try {
      await _firestore.collection('chats').doc(chatId).set({
        'typing': {uid: isTyping},
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Deletes a specific message locally
  static Future<void> deleteMessage(String chatId, String messageId) async {
    try {
      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId)
          .delete();
    } catch (_) {}
  }

  /// Deletes a message for everyone (replaces content with deleted placeholder)
  static Future<void> deleteMessageForEveryone(String chatId, String messageId) async {
    try {
      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId)
          .update({
        'text': 'This message was deleted',
        'type': 'deleted',
        'isDeleted': true,
        'mediaUrl': null,
        'localPath': null,
        'deletedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Error deleting message for everyone: $e");
    }
  }

  /// Edits an existing text message
  static Future<void> editMessage(String chatId, String messageId, String newText) async {
    try {
      final cleanText = newText.trim();
      if (cleanText.isEmpty) return;
      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId)
          .update({
        'text': cleanText,
        'isEdited': true,
        'editedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Error editing message: $e");
    }
  }

  /// Toggles pinning a chat for the user
  static Future<void> togglePinChat({
    required String myUid,
    required String chatId,
    required bool isCurrentlyPinned,
  }) async {
    try {
      final userRef = _firestore.collection('users').doc(myUid);
      if (isCurrentlyPinned) {
        await userRef.update({
          'pinnedChats': FieldValue.arrayRemove([chatId]),
        });
      } else {
        await userRef.set({
          'pinnedChats': FieldValue.arrayUnion([chatId]),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint("Error toggling pin chat: $e");
    }
  }

  /// Sends a poll message
  static Future<void> sendPoll({
    required String chatId,
    required String senderId,
    required String senderName,
    required String receiverId,
    required String question,
    required List<String> options,
    bool allowMultiple = false,
    bool isGroup = false,
    List<String>? groupParticipants,
  }) async {
    final List<Map<String, dynamic>> pollOptions = [];
    for (int i = 0; i < options.length; i++) {
      pollOptions.add({
        'id': i.toString(),
        'text': options[i].trim(),
        'voterUids': <String>[],
      });
    }

    final pollData = {
      'question': question.trim(),
      'options': pollOptions,
      'allowMultiple': allowMultiple,
      'totalVotes': 0,
      'createdAt': FieldValue.serverTimestamp(),
    };

    await sendMessage(
      chatId: chatId,
      senderId: senderId,
      senderName: senderName,
      receiverId: receiverId,
      text: question.trim(),
      type: 'poll',
      poll: pollData,
      isGroup: isGroup,
      groupParticipants: groupParticipants,
    );
  }

  /// Sends a multi-image gallery message
  static Future<void> sendGallery({
    required String chatId,
    required String senderId,
    required String senderName,
    required String receiverId,
    required List<Map<String, dynamic>> images, // [{url, localPath, fileName}]
    String? caption,
    bool isGroup = false,
    List<String>? groupParticipants,
  }) async {
    await sendMessage(
      chatId: chatId,
      senderId: senderId,
      senderName: senderName,
      receiverId: receiverId,
      text: caption ?? '📷 ${images.length} photo${images.length == 1 ? '' : 's'}',
      type: 'gallery',
      mediaUrl: images.map((e) => e['url'] as String? ?? '').join('|||'),
      fileName: images.map((e) => e['localPath'] as String? ?? '').join('|||'),
      isGroup: isGroup,
      groupParticipants: groupParticipants,
    );
  }

  /// Votes in a poll (supports both single and multiple choice voting)
  static Future<void> votePoll({
    required String chatId,
    required String messageId,
    required String optionId,
    required String voterUid,
  }) async {
    if (voterUid.isEmpty) return;
    try {
      final msgRef = _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId);

      await _firestore.runTransaction((transaction) async {
        final snap = await transaction.get(msgRef);
        if (!snap.exists) return;

        final data = snap.data();
        final poll = Map<String, dynamic>.from(data?['poll'] ?? {});
        final rawOptions = poll['options'] as List? ?? [];
        final options = rawOptions
            .map((o) => Map<String, dynamic>.from(o as Map))
            .toList();
        final allowMultiple = poll['allowMultiple'] == true;

        final Set<String> uniqueVoters = {};

        for (final opt in options) {
          final voters = List<String>.from(opt['voterUids'] ?? []);
          final optId = opt['id']?.toString() ?? '';
          if (optId == optionId) {
            if (voters.contains(voterUid)) {
              voters.remove(voterUid);
            } else {
              voters.add(voterUid);
            }
          } else if (!allowMultiple) {
            voters.remove(voterUid);
          }
          opt['voterUids'] = voters;
          uniqueVoters.addAll(voters);
        }

        poll['options'] = options;
        poll['totalVotes'] = uniqueVoters.length;

        transaction.update(msgRef, {'poll': poll});
      });
    } catch (e) {
      debugPrint("Error voting in poll: $e");
    }
  }

  /// Deletes a conversation and all its messages completely
  static Future<void> deleteConversation(String chatId) async {
    try {
      // 1. Delete all messages inside the subcollection
      final messagesSnap = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .get();

      final batch = _firestore.batch();
      for (final doc in messagesSnap.docs) {
        batch.delete(doc.reference);
      }
      // 2. Delete the conversation document
      batch.delete(_firestore.collection('chats').doc(chatId));
      await batch.commit();
    } catch (e) {
      debugPrint("Error deleting conversation: $e");
      // Fallback: Delete main document directly
      try {
        await _firestore.collection('chats').doc(chatId).delete();
      } catch (_) {}
    }
  }

  /// Clears all messages in a conversation without deleting the conversation container
  static Future<void> clearChatHistory(String chatId) async {
    try {
      final messagesSnap = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .get();

      if (messagesSnap.docs.isNotEmpty) {
        final batch = _firestore.batch();
        for (final doc in messagesSnap.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }

      await _firestore.collection('chats').doc(chatId).update({
        'lastMessage': 'Chat history cleared',
        'lastMessageTime': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Error clearing chat history: $e");
    }
  }

  /// Leaves a group chat
  static Future<void> leaveGroup({
    required String chatId,
    required String uid,
    required String userName,
  }) async {
    try {
      final docRef = _firestore.collection('chats').doc(chatId);
      final systemText = '$userName left the group';

      await docRef.update({
        'participants': FieldValue.arrayRemove([uid]),
        'admins': FieldValue.arrayRemove([uid]),
        'lastMessage': systemText,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastSenderId': uid,
        'lastSenderName': userName,
      });

      final msgRef = docRef.collection('messages').doc();
      await msgRef.set({
        'id': msgRef.id,
        'senderId': uid,
        'senderName': userName,
        'receiverId': '',
        'text': systemText,
        'type': 'system',
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'read',
        'isGroup': true,
      });
    } catch (e) {
      debugPrint("Error leaving group: $e");
    }
  }

  /// Marks a conversation as unread manually
  static Future<void> markAsUnread(String chatId, String myUid) async {
    try {
      await _firestore.collection('chats').doc(chatId).set({
        'unreadCounts': {myUid: 1},
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Error marking conversation as unread: $e");
    }
  }

  // ─── Group Admin Controls ─────────────────────────────────────────────────

  /// Updates granular group permission flags set by admins.
  static Future<void> updateGroupPermissions({
    required String chatId,
    bool? onlyAdminsCanPost,
    bool? onlyAdminsCanEditInfo,
    bool? onlyAdminsCanAddMembers,
  }) async {
    final Map<String, dynamic> updates = {};
    if (onlyAdminsCanPost != null) updates['onlyAdminsCanPost'] = onlyAdminsCanPost;
    if (onlyAdminsCanEditInfo != null) updates['onlyAdminsCanEditInfo'] = onlyAdminsCanEditInfo;
    if (onlyAdminsCanAddMembers != null) updates['onlyAdminsCanAddMembers'] = onlyAdminsCanAddMembers;
    if (updates.isEmpty) return;
    await _firestore.collection('chats').doc(chatId).update(updates);
  }

  /// Promotes a member to admin.
  static Future<void> promoteMemberToAdmin({
    required String chatId,
    required String targetUid,
    required String promoterName,
  }) async {
    await _firestore.collection('chats').doc(chatId).update({
      'admins': FieldValue.arrayUnion([targetUid]),
    });
    final msgRef = _firestore.collection('chats').doc(chatId).collection('messages').doc();
    await msgRef.set({
      'id': msgRef.id,
      'senderId': targetUid,
      'senderName': promoterName,
      'receiverId': '',
      'text': '$promoterName is now an admin',
      'type': 'system',
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'read',
      'isGroup': true,
    });
  }

  /// Demotes an admin to regular member.
  static Future<void> demoteAdminToMember({
    required String chatId,
    required String targetUid,
  }) async {
    await _firestore.collection('chats').doc(chatId).update({
      'admins': FieldValue.arrayRemove([targetUid]),
    });
  }

  /// Removes a member from the group.
  static Future<void> removeMemberFromGroup({
    required String chatId,
    required String targetUid,
    required String targetName,
    required String removerName,
  }) async {
    final systemText = '$removerName removed $targetName from the group';
    await _firestore.collection('chats').doc(chatId).update({
      'participants': FieldValue.arrayRemove([targetUid]),
      'admins': FieldValue.arrayRemove([targetUid]),
      'lastMessage': systemText,
      'lastMessageTime': FieldValue.serverTimestamp(),
    });
    final msgRef = _firestore.collection('chats').doc(chatId).collection('messages').doc();
    await msgRef.set({
      'id': msgRef.id,
      'senderId': targetUid,
      'senderName': removerName,
      'receiverId': '',
      'text': systemText,
      'type': 'system',
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'read',
      'isGroup': true,
    });
  }

  // ─── Invite Links ─────────────────────────────────────────────────────────

  /// Generates (or regenerates) an invite link token for a group.
  /// The token is stored in the chat document and the full link is
  /// https://lichat.app/join/{token}
  static Future<String> generateInviteLink(String chatId) async {
    final token = '${chatId.substring(0, 8)}-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    await _firestore.collection('chats').doc(chatId).update({
      'inviteToken': token,
      'inviteTokenCreatedAt': FieldValue.serverTimestamp(),
    });
    return 'https://lichat.app/join/$token';
  }

  /// Revokes the current invite link.
  static Future<void> revokeInviteLink(String chatId) async {
    await _firestore.collection('chats').doc(chatId).update({
      'inviteToken': FieldValue.delete(),
      'inviteTokenCreatedAt': FieldValue.delete(),
    });
  }

  /// Stream of the full group document (for GroupInfoScreen).
  static Stream<DocumentSnapshot<Map<String, dynamic>>> streamGroupInfo(String chatId) {
    return _firestore.collection('chats').doc(chatId).snapshots();
  }

  /// Stream of chat metadata (typing status, unread counts)

  static Stream<DocumentSnapshot<Map<String, dynamic>>> streamChatMeta(String chatId) {
    return _firestore.collection('chats').doc(chatId).snapshots();
  }

  /// Toggles the starred (bookmarked) state of a message for the current user.
  /// Stars are stored in the user's own document to avoid cross-user visibility.
  static Future<void> toggleStarMessage({
    required String myUid,
    required String chatId,
    required String messageId,
    required Map<String, dynamic> messageData,
    required bool currentlyStarred,
  }) async {
    final starRef = _firestore
        .collection('users')
        .doc(myUid)
        .collection('starredMessages')
        .doc(messageId);

    if (currentlyStarred) {
      await starRef.delete();
    } else {
      await starRef.set({
        'chatId': chatId,
        'messageId': messageId,
        'senderId': messageData['senderId'] ?? '',
        'senderName': messageData['senderName'] ?? '',
        'text': messageData['text'] ?? '',
        'type': messageData['type'] ?? 'text',
        'mediaUrl': messageData['mediaUrl'],
        'fileName': messageData['fileName'],
        'duration': messageData['duration'],
        'timestamp': messageData['timestamp'],
        'starredAt': FieldValue.serverTimestamp(),
        'isGroup': messageData['isGroup'] ?? false,
      });
    }
  }

  /// Returns true if a specific message is starred by [myUid].
  static Future<bool> isMessageStarred({
    required String myUid,
    required String messageId,
  }) async {
    final doc = await _firestore
        .collection('users')
        .doc(myUid)
        .collection('starredMessages')
        .doc(messageId)
        .get();
    return doc.exists;
  }

  /// Real-time stream of all starred messages for [myUid], newest first.
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamStarredMessages(String? myUid) {
    if (myUid == null || myUid.isEmpty) return const Stream.empty();
    return _firestore
        .collection('users')
        .doc(myUid)
        .collection('starredMessages')
        .orderBy('starredAt', descending: true)
        .snapshots();
  }
}

