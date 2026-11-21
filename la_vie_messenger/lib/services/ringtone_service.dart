import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class RingtoneService {
  static final RingtoneService instance = RingtoneService._internal();
  factory RingtoneService() => instance;
  RingtoneService._internal();

  static const MethodChannel _overlayChannel =
      MethodChannel('org.lifechangerstouch.lavie.messenger/call_overlay');

  AudioPlayer? _player;
  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  AudioPlayer _getOrCreatePlayer() {
    if (_player == null) {
      _player = AudioPlayer();
      _player!.setPlayerMode(PlayerMode.lowLatency);
    }
    return _player!;
  }

  /// Sets up audio context to request transient audio focus that allows ducking,
  /// preventing audio focus lockouts on Android communication channels.
  Future<void> _applyRingtoneAudioContext() async {
    try {
      await _player?.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: false,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.notificationRingtone,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playAndRecord,
            options: const {AVAudioSessionOptions.duckOthers},
          ),
        ),
      );
    } catch (e) {
      debugPrint('RingtoneService: audio context setup warning: $e');
    }
  }

  /// Plays the rhythmic chime ringtone on loop and starts synchronized vibration
  Future<void> startIncomingRing() async {
    try {
      await stop();
      _isPlaying = true;

      // Start native rhythmic call vibration
      try {
        await _overlayChannel.invokeMethod('startCallVibration');
      } catch (vibErr) {
        debugPrint('RingtoneService native vibration error: $vibErr');
      }

      final player = _getOrCreatePlayer();
      await _applyRingtoneAudioContext();
      await player.setReleaseMode(ReleaseMode.loop);
      await player.play(AssetSource('sounds/incoming_ring.wav'));
      debugPrint('Incoming call ringtone & vibration started');
    } catch (e) {
      debugPrint('Error starting incoming ringtone: $e');
      _isPlaying = false;
    }
  }

  /// Plays the periodic cadence tone for outgoing calls (dial tone)
  Future<void> startOutgoingRing() async {
    try {
      await stop();
      _isPlaying = true;

      // Subtle haptic cue when call connection initiates
      try {
        HapticFeedback.lightImpact();
      } catch (_) {}

      final player = _getOrCreatePlayer();
      await _applyRingtoneAudioContext();
      await player.setReleaseMode(ReleaseMode.loop);
      await player.play(AssetSource('sounds/outgoing_ring.wav'));
      debugPrint('Outgoing call ring tone started');
    } catch (e) {
      debugPrint('Error starting outgoing ring: $e');
      _isPlaying = false;
    }
  }

  /// Triggers a brief tactile confirmation pulse (e.g., when call is answered, connected, or ended)
  Future<void> triggerHapticPulse({int durationMs = 45}) async {
    try {
      await _overlayChannel.invokeMethod('vibrateFeedback', {'duration': durationMs});
    } catch (_) {
      try {
        HapticFeedback.mediumImpact();
      } catch (_) {}
    }
  }

  /// Stops any currently playing ringtone and cancels vibration immediately
  /// and disposes the player to release Android AudioFocus and AudioTrack.
  Future<void> stop() async {
    _isPlaying = false;

    // Immediately stop native call vibration
    try {
      await _overlayChannel.invokeMethod('stopCallVibration');
    } catch (_) {}

    final p = _player;
    _player = null;
    if (p != null) {
      try {
        await p.stop();
        await p.release();
        await p.dispose();
        debugPrint('Ringtone stopped and disposed');
      } catch (e) {
        debugPrint('Error stopping ringtone: $e');
      }
    }
  }

  /// Cleans up player resources entirely (call on app dispose)
  void dispose() {
    stop();
  }
}
