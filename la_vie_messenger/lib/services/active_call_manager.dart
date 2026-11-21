import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show Helper;
import 'package:livekit_client/livekit_client.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'call_signaling_service.dart';
import 'ringtone_service.dart';
import 'sound_service.dart';
import '../screens/call_screens.dart';

enum AudioOutputDevice {
  earpiece,
  speaker,
  bluetooth,
}

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

class ActiveCallManager extends ChangeNotifier {
  static final ActiveCallManager instance = ActiveCallManager._internal();
  // NOTE: Do NOT register a setMethodCallHandler here.
  // MainShell exclusively owns the _overlayChannel handler and delegates
  // onEndCallAction / onReturnToCall to the methods below.
  ActiveCallManager._internal();

  static const MethodChannel _overlayChannel =
      MethodChannel('org.lifechangerstouch.lavie.messenger/call_overlay');

  Room? _room;
  EventsListener<RoomEvent>? _listener;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _callStatusSub;
  Timer? _durationTimer;

  String? _callId;
  String? _roomName;
  String? _peerName;
  bool _isVideo = false;
  bool _isMinimized = false;
  bool _isConnecting = false;
  int _durationSeconds = 0;
  DateTime? _callConnectedAt;
  bool _isMuted = false;
  bool _isVideoOff = false;
  bool _isFrontCamera = true;
  bool _isSpeakerOn = true;
  AudioOutputDevice _currentAudioOutput = AudioOutputDevice.speaker;
  String? _errorMessage;

  // Recording State (LiveKit Egress Ephemeral Relay)
  bool _isRecording = false;
  bool _isRecordingStarting = false;
  String? _recordingEgressId;
  String? _recordingFileName;
  String? _recordingUrl;
  bool _recordingReady = false;

  bool _isScreenSharing = false;
  bool _isDataSaver = false;

  // Getters
  bool get hasActiveCall => _callId != null && (_room != null || _isConnecting);
  bool get isMinimized => _isMinimized;
  bool get isConnecting => _isConnecting;
  bool get isVideo => _isVideo;
  String? get callId => _callId;
  String? get roomName => _roomName;
  String get peerName => _peerName ?? 'User';
  int get durationSeconds => _durationSeconds;
  bool get isMuted => _isMuted;
  bool get isVideoOff => _isVideoOff;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get isScreenSharing => _isScreenSharing;
  bool get isDataSaver => _isDataSaver;
  AudioOutputDevice get currentAudioOutput => _currentAudioOutput;
  bool get isFrontCamera => _isFrontCamera;
  String? get errorMessage => _errorMessage;
  Room? get room => _room;
  bool get isRecording => _isRecording;
  bool get isRecordingStarting => _isRecordingStarting;
  String? get recordingUrl => _recordingUrl;
  String? get recordingFileName => _recordingFileName;
  bool get recordingReady => _recordingReady;

  List<Map<String, dynamic>> _availableAudioDevices = [];
  List<Map<String, dynamic>> get availableAudioDevices => _availableAudioDevices;

  ConnectionQuality get localConnectionQuality =>
      _room?.localParticipant?.connectionQuality ?? ConnectionQuality.excellent;
  ConnectionState get roomConnectionState =>
      _room?.connectionState ?? ConnectionState.disconnected;
  bool get isReconnecting => _room?.connectionState == ConnectionState.reconnecting;

