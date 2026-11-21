import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Persona settings controlling the AI Twin's behaviour
class TwinSettings {
  final bool isEnabled;
  final bool autonomousMode;

  /// When false (default), the 🤖 badge is hidden.
  /// Recipient must explicitly request to know if it was AI.
  final bool showAiBadge;

  /// Chat IDs excluded from twin auto-reply / suggestions
  final Set<String> excludedChatIds;

  /// Autonomous timer end time (null = no timed session)
  final DateTime? autonomousUntil;

  const TwinSettings({
    this.isEnabled = false,
    this.autonomousMode = false,
    this.showAiBadge = false, // Off by default — show only on request
    this.excludedChatIds = const {},
    this.autonomousUntil,
  });

  bool get isAutonomousActive {
    if (!autonomousMode) return false;
    if (autonomousUntil == null) return true; // permanent until toggled off
    return DateTime.now().isBefore(autonomousUntil!);
  }

  Map<String, dynamic> toMap() => {
    'isEnabled': isEnabled,
    'autonomousMode': autonomousMode,
    'showAiBadge': showAiBadge,
    'excludedChatIds': excludedChatIds.toList(),
    'autonomousUntil': autonomousUntil?.toIso8601String(),
  };

  factory TwinSettings.fromMap(Map<String, dynamic> m) => TwinSettings(
    isEnabled: m['isEnabled'] == true,
    autonomousMode: m['autonomousMode'] == true,
    showAiBadge: m['showAiBadge'] == true,
    excludedChatIds: Set<String>.from(m['excludedChatIds'] ?? []),
    autonomousUntil: m['autonomousUntil'] != null
        ? DateTime.tryParse(m['autonomousUntil'] as String)
        : null,
  );

  TwinSettings copyWith({
    bool? isEnabled,
    bool? autonomousMode,
    bool? showAiBadge,
    Set<String>? excludedChatIds,
    DateTime? autonomousUntil,
    bool clearTimer = false,
  }) =>
      TwinSettings(
        isEnabled: isEnabled ?? this.isEnabled,
        autonomousMode: autonomousMode ?? this.autonomousMode,
        showAiBadge: showAiBadge ?? this.showAiBadge,
        excludedChatIds: excludedChatIds ?? this.excludedChatIds,
        autonomousUntil: clearTimer ? null : (autonomousUntil ?? this.autonomousUntil),
      );
}

/// Distilled persona profile from the AI training pass
class TwinPersona {
  final List<String> toneSignature;
  final String typicalGreeting;
  final String typicalSignOff;
  final String vocabularyLevel;
  final int avgResponseLengthWords;
  final bool usesEmojis;
  final String emojiFrequency;
  final String punctuationStyle;
  final double humorIndex;
  final double empathyIndex;
  final String decisionStyle;
  final List<String> samplePhrases;
  final int trainedOnCount;
  final DateTime? lastTrained;

  const TwinPersona({
    this.toneSignature = const [],
    this.typicalGreeting = 'Hey!',
    this.typicalSignOff = '',
    this.vocabularyLevel = 'moderate',
    this.avgResponseLengthWords = 10,
    this.usesEmojis = true,
    this.emojiFrequency = 'moderate',
    this.punctuationStyle = 'casual',
    this.humorIndex = 0.3,
    this.empathyIndex = 0.5,
    this.decisionStyle = 'direct',
    this.samplePhrases = const [],
    this.trainedOnCount = 0,
    this.lastTrained,
  });

  factory TwinPersona.fromMap(Map<String, dynamic> m) => TwinPersona(
    toneSignature: List<String>.from(m['tone_signature'] ?? []),
    typicalGreeting: m['typical_greeting'] as String? ?? 'Hey!',
    typicalSignOff: m['typical_sign_off'] as String? ?? '',
    vocabularyLevel: m['vocabulary_level'] as String? ?? 'moderate',
    avgResponseLengthWords: (m['avg_response_length_words'] as num?)?.toInt() ?? 10,
    usesEmojis: m['uses_emojis'] == true,
    emojiFrequency: m['emoji_frequency'] as String? ?? 'moderate',
    punctuationStyle: m['punctuation_style'] as String? ?? 'casual',
    humorIndex: (m['humor_index'] as num?)?.toDouble() ?? 0.3,
    empathyIndex: (m['empathy_index'] as num?)?.toDouble() ?? 0.5,
    decisionStyle: m['decision_style'] as String? ?? 'direct',
    samplePhrases: List<String>.from(m['sample_phrases'] ?? []),
    trainedOnCount: (m['trained_on_count'] as num?)?.toInt() ?? 0,
    lastTrained: m['last_trained'] != null
        ? (m['last_trained'] is Timestamp
            ? (m['last_trained'] as Timestamp).toDate()
            : DateTime.tryParse(m['last_trained'].toString()))
        : null,
  );

