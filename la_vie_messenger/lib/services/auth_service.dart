import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'presence_service.dart';
import 'active_call_manager.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Performs a complete, production-grade sign-out for LiChat:
  /// 1. Marks user offline in Firestore and halts presence heartbeat.
  /// 2. Deletes FCM token from Firestore so the device won't ring for this user after logout.
  /// 3. Ends any active or minimized LiveKit calls & disposes native PiP overlays.
  /// 4. Signs out of Google Sign-In session.
  /// 5. Signs out of Firebase Auth.
  /// 6. Flushes navigation and safely resets back to AuthGate.
  static Future<void> signOut(BuildContext context) async {
    final user = _auth.currentUser;
    final uid = user?.uid;

    try {
      // 1. Mark offline immediately in Firestore
      if (uid != null) {
        PresenceService.setOffline(uid);
      }

      // 2. Remove FCM device token from Firestore & delete local registration
      if (uid != null) {
        try {
          await _firestore.collection('users').doc(uid).update({
            'fcmToken': FieldValue.delete(),
            'fcm_token': FieldValue.delete(),
            'isOnline': false,
            'lastSeen': FieldValue.serverTimestamp(),
          }).timeout(const Duration(seconds: 4));
        } catch (e) {
          debugPrint("Error clearing FCM token from Firestore: $e");
        }

        if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
          try {
            await FirebaseMessaging.instance.deleteToken().timeout(const Duration(seconds: 3));
          } catch (e) {
            debugPrint("Error deleting local FCM token: $e");
          }
        }
      }

      // 3. Terminate any active LiveKit calls, floating overlays or native PiP
      try {
        await ActiveCallManager.instance.endCall();
        await ActiveCallManager.instance.cleanup();
      } catch (e) {
        debugPrint("Error cleaning up calls on signout: $e");
      }

      // 4. Sign out of Google Sign-In if signed in
      try {
        final googleSignIn = GoogleSignIn(
          serverClientId: '563333021985-nbrjkql6t8evhd7i47lf8s7ie4khjdi6.apps.googleusercontent.com',
        );
        if (await googleSignIn.isSignedIn()) {
          await googleSignIn.signOut();
        }
      } catch (e) {
        debugPrint("Error signing out of Google: $e");
      }

      // 5. Sign out of Firebase Auth
      await _auth.signOut();

      // 6. Reset navigation stack cleanly to root AuthGate
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil('/', (route) => false);
      }
    } catch (e) {
      debugPrint("Error during complete signout: $e");
      // Fallback guarantee: ensure Firebase Auth is signed out
      await _auth.signOut();
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil('/', (route) => false);
      }
    }
  }

  /// Permanently deletes the user's account and personal data (Required by Apple & Google Play policies)
  static Future<void> deleteAccount(BuildContext context) async {
    final user = _auth.currentUser;
    final uid = user?.uid;
    if (uid == null || user == null) return;

    try {
      // 1. Mark user offline & cleanup calls
      PresenceService.setOffline(uid);
      try {
        await ActiveCallManager.instance.endCall();
        await ActiveCallManager.instance.cleanup();
      } catch (_) {}

      // 2. Delete Firestore user record and AI persona data
      try {
        await _firestore.collection('users').doc(uid).collection('twin').doc('profile').delete();
        await _firestore.collection('users').doc(uid).collection('twin').doc('settings').delete();
        await _firestore.collection('users').doc(uid).delete();
      } catch (e) {
        debugPrint("Error deleting user firestore records: $e");
      }

      // 3. Clear Google Sign-In session
      try {
        final googleSignIn = GoogleSignIn(
          serverClientId: '563333021985-nbrjkql6t8evhd7i47lf8s7ie4khjdi6.apps.googleusercontent.com',
        );
        if (await googleSignIn.isSignedIn()) {
          await googleSignIn.signOut();
        }
      } catch (_) {}

      // 4. Delete Firebase Auth User
      await user.delete();

      // 5. Navigate to root
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil('/', (route) => false);
      }
    } catch (e) {
      debugPrint("Error deleting user account: $e");
      rethrow;
    }
  }
}
