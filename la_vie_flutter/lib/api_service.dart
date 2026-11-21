import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
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

class WaitingApprovalException implements Exception {
  final String roomId;
  final String title;
  final String hostName;
  final String message;

  WaitingApprovalException({
    required this.roomId,
    required this.title,
    required this.hostName,
    required this.message,
  });

  @override
  String toString() => message;
}

class EntryDeniedException implements Exception {
  final String message;
  EntryDeniedException(this.message);

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
                if (detail['error'] == 'waiting_approval') {
                  throw WaitingApprovalException(
                    roomId: detail['room_id']?.toString() ?? roomName,
                    title: detail['title']?.toString() ?? 'Private Meeting',
                    hostName: detail['host_name']?.toString() ?? 'Host',
                    message: detail['message']?.toString() ?? 'Waiting for host approval.',
                  );
                }
                if (detail['error'] == 'entry_denied') {
                  throw EntryDeniedException(
                    detail['message']?.toString() ?? 'The host declined your request to join this meeting.',
                  );
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
              if (e is AlreadyInMeetingException || e is WaitingApprovalException || e is EntryDeniedException) rethrow;
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
        if (e is AlreadyInMeetingException || e is WaitingApprovalException || e is EntryDeniedException || e.toString().contains('locked')) {
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
    return 'wss://lavie-prod-ngzo1pm2.livekit.cloud';
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

  static Future<bool> submitMeetingFeedback({
    required String roomId,
    required int rating,
    List<String> tags = const [],
    String comment = '',
    String wouldRecommend = 'yes',
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final authToken = await user?.getIdToken();

      final response = await http.post(
        Uri.parse('$baseUrl/api/meeting/feedback'),
        headers: {
          'Content-Type': 'application/json',
          if (authToken != null) 'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({
          'room_id': roomId,
          'rating': rating,
          'tags': tags,
          'comment': comment,
          'would_recommend': wouldRecommend,
          'user_id': user?.uid ?? 'anonymous',
          'user_name': user?.displayName ?? 'User',
        }),
      ).timeout(requestTimeout);

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Fetches safe public metadata for a scheduled meeting (supports upcoming invite lobby).
  static Future<Map<String, dynamic>?> fetchPublicMeetingInfo(String roomId) async {
    try {
      final cleanId = roomId.split('#').first.trim();
      if (cleanId.isEmpty) return null;
      final user = FirebaseAuth.instance.currentUser;
      final authToken = await user?.getIdToken();

      final response = await http.get(
        Uri.parse('$baseUrl/api/meeting/${Uri.encodeComponent(cleanId)}/info'),
        headers: {
          if (authToken != null) 'Authorization': 'Bearer $authToken',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Subscribes an invitee/user to server FCM push reminders and bookmarks the meeting.
  static Future<bool> subscribeMeetingReminder(
    String roomId, {
    int reminderMinutes = 15,
    String? fcmToken,
  }) async {
    try {
      final cleanId = roomId.split('#').first.trim();
      final user = FirebaseAuth.instance.currentUser;
      final authToken = await user?.getIdToken();
      if (authToken == null) return false;

      final response = await http.post(
        Uri.parse('$baseUrl/api/meeting/${Uri.encodeComponent(cleanId)}/reminder'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({
          'reminderMinutes': reminderMinutes,
          if (fcmToken != null && fcmToken.isNotEmpty) 'fcmToken': fcmToken,
        }),
      ).timeout(requestTimeout);

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Removes a user's reminder subscription and saved meeting bookmark.
  static Future<bool> unsubscribeMeetingReminder(String roomId) async {
    try {
      final cleanId = roomId.split('#').first.trim();
      final user = FirebaseAuth.instance.currentUser;
      final authToken = await user?.getIdToken();
      if (authToken == null) return false;

      final response = await http.delete(
        Uri.parse('$baseUrl/api/meeting/${Uri.encodeComponent(cleanId)}/reminder'),
        headers: {
          'Authorization': 'Bearer $authToken',
        },
      ).timeout(requestTimeout);

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Sends a knock request to enter a private meeting's waiting room.
  static Future<String> knockRoom(String roomId) async {
    try {
      final cleanId = roomId.split('#').first.trim();
      final user = FirebaseAuth.instance.currentUser;
      final authToken = await user?.getIdToken();
      if (authToken == null) return 'pending';

      final response = await http.post(
        Uri.parse('$baseUrl/api/room/${Uri.encodeComponent(cleanId)}/knock'),
        headers: {'Authorization': 'Bearer $authToken'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['status']?.toString() ?? 'pending';
      }
      return 'pending';
    } catch (_) {
      return 'pending';
    }
  }

  /// Polls the current waiting-room status ('pending', 'admitted', 'denied', 'locked', 'open').
  static Future<String> checkKnockStatus(String roomId) async {
    try {
      final cleanId = roomId.split('#').first.trim();
      final user = FirebaseAuth.instance.currentUser;
      final authToken = await user?.getIdToken();
      if (authToken == null) return 'pending';

      final response = await http.get(
        Uri.parse('$baseUrl/api/room/${Uri.encodeComponent(cleanId)}/knock-status'),
        headers: {'Authorization': 'Bearer $authToken'},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['status']?.toString() ?? 'pending';
      }
      return 'pending';
    } catch (_) {
      return 'pending';
    }
  }

  /// Host-only: fetches pending guests waiting for admission.
  static Future<List<Map<String, dynamic>>> fetchWaitingRoomGuests(String roomId) async {
    try {
      final cleanId = roomId.split('#').first.trim();
      final user = FirebaseAuth.instance.currentUser;
      final authToken = await user?.getIdToken();
      if (authToken == null) return [];

      final response = await http.get(
        Uri.parse('$baseUrl/api/room/${Uri.encodeComponent(cleanId)}/waiting-room'),
        headers: {'Authorization': 'Bearer $authToken'},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['waiting'] as List? ?? [];
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Host-only: admit, deny, or admit_all waiting room guests.
  static Future<bool> decideWaitingGuest(String roomId, String targetUid, String action) async {
    try {
      final cleanId = roomId.split('#').first.trim();
      final user = FirebaseAuth.instance.currentUser;
      final authToken = await user?.getIdToken();
      if (authToken == null) return false;

      final response = await http.post(
        Uri.parse('$baseUrl/api/room/${Uri.encodeComponent(cleanId)}/waiting-room/decision'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({
          'target_uid': targetUid,
          'action': action,
        }),
      ).timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Host-only: toggles Private Waiting Room requirement on an active meeting.
  static Future<bool> toggleWaitingRoom(String roomId, bool enabled) async {
    try {
      final cleanId = roomId.split('#').first.trim();
      final user = FirebaseAuth.instance.currentUser;
      final authToken = await user?.getIdToken();
      if (authToken == null) return false;

      final response = await http.post(
        Uri.parse('$baseUrl/api/room/waiting-room/toggle'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({
          'room_id': cleanId,
          'enabled': enabled,
        }),
      ).timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Uploads a user's profile avatar to the backend `/api/profile/upload` endpoint
  /// with explicit image MIME headers and structured error handling.
  static Future<String> uploadProfilePhoto({
    required File file,
    required String uid,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final authToken = await user?.getIdToken();
    if (authToken == null) {
      throw Exception('Please log in again before updating your profile photo.');
    }

    final rawName = file.path.split(Platform.pathSeparator).last;
    final lowerExt = rawName.contains('.') ? rawName.split('.').last.toLowerCase() : 'jpg';
    final subtype = (lowerExt == 'jpg' || lowerExt == 'jpeg')
        ? 'jpeg'
        : (['png', 'webp', 'gif'].contains(lowerExt) ? lowerExt : 'jpeg');
    final safeName = 'avatar_$uid.$lowerExt';

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );

    final formData = FormData.fromMap({
      'uid': uid,
      'file': await MultipartFile.fromFile(
        file.path,
        filename: safeName,
        contentType: DioMediaType('image', subtype),
      ),
    });

    try {
      final response = await dio.post(
        '$baseUrl/api/profile/upload',
        data: formData,
        options: Options(
          headers: {
            'Authorization': 'Bearer $authToken',
          },
        ),
      );

      final data = response.data;
      if (data is Map && data['success'] == true && data['url'] != null) {
        final rawUrl = data['url'].toString();
        return rawUrl.startsWith('http') ? rawUrl : '$baseUrl$rawUrl';
      }
      throw Exception('Server did not return a valid image URL.');
    } on DioException catch (e) {
      final respData = e.response?.data;
      String message = 'Unable to upload profile photo. Please try again.';
      if (respData is Map && respData['detail'] != null) {
        message = respData['detail'].toString();
      } else if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        message = 'Network error while uploading photo. Check your internet connection.';
      } else if (e.message != null && e.message!.isNotEmpty) {
        message = e.message!;
      }
      throw Exception(message);
    }
  }

  /// Sends a 6-digit email verification OTP before creating a new user account.
  static Future<void> sendSignupOtp({
    required String email,
    required String displayName,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/send-signup-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email.trim(),
        'display_name': displayName.trim(),
      }),
    ).timeout(requestTimeout);

    if (response.statusCode != 200) {
      String msg = 'Failed to send verification code.';
      try {
        final data = jsonDecode(response.body);
        if (data is Map && data['detail'] != null) {
          msg = data['detail'].toString();
        }
      } catch (_) {}
      throw Exception(msg);
    }
  }

  /// Verifies the 6-digit signup OTP and creates the verified user account.
  static Future<void> verifySignupOtp({
    required String email,
    required String otp,
    required String password,
    required String displayName,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/verify-signup-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email.trim(),
        'otp': otp.trim(),
        'password': password,
        'display_name': displayName.trim(),
      }),
    ).timeout(requestTimeout);

    if (response.statusCode != 200) {
      String msg = 'Verification failed.';
      try {
        final data = jsonDecode(response.body);
        if (data is Map && data['detail'] != null) {
          msg = data['detail'].toString();
        }
      } catch (_) {}
      throw Exception(msg);
    }
  }
}