  String get formattedDuration {
    final m = (_durationSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_durationSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Initialize and connect to LiveKit Call
  Future<void> connect({
    required String callId,
    required String roomName,
    required bool isVideo,
    required String peerName,
  }) async {
    if (_callId == callId && (_room != null || _isConnecting)) {
      // Already running or actively establishing this exact call
      _isMinimized = false;
      notifyListeners();
      return;
    }

    // Quietly cancel prior state without notifying listeners
    _durationTimer?.cancel();
    _durationTimer = null;
    _callStatusSub?.cancel();
    _callStatusSub = null;
    _listener?.dispose();
    _listener = null;
    try {
      await _room?.disconnect();
    } catch (_) {}
    _room = null;

    _callId = callId;
    _roomName = roomName;
    _isVideo = isVideo;
    _peerName = peerName;
    _isVideoOff = !isVideo;
    // Default to loudspeaker for group and 1-on-1 calls so audio is immediately loud and clear.
    // Users can toggle to private earpiece anytime using the audio output button.
    _isMuted = false;
    _isFrontCamera = true;
    _currentAudioOutput = AudioOutputDevice.speaker;
    _isSpeakerOn = true;
    _isConnecting = true;
    _durationSeconds = 0;
    _isMinimized = false;
    _errorMessage = null;
    _callConnectedAt = null;

    notifyListeners();

    // Ensure any playing ringtones or dial tones are stopped and disposed immediately
    await RingtoneService.instance.stop();
    // Mandatory hardware settle window: give Android audio HAL 200ms to fully release ringtone AudioTrack
    await Future.delayed(const Duration(milliseconds: 200));

    // Request exclusive VoIP audio focus and prepare native communication mode
    try {
      await _overlayChannel.invokeMethod('prepareVoipAudio');
    } catch (_) {}

    // Check runtime microphone permission to prevent silent audio failure
    try {
      final micStatus = await Permission.microphone.status;
      if (!micStatus.isGranted) {
        final req = await Permission.microphone.request();
        if (!req.isGranted) {
          debugPrint("Microphone permission was not granted by user!");
        }
      }
      if (await Permission.bluetoothConnect.status.isDenied) {
        await Permission.bluetoothConnect.request();
      }
    } catch (permErr) {
      debugPrint("Permission check error: $permErr");
    }

    // Listen to Firestore call status for remote hang-up.
    _callStatusSub = CallSignalingService.streamCall(callId).listen((snap) {
      if (!snap.exists) return;
      // Guard: if _callId is null we already cleaned up from our side (endCall).
      if (_callId == null) return;
      final data = snap.data();
      if (data != null) {
        // Track recording updates from either side
        final recActive = data['isRecording'] == true;
        if (recActive != _isRecording) {
          _isRecording = recActive;
          _recordingEgressId = data['recordingEgressId'] as String? ?? _recordingEgressId;
          _recordingFileName = data['recordingFileName'] as String? ?? _recordingFileName;
          notifyListeners();
        }
        if (data['recordingReady'] == true && !_recordingReady) {
          _recordingReady = true;
          _recordingUrl = data['recordingUrl'] as String?;
          _recordingFileName = data['recordingFileName'] as String? ?? _recordingFileName;
          notifyListeners();
        }
      }
      final status = snap.data()?['status'];
      if (status == 'ended' || status == 'declined') {
        if (_isConnecting) return;
        final connectedAt = _callConnectedAt;
        if (connectedAt != null &&
            DateTime.now().difference(connectedAt).inSeconds < 2) {
          return;
        }
        cleanup();
      }
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      final userId = user?.uid ?? 'guest_${DateTime.now().millisecondsSinceEpoch}';
      final userName = user?.displayName ?? 'User';

      final tokenData = await CallSignalingService.getOrFetchToken(
        roomName: roomName,
        userId: userId,
        userName: userName,
      );

      if (tokenData == null) {
        throw Exception("Could not acquire LiveKit call token");
      }

      final token = tokenData['token']!;
      final wsUrl = tokenData['url']!;

      final room = Room(
        roomOptions: RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultCameraCaptureOptions: const CameraCaptureOptions(
            cameraPosition: CameraPosition.front,
            maxFrameRate: 30,
          ),
          defaultAudioCaptureOptions: const AudioCaptureOptions(
            noiseSuppression: true,
            echoCancellation: true,
            autoGainControl: true,
            highPassFilter: true,
            typingNoiseDetection: true,
            stopAudioCaptureOnMute: false, // CRITICAL: false keeps Android native AudioRecord alive without hardware failure
          ),
          defaultAudioPublishOptions: const AudioPublishOptions(
            dtx: false, // CRITICAL: false prevents packet drop / freeze on mobile carrier jitter
            encoding: AudioEncoding.presetSpeech,
          ),
          defaultAudioOutputOptions: AudioOutputOptions(
            speakerOn: _isSpeakerOn,
          ),
        ),
      );
      _room = room;

      _listener = room.createListener();
      _listener!
        ..on<RoomDisconnectedEvent>((event) {
          debugPrint("LiveKit Room disconnected: ${event.reason}");
          cleanup();
        })
        ..on<ParticipantDisconnectedEvent>((event) {
          debugPrint("Participant disconnected: ${event.participant.identity}");
          notifyListeners();
          final r = _room;
          if (r != null && r.remoteParticipants.isEmpty) {
            cleanup();
          }
        })
        ..on<TrackSubscribedEvent>((event) {
          debugPrint("TrackSubscribed: ${event.track.kind} (${event.track.sid}) from ${event.participant.identity}");
          if (event.track.kind == TrackType.AUDIO) {
            setAudioOutput(_currentAudioOutput);
          }
          notifyListeners();
        })
        ..on<TrackUnsubscribedEvent>((_) => notifyListeners())
        ..on<ParticipantConnectedEvent>((event) {
          debugPrint("ParticipantConnected: ${event.participant.identity}");
          setAudioOutput(_currentAudioOutput);
          notifyListeners();
        })
        ..on<LocalTrackPublishedEvent>((_) => notifyListeners())
        ..on<LocalTrackUnpublishedEvent>((_) => notifyListeners())
        ..on<TrackMutedEvent>((_) => notifyListeners())
        ..on<TrackUnmutedEvent>((_) => notifyListeners())
        ..on<ParticipantConnectionQualityUpdatedEvent>((_) => notifyListeners())
        ..on<RoomReconnectingEvent>((_) => notifyListeners())
        ..on<RoomReconnectedEvent>((_) => notifyListeners());

      await room.connect(wsUrl, token);

      // 1. Enable microphone safely with retry
      try {
        await room.localParticipant?.setMicrophoneEnabled(!_isMuted);
      } catch (micErr) {
        debugPrint("Error enabling microphone on first attempt: $micErr. Retrying...");
        await Future.delayed(const Duration(milliseconds: 300));
        try {
          await room.localParticipant?.setMicrophoneEnabled(!_isMuted);
        } catch (retryErr) {
          debugPrint("Microphone enable retry failed: $retryErr");
        }
      }

      // 2. Enable camera safely if video call
      if (isVideo) {
        try {
          await room.localParticipant?.setCameraEnabled(!_isVideoOff);
        } catch (camErr) {
          debugPrint("Error enabling camera: $camErr");
          _isVideoOff = true;
        }
      }

      // 3. Route audio output through both LiveKit Hardware and native Android AudioManager
      try {
        await setAudioOutput(_currentAudioOutput);
      } catch (hwErr) {
        debugPrint("Error initializing audio output: $hwErr");
      }

      _isConnecting = false;
      _callConnectedAt = DateTime.now();

      // 4. Tactile confirmation pulse (avoids playing media player audio so WebRTC VoIP audio focus is never stolen)
      RingtoneService.instance.triggerHapticPulse(durationMs: 60);

      // 5. Query available native audio routing endpoints (speaker, earpiece, bluetooth)
      refreshAvailableAudioDevices();

      // 6. VoIP Audio Watchdog: 1500ms after connection, verify microphone is actively transmitting
      Timer(const Duration(milliseconds: 1500), () async {
        final r = _room;
        if (r == null || !hasActiveCall) return;
        final lp = r.localParticipant;
        if (lp != null && !_isMuted && !lp.isMicrophoneEnabled()) {
          debugPrint("[VoIP Watchdog] Re-priming microphone publication...");
          try {
            await lp.setMicrophoneEnabled(true);
            await setAudioOutput(_currentAudioOutput);
          } catch (_) {}
        }
      });

      // Start the call duration timer ONLY after successful connection
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _durationSeconds++;
        notifyListeners();
      });

      notifyListeners();
    } catch (e) {
      debugPrint('ActiveCallManager connect error: $e');
      _isConnecting = false;
      _errorMessage = e.toString();
      // Cancel Firestore subscription to prevent stale listener
      _callStatusSub?.cancel();
      _callStatusSub = null;
      // Evict token from cache so next attempt fetches fresh credentials
      CallSignalingService.evictTokenCache(roomName);
      notifyListeners();
    }
  }

