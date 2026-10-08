import 'package:flutter/material.dart';

class FriendlyErrorInfo {
  final String title;
  final String message;
  final IconData icon;
  final Color iconColor;
  final bool isCancellation;

  const FriendlyErrorInfo({
    required this.title,
    required this.message,
    required this.icon,
    this.iconColor = Colors.redAccent,
    this.isCancellation = false,
  });
}

class ErrorUtils {
  static FriendlyErrorInfo parseMeetingError(dynamic error) {
    if (error == null) {
      return const FriendlyErrorInfo(
        title: 'Connection Failed',
        message: 'An unexpected error occurred. Please try again.',
        icon: Icons.error_outline_rounded,
      );
    }

    final str = error.toString().toLowerCase();

    // 1. User Cancellation (e.g. screen projection prompt dismissed)
    if (str.contains('cancelled') ||
        str.contains('canceled') ||
        str.contains('mediaprojection cancelled') ||
        str.contains('user cancelled')) {
      return const FriendlyErrorInfo(
        title: 'Cancelled',
        message: 'Operation was cancelled.',
        icon: Icons.close_rounded,
        isCancellation: true,
      );
    }

    // 2. Room Locked
    if (str.contains('locked')) {
      return const FriendlyErrorInfo(
        title: 'Meeting Is Locked',
        message: 'This meeting has been locked by the host. No new participants may join.',
        icon: Icons.lock_outline_rounded,
        iconColor: Colors.amber,
      );
    }

    // 3. ICE / WebRTC Media Connection Timeout
    if (str.contains('mediaconnectexception') ||
        str.contains('ice connectivity') ||
        str.contains('peerconnection')) {
      return const FriendlyErrorInfo(
        title: 'Network Connection Unstable',
        message:
            'Unable to establish media connection.\n\nYour internet connection may be too slow or your network/carrier is restricting WebRTC media traffic. Please switch to a stronger connection or Wi-Fi and try again.',
        icon: Icons.wifi_off_rounded,
        iconColor: Colors.amber,
      );
    }

    // 4. Offline / DNS / Host Lookup Failure
    if (str.contains('socketexception') ||
        str.contains('failed host lookup') ||
        str.contains('no address associated with hostname') ||
        str.contains('network error') ||
        str.contains('connection dropped')) {
      return const FriendlyErrorInfo(
        title: 'No Internet Connection',
        message:
            'Unable to reach the conference server. Please check your cellular data or Wi-Fi connection and try again.',
        icon: Icons.signal_wifi_connected_no_internet_4_rounded,
        iconColor: Colors.redAccent,
      );
    }

    // 5. Connection Timeout
    if (str.contains('timeoutexception') || str.contains('timed out')) {
      return const FriendlyErrorInfo(
        title: 'Connection Timed Out',
        message: 'The server took too long to respond. Please check your network and try again.',
        icon: Icons.timer_off_outlined,
        iconColor: Colors.amber,
      );
    }

    // 6. Camera / Microphone In Use or Busy
    if (str.contains('notreadableerror') ||
        str.contains('could not start video source') ||
        str.contains('trackpublishexception') ||
        str.contains('camera busy') ||
        str.contains('device in use')) {
      return const FriendlyErrorInfo(
        title: 'Camera or Microphone In Use',
        message:
            'Your camera or microphone is currently in use by another application. Please close other camera/call apps and try again.',
        icon: Icons.videocam_off_rounded,
        iconColor: Colors.amber,
      );
    }

    // 7. Permissions Denied
    if (str.contains('notallowederror') ||
        str.contains('permission_denied') ||
        str.contains('permission denied') ||
        str.contains('permissiondeniedexception')) {
      return const FriendlyErrorInfo(
        title: 'Permissions Required',
        message:
            'Camera and microphone access are required for meetings. Please grant camera and microphone permissions in your device settings.',
        icon: Icons.security_rounded,
        iconColor: Colors.amber,
      );
    }

    // 8. Server 500 / Token Failure
    if (str.contains('status 50') ||
        str.contains('status 502') ||
        str.contains('status 503') ||
        str.contains('internal server error')) {
      return const FriendlyErrorInfo(
        title: 'Server Temporarily Unavailable',
        message: 'The meeting server encountered a temporary glitch. Please try again in a few moments.',
        icon: Icons.cloud_off_rounded,
        iconColor: Colors.redAccent,
      );
    }

    // 9. Meeting Not Found / 404
    if (str.contains('status 404') || str.contains('not found')) {
      return const FriendlyErrorInfo(
        title: 'Meeting Not Found',
        message: 'No active meeting was found with this ID. Please double-check your code or link.',
        icon: Icons.search_off_rounded,
        iconColor: Colors.amber,
      );
    }

    // Generic fallback: strip technical prefixes
    String cleaned = error.toString();
    if (cleaned.startsWith('Exception: ')) {
      cleaned = cleaned.substring('Exception: '.length);
    }
    if (cleaned.startsWith('Error: ')) {
      cleaned = cleaned.substring('Error: '.length);
    }
    if (cleaned.startsWith('LiveKit Exception: ')) {
      cleaned = cleaned.substring('LiveKit Exception: '.length);
    }

    return FriendlyErrorInfo(
      title: 'Connection Failed',
      message: cleaned,
      icon: Icons.error_outline_rounded,
      iconColor: Colors.redAccent,
    );
  }

  static String parseAuthError(dynamic error) {
    if (error == null) return 'An authentication error occurred.';
    final str = error.toString().toLowerCase();

    if (str.contains('user-not-found') || str.contains('wrong-password') || str.contains('invalid-credential')) {
      return 'Invalid email or password. Please check your credentials.';
    }
    if (str.contains('email-already-in-use')) {
      return 'An account with this email address already exists.';
    }
    if (str.contains('invalid-email')) {
      return 'Please enter a valid email address.';
    }
    if (str.contains('weak-password')) {
      return 'Password should be at least 6 characters long.';
    }
    if (str.contains('user-disabled')) {
      return 'This user account has been disabled. Please contact support.';
    }
    if (str.contains('network-request-failed')) {
      return 'Network error. Please check your internet connection and try again.';
    }
    if (str.contains('requires-recent-login')) {
      return 'For security, please log out and log back in before making this change.';
    }

    String cleaned = error.toString();
    if (cleaned.startsWith('Exception: ')) {
      cleaned = cleaned.substring('Exception: '.length);
    }
    return cleaned;
  }
}