  bool get isSufficientlyTrained => trainedOnCount >= 20;

  String get toneLabel {
    if (toneSignature.isEmpty) return 'Analyzing…';
    return toneSignature.take(3).join(' · ');
  }

  String get emojiLabel {
    switch (emojiFrequency) {
      case 'heavy': return 'Heavy emoji user 😄🔥👍';
      case 'moderate': return 'Moderate emoji use 👍';
      case 'rare': return 'Occasional emojis';
      case 'never': return 'No emojis';
      default: return 'Moderate emoji use';
    }
  }
}

/// Central service for the LiChat AI Digital Twin feature
class TwinService {
  static const String _backendUrl = 'https://la-vie.lifechangerstouch.org';

  // Batched training buffer (flushes every _batchSize messages)
  static final List<String> _trainingBuffer = [];
  static const int _batchSize = 10;

  // ─── PERSONA TRAINING ────────────────────────────────────────────────────────

  /// Call this after every outgoing message the user sends.
  /// Accumulates in a buffer and flushes to the backend in silent batches.
  static Future<void> learnFromMessage(String messageText) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || messageText.trim().length < 3) return;

    _trainingBuffer.add(messageText.trim());

    if (_trainingBuffer.length >= _batchSize) {
      await _flushTrainingBatch(uid);
    }
  }

  /// Manually trigger a training flush (e.g. when app is backgrounded)
  static Future<void> flushTraining() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _flushTrainingBatch(uid);
  }

  static Future<void> _flushTrainingBatch(String uid) async {
    if (_trainingBuffer.isEmpty) return;
    final batch = List<String>.from(_trainingBuffer);
    _trainingBuffer.clear();
    try {
      await http.post(
        Uri.parse('$_backendUrl/api/twin/train'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'uid': uid, 'messages': batch}),
      ).timeout(const Duration(seconds: 20));
      debugPrint('TwinService: Trained on ${batch.length} messages');
    } catch (e) {
      // Re-queue failed batch (best-effort)
      _trainingBuffer.insertAll(0, batch);
      debugPrint('TwinService: Training batch failed — will retry: $e');
    }
  }

  // ─── REPLY GENERATION ────────────────────────────────────────────────────────

  /// Generates 1–3 reply candidates in the user's authentic voice.
  /// Returns empty list on failure (graceful degradation).
  static Future<List<String>> generateReplies({
    required String incomingMessage,
    required List<Map<String, dynamic>> context,
    required String senderName,
    required String chatTitle,
    required bool isGroup,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || incomingMessage.trim().isEmpty) return [];

    try {
      final res = await http.post(
        Uri.parse('$_backendUrl/api/twin/reply'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid': uid,
          'incoming_message': incomingMessage,
          'conversation_context': context
              .where((m) => (m['text'] as String? ?? '').isNotEmpty)
              .take(10)
              .toList(),
          'sender_name': senderName,
          'chat_title': chatTitle,
          'is_group': isGroup,
        }),
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final replies = List<String>.from(data['replies'] ?? []);
        return replies.where((r) => r.trim().isNotEmpty).take(3).toList();
      }
    } catch (e) {
      debugPrint('TwinService: Reply generation failed: $e');
    }
    return [];
  }

  // ─── SETTINGS ────────────────────────────────────────────────────────────────

  /// Stream current settings from Firestore (real-time, nil-safe)
  static Stream<TwinSettings> streamSettings() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(const TwinSettings());
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('twin')
        .doc('settings')
        .snapshots()
        .map((snap) => snap.exists
            ? TwinSettings.fromMap(snap.data()!)
            : const TwinSettings());
  }

  /// Persist settings to Firestore
  static Future<void> saveSettings(TwinSettings settings) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('twin')
        .doc('settings')
        .set(settings.toMap(), SetOptions(merge: true));
  }

  // ─── PROFILE ─────────────────────────────────────────────────────────────────

  /// Fetch current persona profile; returns null if not yet trained
  static Future<TwinPersona?> fetchPersona() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    try {
      final res = await http.get(
        Uri.parse('$_backendUrl/api/twin/profile/$uid'),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['trained'] == true && data['profile'] != null) {
          return TwinPersona.fromMap(data['profile'] as Map<String, dynamic>);
        }
      }
    } catch (e) {
      debugPrint('TwinService: Fetch persona failed: $e');
    }
    return null;
  }

  /// Stream persona from Firestore directly (real-time updates as training runs)
  static Stream<TwinPersona?> streamPersona() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(null);
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('twin')
        .doc('profile')
        .snapshots()
        .map((snap) => snap.exists ? TwinPersona.fromMap(snap.data()!) : null);
  }
}
