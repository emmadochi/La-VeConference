import 'dart:convert';
import 'dart:io';
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
  static const Duration requestTimeout = Duration(seconds: 15);

  static Future<Map<String, dynamic>> getTokenDetails(String roomName, String participantName, {bool force = false}) async {
    // Generate a unique peer ID or use Firebase UID
    final user = FirebaseAuth.instance.currentUser;
    final peerId = user?.uid ?? 'peer_${DateTime.now().millisecondsSinceEpoch}';
    
    final authToken = await user?.getIdToken();
    final uri = Uri.parse('$baseUrl/token/$roomName/$peerId?name=${Uri.encodeComponent(participantName)}${force ? "&force=true" : ""}');

    int attempts = 0;
    const maxAttempts = 3;
    dynamic lastError;

    while (attempts < maxAttempts) {
      attempts++;
      try {
        final client = http.Client();
        try {
          final response = await client.get(
            uri,
            headers: {
              if (authToken != null) 'Authorization': 'Bearer $authToken',
            },
          ).timeout(requestTimeout);

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            return data;
          } else if (response.statusCode == 403 || response.statusCode == 409) {
            try {
              final data = jsonDecode(response.body);
              final detail = data['detail'];
              if (detail is Map) {
                if (detail['error'] == 'room_locked') {
                  throw Exception(detail['message']?.toString() ?? 'This meeting has been locked by the host.');
                }
                throw AlreadyInMeetingException(
                  activeRoom: detail['active_room']?.toString() ?? '',
                  targetRoom: detail['target_room']?.toString() ?? roomName,
                  message: detail['message']?.toString() ?? 'You are already in another meeting.',
                );
              } else if (detail is String) {
                if (detail.toLowerCase().contains('locked')) {
                  throw Exception(detail);
                }
                throw AlreadyInMeetingException(
                  activeRoom: '',
                  targetRoom: roomName,
                  message: detail,
                );
              }
            } catch (e) {
              if (e is AlreadyInMeetingException) rethrow;
              if (e.toString().contains('locked')) rethrow;
            }
            throw Exception('Access denied: Unable to join meeting.');
          } else if (response.statusCode >= 500) {
            throw Exception('The meeting server is temporarily unavailable. Please try again in a few moments.');
          } else if (response.statusCode == 404) {
            throw Exception('Meeting room not found. Please verify your meeting code.');
          } else {
            throw Exception('Unable to join meeting. Please check your connection and try again.');
          }
        } finally {
          client.close();
        }
      } catch (e) {
        lastError = e;
        if (e is AlreadyInMeetingException || e.toString().contains('locked')) {
          rethrow;
        }
        if (attempts < maxAttempts) {
          // Exponential backoff before retrying
          await Future.delayed(Duration(milliseconds: 600 * attempts));
        }
      }
    }

    // If all attempts failed
    final errStr = lastError?.toString() ?? 'Unknown error';
    if (errStr.contains('Connection closed') || errStr.contains('SocketException') || errStr.contains('TimeoutException') || errStr.contains('Failed host lookup')) {
      throw Exception('Unable to reach the conference server. Please check your internet connection and try again.');
    }
    throw Exception(errStr.replaceFirst('Exception: ', ''));
  }

  static Future<String> getToken(String roomName, String participantName, {bool force = false}) async {
    final data = await getTokenDetails(roomName, participantName, force: force);
    return data['token'] as String;
  }

  static Future<String> getLiveKitUrl() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/tunnel-config')).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['livekit_url'] as String;
      }
    } catch (e) {
      // ignore
    }
    return 'wss://lavie-live-bmlbvgd2.livekit.cloud';
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
      ).timeout(requestTimeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['egress_id'] as String?;
      } else {
        throw Exception('${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      // Return null or throw for client recording fallback
      return null;
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
      ).timeout(requestTimeout);
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

  static Future<bool> toggleRoomLock(String roomName, bool isLocked) async {
    try {
      final authToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/room/lock'),
        headers: {
          'Content-Type': 'application/json',
          if (authToken != null) 'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({'room_id': roomName, 'is_locked': isLocked}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Failed to toggle room lock via API: $e');
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

  static Future<Map<String, dynamic>> generateMeetingSummary({
    required String roomId,
    String title = '',
    String? transcriptText,
    String? audioPath,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final authToken = await user?.getIdToken();

      final uri = Uri.parse('$baseUrl/api/meeting/summarize');
      final request = http.MultipartRequest('POST', uri);

      if (authToken != null) {
        request.headers['Authorization'] = 'Bearer $authToken';
      }

      request.fields['room_id'] = roomId;
      if (title.isNotEmpty) {
        request.fields['title'] = title;
      }
      if (transcriptText != null && transcriptText.isNotEmpty) {
        request.fields['transcript_text'] = transcriptText;
      }

      if (audioPath != null && audioPath.isNotEmpty) {
        final audioFile = File(audioPath);
        if (await audioFile.exists()) {
          request.files.add(await http.MultipartFile.fromPath('audio_file', audioPath));
        }
      }

      final streamedResponse = await request.send().timeout(const Duration(seconds: 90));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data;
      } else {
        final err = jsonDecode(response.body);
        throw Exception(err['detail'] ?? 'Failed to generate AI summary');
      }
    } catch (e) {
      throw Exception('AI Summary Error: $e');
    }
  }
}