  void minimize() {
    _isMinimized = true;
    try {
      _overlayChannel.invokeMethod('showOngoingCall', {
        'callId': _callId ?? '',
        'peerName': _peerName ?? 'User',
        'isVideo': _isVideo,
      });
    } catch (_) {}
    notifyListeners();
  }

  void unminimize() {
    _isMinimized = false;
    try {
      _overlayChannel.invokeMethod('hideOngoingCall');
    } catch (_) {}
    notifyListeners();
  }

  void maximize([BuildContext? context]) {
    if (!hasActiveCall || _callId == null || _roomName == null) return;
    
    // Always prefer rootNavigatorKey so navigation succeeds regardless of where context is
    final nav = rootNavigatorKey.currentState ??
        (context != null ? Navigator.maybeOf(context, rootNavigator: true) : null);

    if (nav == null) {
      debugPrint("ActiveCallManager.maximize: Root navigator is not ready");
      return;
    }

    // Unminimize once navigator is confirmed ready
    unminimize();

    nav.push(
      MaterialPageRoute(
        builder: (context) => ActiveCallScreen(
          callId: _callId!,
          roomName: _roomName!,
          isVideo: _isVideo,
          peerName: _peerName ?? 'User',
        ),
      ),
    );
  }

  Future<void> enterNativePip() async {
    try {
      await _overlayChannel.invokeMethod('enterPip');
    } catch (e) {
      debugPrint("Native PiP invocation error: $e");
    }
  }

