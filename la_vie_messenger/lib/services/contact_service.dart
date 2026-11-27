import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ContactService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _backendUrl = 'https://la-vie.lifechangerstouch.org';

  /// Generates the payload encoded into the user's personal QR code.
  static String generateQrPayload({
    required String uid,
    required String name,
    String? avatar,
  }) {
    return jsonEncode({
      'protocol': 'lavie_connect',
      'version': '1.0',
      'uid': uid,
      'name': name,
      'avatar': avatar ?? '',
    });
  }

  /// Parses a scanned QR payload. Returns null if invalid.
  static Map<String, dynamic>? parseQrPayload(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    // 1. Check URI format (lichat://connect?uid=... or https://la-vie.lifechangerstouch.org/connect?uid=...)
    if (trimmed.startsWith('lichat:') || trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      try {
        final uri = Uri.parse(trimmed);
        final uid = uri.queryParameters['uid'];
        if (uid != null && uid.isNotEmpty) {
          return {
            'uid': uid,
            'name': uri.queryParameters['name'] ?? 'Contact',
            'avatar': uri.queryParameters['avatar'] ?? '',
          };
        }
      } catch (_) {}
    }

    // 2. Check JSON payload format
    try {
      final data = jsonDecode(trimmed);
      if (data is Map<String, dynamic> && data['protocol'] == 'lavie_connect' && data['uid'] != null) {
        return data;
      }
    } catch (_) {}

    // 3. Fallback: check if raw string is directly a UID
    if (!trimmed.contains('{') && !trimmed.contains('/') && trimmed.length >= 10) {
      return {'uid': trimmed, 'name': 'Contact', 'avatar': ''};
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // CONTACT REQUEST FLOW (secure — requires explicit approval from target)
  // ---------------------------------------------------------------------------

  /// Sends a contact request to [targetUid]. Target must Accept before any
  /// pairing occurs. Returns a map with keys: 'success', 'status', 'message'.
  /// Sends a contact request to [targetUid]. Target must Accept before any
  /// pairing occurs. Returns a map with keys: 'success', 'status', 'message'.
  static Future<Map<String, dynamic>> sendContactRequest({
    required String senderUid,
    required String senderName,
    String? senderAvatar,
    required String targetUid,
    String? introNote,
    String? introPhotoUrl,
  }) async {
    if (senderUid == targetUid) {
      return {'success': false, 'status': 'self', 'message': 'You cannot add yourself.'};
    }

    // 1. Check if already paired
    try {
      final existing = await _firestore
          .collection('users').doc(senderUid)
          .collection('contacts').doc(targetUid)
          .get();
      if (existing.exists) {
        return {'success': false, 'status': 'already_contacts', 'message': 'You are already contacts.'};
      }
    } catch (_) {}

    // 2. Direct Firestore write: write to target's pending requests and sender's outgoing
    try {
      final targetPayload = <String, dynamic>{
        'sender_uid':    senderUid,
        'sender_name':   senderName,
        'sender_avatar': senderAvatar ?? '',
        'status':        'pending',
        'createdAt':     FieldValue.serverTimestamp(),
      };
      if (introNote != null && introNote.trim().isNotEmpty) {
        targetPayload['intro_note'] = introNote.trim();
      }
      if (introPhotoUrl != null && introPhotoUrl.trim().isNotEmpty) {
        targetPayload['intro_photo_url'] = introPhotoUrl.trim();
      }

      await _firestore
          .collection('users').doc(targetUid)
          .collection('contact_requests').doc(senderUid)
          .set(targetPayload, SetOptions(merge: true));

      final senderPayload = <String, dynamic>{
        'target_uid': targetUid,
        'status':     'pending',
        'createdAt':  FieldValue.serverTimestamp(),
      };
      if (introNote != null && introNote.trim().isNotEmpty) {
        senderPayload['intro_note'] = introNote.trim();
      }
      if (introPhotoUrl != null && introPhotoUrl.trim().isNotEmpty) {
        senderPayload['intro_photo_url'] = introPhotoUrl.trim();
      }

      await _firestore
          .collection('users').doc(senderUid)
          .collection('outgoing_requests').doc(targetUid)
          .set(senderPayload, SetOptions(merge: true));
    } catch (fe) {
      debugPrint("Direct Firestore request write error: $fe");
    }

    // 3. Trigger backend API for push notification & Admin SDK sync
    try {
      http.post(
        Uri.parse('$_backendUrl/api/contacts/request'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sender_uid':       senderUid,
          'sender_name':      senderName,
          'sender_avatar':    senderAvatar ?? '',
          'target_uid':       targetUid,
          'intro_note':       introNote ?? '',
          'intro_photo_url':  introPhotoUrl ?? '',
        }),
      ).timeout(const Duration(seconds: 8)).catchError((e) {
        debugPrint("sendContactRequest push timeout: $e");
        return http.Response('{"status":"offline"}', 200);
      });
    } catch (e) {
      debugPrint("sendContactRequest backend notify note: $e");
    }

    return {
      'success': true,
      'status': 'request_sent',
      'message': 'Contact request sent! They will be notified.',
    };
  }

  /// Sends a pre-acceptance clarification or verification message
  static Future<void> sendRequestMessage({
    required String senderUid,
    required String targetUid,
    required String authorUid,
    required String authorName,
    required String text,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return;

    try {
      await _firestore
          .collection('users')
          .doc(targetUid)
          .collection('contact_requests')
          .doc(senderUid)
          .collection('messages')
          .add({
        'author_uid': authorUid,
        'author_name': authorName,
        'text': cleanText,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Error writing request message: $e");
    }

    try {
      http.post(
        Uri.parse('$_backendUrl/api/contacts/request/message'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sender_uid': senderUid,
          'target_uid': targetUid,
          'author_uid': authorUid,
          'author_name': authorName,
          'text': cleanText,
        }),
      ).timeout(const Duration(seconds: 6)).catchError((_) => http.Response('{}', 200));
    } catch (_) {}
  }

  /// Real-time stream of pre-acceptance messages between requester and target
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamRequestMessages({
    required String targetUid,
    required String senderUid,
  }) {
    return _firestore
        .collection('users')
        .doc(targetUid)
        .collection('contact_requests')
        .doc(senderUid)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots();
  }

  /// Accept or decline an incoming contact request.
  /// [action] must be either "accept" or "decline".
  static Future<Map<String, dynamic>> respondToContactRequest({
    required String responderUid,
    required String responderName,
    String? responderAvatar,
    required String senderUid,
    required String action, // "accept" | "decline"
  }) async {
    final cleanAction = action.trim().toLowerCase();

    // 1. Fetch pending request details locally if available
    String senderName = 'LiChat User';
    String senderAvatar = '';
    try {
      final reqDoc = await _firestore
          .collection('users').doc(responderUid)
          .collection('contact_requests').doc(senderUid)
          .get();
      if (reqDoc.exists && reqDoc.data() != null) {
        final d = reqDoc.data()!;
        senderName = d['sender_name'] as String? ?? 'LiChat User';
        senderAvatar = d['sender_avatar'] as String? ?? '';
      } else {
        // Fallback: check sender profile directly
        final uDoc = await _firestore.collection('users').doc(senderUid).get();
        if (uDoc.exists && uDoc.data() != null) {
          final ud = uDoc.data()!;
          senderName = ud['displayName'] ?? ud['name'] ?? 'LiChat User';
          senderAvatar = ud['photoURL'] ?? ud['photoUrl'] ?? ud['avatar'] ?? '';
        }
      }
    } catch (e) {
      debugPrint("Note fetching reqDoc: $e");
    }

    if (cleanAction == 'decline') {
      try {
        await _firestore
            .collection('users').doc(responderUid)
            .collection('contact_requests').doc(senderUid)
            .delete();
        await _firestore
            .collection('users').doc(senderUid)
            .collection('outgoing_requests').doc(responderUid)
            .delete();
      } catch (_) {}

      try {
        http.post(
          Uri.parse('$_backendUrl/api/contacts/request/respond'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'responder_uid':    responderUid,
            'responder_name':   responderName,
            'responder_avatar': responderAvatar ?? '',
            'sender_uid':       senderUid,
            'action':           'decline',
          }),
        ).timeout(const Duration(seconds: 5)).catchError((e) => http.Response('{}', 200));
      } catch (_) {}

      return {'success': true, 'status': 'declined', 'message': 'Request declined.'};
    }

    // ACCEPT: Mutual pairing
    try {
      // Direct write to responder's contacts (guaranteed allowed for auth user)
      await _firestore
          .collection('users').doc(responderUid)
          .collection('contacts').doc(senderUid)
          .set({
            'uid': senderUid,
            'name': senderName,
            'avatar': senderAvatar,
            'pairedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      // Attempt write to sender's contacts
      try {
        await _firestore
            .collection('users').doc(senderUid)
            .collection('contacts').doc(responderUid)
            .set({
              'uid': responderUid,
              'name': responderName,
              'avatar': responderAvatar ?? '',
              'pairedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
      } catch (err) {
        debugPrint("Sender direct write skipped: $err");
      }

      // Cleanup pending request documents
      try {
        await _firestore
            .collection('users').doc(responderUid)
            .collection('contact_requests').doc(senderUid)
            .delete();
        await _firestore
            .collection('users').doc(senderUid)
            .collection('outgoing_requests').doc(responderUid)
            .delete();
      } catch (_) {}

      // Call backend with Admin SDK to guarantee two-way mutual pairing & push alert
      try {
        http.post(
          Uri.parse('$_backendUrl/api/contacts/request/respond'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'responder_uid':    responderUid,
            'responder_name':   responderName,
            'responder_avatar': responderAvatar ?? '',
            'sender_uid':       senderUid,
            'action':           'accept',
          }),
        ).timeout(const Duration(seconds: 8)).catchError((e) {
          debugPrint("respondToContactRequest backend note: $e");
          return http.Response('{"status":"accepted"}', 200);
        });
      } catch (be) {
        debugPrint("Backend respond note: $be");
      }

      return {'success': true, 'status': 'accepted', 'message': 'Contact added!'};
    } catch (e) {
      debugPrint("Error accepting request: $e");
      return {'success': false, 'status': 'error', 'message': 'Could not accept request: $e'};
    }
  }

  /// Real-time stream of incoming pending contact requests for [uid].
  /// Uses in-memory sort to avoid requiring composite indexes in Firestore.
  static Stream<List<Map<String, dynamic>>> streamIncomingRequests(String uid) {
    return _firestore
        .collection('users').doc(uid)
        .collection('contact_requests')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) {
          final list = snap.docs.map((d) {
            final data = Map<String, dynamic>.from(d.data());
            data['sender_uid'] = data['sender_uid'] ?? d.id;
            return data;
          }).toList();
          list.sort((a, b) {
            final aTime = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
            final bTime = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
            return bTime.compareTo(aTime);
          });
          return list;
        });
  }

  /// Real-time stream of outgoing pending requests sent BY [uid].
  static Stream<List<Map<String, dynamic>>> streamOutgoingRequests(String uid) {
    return _firestore
        .collection('users').doc(uid)
        .collection('outgoing_requests')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) {
          final list = snap.docs.map((d) {
            final data = Map<String, dynamic>.from(d.data());
            data['target_uid'] = data['target_uid'] ?? d.id;
            return data;
          }).toList();
          list.sort((a, b) {
            final aTime = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
            final bTime = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
            return bTime.compareTo(aTime);
          });
          return list;
        });
  }

  static final Map<String, bool> _verifiedContactCache = {};

  /// Checks if [peerUid] is a verified contact in [myUid]'s contacts collection (cached for instant performance).
  static Future<bool> isContactVerified(String myUid, String peerUid) async {
    if (myUid.isEmpty || peerUid.isEmpty) return false;
    final cacheKey = '${myUid}_$peerUid';
    if (_verifiedContactCache.containsKey(cacheKey)) {
      return _verifiedContactCache[cacheKey]!;
    }
    try {
      final doc = await _firestore
          .collection('users').doc(myUid)
          .collection('contacts').doc(peerUid)
          .get();
      final exists = doc.exists;
      if (exists) {
        _verifiedContactCache[cacheKey] = true;
      }
      return exists;
    } catch (_) {
      return false;
    }
  }

  /// Invalidate verified contact cache
  static void invalidateContactCache(String myUid, String peerUid) {
    _verifiedContactCache.remove('${myUid}_$peerUid');
  }

  /// Real-time stream to observe if [peerUid] is a verified contact for [myUid].
  static Stream<bool> streamIsContactVerified(String myUid, String peerUid) {
    if (myUid.isEmpty || peerUid.isEmpty) return Stream.value(false);
    return _firestore
        .collection('users').doc(myUid)
        .collection('contacts').doc(peerUid)
        .snapshots()
        .map((doc) => doc.exists);
  }

  /// Deletes a contact from [myUid]'s contacts collection.
  static Future<bool> deleteContact(String myUid, String peerUid) async {
    if (myUid.isEmpty || peerUid.isEmpty) return false;
    try {
      await _firestore
          .collection('users').doc(myUid)
          .collection('contacts').doc(peerUid)
          .delete();
      try {
        await _firestore
            .collection('users').doc(peerUid)
            .collection('contacts').doc(myUid)
            .delete();
      } catch (_) {}
      invalidateContactCache(myUid, peerUid);

      // Notify backend Admin SDK to ensure sync
      try {
        http.post(
          Uri.parse('$_backendUrl/api/contacts/delete'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'my_uid': myUid,
            'peer_uid': peerUid,
          }),
        ).timeout(const Duration(seconds: 5)).catchError((_) => http.Response('{}', 200));
      } catch (_) {}

      return true;
    } catch (e) {
      debugPrint("Error deleting contact: $e");
      return false;
    }
  }

  /// Blocks a user, preventing them from contacting [myUid].
  static Future<bool> blockContact(String myUid, String peerUid) async {
    if (myUid.isEmpty || peerUid.isEmpty) return false;
    try {
      await _firestore
          .collection('users').doc(myUid)
          .collection('blocked_users').doc(peerUid)
          .set({
            'uid': peerUid,
            'blockedAt': FieldValue.serverTimestamp(),
          });

      // Remove from active contacts
      await deleteContact(myUid, peerUid);

      // Notify backend Admin SDK
      try {
        http.post(
          Uri.parse('$_backendUrl/api/contacts/block'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'my_uid': myUid,
            'peer_uid': peerUid,
          }),
        ).timeout(const Duration(seconds: 5)).catchError((_) => http.Response('{}', 200));
      } catch (_) {}

      return true;
    } catch (e) {
      debugPrint("Error blocking contact: $e");
      return false;
    }
  }

  /// Unblocks a previously blocked user.
  static Future<bool> unblockContact(String myUid, String peerUid) async {
    if (myUid.isEmpty || peerUid.isEmpty) return false;
    try {
      await _firestore
          .collection('users').doc(myUid)
          .collection('blocked_users').doc(peerUid)
          .delete();

      try {
        http.post(
          Uri.parse('$_backendUrl/api/contacts/unblock'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'my_uid': myUid,
            'peer_uid': peerUid,
          }),
        ).timeout(const Duration(seconds: 5)).catchError((_) => http.Response('{}', 200));
      } catch (_) {}

      return true;
    } catch (e) {
      debugPrint("Error unblocking contact: $e");
      return false;
    }
  }

  /// Checks if [peerUid] is blocked by [myUid].
  static Future<bool> isUserBlocked(String myUid, String peerUid) async {
    if (myUid.isEmpty || peerUid.isEmpty) return false;
    try {
      final doc = await _firestore
          .collection('users').doc(myUid)
          .collection('blocked_users').doc(peerUid)
          .get();
      return doc.exists;
    } catch (_) {
      return false;
    }
  }

  /// Stream to observe if [peerUid] is blocked by [myUid].
  static Stream<bool> streamIsUserBlocked(String myUid, String peerUid) {
    if (myUid.isEmpty || peerUid.isEmpty) return Stream.value(false);
    return _firestore
        .collection('users').doc(myUid)
        .collection('blocked_users').doc(peerUid)
        .snapshots()
        .map((doc) => doc.exists);
  }



  /// Mutually pairs two users so both show up in each other's contacts list.
  static Future<bool> pairContacts({
    required String myUid,
    required String myName,
    String? myAvatar,
    required String peerUid,
    required String peerName,
    String? peerAvatar,
  }) async {
    if (myUid == peerUid) {
      debugPrint("Cannot pair with yourself.");
      return false;
    }

    try {
      // 1. Add peer to my contacts collection (Always authorized for current user)
      final myContactRef = _firestore
          .collection('users')
          .doc(myUid)
          .collection('contacts')
          .doc(peerUid);
      await myContactRef.set({
        'uid': peerUid,
        'name': peerName,
        'avatar': peerAvatar ?? '',
        'pairedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 2. Direct client-side mutual write attempt (catches silently if rules forbid)
      try {
        final peerContactRef = _firestore
            .collection('users')
            .doc(peerUid)
            .collection('contacts')
            .doc(myUid);
        await peerContactRef.set({
          'uid': myUid,
          'name': myName,
          'avatar': myAvatar ?? '',
          'pairedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (clientRuleErr) {
        debugPrint("Direct peer write skipped by security rules: $clientRuleErr");
      }

      // 3. Call backend API with Firebase Admin SDK to guarantee mutual pairing & push alert
      try {
        http.post(
          Uri.parse('$_backendUrl/api/contacts/pair'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'my_uid': myUid,
            'my_name': myName,
            'my_avatar': myAvatar ?? '',
            'peer_uid': peerUid,
            'peer_name': peerName,
            'peer_avatar': peerAvatar ?? '',
          }),
        ).timeout(const Duration(seconds: 5)).catchError((e) {
          debugPrint("Backend pairing timeout or note: $e");
          return http.Response('{"status":"offline"}', 200);
        });
      } catch (backendErr) {
        debugPrint("Error contacting backend for pairing: $backendErr");
      }

      return true;
    } catch (e) {
      debugPrint("Error pairing contacts: $e");
      return false;
    }
  }

  /// Stream of all paired contacts for a user with instant in-memory sorting.
  static Stream<List<Map<String, dynamic>>> streamContacts(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('contacts')
        .snapshots()
        .map((snapshot) {
      final list = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final d = Map<String, dynamic>.from(doc.data());
        d['uid'] = (d['uid'] as String?)?.isNotEmpty == true ? d['uid'] : doc.id;
        final pUid = d['uid'] as String;
        final name = d['name'] as String?;
        if (name != null && name.isNotEmpty && name != 'Contact') {
          _profileCache['$uid:$pUid'] = d;
          _profileCache[pUid] = d;
        }
        list.add(d);
      }
      list.sort((a, b) {
        final aTime = (a['pairedAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
        final bTime = (b['pairedAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
        return bTime.compareTo(aTime);
      });
      return list;
    });
  }

  static final Map<String, Map<String, dynamic>> _profileCache = {};

  /// Synchronous cache lookup for instantaneous 0ms contact name display
  static Map<String, dynamic>? getCachedProfile(String peerUid, {String? myUid}) {
    if (myUid != null && _profileCache.containsKey('$myUid:$peerUid')) {
      return _profileCache['$myUid:$peerUid'];
    }
    if (_profileCache.containsKey(peerUid)) {
      return _profileCache[peerUid];
    }
    return null;
  }

  /// Fetches contact info from my paired contacts first, then fallback to user profile (cached in RAM)
  static Future<Map<String, dynamic>?> fetchContactOrProfile(String myUid, String peerUid) async {
    final cacheKey = '$myUid:$peerUid';
    if (_profileCache.containsKey(cacheKey)) {
      return _profileCache[cacheKey];
    }
    if (_profileCache.containsKey(peerUid)) {
      return _profileCache[peerUid];
    }

    try {
      // 1. Check if peer is in my paired contacts subcollection
      final contactDoc = await _firestore
          .collection('users')
          .doc(myUid)
          .collection('contacts')
          .doc(peerUid)
          .get();
      if (contactDoc.exists && contactDoc.data() != null) {
        final data = contactDoc.data()!;
        final name = data['name'] as String?;
        if (name != null && name.isNotEmpty && name != 'Contact') {
          _profileCache[cacheKey] = data;
          _profileCache[peerUid] = data;
          return data;
        }
      }

      // 2. Check root user doc
      final userDoc = await _firestore.collection('users').doc(peerUid).get();
      if (userDoc.exists && userDoc.data() != null) {
        final uData = userDoc.data()!;
        final name = uData['displayName'] ?? uData['name'];
        if (name != null && name.toString().isNotEmpty && name != 'Contact') {
          final res = {
            'name': name,
            'avatar': uData['photoURL'] ?? uData['photoUrl'] ?? uData['avatar'],
            'email': uData['email'],
          };
          _profileCache[cacheKey] = res;
          _profileCache[peerUid] = res;
          return res;
        }
      }
    } catch (e) {
      debugPrint("Error fetching contact profile: $e");
    }
    return null;
  }

  /// Fetches the latest profile data for a specific user.
  static Future<Map<String, dynamic>?> fetchUserProfile(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        return doc.data();
      }
    } catch (e) {
      debugPrint("Error fetching user profile: $e");
    }
    return null;
  }

  /// Updates contact's custom nickname privately for the current user
  static Future<void> updateContactNickname({
    required String myUid,
    required String peerUid,
    required String newNickname,
  }) async {
    final cleanName = newNickname.trim();
    if (cleanName.isEmpty) return;

    try {
      await _firestore
          .collection('users')
          .doc(myUid)
          .collection('contacts')
          .doc(peerUid)
          .set({
            'uid': peerUid,
            'name': cleanName,
          }, SetOptions(merge: true));

      // Update in-memory profile cache immediately
      final cacheKey = '$myUid:$peerUid';
      if (_profileCache.containsKey(cacheKey)) {
        _profileCache[cacheKey]!['name'] = cleanName;
      } else {
        _profileCache[cacheKey] = {'name': cleanName};
      }
    } catch (e) {
      debugPrint("Error updating contact nickname: $e");
    }
  }

  /// Ensures current user has a unique LiChat Code (e.g. LC-83921).
  static Future<String> ensureUserLiChatCode(String uid, {String? displayName}) async {
    try {
      final userDoc = await _firestore.collection('users').doc(uid).get();
      if (userDoc.exists) {
        final data = userDoc.data() ?? {};
        final existingCode = data['lichat_code'] as String?;
        if (existingCode != null && existingCode.isNotEmpty) {
          return existingCode;
        }
      }

      // Generate a new clean 6-digit LiChat Code: LC-XXXXXX
      final rand = Random();
      final numCode = 100000 + rand.nextInt(900000);
      final newCode = 'LC-$numCode';

      await _firestore.collection('users').doc(uid).set({
        'lichat_code': newCode,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return newCode;
    } catch (e) {
      debugPrint("Error ensuring LiChat code: $e");
      final fallback = uid.length >= 6 ? uid.substring(0, 6).toUpperCase() : uid.toUpperCase();
      return 'LC-$fallback';
    }
  }

  /// Looks up a user by their unique LiChat Code, Handle, or Email and sends
  /// them a contact REQUEST (they must Accept before pairing is complete).
  static Future<Map<String, dynamic>> pairByUniqueCode({
    required String myUid,
    required String myName,
    String? myAvatar,
    required String code,
    String? introNote,
    String? introPhotoUrl,
  }) async {
    final cleanCode = code.trim().toUpperCase().replaceAll('@', '').replaceAll('#', '');
    if (cleanCode.isEmpty) {
      return {'success': false, 'message': 'Please enter a valid LiChat code.'};
    }

    try {
      // 1. Try Backend API lookup (guaranteed via Admin SDK)
      try {
        final res = await http.post(
          Uri.parse('$_backendUrl/api/contacts/lookup-code'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'code': cleanCode}),
        ).timeout(const Duration(seconds: 6));

        if (res.statusCode == 200) {
          final resData = jsonDecode(res.body);
          if (resData['status'] == 'success' && resData['user'] != null) {
            final user = resData['user'] as Map<String, dynamic>;
            final peerUid = user['uid'] as String;
            if (peerUid == myUid) {
              return {'success': false, 'message': 'This is your own LiChat code!'};
            }
            final peerName = user['name'] ?? 'LiChat User';
            final peerAvatar = user['avatar'] ?? '';

            final result = await sendContactRequest(
              senderUid:       myUid,
              senderName:      myName,
              senderAvatar:    myAvatar,
              targetUid:       peerUid,
              introNote:       introNote,
              introPhotoUrl:   introPhotoUrl,
            );
            final status = result['status'] as String? ?? '';
            final isSuccess = (result['success'] == true) || status == 'success' || status == 'request_sent';
            if (isSuccess) {
              return {
                'success': true,
                'status': 'request_sent',
                'peerUid': peerUid,
                'peerName': peerName,
                'peerAvatar': peerAvatar,
                'message': result['message'] ?? 'Request sent to $peerName! They\'ll be notified.',
              };
            } else if (status == 'already_contacts') {
              return {'success': false, 'status': status, 'message': 'You are already contacts.'};
            } else if (status == 'already_sent') {
              return {'success': false, 'status': status, 'peerName': peerName, 'message': 'Request already pending — waiting for $peerName\'s approval.'};
            } else {
              return {...result, 'peerName': peerName};
            }
          }
        }
      } catch (apiErr) {
        debugPrint("API lookup error, falling back to direct Firestore query: $apiErr");
      }

      // 2. Direct Firestore Query Fallback
      final candidateCodes = [cleanCode];
      if (!cleanCode.startsWith('LC-')) {
        candidateCodes.add('LC-$cleanCode');
      } else {
        candidateCodes.add(cleanCode.replaceFirst('LC-', ''));
      }

      for (final cand in candidateCodes) {
        final query = await _firestore
            .collection('users')
            .where('lichat_code', isEqualTo: cand)
            .limit(1)
            .get();

        if (query.docs.isNotEmpty) {
          final doc = query.docs.first;
          final peerUid = doc.id;
          if (peerUid == myUid) {
            return {'success': false, 'message': 'This is your own LiChat code!'};
          }
          final udata = doc.data();
          final peerName = udata['displayName'] ?? udata['name'] ?? 'LiChat User';
          final peerAvatar = udata['photoURL'] ?? udata['photoUrl'] ?? udata['avatar'] ?? '';

          final result = await sendContactRequest(
            senderUid:       myUid,
            senderName:      myName,
            senderAvatar:    myAvatar,
            targetUid:       peerUid,
            introNote:       introNote,
            introPhotoUrl:   introPhotoUrl,
          );
          final status = result['status'] as String? ?? '';
          final isSuccess = (result['success'] == true) || status == 'success' || status == 'request_sent';
          if (isSuccess) {
            return {
              'success': true,
              'status': 'request_sent',
              'peerUid': peerUid,
              'peerName': peerName,
              'peerAvatar': peerAvatar,
              'message': result['message'] ?? 'Request sent to $peerName! They\'ll be notified.',
            };
          } else if (status == 'already_contacts') {
            return {'success': false, 'status': status, 'message': 'You are already contacts.'};
          } else if (status == 'already_sent') {
            return {'success': false, 'status': status, 'peerName': peerName, 'message': 'Request already pending — waiting for $peerName\'s approval.'};
          } else {
            return {...result, 'peerName': peerName};
          }
        }
      }

      return {'success': false, 'message': 'No LiChat user found matching "$cleanCode". Please verify the code and try again.'};
    } catch (e) {
      debugPrint("Error in pairByUniqueCode: $e");
      return {'success': false, 'message': 'Failed to connect: $e'};
    }
  }

  /// Customizes user's unique LiChat Code / Handle (e.g. LC-EMMA)
  static Future<Map<String, dynamic>> updateCustomLiChatCode({
    required String uid,
    required String newCode,
  }) async {
    final cleanCode = newCode.trim().toUpperCase().replaceAll(' ', '_');
    if (cleanCode.length < 3 || cleanCode.length > 16) {
      return {'success': false, 'message': 'Code must be between 3 and 16 characters.'};
    }

    try {
      // Check if code is already taken by another user
      final existing = await _firestore
          .collection('users')
          .where('lichat_code', isEqualTo: cleanCode)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty && existing.docs.first.id != uid) {
        return {'success': false, 'message': 'This LiChat code is already taken. Please choose another.'};
      }

      await _firestore.collection('users').doc(uid).set({
        'lichat_code': cleanCode,
      }, SetOptions(merge: true));

      return {'success': true, 'code': cleanCode, 'message': 'LiChat code updated!'};
    } catch (e) {
      return {'success': false, 'message': 'Could not update code: $e'};
    }
  }
}
