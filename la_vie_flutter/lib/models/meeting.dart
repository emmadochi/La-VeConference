import 'package:cloud_firestore/cloud_firestore.dart';

class Meeting {
  final String id;
  final String title;
  final String roomId;
  final String hostId;
  final DateTime scheduledTime;

  Meeting({
    required this.id,
    required this.title,
    required this.roomId,
    required this.hostId,
    required this.scheduledTime,
  });

  factory Meeting.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    // Web app saves time as ISO8601 string (e.g. "2026-07-19T09:00")
    DateTime parsedTime;
    try {
      if (data['scheduledTime'] is Timestamp) {
        parsedTime = (data['scheduledTime'] as Timestamp).toDate();
      } else {
        parsedTime = DateTime.parse(data['scheduledTime'].toString());
      }
    } catch (e) {
      parsedTime = DateTime.now();
    }

    return Meeting(
      id: doc.id,
      title: data['title'] ?? 'Untitled Meeting',
      roomId: data['roomId'] ?? '',
      hostId: data['hostId'] ?? '',
      scheduledTime: parsedTime,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'roomId': roomId,
      'hostId': hostId,
      'scheduledTime': scheduledTime.toIso8601String(),
    };
  }
}
