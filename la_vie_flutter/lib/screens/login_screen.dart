import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'signup_screen.dart';
import '../main_layout.dart';
import '../api_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MainLayout()),
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _error = e.message ?? "Authentication failed. Please check your credentials.";
      });
    } catch (e) {
      setState(() {
        final errStr = e.toString();
        if (errStr.contains('invalid-credential') || errStr.contains('user-not-found') || errStr.contains('wrong-password')) {
          _error = "Invalid email or password. Please check your details.";
        } else {
          _error = errStr.replaceFirst(RegExp(r'^[A-Za-z]+Exception:?\s*'), '');
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showForgotPasswordDialog() {
    final resetEmailController = TextEditingController(text: _emailController.text.trim());
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
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withOpacity(0.95),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3), width: 1.5),
                    ),
                    child: SingleChildScrollView(
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
                                  color: const Color(0xFF00E5FF).withOpacity(0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  step == 1 ? Icons.lock_reset : Icons.verified_user_outlined,
                                  color: const Color(0xFF00E5FF),
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  step == 1 ? 'Reset Password' : 'Enter 6-Digit Code',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                                onPressed: isProcessing ? null : () => Navigator.pop(context),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Subtitle Description
                          Text(
                            step == 1
                                ? 'Enter your registered email and we will send a 6-digit verification code directly to your inbox.'
                                : 'We sent a verification code to ${resetEmailController.text.trim()}. Enter the code and your new password below.',
                            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13, height: 1.4),
                          ),
                          const SizedBox(height: 16),

                          // Error Banner
                          if (dialogError != null) ...[
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      dialogError!,
                                      style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],

                          // Success Banner
                          if (dialogSuccess != null) ...[
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00FFA3).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFF00FFA3).withOpacity(0.3)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.check_circle_outline, color: Color(0xFF00FFA3), size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      dialogSuccess!,
                                      style: const TextStyle(color: Color(0xFF00FFA3), fontSize: 12, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],

                          // STEP 1: EMAIL INPUT
                          if (step == 1) ...[
                            _buildTextField(
                              controller: resetEmailController,
                              hint: 'Email Address',
                              icon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                Expanded(
                                  child: TextButton(
                                    onPressed: isProcessing ? null : () => Navigator.pop(context),
                                    child: Text(
                                      'Cancel',
                                      style: TextStyle(color: Colors.white.withOpacity(0.6)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 2,
                                  child: GestureDetector(
                                    onTap: isProcessing
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
                                              await ApiService.sendPasswordResetOtp(email);
                                              setDialogState(() {
                                                isProcessing = false;
                                                step = 2;
                                                dialogSuccess = 'Code sent! Please check your email.';
                                              });
                                            } catch (e) {
                                              setDialogState(() {
                                                isProcessing = false;
                                                dialogError = e.toString().replaceAll('Exception: ', '');
                                              });
                                            }
                                          },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 13),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [Color(0xFF00E5FF), Color(0xFF6C11FF)],
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF00E5FF).withOpacity(0.3),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Center(
                                        child: isProcessing
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                              )
                                            : const Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(Icons.send, color: Color(0xFF070B19), size: 16),
                                                  SizedBox(width: 6),
                                                  Text(
                                                    'Send Code',
                                                    style: TextStyle(color: Color(0xFF070B19), fontWeight: FontWeight.bold, fontSize: 13),
                                                  ),
                                                ],
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],

                          // STEP 2: OTP & NEW PASSWORD INPUTS
                          if (step == 2) ...[
                            // 6-Digit OTP Field
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.4)),
                              ),
                              child: TextField(
                                controller: otpController,
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF00E5FF),
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 8,
                                ),
                                decoration: const InputDecoration(
                                  counterText: '',
                                  hintText: '• • • • • •',
                                  hintStyle: TextStyle(color: Colors.white30, letterSpacing: 8),
                                  border: InputBorder.none,
                                  prefixIcon: Icon(Icons.pin, color: Color(0xFF00E5FF)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // New Password Field
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white.withOpacity(0.12)),
                              ),
                              child: TextField(
                                controller: newPasswordController,
                                obscureText: obscureNewPassword,
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                                decoration: InputDecoration(
                                  hintText: 'New Password (min 6 characters)',
                                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                                  prefixIcon: const Icon(Icons.lock_outline, color: Colors.white70, size: 20),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      obscureNewPassword ? Icons.visibility_off : Icons.visibility,
                                      color: Colors.white54,
                                      size: 18,
                                    ),
                                    onPressed: () => setDialogState(() => obscureNewPassword = !obscureNewPassword),
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Confirm New Password Field
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white.withOpacity(0.12)),
                              ),
                              child: TextField(
                                controller: confirmPasswordController,
                                obscureText: obscureNewPassword,
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                                decoration: const InputDecoration(
                                  hintText: 'Confirm New Password',
                                  hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                                  prefixIcon: Icon(Icons.lock_clock_outlined, color: Colors.white70, size: 20),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),

                            // Submit Reset Button
                            GestureDetector(
                              onTap: isProcessing
                                  ? null
                                  : () async {
                                      final email = resetEmailController.text.trim();
                                      final otp = otpController.text.trim();
                                      final newPass = newPasswordController.text.trim();
                                      final confirmPass = confirmPasswordController.text.trim();

                                      if (otp.length != 6) {
                                        setDialogState(() {
                                          dialogError = 'Please enter the complete 6-digit verification code.';
                                          dialogSuccess = null;
                                        });
                                        return;
                                      }

                                      if (newPass.length < 6) {
                                        setDialogState(() {
                                          dialogError = 'New password must be at least 6 characters.';
                                          dialogSuccess = null;
                                        });
                                        return;
                                      }

                                      if (newPass != confirmPass) {
                                        setDialogState(() {
                                          dialogError = 'Passwords do not match.';
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
                                        final res = await ApiService.verifyPasswordResetOtp(
                                          email: email,
                                          otp: otp,
                                          newPassword: newPass,
                                        );

                                        setDialogState(() {
                                          isProcessing = false;
                                          dialogSuccess = 'Password updated successfully! Logging you in...';
                                        });

                                        _emailController.text = email;
                                        _passwordController.text = newPass;

                                        // Auto-login with the new password
                                        Future.delayed(const Duration(milliseconds: 1200), () async {
                                          if (context.mounted) {
                                            Navigator.pop(context);
                                            await _login();
                                          }
                                        });
                                      } catch (e) {
                                        setDialogState(() {
                                          isProcessing = false;
                                          dialogError = e.toString().replaceAll('Exception: ', '');
                                        });
                                      }
                                    },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF00FFA3), Color(0xFF00E5FF)],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF00FFA3).withOpacity(0.3),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: isProcessing
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(color: Color(0xFF070B19), strokeWidth: 2.5),
                                        )
                                      : const Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.check_circle, color: Color(0xFF070B19), size: 18),
                                            SizedBox(width: 8),
                                            Text(
                                              'Update Password & Sign In',
                                              style: TextStyle(
                                                color: Color(0xFF070B19),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Resend Code Link
                            Center(
                              child: TextButton.icon(
                                onPressed: isProcessing
                                    ? null
                                    : () async {
                                        setDialogState(() {
                                          isProcessing = true;
                                          dialogError = null;
                                          dialogSuccess = null;
                                        });
                                        try {
                                          await ApiService.sendPasswordResetOtp(resetEmailController.text.trim());
                                          setDialogState(() {
                                            isProcessing = false;
                                            dialogSuccess = 'A fresh 6-digit code has been sent to your email.';
                                          });
                                        } catch (e) {
                                          setDialogState(() {
                                            isProcessing = false;
                                            dialogError = e.toString().replaceAll('Exception: ', '');
                                          });
                                        }
                                      },
                                icon: const Icon(Icons.refresh, color: Color(0xFF00E5FF), size: 16),
                                label: const Text(
                                  'Resend Verification Code',
                                  style: TextStyle(color: Color(0xFF00E5FF), fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final GoogleSignInAccount googleUser = await GoogleSignIn.instance.authenticate();

      final GoogleSignInAuthentication googleAuth = googleUser.authentication;
      final GoogleSignInClientAuthorization? clientAuth = await googleUser.authorizationClient.authorizationForScopes([
        'email',
        'https://www.googleapis.com/auth/userinfo.profile',
        'https://www.googleapis.com/auth/calendar.events',
      ]);

      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: clientAuth?.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MainLayout()),
        );
      }
    } on GoogleSignInException catch (e) {
      if (e.code == 'sign_in_canceled' || e.code == 'canceled' || e.code == 'GoogleSignInExceptionCode.canceled' || e.toString().toLowerCase().contains('cancel')) {
        return;
      }
      setState(() {
        _error = "Google Sign In failed: ${e.toString()}";
      });
    } on FirebaseAuthException catch (e) {
      setState(() {
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _error = "An unexpected error occurred with Google Sign In.";
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  bool _isPasswordVisible = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B19),
      body: Stack(
        children: [
          // Background Glows
          Positioned(
            top: -120,
            right: -120,
            child: Container(
              width: 380,
              height: 380,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF00E5FF).withOpacity(0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -120,
            left: -120,
            child: Container(
              width: 380,
              height: 380,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF5C00FF).withOpacity(0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 32.0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 450),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        padding: const EdgeInsets.all(32.0),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A).withOpacity(0.75),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.12),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.4),
                              blurRadius: 30,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Logo with glow ring
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.05),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF00E5FF).withOpacity(0.2),
                                    blurRadius: 20,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Image.asset(
                                'assets/logoI.png',
                                width: 72,
                                height: 72,
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'Welcome Back',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Sign in to continue to La-Vie Premium',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 13,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 32),

                            // Error Banner
                            if (_error != null) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _error!,
                                        style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],

                            // Email Field
                            _buildTextField(
                              controller: _emailController,
                              hint: 'Email Address',
                              icon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                            ),
                            const SizedBox(height: 16),

                            // Password Field
                            _buildTextField(
                              controller: _passwordController,
                              hint: 'Password',
                              icon: Icons.lock_outline,
                              obscureText: !_isPasswordVisible,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                                  color: Colors.white38,
                                  size: 20,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _isPasswordVisible = !_isPasswordVisible;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Forgot Password Link
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
                                  style: TextStyle(
                                    color: const Color(0xFF00E5FF).withOpacity(0.9),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Login Button
                            GestureDetector(
                              onTap: _isLoading ? null : _login,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF6C11FF), Color(0xFF00E5FF)],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF00E5FF).withOpacity(0.35),
                                      blurRadius: 18,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text(
                                          'SIGN IN',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1.5,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Google Sign In Button
                            GestureDetector(
                              onTap: _isLoading ? null : _signInWithGoogle,
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.15),
                                      blurRadius: 10,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(Icons.g_mobiledata, color: Colors.black, size: 28),
                                    SizedBox(width: 8),
                                    Text(
                                      'SIGN IN WITH GOOGLE',
                                      style: TextStyle(
                                        color: Colors.black87,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 28),

                            // Sign Up Link
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  "Don't have an account? ",
                                  style: TextStyle(color: Colors.white54, fontSize: 13),
                                ),
                                GestureDetector(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => const SignupScreen()),
                                    );
                                  },
                                  child: const Text(
                                    "Sign Up",
                                    style: TextStyle(
                                      color: Color(0xFF00E5FF),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    Widget? suffixIcon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
          prefixIcon: Icon(icon, color: const Color(0xFF00E5FF), size: 20),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        ),
      ),
    );
  }
}
