import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../api_service.dart';
import '../main_layout.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({Key? key}) : super(key: key);

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();
  bool _isLoading = false;
  bool _isOtpStep = false;
  int _resendSeconds = 0;
  Timer? _resendTimer;
  String? _error;
  String? _statusMessage;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _startResendCooldown([int seconds = 45]) {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = seconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  Future<void> _sendSignupOtp() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (name.isEmpty) {
      setState(() => _error = 'Please enter your full name.');
      return;
    }
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters long.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _statusMessage = null;
    });

    try {
      await ApiService.sendSignupOtp(email: email, displayName: name);
      if (mounted) {
        setState(() {
          _isOtpStep = true;
          _otpController.clear();
          _statusMessage = 'We sent a 6-digit verification code to $email.';
        });
        _startResendCooldown(45);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _resendOtp() async {
    if (_resendSeconds > 0 || _isLoading) return;
    await _sendSignupOtp();
  }

  Future<void> _signup() async {
    if (!_isOtpStep) {
      await _sendSignupOtp();
      return;
    }

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final otp = _otpController.text.trim();

    if (otp.length != 6) {
      setState(() => _error = 'Please enter the 6-digit verification code.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await ApiService.verifySignupOtp(
        email: email,
        otp: otp,
        password: password,
        displayName: name,
      );

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MainLayout()),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message ?? 'Could not sign in after verification.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
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
          Positioned(
            bottom: -120,
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
                            // Back Button + Header
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.arrow_back, color: Colors.white70),
                                  onPressed: () => Navigator.pop(context),
                                ),
                                const Expanded(
                                  child: Text(
                                    'Create Account',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                const SizedBox(width: 48), // Balance spacing
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Join La-Vie Premium today',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 13,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 28),

                            // Success / Status Banner
                            if (_statusMessage != null) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00E5FF).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.35)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.mark_email_read_outlined, color: Color(0xFF00E5FF), size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _statusMessage!,
                                        style: const TextStyle(color: Colors.white, fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],

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

                            if (!_isOtpStep) ...[
                              // Name Field
                              _buildTextField(
                                controller: _nameController,
                                hint: 'Full Name',
                                icon: Icons.person_outline,
                              ),
                              const SizedBox(height: 16),

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
                            ] else ...[
                              // Step 2: 6-Digit Email OTP Field
                              _buildTextField(
                                controller: _otpController,
                                hint: '6-Digit Verification Code',
                                icon: Icons.verified_user_outlined,
                                keyboardType: TextInputType.number,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  TextButton(
                                    onPressed: _isLoading
                                        ? null
                                        : () {
                                            setState(() {
                                              _isOtpStep = false;
                                              _error = null;
                                              _statusMessage = null;
                                            });
                                          },
                                    child: const Text(
                                      'Change Email',
                                      style: TextStyle(color: Colors.white60, fontSize: 13),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: (_resendSeconds > 0 || _isLoading) ? null : _resendOtp,
                                    child: Text(
                                      _resendSeconds > 0 ? 'Resend in ${_resendSeconds}s' : 'Resend Code',
                                      style: TextStyle(
                                        color: _resendSeconds > 0 ? Colors.white38 : const Color(0xFF00E5FF),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 28),

                            // Sign Up Button
                            GestureDetector(
                              onTap: _isLoading ? null : _signup,
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
                                      : Text(
                                          _isOtpStep ? 'VERIFY & CREATE ACCOUNT' : 'CONTINUE',
                                          style: const TextStyle(
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

                            // Google Sign Up Button
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
                                      'SIGN UP WITH GOOGLE',
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
