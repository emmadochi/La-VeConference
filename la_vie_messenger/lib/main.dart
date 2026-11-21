import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:desktop_webview_auth/desktop_webview_auth.dart';
import 'package:desktop_webview_auth/google.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'theme/app_theme.dart';
import 'services/theme_service.dart';
import 'screens/main_shell.dart';
import 'widgets/global_active_call_overlay.dart';
import 'services/active_call_manager.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
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
    final data = message.data;
    final chatId = data['chat_id'] ?? data['chatId'];
    final messageId = data['message_id'] ?? data['messageId'];
    final receiverId = data['receiver_id'] ?? data['receiverId'];
    if (chatId != null && chatId.toString().isNotEmpty) {
      http.post(
        Uri.parse('https://la-vie.lifechangerstouch.org/api/chat/delivered'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chat_id': chatId,
          'message_id': messageId,
          'receiver_id': receiverId,
        }),
      ).timeout(const Duration(seconds: 4)).catchError((_) => http.Response('{}', 200));
    }
  } catch (_) {}
  debugPrint("Handling background push notification: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase safely (iOS reads GoogleService-Info.plist automatically)
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
  } catch (e) {
    debugPrint("Firebase.initializeApp with options: $e");
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
    } catch (err) {
      debugPrint("Fallback Firebase.initializeApp: $err");
    }
  }

  if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
    try {
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    } catch (e) {
      debugPrint("FirebaseMessaging init: $e");
    }
  }

  // Initialize Theme Service
  await ThemeService.instance.init();

  // Prevent release mode grey screen on widget build errors
  ErrorWidget.builder = (FlutterErrorDetails details) {
    debugPrint("Flutter UI error caught safely: ${details.exceptionAsString()}");
    return const SizedBox.shrink();
  };

  runApp(const LiChatApp());
}

class LiChatApp extends StatelessWidget {
  const LiChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeService.instance,
      builder: (context, _) {
        return MaterialApp(
          title: 'LiChat',
          navigatorKey: rootNavigatorKey,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeService.instance.currentMode,
          builder: (context, child) {
            return Stack(
              children: [
                if (child != null) child,
                ListenableBuilder(
                  listenable: ActiveCallManager.instance,
                  builder: (context, _) {
                    final callManager = ActiveCallManager.instance;
                    if (!callManager.hasActiveCall || !callManager.isMinimized) {
                      return const SizedBox.shrink();
                    }
                    return const Positioned.fill(
                      child: GlobalActiveCallOverlay(),
                    );
                  },
                ),
              ],
            );
          },
          home: const AuthGate(),
          routes: {
            '/': (context) => const AuthGate(),
          },
        );
      },
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      initialData: FirebaseAuth.instance.currentUser,
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && snapshot.data == null) {
          return const Scaffold(
            backgroundColor: AppTheme.background,
            body: Center(child: CircularProgressIndicator(color: AppTheme.mint)),
          );
        }

        if (snapshot.hasData && snapshot.data != null) {
          return const MainShell();
        }

        return const WelcomeAuthScreen();
      },
    );
  }
}

class WelcomeAuthScreen extends StatefulWidget {
  const WelcomeAuthScreen({Key? key}) : super(key: key);

  @override
  State<WelcomeAuthScreen> createState() => _WelcomeAuthScreenState();
}