  Future<void> toggleMute() async {
    final next = !_isMuted;
    _isMuted = next;
    await _room?.localParticipant?.setMicrophoneEnabled(!next);
    notifyListeners();
  }

  Future<void> enableVideo() async {
    _isVideo = true;
    _isVideoOff = false;
    try {
      await _room?.localParticipant?.setCameraEnabled(true);
    } catch (e) {
      debugPrint("Error enabling camera on video upgrade: $e");
    }
    notifyListeners();
  }

  Future<void> toggleVideo() async {
    if (!_isVideo) {
      // Transition from audio call to video call
      await enableVideo();
      return;
    }
    final next = !_isVideoOff;
    _isVideoOff = next;
    await _room?.localParticipant?.setCameraEnabled(!next);
    notifyListeners();
  }

  Future<void> toggleDataSaver() async {
    _isDataSaver = !_isDataSaver;
    try {
      final videoTrack = _room?.localParticipant?.videoTrackPublications.firstOrNull?.track;
      if (videoTrack is LocalVideoTrack) {
        await videoTrack.restartTrack(CameraCaptureOptions(
          maxFrameRate: _isDataSaver ? 15 : 30,
        ));
      }
    } catch (e) {
      debugPrint("Data saver mode toggle note: $e");
    }
    notifyListeners();
  }

  Future<void> switchCamera() async {
    final track = _room?.localParticipant?.videoTrackPublications.firstOrNull?.track;
    if (track is LocalVideoTrack) {
      final nextPosition = _isFrontCamera ? CameraPosition.back : CameraPosition.front;
      await track.restartTrack(CameraCaptureOptions(cameraPosition: nextPosition));
      _isFrontCamera = !_isFrontCamera;
      notifyListeners();
    }
  }

