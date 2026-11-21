import 'package:cloud_firestore/cloud_firestore.dart';

class StatusItem {
  final String id;
  final String uid;
  final String userName;
  final String? userAvatar;
  final String type; // 'text', 'image', 'video', 'audio'
  final String content; // text content or media URL
  final String? caption;
  final List<int> gradientColors;
  final String fontStyle;
  final DateTime createdAt;
  final DateTime expiresAt;
  final List<String> viewers;
  final Map<String, dynamic> viewerInfo; // uid -> { 'name': String, 'avatar': String, 'viewedAt': Timestamp }
  final String privacy; // 'all', 'exclude', 'include'
  final List<String> privacyUids;
  final int? duration; // Duration in seconds for audio status
  final int? durationHours; // Selected longevity (e.g. 4, 12, 24, 48 hours)

  StatusItem({
    required this.id,
    required this.uid,
    required this.userName,
    this.userAvatar,
    required this.type,
    required this.content,
    this.caption,
    this.gradientColors = const [0xFF7C3AED, 0xFF9333EA],
    this.fontStyle = 'default',
    required this.createdAt,
    required this.expiresAt,
    this.viewers = const [],
    this.viewerInfo = const {},
    this.privacy = 'all',
    this.privacyUids = const [],
    this.duration,
    this.durationHours,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  bool hasBeenViewedBy(String myUid) => viewers.contains(myUid);

  bool canBeViewedBy(String viewerUid) {
    if (uid == viewerUid) return true;
    if (privacy == 'exclude') {
      return !privacyUids.contains(viewerUid);
    } else if (privacy == 'include') {
      return privacyUids.contains(viewerUid);
    }
    return true;
  }

  factory StatusItem.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    DateTime parseTime(dynamic val, DateTime fallback) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? fallback;
      return fallback;
    }

    final created = parseTime(data['createdAt'], DateTime.now());
    final expires = parseTime(data['expiresAt'], created.add(const Duration(hours: 24)));

    List<int> colors = [0xFF7C3AED, 0xFF9333EA];
    if (data['gradientColors'] is List) {
      colors = (data['gradientColors'] as List)
          .map((c) => c is int ? c : int.tryParse(c.toString()) ?? 0xFF7C3AED)
          .toList();
    }

    return StatusItem(
      id: doc.id,
      uid: data['uid'] ?? '',
      userName: data['userName'] ?? 'Unknown User',
      userAvatar: data['userAvatar'],
      type: data['type'] ?? 'text',
      content: data['content'] ?? '',
      caption: data['caption'],
      gradientColors: colors.isNotEmpty ? colors : [0xFF7C3AED, 0xFF9333EA],
      fontStyle: data['fontStyle'] ?? 'default',
      createdAt: created,
      expiresAt: expires,
      viewers: List<String>.from(data['viewers'] ?? []),
      viewerInfo: Map<String, dynamic>.from(data['viewerInfo'] ?? {}),
      privacy: data['privacy'] as String? ?? 'all',
      privacyUids: List<String>.from(data['privacyUids'] ?? []),
      duration: data['duration'] as int?,
      durationHours: data['durationHours'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uid': uid,
      'userName': userName,
      'userAvatar': userAvatar,
      'type': type,
      'content': content,
      'caption': caption,
      'gradientColors': gradientColors,
      'fontStyle': fontStyle,
      'createdAt': Timestamp.fromDate(createdAt),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'viewers': viewers,
      'viewerInfo': viewerInfo,
      'privacy': privacy,
      'privacyUids': privacyUids,
      if (duration != null) 'duration': duration,
      if (durationHours != null) 'durationHours': durationHours,
    };
  }
}

class UserStatusGroup {
  final String uid;
  final String userName;
  final String? userAvatar;
  final List<StatusItem> items;

  UserStatusGroup({
    required this.uid,
    required this.userName,
    this.userAvatar,
    required this.items,
  });

  bool hasUnseenBy(String myUid) {
    return items.any((item) => !item.hasBeenViewedBy(myUid));
  }

  int seenCountBy(String myUid) {
    return items.where((item) => item.hasBeenViewedBy(myUid)).length;
  }

  DateTime get lastUpdated {
    if (items.isEmpty) return DateTime.now();
    return items.map((e) => e.createdAt).reduce((a, b) => a.isAfter(b) ? a : b);
  }

  StatusItem? get latestItem => items.isNotEmpty ? items.last : null;
}
