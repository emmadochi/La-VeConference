import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

class AlreadyInMeetingException implements Exception {
  final String activeRoom;
  final String targetRoom;
  final String message;

  AlreadyInMeetingException({
    required this.activeRoom,
    required this.targetRoom,
    required this.message,
  });

  @override
  String toString() => message;
}

class ApiService {
  static const String baseUrl = 'https://la-vie.lifechangerstouch.org';

  static Future<String> getToken(String roomName, String participantName, {bool force = false}) async {
    // Generate a unique peer ID or use Firebase UID
    final user = FirebaseAuth.instance.currentUser;
    final peerId = user?.uid ?? 'peer_${DateTime.now().millisecondsSinceEpoch}';
    
    final authToken = await user?.getIdToken();
    
    final uri = Uri.parse('$baseUrl/token/$roomName/$peerId?name=${Uri.encodeComponent(participantName)}${force ? "&force=true" : ""}');
    final response = await http.get(
      uri,
      headers: {
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['token'] as String;
    } else if (response.statusCode == 403 || response.statusCode == 409) {
      try {
        final data = jsonDecode(response.body);
        final detail = data['detail'];
        if (detail is Map) {
          throw AlreadyInMeetingException(
            activeRoom: detail['active_room']?.toString() ?? '',
            targetRoom: detail['target_room']?.toString() ?? roomName,
            message: detail['message']?.toString() ?? 'You are already in another meeting.',
          );
        } else if (detail is String) {
          throw AlreadyInMeetingException(
            activeRoom: '',
            targetRoom: roomName,
            message: detail,
          );
        }
      } catch (e) {
        if (e is AlreadyInMeetingException) rethrow;
      }
      throw Exception('You are already in another meeting.');
    } else {
      throw Exception('Failed to load token: ${response.body}');
    }
  }

  static Future<String> getLiveKitUrl() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/tunnel-config'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['livekit_url'] as String;
      }
    } catch (e) {
      // ignore
    }
    return 'wss://la-vie-nffo0a6v.livekit.cloud';
  }

  static Future<String?> startRecording(String roomName) async {
    try {
      final authToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/record/start'),
        headers: {
          'Content-Type': 'application/json',
          if (authToken != null) 'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({'room_id': roomName}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['egress_id'] as String?;
      } else {
        throw Exception('${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to connect: $e');
    }
  }

  static Future<bool> stopRecording(String egressId) async {
    try {
      final authToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/record/stop'),
        headers: {
          'Content-Type': 'application/json',
          if (authToken != null) 'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({'egress_id': egressId}),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> endMeeting(String roomName) async {
    try {
      final authToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/end_meeting'),
        headers: {
          'Content-Type': 'application/json',
          if (authToken != null) 'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({'room_id': roomName}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Failed to end meeting via API: $e');
      return false;
    }
  }

  static Future<Map<String, String>?> createIngress(String roomName) async {
    try {
      final authToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/create_ingress'),
        headers: {
          'Content-Type': 'application/json',
          if (authToken != null) 'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({'room_id': roomName}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'rtmp_url': data['rtmp_url'] ?? '',
          'stream_key': data['stream_key'] ?? '',
        };
      }
    } catch (e) {
      print('Failed to create ingress: $e');
    }
    return null;
  }

  // --- Subscription & Multi-Streaming ---

  static Future<Map<String, dynamic>?> getUserSubscription() async {
    try {
      final authToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/user/subscription'),
        headers: {
          if (authToken != null) 'Authorization': 'Bearer $authToken',
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['subscription'] as Map<String, dynamic>?;
      }
    } catch (e) {
      print('Failed to get subscription: $e');
    }
    return null;
  }

  static Future<bool> subscribePlan(String plan) async {
    try {
      final authToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/user/subscribe'),
        headers: {
          'Content-Type': 'application/json',
          if (authToken != null) 'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({'plan': plan}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Failed to subscribe plan: $e');
      return false;
    }
  }

  static Future<List<dynamic>> getStreamDestinations() async {
    try {
      final authToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/streaming/destinations'),
        headers: {
          if (authToken != null) 'Authorization': 'Bearer $authToken',
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['destinations'] as List<dynamic>? ?? [];
      }
    } catch (e) {
      print('Failed to fetch destinations: $e');
    }
    return [];
  }

  static Future<bool> saveStreamDestinations(List<Map<String, dynamic>> destinations) async {
    try {
      final authToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/streaming/destinations'),
        headers: {
          'Content-Type': 'application/json',
          if (authToken != null) 'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({'destinations': destinations}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Failed to save destinations: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> startMultiStream(
    String roomName,
    List<String> rtmpUrls, {
    String layout = 'speaker',
  }) async {
    try {
      final authToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/streaming/start'),
        headers: {
          'Content-Type': 'application/json',
          if (authToken != null) 'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({
          'room_id': roomName,
          'rtmp_urls': rtmpUrls,
          'layout': layout,
        }),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>?;
      }
    } catch (e) {
      print('Failed to start multi-stream: $e');
    }
    return null;
  }

  static Future<bool> stopMultiStream(String roomName, String? egressId) async {
    try {
      final authToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/streaming/stop'),
        headers: {
          'Content-Type': 'application/json',
          if (authToken != null) 'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({
          'room_id': roomName,
          'egress_id': egressId,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Failed to stop multi-stream: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> getStreamingStatus(String roomName) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/streaming/status/$roomName'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>?;
      }
    } catch (e) {
      print('Failed to get streaming status: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>> createSupportTicket({
    required String category,
    required String subject,
    required String message,
    String priority = 'normal',
  }) async {
    try {
      final authToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/support/tickets'),
        headers: {
          'Content-Type': 'application/json',
          if (authToken != null) 'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({
          'category': category,
          'subject': subject,
          'message': message,
          'priority': priority,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        final err = jsonDecode(response.body);
        throw Exception(err['detail'] ?? 'Failed to submit ticket');
      }
    } catch (e) {
      throw Exception('Support request error: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getMySupportTickets() async {
    try {
      final authToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/support/my-tickets'),
        headers: {
          if (authToken != null) 'Authorization': 'Bearer $authToken',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['tickets'] as List<dynamic>? ?? [];
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return [];
    } catch (e) {
      print('Error fetching tickets: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>> sendPasswordResetOtp(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/send-reset-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email.trim().toLowerCase()}),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        return data;
      } else {
        throw Exception(data['detail'] ?? 'Failed to send verification code');
      }
    } catch (e) {
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

  static Future<Map<String, dynamic>> verifyPasswordResetOtp({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/verify-reset-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email.trim().toLowerCase(),
          'otp': otp.trim(),
          'new_password': newPassword.trim(),
        }),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        return data;
      } else {
        throw Exception(data['detail'] ?? 'Failed to reset password');
      }
    } catch (e) {
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }
}




