import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Singleton service for playing app interaction sounds in a WhatsApp-like style.
/// Uses a pool of low-latency AudioPlayer instances to avoid playback queue delays.
class SoundService {
  static final SoundService instance = SoundService._internal();
  factory SoundService() => instance;
  SoundService._internal();

  // Preference key for user toggle
  static const String _prefKeyEnabled = 'sound_effects_enabled';

  bool _enabled = true;
  bool get isEnabled => _enabled;

  // Pool of players for short sounds (prevents queueing)
  static const int _poolSize = 4;
  final List<AudioPlayer> _pool = [];
  int _poolIndex = 0;

  bool _initialised = false;

  // Cooldown tracker to prevent duplicate overlapping sounds (e.g., FCM + Firestore at same instant)
  final Map<String, int> _lastPlayTimes = {};

  /// Call once during app startup (e.g. in main or MainShell.initState)
  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;

    // Load user preference
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_prefKeyEnabled) ?? true;
    } catch (_) {}

    // Warm up the player pool
    for (int i = 0; i < _poolSize; i++) {
      try {
        final player = AudioPlayer();
        await player.setPlayerMode(PlayerMode.lowLatency);
        await player.setAudioContext(
          AudioContext(
            android: const AudioContextAndroid(
              isSpeakerphoneOn: false,
              stayAwake: false,
              contentType: AndroidContentType.sonification,
              usageType: AndroidUsageType.assistanceSonification,
              audioFocus: AndroidAudioFocus.gainTransientMayDuck,
            ),
            iOS: AudioContextIOS(
              category: AVAudioSessionCategory.ambient,
              options: const {AVAudioSessionOptions.mixWithOthers},
            ),
          ),
        );
        _pool.add(player);
      } catch (e) {
        debugPrint('SoundService pool init warning: $e');
      }
    }

    debugPrint('SoundService: initialized (enabled=$_enabled, pool=${_pool.length})');
  }

  /// Toggle sound effects on/off and persist the preference.
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKeyEnabled, value);
    } catch (_) {}
  }

  // -- Individual sound triggers --

  /// Short ascending double-chime -- played when the user taps Send.
  Future<void> playMessageSent() => _play('sounds/message_sent.wav', debounceMs: 150);

  /// Warm descending double-pop -- played when a chat message arrives in foreground.
  Future<void> playMessageReceived() => _play('sounds/message_received.wav', debounceMs: 400);

  /// Bright ascending arp -- played when a call is established.
  Future<void> playCallConnected() => _play('sounds/call_connected.wav', debounceMs: 1000);

  /// Sad descending two-tone -- played when a call ends.
  Future<void> playCallEnded() => _play('sounds/call_ended.wav', debounceMs: 1000);

  /// Single bell tone -- played for generic/system notifications.
  Future<void> playNotification() => _play('sounds/notification.wav', debounceMs: 400);

  /// Two subtle soft ticks -- played when a message is delivered (double-tick).
  Future<void> playMessageDelivered() => _play('sounds/message_delivered.wav', debounceMs: 200);

  /// Soft single click -- played when voice recording starts.
  Future<void> playRecordStart() => _play('sounds/record_start.wav', debounceMs: 200);

  /// Soft double-click -- played when voice recording stops.
  Future<void> playRecordStop() => _play('sounds/record_stop.wav', debounceMs: 200);

  // -- Private helpers --

  Future<void> _play(String assetPath, {int debounceMs = 0}) async {
    if (!_enabled) return;
    if (!_initialised) await init();
    if (_pool.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (debounceMs > 0) {
      final last = _lastPlayTimes[assetPath] ?? 0;
      if (now - last < debounceMs) return;
      _lastPlayTimes[assetPath] = now;
    }

    try {
      final player = _pool[_poolIndex % _pool.length];
      _poolIndex++;
      // Stop any previous sound on this slot and play the new one
      await player.stop();
      await player.play(AssetSource(assetPath), volume: 0.85);
    } catch (e) {
      debugPrint('SoundService: playback error for $assetPath -- $e');
    }
  }

  /// Release all player resources. Call on app termination.
  Future<void> dispose() async {
    for (final player in _pool) {
      try {
        await player.dispose();
      } catch (_) {}
    }
    _pool.clear();
    _initialised = false;
  }
}