  Future<void> refreshAvailableAudioDevices() async {
    try {
      final res = await _overlayChannel.invokeMethod('getAvailableAudioDevices');
      if (res is List) {
        _availableAudioDevices = res
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error fetching available audio devices: $e");
    }
  }

  Future<void> setAudioOutput(AudioOutputDevice device) async {
    _currentAudioOutput = device;
    _isSpeakerOn = device == AudioOutputDevice.speaker;

    // 1. LiveKit WebRTC internal Hardware
    try {
      await Hardware.instance.setSpeakerphoneOn(_isSpeakerOn);
    } catch (e) {
      debugPrint("Hardware.instance.setSpeakerphoneOn warning: $e");
    }

    // 2. Native Android AudioManager communication routing (independent execution)
    try {
      await _overlayChannel.invokeMethod('setAudioOutput', {
        'device': device.name,
      });
    } catch (e) {
      debugPrint("Native overlay setAudioOutput error: $e");
    }

    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    if (_isSpeakerOn) {
      await setAudioOutput(AudioOutputDevice.earpiece);
    } else {
      await setAudioOutput(AudioOutputDevice.speaker);
    }
  }

  Future<void> endCall() async {
    // Immediately dismiss any floating overlay so it does not persist during teardown
    _isMinimized = false;
    notifyListeners();

    if (_isRecording && _callId != null) {
      CallSignalingService.stopCallRecording(
        callId: _callId!,
        egressId: _recordingEgressId,
        fileName: _recordingFileName,
      ).catchError((_) => null);
    }
    if (_callId != null) {
      CallSignalingService.endCall(_callId!, durationSeconds: _durationSeconds);
    }
    await cleanup();
  }

  Future<void> toggleScreenShare() async {
    final lp = _room?.localParticipant;
    if (lp == null) return;

    final wantedState = !_isScreenSharing;
    try {
      if (wantedState) {
        // 1. On Android, request capture permission first to obtain user consent
        // and initialize media projection data before starting foreground service.
        if (defaultTargetPlatform == TargetPlatform.android) {
          final hasCapturePermission = await Helper.requestCapturePermission();
          if (!hasCapturePermission) {
            debugPrint("Screen share permission denied by user");
            return;
          }
          // 2. Start native foreground service with FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
          // (CRITICAL on Android 14+ / API 34+ to prevent fatal SecurityException crash)
          try {
            await _overlayChannel.invokeMethod('startScreenCaptureService');
          } catch (svcErr) {
            debugPrint("Error starting native screen capture foreground service: $svcErr");
          }
        }

        // 3. Enable screen share: use explicit params so LiveKit doesn't crash
        // with null defaults on some Android versions.
        await lp.setScreenShareEnabled(
          true,
          screenShareCaptureOptions: const ScreenShareCaptureOptions(
            useiOSBroadcastExtension: false,
            params: VideoParametersPresets.screenShareH720FPS15,
          ),
        );
      } else {
        await lp.setScreenShareEnabled(false);
        if (defaultTargetPlatform == TargetPlatform.android) {
          try {
            await _overlayChannel.invokeMethod('stopScreenCaptureService');
          } catch (_) {}
        }
      }
      _isScreenSharing = wantedState;
      notifyListeners();
    } catch (e) {
      debugPrint("Error toggling screen share (wanted=$wantedState): $e");
      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          await _overlayChannel.invokeMethod('stopScreenCaptureService');
        } catch (_) {}
      }
      // Always roll back so UI is not stuck in wrong state
      _isScreenSharing = false;
      notifyListeners();
    }
  }

  Future<void> toggleRecording() async {
    if (_callId == null || _roomName == null) return;
    if (_isRecording) {
      final egressId = _recordingEgressId;
      final fileName = _recordingFileName;
      _isRecording = false;
      notifyListeners();
      await CallSignalingService.stopCallRecording(
        callId: _callId!,
        egressId: egressId,
        fileName: fileName,
      );
    } else {
      _isRecordingStarting = true;
      notifyListeners();
      try {
        final res = await CallSignalingService.startCallRecording(
          callId: _callId!,
          roomName: _roomName!,
        );
        if (res != null && res['status'] == 'success') {
          _isRecording = true;
          _recordingEgressId = res['egress_id'] as String?;
          _recordingFileName = res['file_name'] as String?;
        }
      } catch (e) {
        debugPrint("ActiveCallManager toggleRecording error: $e");
      } finally {
        _isRecordingStarting = false;
        notifyListeners();
      }
    }
  }

  Future<void> cleanup() async {
    RingtoneService.instance.triggerHapticPulse(durationMs: 40);
    SoundService.instance.playCallEnded();
    _durationTimer?.cancel();
    _durationTimer = null;
    _callStatusSub?.cancel();
    _callStatusSub = null;
    _listener?.dispose();
    _listener = null;
    _isMinimized = false;
    _isConnecting = false;
    _isScreenSharing = false;
    notifyListeners();

    try {
      await _overlayChannel.invokeMethod('hideOngoingCall');
      await _overlayChannel.invokeMethod('stopScreenCaptureService');
      await _overlayChannel.invokeMethod('resetAudio');
    } catch (_) {}
    try {
      await _room?.disconnect();
    } catch (_) {}
    _room = null;
    _callId = null;
    _roomName = null;
    _peerName = null;
    _durationSeconds = 0;
    _callConnectedAt = null;
    _isRecording = false;
    _isRecordingStarting = false;
    _recordingEgressId = null;
    _recordingFileName = null;
    _recordingUrl = null;
    _recordingReady = false;
    notifyListeners();
  }

  /// Helper to get remote video tracks
  List<VideoTrack> getRemoteVideoTracks() {
    final r = _room;
    if (r == null) return [];
    final tracks = <VideoTrack>[];
    for (final participant in r.remoteParticipants.values) {
      for (final pub in participant.videoTrackPublications) {
        final tr = pub.track;
        if (tr != null && !pub.muted) {
          tracks.add(tr);
        }
      }
    }
    return tracks;
  }

  /// Helper to get local video track
  VideoTrack? getLocalVideoTrack() {
    final r = _room;
    if (r == null || _isVideoOff) return null;
    for (final pub in r.localParticipant?.videoTrackPublications ?? []) {
      final tr = pub.track;
      if (tr != null && !pub.muted) {
        return tr;
      }
    }
    return null;
  }
}