class _WelcomeAuthScreenState extends State<WelcomeAuthScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  bool _isSignUp = false;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _isPasswordVisible = false;
  String? _error;
  String? _infoBanner;

  void _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();

    if (email.isEmpty || password.isEmpty || (_isSignUp && name.isEmpty)) {
      setState(() => _error = 'Please fill in all fields');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _infoBanner = null;
    });

    try {
      if (_isSignUp) {
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        await cred.user?.updateDisplayName(name);
        await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).set({
          'displayName': name,
          'name': name,
          'email': email,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        if (cred.user != null) {
          final currentName = cred.user!.displayName ?? email.split('@')[0];
          await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).set({
            'displayName': currentName,
            'name': currentName,
            'email': email,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use' && _isSignUp) {
        // Smart Auto-Login: check if the password typed matches their existing Conference account
        try {
          final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: email,
            password: password,
          );
          if (cred.user != null) {
            final currentName = cred.user!.displayName ?? (name.isNotEmpty ? name : email.split('@')[0]);
            await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).set({
              'displayName': currentName,
              'name': currentName,
              'email': email,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            return;
          }
        } catch (_) {
          // Password didn't match their existing Conference password
        }

        // Show friendly "La-Vie Account Detected" dialog
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isSignUp = false;
            _error = null;
          });
          _showExistingAccountDialog(email);
          return;
        }
      }
      setState(() => _error = _formatAuthError(e));
    } catch (e) {
      setState(() => _error = _formatAuthError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showExistingAccountDialog(String email) {
    final isDark = AppTheme.isDark(context);
    final textPrimary = isDark ? Colors.white : AppTheme.lightTextPrimary;
    final textSecondary = isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;
    final surfaceColor = isDark ? AppTheme.surface : Colors.white;
    final border = isDark ? AppTheme.borderHighlight : AppTheme.lightBorder;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return Dialog(
          backgroundColor: surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: border),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: AppTheme.lilac.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.lilac.withValues(alpha: 0.35), width: 1.5),
                  ),
                  child: const Icon(Icons.verified_user_rounded, color: AppTheme.lilac, size: 32),
                ),
                const SizedBox(height: 18),
                Text(
                  'La-Vie Account Found!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'An existing account was found for $email from La-Vie Conference.\n\nYour single La-Vie ID works across all our apps! You do not need to register again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7C3AED), Color(0xFFA855F7)],
                    ),
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () {
                      Navigator.pop(dialogCtx);
                      setState(() {
                        _isSignUp = false;
                        _emailController.text = email;
                        _passwordController.clear();
                      });
                    },
                    child: const Text('Log In with My Password', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark ? AppTheme.lilac : AppTheme.lilacDark,
                      side: BorderSide(color: border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () {
                      Navigator.pop(dialogCtx);
                      _showForgotPasswordDialog(initialEmail: email);
                    },
                    child: const Text('I Forgot My Password', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatAuthError(dynamic e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-credential':
        case 'wrong-password':
          return 'Incorrect email or password. Please verify and try again, or use "Forgot Password?".';
        case 'user-not-found':
          return 'No account found with this email. Tap "Sign up" below to create your account.';
        case 'email-already-in-use':
          return 'An account already exists with this email address. Please log in.';
        case 'invalid-email':
          return 'Please enter a valid email address.';
        case 'weak-password':
          return 'Password should be at least 6 characters.';
        case 'user-disabled':
          return 'This account has been disabled. Please contact support.';
        case 'too-many-requests':
          return 'Too many attempts. Please wait a few moments or reset your password.';
        case 'network-request-failed':
          return 'Network error. Please check your internet connection and try again.';
        default:
          return e.message ?? 'Authentication failed. Please try again.';
      }
    }
    final s = e.toString();
    if (s.contains('10') || s.contains('ApiException')) {
      return 'Google Sign-In failed to connect. Please try again or log in with your email.';
    } else if (s.contains('SocketException') || s.contains('network') || s.contains('offline')) {
      return 'Network connection issue. Please check your internet connection.';
    }
    return 'Sign-in failed. Please check your credentials and try again.';
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isGoogleLoading = true;
      _error = null;
      _infoBanner = null;
    });

    try {
      UserCredential userCredential;
      String? googleDisplayName;
      String? googleEmail;
      String? googlePhotoUrl;

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        final result = await DesktopWebviewAuth.signIn(
          GoogleSignInArgs(
            clientId: '563333021985-nbrjkql6t8evhd7i47lf8s7ie4khjdi6.apps.googleusercontent.com',
            redirectUri: 'https://lifeconference-e0add.firebaseapp.com/__/auth/handler',
            scope: 'email profile openid',
          ),
          width: 550,
          height: 650,
        );
        if (result == null || (result.idToken == null && result.accessToken == null)) {
          if (mounted) setState(() => _isGoogleLoading = false);
          return;
        }

        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: result.accessToken,
          idToken: result.idToken,
        );
        userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      } else {
        final GoogleSignIn googleSignIn = GoogleSignIn(
          serverClientId: '563333021985-nbrjkql6t8evhd7i47lf8s7ie4khjdi6.apps.googleusercontent.com',
        );
        final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
        if (googleUser == null) {
          if (mounted) setState(() => _isGoogleLoading = false);
          return;
        }
        googleDisplayName = googleUser.displayName;
        googleEmail = googleUser.email;
        googlePhotoUrl = googleUser.photoUrl;

        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      }

      final user = userCredential.user;
      if (user != null) {
        final name = user.displayName ?? googleDisplayName ?? user.email?.split('@')[0] ?? 'User';
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'displayName': name,
          'name': name,
          'email': user.email ?? googleEmail,
          'photoURL': user.photoURL ?? googlePhotoUrl,
          'avatar': user.photoURL ?? googlePhotoUrl,
          'updatedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _formatAuthError(e));
    } catch (e) {
      final errStr = e.toString();
      if (!errStr.toLowerCase().contains('cancel') && !errStr.toLowerCase().contains('dismiss')) {
        setState(() => _error = _formatAuthError(e));
      }
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  void _showForgotPasswordDialog({String? initialEmail}) {
    final isDark = AppTheme.isDark(context);
    final textPrimary = isDark ? Colors.white : AppTheme.lightTextPrimary;
    final textSecondary = isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;
    final textMuted = isDark ? AppTheme.textMuted : AppTheme.lightTextMuted;
    final surfaceColor = isDark ? AppTheme.surface : Colors.white;
    final surfaceElevated = isDark ? AppTheme.surfaceElevated : AppTheme.lightSurfaceElevated;
    final border = isDark ? AppTheme.borderHighlight : AppTheme.lightBorder;
    final inputBorder = isDark ? AppTheme.border : AppTheme.lightBorder;
    final primaryAccent = isDark ? AppTheme.lilac : AppTheme.lilacDark;

    final resetEmailController = TextEditingController(
      text: (initialEmail != null && initialEmail.isNotEmpty)
          ? initialEmail
          : _emailController.text.trim(),
    );
    final otpController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    int step = 1; // 1 = Enter Email, 2 = Enter OTP & New Password
    bool isProcessing = false;
    bool obscureNewPassword = true;
    String? dialogError;
    String? dialogSuccess;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: surfaceColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: border),
              ),
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: primaryAccent.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            step == 1 ? Icons.lock_reset_rounded : Icons.verified_user_rounded,
                            color: primaryAccent,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            step == 1 ? 'Reset Password' : 'Enter 6-Digit Code',
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: textMuted, size: 20),
                          onPressed: isProcessing ? null : () => Navigator.pop(dialogCtx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    Text(
                      step == 1
                          ? 'Enter your registered email and we will send a 6-digit verification code directly to your inbox.'
                          : 'We sent a verification code to ${resetEmailController.text.trim()}. Enter the code and your new password below.',
                      style: TextStyle(color: textSecondary, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 16),

                    if (dialogError != null) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
                            const SizedBox(width: 8),
                            Expanded(child: Text(dialogError!, style: const TextStyle(color: Colors.redAccent, fontSize: 12))),
                          ],
                        ),
                      ),
                    ],

                    if (dialogSuccess != null) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: primaryAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: primaryAccent.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_outline, color: primaryAccent, size: 16),
                            const SizedBox(width: 8),
                            Expanded(child: Text(dialogSuccess!, style: TextStyle(color: primaryAccent, fontSize: 12))),
                          ],
                        ),
                      ),
                    ],

                    // STEP 1: ENTER EMAIL
                    if (step == 1) ...[
                      TextField(
                        controller: resetEmailController,
                        style: TextStyle(color: textPrimary),
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          hintText: 'your-email@example.com',
                          hintStyle: TextStyle(color: textMuted, fontSize: 13),
                          prefixIcon: Icon(Icons.email_outlined, color: primaryAccent, size: 20),
                          filled: true,
                          fillColor: surfaceElevated,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: inputBorder),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: primaryAccent, width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: textSecondary,
                                side: BorderSide(color: inputBorder),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              onPressed: isProcessing ? null : () => Navigator.pop(dialogCtx),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF7C3AED), Color(0xFFA855F7)],
                                ),
                              ),
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                onPressed: isProcessing
                                    ? null
                                    : () async {
                                        final email = resetEmailController.text.trim();
                                        if (email.isEmpty || !email.contains('@')) {
                                          setDialogState(() {
                                            dialogError = 'Please enter a valid email address.';
                                            dialogSuccess = null;
                                          });
                                          return;
                                        }

                                        setDialogState(() {
                                          isProcessing = true;
                                          dialogError = null;
                                          dialogSuccess = null;
                                        });

                                        try {
                                          final response = await http.post(
                                            Uri.parse('https://la-vie.lifechangerstouch.org/api/auth/send-reset-otp'),
                                            headers: {'Content-Type': 'application/json'},
                                            body: jsonEncode({'email': email.toLowerCase()}),
                                          ).timeout(const Duration(seconds: 10));

                                          if (response.statusCode == 200) {
                                            final data = jsonDecode(response.body);
                                            if (data is Map && data['sent'] == true) {
                                              setDialogState(() {
                                                isProcessing = false;
                                                step = 2;
                                                dialogSuccess = 'Code sent! Please check your inbox & spam folder.';
                                              });
                                            } else {
                                              // Fallback: SMTP couldn't dispatch, trigger Firebase reset link directly
                                              await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                                              setDialogState(() {
                                                isProcessing = false;
                                                dialogSuccess = 'Password reset email sent to $email! Check your inbox.';
                                              });
                                            }
                                          } else if (response.statusCode == 404) {
                                            setDialogState(() {
                                              isProcessing = false;
                                              dialogError = 'No account found with this email. Please check your spelling or sign up.';
                                            });
                                          } else {
                                            // Fallback to Firebase Auth reset email on 503 or server error
                                            await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                                            setDialogState(() {
                                              isProcessing = false;
                                              dialogSuccess = 'Password reset email sent to $email! Check your inbox (and spam folder).';
                                            });
                                          }
                                        } on FirebaseAuthException catch (authErr) {
                                          setDialogState(() {
                                            isProcessing = false;
                                            dialogError = _formatAuthError(authErr);
                                          });
                                        } catch (e) {
                                          try {
                                            await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                                            setDialogState(() {
                                              isProcessing = false;
                                              dialogSuccess = 'Password reset email sent to $email! Check your inbox (and spam folder).';
                                            });
                                          } on FirebaseAuthException catch (authErr) {
                                            setDialogState(() {
                                              isProcessing = false;
                                              dialogError = _formatAuthError(authErr);
                                            });
                                          } catch (err) {
                                            setDialogState(() {
                                              isProcessing = false;
                                              dialogError = 'Could not send reset code. Please verify your email.';
                                            });
                                          }
                                        }
                                      },
                                child: isProcessing
                                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                    : const Text('Send Code', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton.icon(
                          onPressed: isProcessing
                              ? null
                              : () async {
                                  final email = resetEmailController.text.trim();
                                  if (email.isEmpty || !email.contains('@')) {
                                    setDialogState(() {
                                      dialogError = 'Please enter your email address first.';
                                      dialogSuccess = null;
                                    });
                                    return;
                                  }
                                  setDialogState(() {
                                    isProcessing = true;
                                    dialogError = null;
                                    dialogSuccess = null;
                                  });
                                  try {
                                    await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                                    setDialogState(() {
                                      isProcessing = false;
                                      dialogSuccess = 'Password reset email sent directly to $email! Check your inbox & spam folder.';
                                    });
                                  } on FirebaseAuthException catch (authErr) {
                                    setDialogState(() {
                                      isProcessing = false;
                                      dialogError = _formatAuthError(authErr);
                                    });
                                  } catch (err) {
                                    setDialogState(() {
                                      isProcessing = false;
                                      dialogError = 'Could not send reset email. Please try again.';
                                    });
                                  }
                                },
                          icon: const Icon(Icons.mark_email_read_outlined, size: 16, color: AppTheme.lilac),
                          label: const Text(
                            'Or send password reset link directly',
                            style: TextStyle(color: AppTheme.lilac, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],

                    // STEP 2: OTP & NEW PASSWORD
                    if (step == 2) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          color: surfaceElevated,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: primaryAccent.withValues(alpha: 0.5)),
                        ),
                        child: TextField(
                          controller: otpController,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: primaryAccent,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 6,
                          ),
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: '• • • • • •',
                            hintStyle: TextStyle(color: textMuted.withValues(alpha: 0.5), letterSpacing: 6),
                            border: InputBorder.none,
                            prefixIcon: Icon(Icons.pin, color: primaryAccent),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      TextField(
                        controller: newPasswordController,
                        obscureText: obscureNewPassword,
                        style: TextStyle(color: textPrimary),
                        decoration: InputDecoration(
                          hintText: 'New Password (min 6 characters)',
                          hintStyle: TextStyle(color: textMuted, fontSize: 13),
                          prefixIcon: Icon(Icons.lock_outline, color: primaryAccent, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscureNewPassword ? Icons.visibility_off : Icons.visibility,
                              color: textMuted,
                              size: 18,
                            ),
                            onPressed: () => setDialogState(() => obscureNewPassword = !obscureNewPassword),
                          ),
                          filled: true,
                          fillColor: surfaceElevated,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: inputBorder)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: primaryAccent, width: 1.5)),
                        ),
                      ),
                      const SizedBox(height: 14),

                      TextField(
                        controller: confirmPasswordController,
                        obscureText: obscureNewPassword,
                        style: TextStyle(color: textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Confirm New Password',
                          hintStyle: TextStyle(color: textMuted, fontSize: 13),
                          prefixIcon: Icon(Icons.lock_clock_outlined, color: primaryAccent, size: 20),
                          filled: true,
                          fillColor: surfaceElevated,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: inputBorder)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: primaryAccent, width: 1.5)),
                        ),
                      ),
                      const SizedBox(height: 18),

                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF7C3AED), Color(0xFFA855F7)],
                          ),
                        ),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: isProcessing
                              ? null
                              : () async {
                                  final email = resetEmailController.text.trim();
                                  final otp = otpController.text.trim();
                                  final newPass = newPasswordController.text.trim();
                                  final confirmPass = confirmPasswordController.text.trim();

                                  if (otp.length != 6) {
                                    setDialogState(() => dialogError = 'Please enter the 6-digit code.');
                                    return;
                                  }

                                  if (newPass.length < 6) {
                                    setDialogState(() => dialogError = 'Password must be at least 6 characters.');
                                    return;
                                  }

                                  if (newPass != confirmPass) {
                                    setDialogState(() => dialogError = 'Passwords do not match.');
                                    return;
                                  }

                                  setDialogState(() {
                                    isProcessing = true;
                                    dialogError = null;
                                  });

                                  try {
                                    final response = await http.post(
                                      Uri.parse('https://la-vie.lifechangerstouch.org/api/auth/verify-reset-otp'),
                                      headers: {'Content-Type': 'application/json'},
                                      body: jsonEncode({
                                        'email': email.toLowerCase(),
                                        'otp': otp,
                                        'new_password': newPass,
                                      }),
                                    );

                                    if (response.statusCode == 200) {
                                      setDialogState(() {
                                        isProcessing = false;
                                        dialogSuccess = 'Password reset successfully! Logging you in...';
                                      });

                                      _emailController.text = email;
                                      _passwordController.text = newPass;

                                      Future.delayed(const Duration(milliseconds: 1200), () {
                                        if (context.mounted) {
                                          Navigator.pop(dialogCtx);
                                          _submit();
                                        }
                                      });
                                    } else {
                                      final data = jsonDecode(response.body);
                                      setDialogState(() {
                                        isProcessing = false;
                                        dialogError = data['detail'] ?? 'Invalid verification code.';
                                      });
                                    }
                                  } catch (e) {
                                    setDialogState(() {
                                      isProcessing = false;
                                      dialogError = 'Verification error: ${e.toString().replaceAll("Exception: ", "")}';
                                    });
                                  }
                                },
                          child: isProcessing
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                              : const Text('Update Password & Sign In', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        ),
                      ),
                      const SizedBox(height: 10),

                      Center(
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed: isProcessing
                                  ? null
                                  : () async {
                                      final email = resetEmailController.text.trim();
                                      setDialogState(() {
                                        isProcessing = true;
                                        dialogError = null;
                                      });
                                      try {
                                        final resp = await http.post(
                                          Uri.parse('https://la-vie.lifechangerstouch.org/api/auth/send-reset-otp'),
                                          headers: {'Content-Type': 'application/json'},
                                          body: jsonEncode({'email': email.toLowerCase()}),
                                        ).timeout(const Duration(seconds: 10));

                                        if (resp.statusCode == 200) {
                                          final data = jsonDecode(resp.body);
                                          if (data is Map && data['sent'] == true) {
                                            setDialogState(() {
                                              isProcessing = false;
                                              dialogSuccess = 'A fresh 6-digit code has been sent. Check your inbox & spam folder.';
                                            });
                                          } else {
                                            await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                                            setDialogState(() {
                                              isProcessing = false;
                                              dialogSuccess = 'Reset email sent from Firebase! Check your inbox & spam.';
                                            });
                                          }
                                        } else {
                                          await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                                          setDialogState(() {
                                            isProcessing = false;
                                            dialogSuccess = 'Reset email sent from Firebase! Check your inbox & spam.';
                                          });
                                        }
                                      } catch (_) {
                                        try {
                                          await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                                          setDialogState(() {
                                            isProcessing = false;
                                            dialogSuccess = 'Reset email sent from Firebase! Check your inbox & spam.';
                                          });
                                        } catch (e) {
                                          setDialogState(() => isProcessing = false);
                                        }
                                      }
                                    },
                              icon: const Icon(Icons.refresh, color: AppTheme.lilac, size: 16),
                              label: const Text('Resend Code', style: TextStyle(color: AppTheme.lilac, fontSize: 12, fontWeight: FontWeight.w600)),
                            ),
                            Text('•', style: TextStyle(color: textMuted)),
                            TextButton.icon(
                              onPressed: isProcessing
                                  ? null
                                  : () async {
                                      final email = resetEmailController.text.trim();
                                      setDialogState(() {
                                        isProcessing = true;
                                        dialogError = null;
                                      });
                                      try {
                                        await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                                        setDialogState(() {
                                          isProcessing = false;
                                          dialogSuccess = 'Reset link sent to $email! Check your inbox (including spam).';
                                        });
                                      } on FirebaseAuthException catch (authErr) {
                                        setDialogState(() {
                                          isProcessing = false;
                                          dialogError = _formatAuthError(authErr);
                                        });
                                      } catch (e) {
                                        setDialogState(() {
                                          isProcessing = false;
                                          dialogError = 'Failed to send reset email. Please verify your email.';
                                        });
                                      }
                                    },
                              icon: const Icon(Icons.send_rounded, color: AppTheme.lilac, size: 16),
                              label: const Text('Send Reset Link Instead', style: TextStyle(color: AppTheme.lilac, fontSize: 12, fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _demoLogin() async {
    setState(() => _isLoading = true);
    try {
      final cred = await FirebaseAuth.instance.signInAnonymously();
      await cred.user?.updateDisplayName('Guest User');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildGoogleLogo() {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: const Text(
        'G',
        style: TextStyle(
          color: Color(0xFF4285F4),
          fontWeight: FontWeight.w900,
          fontSize: 15,
          fontFamily: 'sans-serif',
        ),
      ),
    );
  }

  Widget _buildDesktopShowcasePanel(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final primaryAccent = isDark ? AppTheme.lilac : AppTheme.lilacDark;
    final textPrimary = isDark ? Colors.white : AppTheme.lightTextPrimary;
    final textSecondary = isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;

    return Container(
      width: 400,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E1738), const Color(0xFF130E26), const Color(0xFF0C0A17)]
              : [const Color(0xFFF3EDFD), const Color(0xFFEBE2FC), const Color(0xFFE5D9FA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Glowing Brand Badge
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                colors: [Color(0xFF8B5CF6), Color(0xFFC084FC)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: primaryAccent.withValues(alpha: isDark ? 0.35 : 0.25),
                  blurRadius: 24,
                  spreadRadius: 2,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.all(2.5),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(19.5),
              child: Image.asset('assets/images/lichat_logo.png', fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 28),

          Text(
            'LiChat Desktop',
            style: TextStyle(
              color: textPrimary,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'End-to-end encrypted messaging, crystal-clear voice and HD video calling.',
            style: TextStyle(
              color: textSecondary,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 36),

          // Feature list
          _buildShowcaseFeatureItem(
            icon: Icons.lock_outline_rounded,
            title: 'End-to-End Encrypted',
            subtitle: 'Messages, media and call signaling are private to your device.',
            isDark: isDark,
            primaryAccent: primaryAccent,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),
          const SizedBox(height: 20),
          _buildShowcaseFeatureItem(
            icon: Icons.videocam_outlined,
            title: 'HD Voice & Video Calls',
            subtitle: 'Low-latency global calling powered by LiveKit audio/video engine.',
            isDark: isDark,
            primaryAccent: primaryAccent,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),
          const SizedBox(height: 20),
          _buildShowcaseFeatureItem(
            icon: Icons.qr_code_scanner_rounded,
            title: 'Instant QR Sync',
            subtitle: 'Pair quickly with phone or tablet using companion barcode sync.',
            isDark: isDark,
            primaryAccent: primaryAccent,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),

          const Spacer(),

          // Security Badge Footer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_outlined, size: 15, color: primaryAccent),
                const SizedBox(width: 8),
                Text(
                  'Unified La-Vie Ecosystem Authentication',
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShowcaseFeatureItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isDark,
    required Color primaryAccent,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: primaryAccent.withValues(alpha: isDark ? 0.15 : 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: primaryAccent, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAuthForm({required bool isDesktop}) {
    final isDark = AppTheme.isDark(context);
    final primaryAccent = isDark ? AppTheme.lilac : AppTheme.lilacDark;
    final textPrimary = isDark ? Colors.white : AppTheme.lightTextPrimary;
    final textSecondary = isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;
    final textMuted = isDark ? AppTheme.textMuted : AppTheme.lightTextMuted;
    final surfaceElevated = isDark ? AppTheme.surfaceElevated : Colors.white;
    final border = isDark ? AppTheme.border : AppTheme.lightBorder;
    final borderHighlight = isDark ? AppTheme.borderHighlight : AppTheme.lightBorder;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 36.0 : 24.0,
        vertical: isDesktop ? 32.0 : 20.0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isDesktop) ...[
            const SizedBox(height: 8),
            // Mobile Brand Header
            Center(
              child: Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8B5CF6), Color(0xFFC084FC)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: primaryAccent.withValues(alpha: isDark ? 0.35 : 0.22),
                      blurRadius: 18,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(2),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.asset('assets/images/lichat_logo.png', fit: BoxFit.cover),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: Text(
                _isSignUp ? 'Create Account' : 'Welcome to LiChat',
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                'Private, barcode-paired messaging & HD calling.',
                textAlign: TextAlign.center,
                style: TextStyle(color: textSecondary, fontSize: 13.5),
              ),
            ),
            const SizedBox(height: 24),
          ] else ...[
            Text(
              _isSignUp ? 'Create LiChat Account' : 'Welcome Back',
              style: TextStyle(
                color: textPrimary,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _isSignUp
                  ? 'Join LiChat to message and call across all your devices.'
                  : 'Log in with your email or La-Vie Conference credentials.',
              style: TextStyle(color: textSecondary, fontSize: 13.5),
            ),
            const SizedBox(height: 24),
          ],

          // Segmented Pill Tab Switcher: Log In / Sign Up
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(11),
                    onTap: () {
                      if (_isSignUp) {
                        setState(() {
                          _isSignUp = false;
                          _error = null;
                          _infoBanner = null;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: !_isSignUp ? surfaceElevated : Colors.transparent,
                        borderRadius: BorderRadius.circular(11),
                        boxShadow: !_isSignUp
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Log In',
                        style: TextStyle(
                          color: !_isSignUp ? textPrimary : textMuted,
                          fontSize: 14,
                          fontWeight: !_isSignUp ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(11),
                    onTap: () {
                      if (!_isSignUp) {
                        setState(() {
                          _isSignUp = true;
                          _error = null;
                          _infoBanner = null;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: _isSignUp ? surfaceElevated : Colors.transparent,
                        borderRadius: BorderRadius.circular(11),
                        boxShadow: _isSignUp
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Create Account',
                        style: TextStyle(
                          color: _isSignUp ? textPrimary : textMuted,
                          fontSize: 14,
                          fontWeight: _isSignUp ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Google Sign-In Button (Modern, High-Contrast)
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: textPrimary,
                side: BorderSide(color: borderHighlight, width: 1.2),
                backgroundColor: surfaceElevated,
                elevation: isDark ? 0 : 1,
                shadowColor: Colors.black.withValues(alpha: 0.06),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _isGoogleLoading ? null : _signInWithGoogle,
              child: _isGoogleLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: primaryAccent, strokeWidth: 2.2),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildGoogleLogo(),
                        const SizedBox(width: 12),
                        Text(
                          _isSignUp ? 'Sign up with Google' : 'Continue with Google',
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 18),

          // Divider: OR
          Row(
            children: [
              Expanded(child: Divider(color: border, thickness: 1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  'OR WITH EMAIL',
                  style: TextStyle(
                    color: textMuted.withValues(alpha: 0.8),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              Expanded(child: Divider(color: border, thickness: 1)),
            ],
          ),
          const SizedBox(height: 18),

          // Error banner
          if (_error != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: isDark ? 0.12 : 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12.5, height: 1.3),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _error = null),
                    child: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 16),
                  ),
                ],
              ),
            ),

          // Info banner
          if (_infoBanner != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: primaryAccent.withValues(alpha: isDark ? 0.12 : 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: primaryAccent.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(Icons.verified_user_rounded, color: primaryAccent, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _infoBanner!,
                      style: TextStyle(color: textPrimary, fontSize: 12.5, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),

          // Sign Up: Full Name
          if (_isSignUp) ...[
            TextField(
              controller: _nameController,
              style: TextStyle(color: textPrimary, fontSize: 14.5),
              decoration: InputDecoration(
                labelText: 'Full Name',
                prefixIcon: Icon(Icons.person_outline_rounded, color: textMuted, size: 20),
                labelStyle: TextStyle(color: textMuted, fontSize: 13.5),
                floatingLabelStyle: TextStyle(color: primaryAccent, fontWeight: FontWeight.w600),
                filled: true,
                fillColor: surfaceElevated,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: border, width: 1.2),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: primaryAccent, width: 1.8),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Email Address
          TextField(
            controller: _emailController,
            style: TextStyle(color: textPrimary, fontSize: 14.5),
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Email Address',
              prefixIcon: Icon(Icons.alternate_email_rounded, color: textMuted, size: 19),
              labelStyle: TextStyle(color: textMuted, fontSize: 13.5),
              floatingLabelStyle: TextStyle(color: primaryAccent, fontWeight: FontWeight.w600),
              filled: true,
              fillColor: surfaceElevated,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: border, width: 1.2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: primaryAccent, width: 1.8),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Password
          TextField(
            controller: _passwordController,
            obscureText: !_isPasswordVisible,
            style: TextStyle(color: textPrimary, fontSize: 14.5),
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: Icon(Icons.lock_outline_rounded, color: textMuted, size: 19),
              labelStyle: TextStyle(color: textMuted, fontSize: 13.5),
              floatingLabelStyle: TextStyle(color: primaryAccent, fontWeight: FontWeight.w600),
              filled: true,
              fillColor: surfaceElevated,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: border, width: 1.2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: primaryAccent, width: 1.8),
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                  color: textMuted,
                  size: 19,
                ),
                onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
              ),
            ),
          ),

          // Forgot Password link
          if (!_isSignUp) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _isLoading ? null : _showForgotPasswordDialog,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Forgot Password?',
                  style: TextStyle(color: primaryAccent, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Primary Gradient Submit Button
          Container(
            width: double.infinity,
            height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                colors: [Color(0xFF7C3AED), Color(0xFFA855F7), Color(0xFFB388FF)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFA855F7).withValues(alpha: isDark ? 0.35 : 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _isLoading ? null : _submit,
              child: _isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                    )
                  : Text(
                      _isSignUp ? 'Create Account' : 'Log In',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                    ),
            ),
          ),
          const SizedBox(height: 14),

          // Unified Ecosystem note
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.hub_rounded, size: 16, color: primaryAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'La-Vie Conference accounts work automatically in LiChat.',
                    style: TextStyle(color: textSecondary, fontSize: 11.5, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Guest Login
          Center(
            child: TextButton(
              onPressed: _demoLogin,
              child: Text(
                'Continue as Guest for Instant Preview',
                style: TextStyle(color: textMuted, fontSize: 12.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final border = isDark ? AppTheme.border : AppTheme.lightBorder;
    final surfaceElevated = isDark ? AppTheme.surfaceElevated : Colors.white;
    final isDesktop = MediaQuery.of(context).size.width >= 850;

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      body: Stack(
        children: [
          // Ambient Lilac Glow
          Positioned(
            top: -60,
            left: -40,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    (isDark ? const Color(0xFFA855F7) : const Color(0xFF8B5CF6)).withValues(alpha: isDark ? 0.22 : 0.12),
                    (isDark ? const Color(0xFF7C3AED) : const Color(0xFFA855F7)).withValues(alpha: isDark ? 0.08 : 0.04),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: isDesktop
                ? Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 920),
                        decoration: BoxDecoration(
                          color: surfaceElevated,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: border.withValues(alpha: 0.8), width: 1.2),
                          boxShadow: [
                            BoxShadow(
                              color: isDark ? Colors.black.withValues(alpha: 0.45) : Colors.black.withValues(alpha: 0.08),
                              blurRadius: 36,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Left: Desktop Showcase Panel
                              _buildDesktopShowcasePanel(context),

                              // Vertical Divider
                              VerticalDivider(
                                width: 1,
                                thickness: 1,
                                color: border.withValues(alpha: 0.8),
                              ),

                              // Right: Interactive Auth Form
                              Expanded(
                                child: _buildAuthForm(isDesktop: true),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: _buildAuthForm(isDesktop: false),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
