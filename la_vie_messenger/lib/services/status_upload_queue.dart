import 'dart:io';
import 'package:flutter/foundation.dart';
import 'status_service.dart';

enum StatusUploadState { uploading, completed, failed }

class StatusUploadTask {
  final String id;
  final String uid;
  final String userName;
  final String? userAvatar;
  final String type; // 'image', 'video', 'audio'
  final File? file;
  final String? caption;
  final String privacy;
  final List<String> privacyUids;
  final int? durationSeconds;
  final List<int>? gradientColors;
  final int durationHours;

  double progress; // 0.0 to 1.0
  StatusUploadState state;
  String? error;
  DateTime timestamp;

  StatusUploadTask({
    required this.id,
    required this.uid,
    required this.userName,
    this.userAvatar,
    required this.type,
    this.file,
    this.caption,
    this.privacy = 'all',
    this.privacyUids = const [],
    this.durationSeconds,
    this.gradientColors,
    this.durationHours = 24,
    this.progress = 0.0,
    this.state = StatusUploadState.uploading,
    this.error,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class StatusUploadQueue extends ChangeNotifier {
  static final StatusUploadQueue instance = StatusUploadQueue._();
  StatusUploadQueue._();

  final List<StatusUploadTask> _tasks = [];
  bool _isProcessing = false;

  List<StatusUploadTask> get tasks => List.unmodifiable(_tasks);

  StatusUploadTask? get currentTask {
    for (final t in _tasks) {
      if (t.state == StatusUploadState.uploading) return t;
    }
    for (final t in _tasks) {
      if (t.state == StatusUploadState.failed) return t;
    }
    return _tasks.isNotEmpty ? _tasks.last : null;
  }

  bool get isUploading => _tasks.any((t) => t.state == StatusUploadState.uploading);
  bool get hasFailed => _tasks.any((t) => t.state == StatusUploadState.failed);

  void enqueueMediaStatus({
    required String uid,
    required String userName,
    String? userAvatar,
    required File file,
    required String type, // 'image' or 'video'
    String? caption,
    String privacy = 'all',
    List<String> privacyUids = const [],
    int durationHours = 24,
  }) {
    final task = StatusUploadTask(
      id: '${DateTime.now().millisecondsSinceEpoch}_${file.hashCode}',
      uid: uid,
      userName: userName,
      userAvatar: userAvatar,
      type: type,
      file: file,
      caption: caption,
      privacy: privacy,
      privacyUids: privacyUids,
      durationHours: durationHours,
      state: StatusUploadState.uploading,
      progress: 0.0,
    );
    _tasks.add(task);
    notifyListeners();
    _processQueue();
  }

  void enqueueAudioStatus({
    required String uid,
    required String userName,
    String? userAvatar,
    required File audioFile,
    required int durationSeconds,
    required List<int> gradientColors,
    String? caption,
    String privacy = 'all',
    List<String> privacyUids = const [],
    int durationHours = 24,
  }) {
    final task = StatusUploadTask(
      id: '${DateTime.now().millisecondsSinceEpoch}_${audioFile.hashCode}',
      uid: uid,
      userName: userName,
      userAvatar: userAvatar,
      type: 'audio',
      file: audioFile,
      durationSeconds: durationSeconds,
      gradientColors: gradientColors,
      caption: caption,
      privacy: privacy,
      privacyUids: privacyUids,
      durationHours: durationHours,
      state: StatusUploadState.uploading,
      progress: 0.0,
    );
    _tasks.add(task);
    notifyListeners();
    _processQueue();
  }

  void retry(String taskId) {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx != -1) {
      _tasks[idx].state = StatusUploadState.uploading;
      _tasks[idx].error = null;
      _tasks[idx].progress = 0.0;
      notifyListeners();
      _processQueue();
    }
  }

  void dismiss(String taskId) {
    _tasks.removeWhere((t) => t.id == taskId);
    notifyListeners();
  }

  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      while (true) {
        final pending = _tasks.where((t) => t.state == StatusUploadState.uploading).toList();
        if (pending.isEmpty) break;

        final current = pending.first;
        try {
          if (current.type == 'audio' && current.file != null) {
            await StatusService.postAudioStatus(
              uid: current.uid,
              userName: current.userName,
              userAvatar: current.userAvatar,
              audioFile: current.file!,
              durationSeconds: current.durationSeconds ?? 30,
              gradientColors: current.gradientColors ?? [0xFF7C3AED, 0xFF9333EA],
              caption: current.caption,
              privacy: current.privacy,
              privacyUids: current.privacyUids,
              durationHours: current.durationHours,
            );
          } else if (current.file != null) {
            await StatusService.postMediaStatus(
              uid: current.uid,
              userName: current.userName,
              userAvatar: current.userAvatar,
              mediaFile: current.file!,
              type: current.type,
              caption: current.caption,
              privacy: current.privacy,
              privacyUids: current.privacyUids,
              durationHours: current.durationHours,
              onProgress: (sent, total) {
                if (total > 0) {
                  current.progress = (sent / total).clamp(0.0, 1.0);
                  notifyListeners();
                }
              },
            );
          }
          current.state = StatusUploadState.completed;
          current.progress = 1.0;
          notifyListeners();

          // Retain briefly so UI shows completion before clearing
          Future.delayed(const Duration(seconds: 3), () {
            _tasks.removeWhere((t) => t.id == current.id && t.state == StatusUploadState.completed);
            notifyListeners();
          });
        } catch (e) {
          debugPrint("Status upload failed for task ${current.id}: $e");
          current.state = StatusUploadState.failed;
          current.error = e.toString();
          notifyListeners();
        }
      }
    } finally {
      _isProcessing = false;
    }
  }
}
