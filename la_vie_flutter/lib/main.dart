import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'screens/login_screen.dart';
import 'main_layout.dart';
import 'services/notification_service.dart';
import 'package:flutter/foundation.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Handling a background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }
  
  // Initialize notifications
  final notificationService = NotificationService();
  await notificationService.init();
  await notificationService.requestPermissions();
  
  // Initialize Firebase with platform-specific options (iOS reads GoogleService-Info.plist)
  try {
    if (Firebase.apps.isEmpty) {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await Firebase.initializeApp();
      } else {
        await Firebase.initializeApp(
          options: const FirebaseOptions(
            apiKey: 'AIzaSyBOVXFmuHPoxb-P_JuYaGxerieuzlypMdo',
            appId: '1:563333021985:android:a299708fe90284e7a13e60',
            messagingSenderId: '563333021985',
            projectId: 'lifeconference-e0add',
            storageBucket: 'lifeconference-e0add.firebasestorage.app',
          ),
        );
      }
    }
    if (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) {
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    }
  } catch (e) {
    debugPrint("Firebase init error: $e");
  }

  try {
    await GoogleSignIn.instance.initialize(
      serverClientId: '563333021985-nbrjkql6t8evhd7i47lf8s7ie4khjdi6.apps.googleusercontent.com',
    );
  } catch (e) {
    debugPrint("Google SignIn init error: $e");
  }

  runApp(const LaVieApp());
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class LaVieApp extends StatelessWidget {
  const LaVieApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'La-Vie Premium',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF00E5FF),
        scaffoldBackgroundColor: const Color(0xFF070B19),
        fontFamily: 'Inter',
      ),
      home: (Firebase.apps.isNotEmpty && FirebaseAuth.instance.currentUser != null)
          ? const MainLayout()
          : const LoginScreen(),
    );
  }
}
