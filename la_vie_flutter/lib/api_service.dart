import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

class ApiService {
  static const String baseUrl = 'https://la-vie.lifechangerstouch.org';

  static Future<String> getToken(String roomName, String participantName) async {
    // Generate a unique peer ID or use Firebase UID
    final user = FirebaseAuth.instance.currentUser;
    final peerId = user?.uid ?? 'peer_${DateTime.now().millisecondsSinceEpoch}';
    
    final authToken = await user?.getIdToken();
    
    final response = await http.get(
      Uri.parse('$baseUrl/token/$roomName/$peerId?name=$participantName'),
      headers: {
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['token'] as String;
    } else if (response.statusCode == 403) {
      final data = jsonDecode(response.body);
      throw Exception(data['detail'] ?? 'You are already in another meeting.');
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
}

