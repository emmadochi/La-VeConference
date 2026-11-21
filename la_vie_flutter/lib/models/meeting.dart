import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

class Meeting {
  final String id;
  final String title;
  final String roomId;
  final String hostId;
  final String hostName;
  final DateTime scheduledTime;
  final String status;
  final String meetingType;
  final bool notified;
  final int hostReminderMinutes;
  final String role; // 'host' or 'invitee'
  final bool requireApproval;
  final bool isPermanent;

  Meeting({
    required this.id,
    required this.title,
    required this.roomId,
    required this.hostId,
    this.hostName = '',
    required this.scheduledTime,
    this.status = 'scheduled',
    this.meetingType = 'scheduled',
    this.notified = false,
    this.hostReminderMinutes = 15,
    this.role = 'host',
    this.requireApproval = false,
    this.isPermanent = false,
  });

  factory Meeting.fromFirestore(DocumentSnapshot doc, {String defaultRole = 'host'}) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};

    DateTime parsedTime;
    try {
      if (data['scheduledTime'] is Timestamp) {
        parsedTime = (data['scheduledTime'] as Timestamp).toDate().toLocal();
      } else {
        parsedTime = DateTime.parse(data['scheduledTime'].toString()).toLocal();
      }
    } catch (e) {
      parsedTime = DateTime.now();
    }

    int remMins = 15;
    final rawRem = data['hostReminderMinutes'] ?? data['reminderMinutes'];
    if (rawRem is int) {
      remMins = rawRem;
    } else if (rawRem != null) {
      remMins = int.tryParse(rawRem.toString()) ?? 15;
    }

    return Meeting(
      id: doc.id,
      title: data['title'] ?? 'Untitled Meeting',
      roomId: data['roomId'] ?? doc.id,
      hostId: data['hostId'] ?? '',
      hostName: data['hostName'] ?? '',
      scheduledTime: parsedTime,
      status: data['status'] ?? 'scheduled',
      meetingType: data['meetingType'] ?? 'scheduled',
      notified: data['notified'] == true,
      hostReminderMinutes: remMins,
      role: data['role'] ?? defaultRole,
      requireApproval: data['requireApproval'] == true,
      isPermanent: data['isPermanent'] == true || data['meetingType'] == 'permanent',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'roomId': roomId,
      'hostId': hostId,
      if (hostName.isNotEmpty) 'hostName': hostName,
      'scheduledTime': scheduledTime.toUtc().toIso8601String(),
      'status': status,
      'meetingType': isPermanent ? 'permanent' : meetingType,
      'notified': notified,
      'hostReminderMinutes': hostReminderMinutes,
      'requireApproval': requireApproval,
      'isPermanent': isPermanent,
    };
  }

  /// Streams both hosted meetings and invitee saved meetings chronologically (no composite index needed).
  static Stream<List<Meeting>> streamUserMeetings(String? uid) {
    if (uid == null || uid.isEmpty) {
      return Stream.value([]);
    }

    late StreamController<List<Meeting>> controller;
    StreamSubscription<QuerySnapshot>? hostedSub;
    StreamSubscription<QuerySnapshot>? savedSub;

    List<Meeting> hosted = [];
    List<Meeting> saved = [];
    bool hasHosted = false;

    void emit() {
      if (controller.isClosed || !hasHosted) return;
      final Map<String, Meeting> merged = {};
      for (final m in saved) {
        final key = m.roomId.isNotEmpty ? m.roomId : m.id;
        merged[key] = m;
      }
      for (final m in hosted) {
        final key = m.roomId.isNotEmpty ? m.roomId : m.id;
        merged[key] = m;
      }
      final list = merged.values.toList()
        ..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
      controller.add(list);
    }

    controller = StreamController<List<Meeting>>(
      onListen: () {
        hostedSub = FirebaseFirestore.instance
            .collection('meetings')
            .where('hostId', isEqualTo: uid)
            .snapshots()
            .listen(
          (snap) {
            hosted = snap.docs.map((d) => Meeting.fromFirestore(d, defaultRole: 'host')).toList();
            hasHosted = true;
            emit();
          },
          onError: (e) {
            if (!controller.isClosed) controller.addError(e);
          },
        );

        savedSub = FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('saved_meetings')
            .snapshots()
            .listen(
          (snap) {
            saved = snap.docs.map((d) => Meeting.fromFirestore(d, defaultRole: 'invitee')).toList();
            emit();
          },
          onError: (_) {
            // Silently ignore if subcollection doesn't exist yet
          },
        );
      },
      onCancel: () async {
        await hostedSub?.cancel();
        await savedSub?.cancel();
      },
    );

    return controller.stream;
  }
}
