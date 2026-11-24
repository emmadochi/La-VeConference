import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart' hide ConnectionState;
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:flutter_background/flutter_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simple_pip_mode/simple_pip.dart';
import 'package:simple_pip_mode/pip_widget.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import '../api_service.dart';
import '../utils/error_utils.dart';
import '../services/notification_service.dart';
import '../widgets/reaction_particle_overlay.dart';
import '../main_layout.dart';

/// Represents the active audio output route during a call.
enum AudioRoute { speaker, earpiece, bluetooth, wiredHeadset }

class ChatMessage {
  final String sender;
  final String message;
  final DateTime timestamp;
  final bool isLocal;
  ChatMessage({required this.sender, required this.message, required this.timestamp, this.isLocal = false});
}

class VideoRoomScreen extends StatefulWidget {
  final String roomName;
  final String participantName;
  final String? meetingTitle;
  final bool initialAudioOn;
  final bool initialVideoOn;
  final bool isHost;

  const VideoRoomScreen({
    Key? key,
    required this.roomName,
    required this.participantName,
    this.meetingTitle,
    this.initialAudioOn = true,
    this.initialVideoOn = true,
    this.isHost = false,
  }) : super(key: key);

  @override
  State<VideoRoomScreen> createState() => _VideoRoomScreenState();
}

class _VideoRoomScreenState extends State<VideoRoomScreen> with WidgetsBindingObserver {
  late Room _room;
  late String _displayMeetingTitle;
  String? _meetingHostId;
  bool get _effectiveIsHost => widget.isHost || (_meetingHostId != null && FirebaseAuth.instance.currentUser?.uid != null && _meetingHostId == FirebaseAuth.instance.currentUser?.uid);
  bool _isRoomInitialized = false;
  bool _isExiting = false;
  AlreadyInMeetingException? _conflictException;
  bool _isLoading = true;
  String? _error;
  late bool _isMuted;
  late bool _isVideoOff;
  bool _isTogglingMic = false;
  bool _isTogglingCamera = false;
  bool _isScreenSharing = false;
  bool _isRecording = false;
  AudioRecorder? _audioRecorder;
  String? _localRecordingPath;
  bool _isDataSaverMode = false;
  Map<String, dynamic>? _activePoll;
  List<Map<String, dynamic>> _qaQuestions = [];
  bool _showQaPopup = false;
  Map<String, ConnectionQuality> _connectionQualities = {};
  String? _egressId;
  Participant? _pinnedParticipant;
  // Audio output routing
  // AudioRoute: which physical output is currently active
  AudioRoute _currentAudioRoute = AudioRoute.speaker;
  List<MediaDevice> _availableAudioOutputs = [];
  StreamSubscription<List<MediaDevice>>? _deviceChangeSubscription;
  bool _isRoomLocked = false;
  bool _isWaitingRoomEnabled = false;
  bool _isWaitingForHostApproval = false;
  bool _isDeniedByHost = false;
  String _waitingRoomMessage = 'Please wait — the host will let you in shortly.';
  Timer? _waitingPollTimer;
  StreamSubscription<QuerySnapshot>? _waitingRoomSub;
  List<Map<String, dynamic>> _waitingGuests = [];

  Timer? _networkPoorTimer;
  DateTime? _networkPopupSnoozedUntil;
  bool _isNetworkPopupShowing = false;

  // PHASE D: Active Speaker tracking
  /// The identity of the participant who is currently the loudest speaker.
  String? _activeSpeakerIdentity;

  final Map<String, String?> _participantAvatarCache = {};
  final Set<String> _pendingAvatarFetches = {};

  String? _getParticipantAvatar(Participant p) {
    final identity = p.identity;
    final isLocal = p == _room.localParticipant;
    if (isLocal) {
      final localPhoto = FirebaseAuth.instance.currentUser?.photoURL;
      if (localPhoto != null && localPhoto.trim().isNotEmpty) return localPhoto.trim();
    }
    if (_participantAvatarCache.containsKey(identity)) {
      return _participantAvatarCache[identity];
    }
    final rawMetadata = p.metadata;
    if (rawMetadata != null && rawMetadata.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawMetadata);
        if (decoded is Map<String, dynamic>) {
          final metaAvatar = decoded['avatar'] ?? decoded['photoURL'] ?? decoded['photoUrl'];
          if (metaAvatar != null && metaAvatar.toString().trim().isNotEmpty) {
            final validUrl = metaAvatar.toString().trim();
            _participantAvatarCache[identity] = validUrl;
            return validUrl;
          }
        }
      } catch (_) {
        if (rawMetadata.startsWith('http://') || rawMetadata.startsWith('https://')) {
          final validUrl = rawMetadata.trim();
          _participantAvatarCache[identity] = validUrl;
          return validUrl;
        }
      }
    }
    if (!_pendingAvatarFetches.contains(identity) && identity.isNotEmpty && !identity.startsWith('peer_')) {
      _pendingAvatarFetches.add(identity);
      FirebaseFirestore.instance.collection('users').doc(identity).get().then((doc) {
        if (doc.exists) {
          final data = doc.data() ?? {};
          final fsAvatar = (data['photoURL'] ?? data['avatar'] ?? data['photoUrl'])?.toString();
          if (fsAvatar != null && fsAvatar.trim().isNotEmpty) {
            _participantAvatarCache[identity] = fsAvatar.trim();
            if (mounted) setState(() {});
            return;
          }
        }
        _participantAvatarCache[identity] = null;
      }).catchError((_) {
        _participantAvatarCache[identity] = null;
      });
    }
    return null;
  }

  Widget _buildParticipantAvatarWidget(Participant p, double avatarSize, double fontSize, String initial) {
    final avatarUrl = _getParticipantAvatar(p);
    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;
    return Center(
      child: Container(
        width: avatarSize,
        height: avatarSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFF5C00FF), Color(0xFF00E5FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00E5FF).withOpacity(0.35),
              blurRadius: avatarSize > 70 ? 20 : 12,
              spreadRadius: avatarSize > 70 ? 2.5 : 1.0,
            ),
          ],
        ),
        padding: const EdgeInsets.all(2.5),
        child: ClipOval(
          child: Container(
            color: const Color(0xFF131728),
            child: hasAvatar
                ? Image.network(
                    avatarUrl,
                    width: avatarSize,
                    height: avatarSize,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Center(
                      child: Text(
                        initial,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: fontSize,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Center(
                        child: Text(
                          initial,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: fontSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    },
                  )
                : Center(
                    child: Text(
                      initial,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: fontSize,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  late EventsListener<RoomEvent> _listener;
  
  final ValueNotifier<List<ChatMessage>> _messagesNotifier = ValueNotifier([]);
  int _unreadCount = 0;
  bool _isChatOpen = false;
  final TextEditingController _chatController = TextEditingController();

  Set<String> _raisedHands = {};
  Map<String, String> _activeReactions = {};
  final GlobalKey<ReactionParticleOverlayState> _reactionOverlayKey = GlobalKey<ReactionParticleOverlayState>();
  Timer? _reactionBroadcastTimer;
  final Map<String, int> _pendingReactions = {};

  bool _isFullScreen = false;
  bool _showFullScreenControls = true;
  Timer? _fullScreenControlsTimer;
  StreamSubscription<DocumentSnapshot>? _meetingSubscription;

  Timer? _meetingTimer;
  int? _roomStartedAtSec;
  int? _scheduledTimeSec;
  String _meetingDurationText = "00:00";

  bool get _isWaitingForScheduledStart {
    if (_scheduledTimeSec == null) return false;
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return nowSec < _scheduledTimeSec!;
  }

  void _startMeetingTimer(int? startedAtSec, {int? scheduledTimeSec}) {
    _meetingTimer?.cancel();
    _scheduledTimeSec = scheduledTimeSec;
    _roomStartedAtSec = startedAtSec;
    _updateMeetingDuration();
    _meetingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      _updateMeetingDuration();
    });
  }

  void _updateMeetingDuration() {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // Gate elapsed chronometer until scheduled start time arrives
    if (_scheduledTimeSec != null && nowSec < _scheduledTimeSec!) {
      final remaining = (_scheduledTimeSec! - nowSec).clamp(0, 86400 * 30);
      final rHours = remaining ~/ 3600;
      final rMins = (remaining % 3600) ~/ 60;
      final rSecs = remaining % 60;
      final countdown = rHours > 0
          ? 'Starts in ${rHours.toString().padLeft(2, '0')}:${rMins.toString().padLeft(2, '0')}:${rSecs.toString().padLeft(2, '0')}'
          : 'Starts in ${rMins.toString().padLeft(2, '0')}:${rSecs.toString().padLeft(2, '0')}';
      if (_meetingDurationText != countdown) {
        setState(() {
          _meetingDurationText = countdown;
        });
      }
      return;
    }

    _roomStartedAtSec ??= _scheduledTimeSec ?? nowSec;
    final elapsed = (nowSec - _roomStartedAtSec!).clamp(0, 86400 * 7);
    final hours = elapsed ~/ 3600;
    final mins = (elapsed % 3600) ~/ 60;
    final secs = elapsed % 60;
    final formatted = hours > 0
        ? '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}'
        : '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    if (_meetingDurationText != formatted) {
      setState(() {
        _meetingDurationText = formatted;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _displayMeetingTitle = widget.meetingTitle ?? (widget.isHost ? "${widget.participantName}'s Meeting" : widget.roomName);
    _isMuted = !widget.initialAudioOn;
    _isVideoOff = !widget.initialVideoOn;
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _connectToRoom();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _connectToRoom({bool force = false}) async {
    try {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _error = null;
          _conflictException = null;
        });
      }

      final prefs = await SharedPreferences.getInstance();
      final muteMicDefault = prefs.getBool('muteMicDefault') ?? false;
      final offCameraDefault = prefs.getBool('offCameraDefault') ?? false;
      final dataSaverMode = prefs.getBool('dataSaverMode') ?? false;

      final bool effectiveAudioOn = widget.initialAudioOn && !muteMicDefault;
      final bool effectiveVideoOn = widget.initialVideoOn && !offCameraDefault;

      if (mounted) {
        setState(() {
          _isMuted = !effectiveAudioOn;
          _isVideoOff = !effectiveVideoOn;
          _isDataSaverMode = dataSaverMode;
        });
      }

      String actualRoomId = widget.roomName;
      String? e2eeKey;

      if (actualRoomId.contains('#')) {
        final parts = actualRoomId.split('#');
        actualRoomId = parts[0];
        e2eeKey = parts[1];
      } else {
        e2eeKey = prefs.getString('e2ee_$actualRoomId');
      }

      // Fetch meeting title and host from Firestore if needed
      try {
        DocumentSnapshot? doc;
        final docDirect = await FirebaseFirestore.instance.collection('meetings').doc(actualRoomId).get();
        if (docDirect.exists && docDirect.data() != null) {
          doc = docDirect;
        } else {
          final meetingQuery = await FirebaseFirestore.instance
              .collection('meetings')
              .where('roomId', isEqualTo: actualRoomId)
              .limit(1)
              .get();
          if (meetingQuery.docs.isNotEmpty) {
            doc = meetingQuery.docs.first;
          }
        }
        if (doc != null && doc.data() != null) {
          final data = doc.data() as Map<String, dynamic>;
          final hostId = data['hostId'] as String?;
          final title = data['title'] as String?;
          final status = data['status'] as String?;
          final currentUid = FirebaseAuth.instance.currentUser?.uid;

          if (mounted) {
            setState(() {
              _meetingHostId = hostId;
              if (title != null && title.trim().isNotEmpty) {
                _displayMeetingTitle = title.trim();
              } else if (_effectiveIsHost && (_displayMeetingTitle == widget.roomName || _displayMeetingTitle.isEmpty)) {
                _displayMeetingTitle = "${widget.participantName}'s Meeting";
              }
            });
          }

          // If the host is joining their own scheduled or previously ended meeting, reactivate it
          if (hostId != null && currentUid != null && hostId == currentUid && status == 'ended') {
            FirebaseFirestore.instance.collection('meetings').doc(doc.id).set({
              'status': 'scheduled',
            }, SetOptions(merge: true)).catchError((e) => debugPrint('Error reactivating meeting: $e'));
          }
        }
      } catch (e) {
        debugPrint('Failed to fetch meeting info from Firestore: $e');
      }

      if (force) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          try {
            await FirebaseFirestore.instance.collection('users').doc(uid).set({'active_room': actualRoomId}, SetOptions(merge: true));
          } catch (e) {
            debugPrint('Failed to set active_room in Firestore: $e');
          }
        }
      }

      final tokenDetails = await ApiService.getTokenDetails(actualRoomId, widget.participantName, force: force);
      final token = tokenDetails['token'] as String;
      final int? roomStartedAt = tokenDetails['room_started_at'] is int
          ? tokenDetails['room_started_at'] as int
          : (tokenDetails['room_started_at'] != null ? int.tryParse(tokenDetails['room_started_at'].toString()) : null);
      final int? scheduledTimeTs = tokenDetails['scheduled_time_ts'] is int
          ? tokenDetails['scheduled_time_ts'] as int
          : (tokenDetails['scheduled_time_ts'] != null ? int.tryParse(tokenDetails['scheduled_time_ts'].toString()) : null);
      _startMeetingTimer(roomStartedAt, scheduledTimeSec: scheduledTimeTs);
      final livekitUrl = await ApiService.getLiveKitUrl();
      
      BaseKeyProvider? keyProvider;
      if (e2eeKey != null) {
        keyProvider = await BaseKeyProvider.create();
        await keyProvider.setKey(e2eeKey);
      }
      
      _room = Room();
      _listener = _room.createListener();
      _isRoomInitialized = true;
      _listener.on<RoomEvent>((event) async {
        if (event is RoomDisconnectedEvent) {
          debugPrint('LiveKit Room Disconnected: ${event.reason}');
          if (_isExiting) return;

          if (mounted) {
            if (event.reason == DisconnectReason.clientInitiated) {
              return;
            }

            String message;
            if (event.reason == DisconnectReason.roomDeleted) {
              message = 'Meeting has ended.';
            } else if (event.reason == DisconnectReason.participantRemoved) {
              message = 'You have been removed from the meeting by the host.';
            } else if (event.reason == DisconnectReason.duplicateIdentity) {
              message = 'You connected to this meeting from another session.';
            } else if (event.reason == DisconnectReason.joinFailure) {
              message = 'Unable to establish media connection. Please check your network.';
            } else {
              message = 'Connection to meeting lost. Please check your internet.';
            }

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message, style: const TextStyle(color: Colors.white)),
                backgroundColor: Colors.redAccent,
              ),
            );
            _exitMeetingScreen();
          }
          return;
        }

        // PHASE D: Track active speakers and promote primary speaker
        if (event is ActiveSpeakersChangedEvent) {
          if (mounted) {
            setState(() {
              if (event.speakers.isNotEmpty) {
                // Pick the first non-local speaker as the primary tile
                final remoteSpeaker = event.speakers
                    .whereType<RemoteParticipant>()
                    .firstOrNull;
                _activeSpeakerIdentity = remoteSpeaker?.identity ?? 
                    _activeSpeakerIdentity;
              }
            });
          }
          return;
        }

        if (event is ParticipantMetadataUpdatedEvent) {
          _participantAvatarCache.remove(event.participant.identity);
          if (mounted) setState(() {});
          return;
        }

        if (event is TrackPublishedEvent) {
          if (_isDataSaverMode && event.publication.kind == TrackType.VIDEO) {
            try {
              event.publication.unsubscribe();
            } catch (_) {}
          }
          return;
        }

        if (event is TrackMutedEvent || event is TrackUnmutedEvent) {
          final dynamic trackEvent = event;
          if (_isRoomInitialized && trackEvent.participant == _room.localParticipant) {
            _syncLocalMediaState();
          } else if (mounted) {
            setState(() {});
          }
          return;
        }

        if (event is LocalTrackPublishedEvent || event is LocalTrackUnpublishedEvent) {
          _syncLocalMediaState();
          return;
        }

        if (event is TrackSubscribedEvent) {
          if (_isDataSaverMode && event.track.kind == TrackType.VIDEO) {
            try {
              event.publication.unsubscribe();
            } catch (_) {}
          }
          return;
        }

          if (event is ParticipantConnectionQualityUpdatedEvent) {
            if (mounted) {
              setState(() {
                _connectionQualities[event.participant.identity] = event.connectionQuality;
              });
              
              if (event.participant == _room.localParticipant) {
                if (event.connectionQuality == ConnectionQuality.poor || event.connectionQuality == ConnectionQuality.lost) {
                  if (!_isVideoOff && !_isNetworkPopupShowing) {
                    if (_networkPopupSnoozedUntil == null || DateTime.now().isAfter(_networkPopupSnoozedUntil!)) {
                      if (_networkPoorTimer == null || !_networkPoorTimer!.isActive) {
                        _networkPoorTimer = Timer(const Duration(seconds: 7), () {
                          if (mounted && !_isVideoOff && !_isNetworkPopupShowing) {
                            _showPoorNetworkDialog();
                          }
                        });
                      }
                    }
                  }
                } else if (event.connectionQuality == ConnectionQuality.excellent || event.connectionQuality == ConnectionQuality.good) {
                  _networkPoorTimer?.cancel();
                }
              }
            }
            return;
          }
          
          if (event is DataReceivedEvent) {
          final decoded = utf8.decode(event.data);

          if (decoded == '__MUTE_ALL__') {
            if (_room.localParticipant != null &&
                (_isLocalMicLive() || _room.localParticipant!.isMicrophoneEnabled())) {
              await _setLocalMicrophoneEnabled(false);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('The host has muted your microphone.', style: TextStyle(color: Colors.white)),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
            return;
          } else if (decoded.startsWith('__MUTE_PARTICIPANT__:')) {
            final targetId = decoded.substring('__MUTE_PARTICIPANT__:'.length);
            if (_room.localParticipant?.identity == targetId) {
              if (_room.localParticipant != null &&
                  (_isLocalMicLive() || _room.localParticipant!.isMicrophoneEnabled())) {
                await _setLocalMicrophoneEnabled(false);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('The host has muted your microphone.', style: TextStyle(color: Colors.white)),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            }
            return;
          } else if (decoded.startsWith('__REQUEST_UNMUTE__:')) {
            final targetId = decoded.substring('__REQUEST_UNMUTE__:'.length);
            if (_room.localParticipant?.identity == targetId && mounted) {
              _showUnmuteRequestDialog();
            }
            return;
          } else if (decoded == '__END_MEETING__') {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('The host has ended the meeting for everyone.', style: TextStyle(color: Colors.white)),
                  backgroundColor: Colors.red,
                ),
              );
              _exitMeetingScreen();
            }
            return;
          }

          try {
            final data = jsonDecode(decoded);
            if (data is Map<String, dynamic>) {
              if (data['type'] == 'reaction') {
                final senderId = data['senderId'] ?? event.participant?.identity;
                final emoji = data['emoji'] as String?;
                final count = (data['count'] as num?)?.toInt() ?? 1;
                if (emoji != null && mounted) {
                  _showReaction(senderId, emoji);
                  for (int i = 0; i < count; i++) {
                    Future.delayed(Duration(milliseconds: i * 80), () {
                      if (mounted) {
                        _reactionOverlayKey.currentState?.spawnReaction(emoji);
                      }
                    });
                  }
                }
                return;
              } else if (data['type'] == 'raise_hand') {
                final senderId = data['senderId'] ?? event.participant?.identity;
                if (senderId != null) {
                  if (mounted) {
                    setState(() {
                      if (data['state'] == true) {
                        _raisedHands.add(senderId);
                      } else {
                        _raisedHands.remove(senderId);
                      }
                    });
                  }
                }
                return;
              } else if (data['type'] == 'whiteboard_toggle') {
                if (data['state'] == true) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(' opened the whiteboard. Desktop users can view it.', style: const TextStyle(color: Colors.white))));
                  }
                }
                return;
              } else if (data['type'] == 'poll_launch') {
                if (mounted) {
                  setState(() {
                    _activePoll = data['poll'];
                  });
                  _showPollBottomSheet();
                }
                return;
              } else if (data['type'] == 'poll_vote' || data['type'] == 'poll_end') {
                if (mounted) {
                  setState(() {
                    _activePoll = null;
                  });
                  if (Navigator.canPop(context)) Navigator.pop(context);
                }
                return;
              } else if (data['type'] == 'qa_question') {
                if (mounted) {
                  setState(() {
                    _qaQuestions.insert(0, data['question']);
                    _showQaPopup = true;
                  });
                }
                return;
              } else if (data['type'] == 'qa_upvote') {
                if (mounted) {
                  setState(() {
                    try {
                      final q = _qaQuestions.firstWhere((q) => q['id'] == data['questionId']);
                      q['upvotes'] = (q['upvotes'] ?? 0) + 1;
                    } catch (e) {}
                  });
                }
                return;
              } else if (data['type'] == 'qa_answered') {
                if (mounted) {
                  setState(() {
                    try {
                      final q = _qaQuestions.firstWhere((q) => q['id'] == data['questionId']);
                      q['answered'] = true;
                      _showQaPopup = false;
                    } catch (e) {}
                  });
                }
                return;
              } else if (data['type'] == 'chat') {
                final newMsg = ChatMessage(
                  sender: data['sender'] ?? event.participant?.name ?? 'Someone',
                  message: data['text'] ?? '',
                  timestamp: DateTime.now(),
                );
                _messagesNotifier.value = List.from(_messagesNotifier.value)..add(newMsg);
                if (mounted) {
                  setState(() {
                    if (!_isChatOpen) {
                      _unreadCount++;
                    }
                  });
                }
                return;
              }
            }
          } catch (_) {
            // Ignore JSON parse errors, treat as legacy chat
          }

          final newMsg = ChatMessage(
            sender: event.participant?.name ?? 'Someone',
            message: decoded,
            timestamp: DateTime.now(),
          );
          _messagesNotifier.value = List.from(_messagesNotifier.value)..add(newMsg);
          
          if (mounted) {
            setState(() {
              if (!_isChatOpen) {
                _unreadCount++;
              }
            });
          }
        } else {
          if (mounted) {
            setState(() {});
          }
        }
      });
      
      await _room.connect(
        livekitUrl,
        token,
        roomOptions: RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultAudioPublishOptions: const AudioPublishOptions(
            dtx: true,
          ),
          e2eeOptions: keyProvider != null ? E2EEOptions(keyProvider: keyProvider) : null,
        ),
        connectOptions: const ConnectOptions(
          timeouts: Timeouts(
            connection: Duration(seconds: 40),
            debounce: Duration(milliseconds: 20),
            publish: Duration(seconds: 20),
            subscribe: Duration(seconds: 20),
            peerConnection: Duration(seconds: 30),
            iceRestart: Duration(seconds: 20),
          ),
        ),
      );
      
      // If Data Saver is active, pause incoming remote video streams
      if (_isDataSaverMode) {
        for (final p in _room.remoteParticipants.values) {
          for (final pub in p.videoTrackPublications) {
            try {
              pub.unsubscribe();
            } catch (_) {}
          }
        }
      }

      // Defensively initialize Camera & Microphone according to effectiveAudioOn / effectiveVideoOn
      try {
        await _room.localParticipant?.setCameraEnabled(effectiveVideoOn);
      } catch (camErr) {
        debugPrint("Camera permission or initialization skipped: $camErr");
      }

      // Allow native audio subsystem 150ms to settle into VoIP mode
      await Future.delayed(const Duration(milliseconds: 150));

      try {
        await _room.localParticipant?.setMicrophoneEnabled(effectiveAudioOn);
      } catch (micErr) {
        debugPrint("Microphone permission or initialization skipped: $micErr");
      }

      _syncLocalMediaState();

      // Start background foreground service so mic/audio capture continues when minimized
      _startBackgroundService();

      // Configure default audio output (Loudspeaker by default)
      try {
        await Hardware.instance.setSpeakerphoneOn(true);
        _currentAudioRoute = AudioRoute.speaker;
      } catch (e) {
        debugPrint("Hardware speakerphone init error: $e");
      }

      // Enumerate available output devices and subscribe to changes
      try {
        await _refreshAudioDevices();
        _deviceChangeSubscription = Hardware.instance.onDeviceChange.stream.listen((devices) async {
          await _refreshAudioDevices();
        });
      } catch (e) {
        debugPrint("Audio device enumeration error: $e");
      }

      // VoIP Audio Watchdog: verify microphone transmission 1500ms after connection
      Timer(const Duration(milliseconds: 1500), () async {
        if (!mounted || !_isRoomInitialized) return;
        if (!_isTogglingMic && !_isMuted && !_isLocalMicLive()) {
          debugPrint("[VoIP Watchdog] Re-priming meeting microphone...");
          await _setLocalMicrophoneEnabled(true, showError: false);
          try {
            await Hardware.instance.setSpeakerphoneOn(_currentAudioRoute == AudioRoute.speaker);
          } catch (_) {}
        }
      });

      // Realtime listener for meeting document in Firestore
      _meetingSubscription?.cancel();
      _meetingSubscription = FirebaseFirestore.instance.collection('meetings').doc(actualRoomId).snapshots().listen((snapshot) {
        if (snapshot.exists) {
          final data = snapshot.data();
          if (data != null) {
            if (data.containsKey('hostId') && data['hostId'] != null) {
              final hostId = data['hostId'] as String?;
              if (_meetingHostId != hostId && mounted) {
                setState(() {
                  _meetingHostId = hostId;
                });
              }
            }
            if (data['status'] == 'ended') {
              DateTime? schedTime;
              if (data['scheduledTime'] != null) {
                try {
                  schedTime = data['scheduledTime'] is Timestamp
                      ? (data['scheduledTime'] as Timestamp).toDate()
                      : DateTime.parse(data['scheduledTime'].toString());
                } catch (_) {}
              }
              final isFutureScheduled = schedTime != null && schedTime.isAfter(DateTime.now());

              if (!isFutureScheduled && mounted && !_effectiveIsHost) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('The host has ended the meeting for everyone.', style: TextStyle(color: Colors.white)),
                    backgroundColor: Colors.red,
                  ),
                );
                _exitMeetingScreen();
              }
            }
            if (data.containsKey('is_locked') && mounted) {
              setState(() {
                _isRoomLocked = data['is_locked'] == true;
              });
            }
            if (data.containsKey('requireApproval') && mounted) {
              setState(() {
                _isWaitingRoomEnabled = data['requireApproval'] == true;
              });
            }
          }
        }
      });

      if (_effectiveIsHost) {
        _startHostWaitingRoomMonitor(actualRoomId);
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } on WaitingApprovalException catch (waitEx) {
      if (mounted) {
        _enterWaitingRoomLobby(actualRoomId: waitEx.roomId, title: waitEx.title);
      }
    } on EntryDeniedException catch (deniedEx) {
      if (mounted) {
        setState(() {
          _isWaitingForHostApproval = false;
          _error = deniedEx.message;
          _isLoading = false;
        });
      }
    } on AlreadyInMeetingException catch (conflict) {
      if (mounted) {
        String active = conflict.activeRoom;
        if (active.isEmpty) {
          try {
            final uid = FirebaseAuth.instance.currentUser?.uid;
            if (uid != null) {
              final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
              active = doc.data()?['active_room'] ?? '';
            }
          } catch (_) {}
        }
        setState(() {
          _isLoading = false;
          _conflictException = AlreadyInMeetingException(
            activeRoom: active,
            targetRoom: conflict.targetRoom,
            message: conflict.message,
          );
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _startBackgroundService() async {
    try {
      final hasPermissions = await FlutterBackground.hasPermissions;
      if (!hasPermissions) {
        debugPrint('FlutterBackground: checking permissions');
      }
      const androidConfig = FlutterBackgroundAndroidConfig(
        notificationTitle: "La_Vie Conference",
        notificationText: "Meeting in progress • Audio active",
        notificationImportance: AndroidNotificationImportance.high,
        notificationIcon: AndroidResource(name: 'launcher_icon', defType: 'mipmap'),
        enableWifiLock: true,
      );
      bool initialized = await FlutterBackground.initialize(androidConfig: androidConfig);
      if (initialized && !FlutterBackground.isBackgroundExecutionEnabled) {
        await FlutterBackground.enableBackgroundExecution();
      }
      _enableAutoPipIfSupported();
    } catch (e) {
      debugPrint('Error starting background service: $e');
    }
  }

  Future<void> _enableAutoPipIfSupported() async {
    try {
      bool isPipSupported = await SimplePip.isPipAvailable;
      if (isPipSupported) {
        SimplePip().setAutoPipMode(aspectRatio: const (16, 9), autoEnter: true);
      }
    } catch (e) {
      debugPrint('Auto PiP configuration skipped: $e');
    }
  }

  Future<void> _stopBackgroundService() async {
    try {
      _stopNativeScreenShareService();
      if (FlutterBackground.isBackgroundExecutionEnabled) {
        await FlutterBackground.disableBackgroundExecution();
      }
    } catch (e) {
      debugPrint('Error stopping background service: $e');
    }
  }

  Future<void> _exitMeetingScreen() async {
    if (_isExiting) return;
    _isExiting = true;
    _meetingSubscription?.cancel();
    _stopBackgroundService();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      FirebaseFirestore.instance.collection('users').doc(uid).update({'active_room': ''}).catchError((_) {});
    }

    // Auto-save recording if actively recording when meeting ends
    if (_isRecording) {
      setState(() => _isRecording = false);
      try {
        final savedPath = await _audioRecorder?.stop();
        final finalPath = savedPath ?? _localRecordingPath;
        if (finalPath != null && File(finalPath).existsSync() && mounted) {
          await _showRecordingSavedDialog(finalPath);
        }
      } catch (e) {
        debugPrint('Error auto-saving recording on exit: $e');
      }
    }

    final savedRoomId = widget.roomName;
    final savedTitle = _displayMeetingTitle;
    final savedDuration = _meetingDurationText;

    // Build chat transcript from messages sent during meeting
    String? chatTranscript;
    if (_messagesNotifier.value.isNotEmpty) {
      chatTranscript = _messagesNotifier.value.map((m) => '${m.sender}: ${m.message}').join('\n');
    }

    // Automatically trigger AI summary in background using chat transcript or metadata
    if (chatTranscript != null && chatTranscript.trim().isNotEmpty) {
      ApiService.generateMeetingSummary(
        roomId: savedRoomId,
        title: savedTitle,
        transcriptText: chatTranscript,
      ).catchError((e) {
        debugPrint('Auto summary generation notice: $e');
        return <String, dynamic>{};
      });
    }

    final bool wasInCall = _isRoomInitialized;
    _waitingPollTimer?.cancel();
    _waitingRoomSub?.cancel();

    if (_isRoomInitialized) {
      try {
        _room.disconnect().catchError((_) {});
      } catch (_) {}
    }
    if (mounted) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const MainLayout()),
          (route) => false,
        );
      }

      if (wasInCall) {
        // Send local push notification thanking user and linking to AI Summary & Notes screen
        final bool leftBeforeStart = _isWaitingForScheduledStart;
        NotificationService().showImmediateNotification(
          id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          title: leftBeforeStart ? 'Scheduled Meeting Standby' : 'Thank you for joining $savedTitle!',
          body: leftBeforeStart
              ? '$savedTitle ($savedDuration) • Tap to view reminders & notifications.'
              : 'Meeting ended ($savedDuration) • Tap to view your AI Summary & Notes.',
          payload: 'open_notes',
        );
      }
    }
  }

  void _enterWaitingRoomLobby({required String actualRoomId, required String title}) {
    _waitingPollTimer?.cancel();
    setState(() {
      _isWaitingForHostApproval = true;
      _isDeniedByHost = false;
      _isLoading = false;
      if (title.isNotEmpty) _displayMeetingTitle = title;
      _waitingRoomMessage = 'Please wait — the host will review and let you in shortly.';
    });

    ApiService.knockRoom(actualRoomId);
    _waitingPollTimer = Timer.periodic(const Duration(milliseconds: 2500), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final status = await ApiService.checkKnockStatus(actualRoomId);
      if (!mounted) return;
      if (status == 'admitted' || status == 'open') {
        timer.cancel();
        setState(() {
          _isWaitingForHostApproval = false;
          _isLoading = true;
        });
        _connectToRoom();
      } else if (status == 'denied' || status == 'locked') {
        timer.cancel();
        setState(() {
          _isDeniedByHost = true;
          _waitingRoomMessage = status == 'locked'
              ? 'The host has locked this meeting.'
              : 'The host declined your request to enter this private meeting.';
        });
      }
    });
  }

  void _startHostWaitingRoomMonitor(String actualRoomId) {
    _waitingRoomSub?.cancel();
    int previousCount = _waitingGuests.length;
    _waitingRoomSub = FirebaseFirestore.instance
        .collection('meetings')
        .doc(actualRoomId)
        .collection('waiting_room')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final list = snap.docs.map((doc) {
        final d = doc.data();
        return <String, dynamic>{
          'uid': d['uid'] ?? doc.id,
          'name': d['name'] ?? 'Guest',
          'email': d['email'] ?? '',
          'photoUrl': d['photoUrl'] ?? '',
        };
      }).toList();
      if (list.length > previousCount) {
        HapticFeedback.mediumImpact();
      }
      previousCount = list.length;
      setState(() {
        _waitingGuests = list;
      });
    }, onError: (err) {
      debugPrint('Waiting room monitor fallback note: $err');
    });
  }

  Future<void> _decideWaitingGuest(String targetUid, String action) async {
    final actualRoomId = widget.roomName.split('#').first.trim();
    if (action == 'admit_all') {
      setState(() => _waitingGuests = []);
    } else {
      setState(() {
        _waitingGuests = _waitingGuests.where((g) => g['uid'] != targetUid).toList();
      });
    }
    await ApiService.decideWaitingGuest(actualRoomId, targetUid, action);
  }

  Future<void> _toggleWaitingRoom() async {
    if (!_effectiveIsHost) return;
    final nextState = !_isWaitingRoomEnabled;
    setState(() => _isWaitingRoomEnabled = nextState);
    final ok = await ApiService.toggleWaitingRoom(widget.roomName, nextState);
    if (!ok && mounted) {
      setState(() => _isWaitingRoomEnabled = !nextState);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update waiting room setting.'), backgroundColor: Colors.redAccent),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextState
                ? 'Private Waiting Room Enabled: New attendees require host approval.'
                : 'Waiting Room Disabled: Attendees can join freely.',
          ),
          backgroundColor: nextState ? const Color(0xFF00E5FF).withOpacity(0.85) : Colors.white24,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  void dispose() {
    _meetingTimer?.cancel();
    _waitingPollTimer?.cancel();
    _waitingRoomSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _meetingSubscription?.cancel();
    _deviceChangeSubscription?.cancel();
    _stopBackgroundService();
    _networkPoorTimer?.cancel();
    _fullScreenControlsTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _chatController.dispose();
    _messagesNotifier.dispose();
    try {
      _audioRecorder?.dispose();
    } catch (_) {}
    if (_isRoomInitialized) {
      try {
        _listener.dispose();
        _room.disconnect().catchError((_) {});
        _room.dispose();
      } catch (_) {}
    }
    super.dispose();
  }

  void _toggleFullScreen({Participant? participant}) {
    if (participant != null && _pinnedParticipant != participant) {
      _pinnedParticipant = participant;
    }
    setState(() {
      _isFullScreen = !_isFullScreen;
      _showFullScreenControls = true;
    });

    if (_isFullScreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      _fullScreenControlsTimer?.cancel();
      _fullScreenControlsTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && _isFullScreen) {
          setState(() {
            _showFullScreenControls = false;
          });
        }
      });
    } else {
      _fullScreenControlsTimer?.cancel();
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  void _onFullScreenTap() {
    setState(() {
      _showFullScreenControls = !_showFullScreenControls;
    });
    if (_showFullScreenControls) {
      _fullScreenControlsTimer?.cancel();
      _fullScreenControlsTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && _isFullScreen) {
          setState(() {
            _showFullScreenControls = false;
          });
        }
      });
    }
  }

  void _sendReaction(String emoji, {Offset? origin}) {
    // 1. Instant local visual and haptic particle burst
    _reactionOverlayKey.currentState?.spawnReaction(emoji, origin: origin);
    final identity = _room.localParticipant?.identity;
    _showReaction(identity, emoji);

    // 2. Queue for throttled network broadcast (max ~4 batches/sec)
    _pendingReactions[emoji] = (_pendingReactions[emoji] ?? 0) + 1;
    if (_reactionBroadcastTimer == null || !_reactionBroadcastTimer!.isActive) {
      _reactionBroadcastTimer = Timer(const Duration(milliseconds: 250), _flushReactions);
    }
  }

  void _flushReactions() async {
    if (_pendingReactions.isEmpty) return;
    final reactionsToSend = Map<String, int>.from(_pendingReactions);
    _pendingReactions.clear();

    final identity = _room.localParticipant?.identity;
    try {
      for (final entry in reactionsToSend.entries) {
        final payload = jsonEncode({
          'type': 'reaction',
          'emoji': entry.key,
          'count': entry.value,
          'senderId': identity,
        });
        await _room.localParticipant?.publishData(utf8.encode(payload), reliable: false);
      }
    } catch (e) {
      debugPrint('Error publishing reaction burst: $e');
    }
  }

  void _toggleHandRaise() async {
    final identity = _room.localParticipant?.identity;
    if (identity == null) return;
    
    final isRaised = !_raisedHands.contains(identity);
    setState(() {
      if (isRaised) {
        _raisedHands.add(identity);
      } else {
        _raisedHands.remove(identity);
      }
    });

    final payload = jsonEncode({'type': 'raise_hand', 'state': isRaised, 'senderId': identity});
    try {
      await _room.localParticipant?.publishData(utf8.encode(payload), reliable: true);
    } catch (_) {}
  }

  void _showReaction(String? identity, String emoji) {
    if (identity == null) return;
    if (!mounted) return;
    setState(() {
      _activeReactions[identity] = emoji;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          if (_activeReactions[identity] == emoji) {
            _activeReactions.remove(identity);
          }
        });
      }
    });
  }

  void _muteAll() async {
    final data = utf8.encode('__MUTE_ALL__');
    try {
      await _room.localParticipant?.publishData(data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Muted all other participants', style: TextStyle(color: Colors.white)), backgroundColor: Color(0xFF5C00FF)));
      }
    } catch (e) {
      debugPrint('Failed to mute all: $e');
    }
  }

  void _muteParticipant(String participantId) async {
    final data = utf8.encode('__MUTE_PARTICIPANT__:$participantId');
    try {
      await _room.localParticipant?.publishData(data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Muted participant', style: TextStyle(color: Colors.white)),
          backgroundColor: Color(0xFF5C00FF),
          duration: Duration(seconds: 2),
        ));
      }
    } catch (e) {
      debugPrint('Failed to mute participant: $e');
    }
  }

  void _requestUnmute(String participantId) async {
    final data = utf8.encode('__REQUEST_UNMUTE__:$participantId');
    try {
      await _room.localParticipant?.publishData(data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Sent unmute request to participant', style: TextStyle(color: Colors.white)),
          backgroundColor: Color(0xFF00E5FF),
          duration: Duration(seconds: 2),
        ));
      }
    } catch (e) {
      debugPrint('Failed to request unmute: $e');
    }
  }

  void _showUnmuteRequestDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0B1226),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: const Color(0xFF00E5FF).withOpacity(0.3)),
          ),
          title: const Row(
            children: [
              Icon(Icons.mic, color: Color(0xFF00E5FF)),
              SizedBox(width: 8),
              Text('Unmute Microphone?', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text(
            'The host has requested that you unmute your microphone to speak.',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Stay Muted', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(dialogCtx);
                await _setLocalMicrophoneEnabled(true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Unmute', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  bool _isLocalMicLive() {
    if (!_isRoomInitialized) return false;
    final lp = _room.localParticipant;
    if (lp == null) return false;
    final pub = lp.audioTrackPublications.firstOrNull;
    return lp.isMicrophoneEnabled() && pub != null && !pub.muted;
  }

  bool _isLocalCamLive() {
    if (!_isRoomInitialized) return false;
    final lp = _room.localParticipant;
    if (lp == null) return false;
    final pub = lp.videoTrackPublications
        .where((p) => p.source == TrackSource.camera)
        .firstOrNull;
    return lp.isCameraEnabled() && pub != null && !pub.muted && pub.track != null;
  }

  void _syncLocalMediaState() {
    if (!_isRoomInitialized || !mounted) return;
    final lp = _room.localParticipant;
    if (lp == null) return;
    final nextMuted = !_isLocalMicLive();
    final nextVideoOff = !_isLocalCamLive();
    setState(() {
      _isMuted = nextMuted;
      _isVideoOff = nextVideoOff;
    });
  }

  Future<void> _setLocalMicrophoneEnabled(bool enable, {bool showError = true}) async {
    if (!_isRoomInitialized) return;
    final lp = _room.localParticipant;
    if (lp == null || _isTogglingMic) return;

    _isTogglingMic = true;
    try {
      await lp.setMicrophoneEnabled(enable);
      if (!enable) {
        // Belt-and-suspenders: ensure every published local audio track is muted
        for (final pub in lp.audioTrackPublications) {
          if (!pub.muted) {
            await pub.mute();
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to toggle microphone ($enable): $e');
      if (showError && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enable
                  ? 'Could not turn on microphone. Check app permissions.'
                  : 'Could not mute microphone: $e',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      _isTogglingMic = false;
      _syncLocalMediaState();
    }
  }

  Future<void> _setLocalCameraEnabled(bool enable, {bool showError = true}) async {
    if (!_isRoomInitialized) return;
    final lp = _room.localParticipant;
    if (lp == null || _isTogglingCamera) return;

    _isTogglingCamera = true;
    try {
      await lp.setCameraEnabled(enable);
      if (!enable) {
        for (final pub in lp.videoTrackPublications) {
          if (pub.source == TrackSource.camera && !pub.muted) {
            await pub.mute();
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to toggle camera ($enable): $e');
      if (showError && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enable
                  ? 'Could not turn on camera. Check app permissions.'
                  : 'Could not turn off camera: $e',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      _isTogglingCamera = false;
      _syncLocalMediaState();
    }
  }

  Future<void> _toggleMute() async {
    if (!_isRoomInitialized || _room.localParticipant == null) return;
    final targetEnable = !_isLocalMicLive();
    await _setLocalMicrophoneEnabled(targetEnable);
  }

  Future<void> _toggleCamera() async {
    if (!_isRoomInitialized || _room.localParticipant == null) return;
    final targetEnable = !_isLocalCamLive();
    await _setLocalCameraEnabled(targetEnable);
  }

  bool _isFrontCamera = true;
  void _flipCamera() async {
    if (_room.localParticipant == null) return;
    final pubs = _room.localParticipant!.videoTrackPublications;
    if (pubs.isNotEmpty) {
      final track = pubs.first.track;
      if (track is LocalVideoTrack) {
        try {
          final newPosition = _isFrontCamera ? CameraPosition.back : CameraPosition.front;
          await track.setCameraPosition(newPosition);
          setState(() {
            _isFrontCamera = !_isFrontCamera;
          });
        } catch (e) {
          debugPrint('Failed to flip camera: $e');
        }
      }
    }
  }

  void _endCall() {
    if (!_effectiveIsHost) {
      _exitMeetingScreen();
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF070B19),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: const Color(0xFF00E5FF).withOpacity(0.3)),
          ),
          title: const Text('End Meeting', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: const Text(
            'Would you like to just leave, or end the meeting for everyone?',
            style: TextStyle(color: Colors.white54),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext); // close dialog
                _exitMeetingScreen();
              },
              child: const Text('Leave Meeting', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(dialogContext); // close dialog immediately
                final roomId = widget.roomName;

                // 1. Broadcast __END_MEETING__ reliably to all participants
                try {
                  final data = utf8.encode('__END_MEETING__');
                  _room.localParticipant?.publishData(data, reliable: true);
                } catch (e) {
                  debugPrint('Failed to broadcast end meeting: $e');
                }

                // 2. Perform backend & Firestore cleanup in background
                // Delete instant meetings completely so they do not clutter dashboard; mark scheduled meetings as ended;
                // Keep permanent rooms alive ('active') across sessions so users can rejoin anytime.
                FirebaseFirestore.instance.collection('meetings').doc(roomId).get().then((snap) {
                  final mData = snap.data();
                  final isPermanent = mData?['isPermanent'] == true || mData?['meetingType'] == 'permanent';
                  final isScheduled = mData?['meetingType'] == 'scheduled' || mData?['scheduledTime'] != null;

                  if (isPermanent) {
                    // Permanent rooms stay active in Firestore so they persist until explicitly deleted by host
                    FirebaseFirestore.instance.collection('meetings').doc(roomId).set({
                      'status': 'active',
                      'last_ended_at': FieldValue.serverTimestamp(),
                    }, SetOptions(merge: true)).catchError((e) => debugPrint('Permanent room update error: $e'));
                  } else if (!isScheduled && (mData?['meetingType'] == 'instant' || roomId.toLowerCase().startsWith('instant'))) {
                    FirebaseFirestore.instance.collection('meetings').where('roomId', isEqualTo: roomId).get().then((querySnap) {
                      for (final doc in querySnap.docs) {
                        doc.reference.delete().catchError((_) {});
                      }
                    }).catchError((_) {});
                    FirebaseFirestore.instance.collection('meetings').doc(roomId).delete().catchError((_) {});
                  } else {
                    FirebaseFirestore.instance.collection('meetings').doc(roomId).set({
                      'status': 'ended',
                      'ended_at': FieldValue.serverTimestamp(),
                    }, SetOptions(merge: true)).catchError((e) => debugPrint('Meeting status update error: $e'));
                  }
                }).catchError((_) {
                  // Fallback: safely mark as ended without deleting if not permanent
                  final isPerm = roomId.startsWith('perm-');
                  if (!isPerm) {
                    FirebaseFirestore.instance.collection('meetings').doc(roomId).set({
                      'status': 'ended',
                      'ended_at': FieldValue.serverTimestamp(),
                    }, SetOptions(merge: true)).catchError((e) => debugPrint('Meeting status fallback update error: $e'));
                  }
                });

                FirebaseFirestore.instance.collection('users').where('active_room', isEqualTo: roomId).get().then((snap) {
                  for (final doc in snap.docs) {
                    doc.reference.update({'active_room': ''}).catchError((_) {});
                  }
                }).catchError((_) {});

                ApiService.endMeeting(roomId);

                // 3. Small 150ms buffer so data packet leaves network before socket teardown
                await Future.delayed(const Duration(milliseconds: 150));

                // 4. Exit screen (prompts recording auto-save if active)
                await _exitMeetingScreen();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('End for All', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showVmixDialog() async {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF070B19),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: const Color(0xFF00E5FF).withOpacity(0.3)),
              ),
              title: Row(
                children: const [
                  Icon(Icons.live_tv, color: Color(0xFF00E5FF)),
                  SizedBox(width: 8),
                  Text('vMix / Live Ingest', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              content: FutureBuilder<Map<String, String>?>(
                future: ApiService.createIngress(widget.roomName),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox(
                      height: 120,
                      child: Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF))),
                    );
                  }
                  final data = snapshot.data;
                  final rtmpUrl = data?['rtmp_url'] ?? 'rtmp://${ApiService.baseUrl.replaceAll('https://', '')}/live';
                  final streamKey = data?['stream_key'] ?? 'lavie-stage-${widget.roomName}';

                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Stream live from vMix, OBS, or RTMP software into this meeting room as the Main Stage.',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        const Text('RTMP SERVER URL', style: TextStyle(color: Color(0xFF00E5FF), fontSize: 11, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        SelectableText(
                          rtmpUrl,
                          style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        const Text('STREAM KEY', style: TextStyle(color: Color(0xFF00E5FF), fontSize: 11, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        SelectableText(
                          streamKey,
                          style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: 'URL: $rtmpUrl\nKey: $streamKey'));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Credentials copied to clipboard!'), backgroundColor: Color(0xFF00E5FF)),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('Copy Credentials'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00E5FF),
                            foregroundColor: const Color(0xFF070B19),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close', style: TextStyle(color: Colors.white54)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static const MethodChannel _screenShareChannel =
      MethodChannel('org.lifechangerstouch.lavie/screen_share');

  Future<void> _startNativeScreenShareService() async {
    if (Platform.isAndroid) {
      try {
        await _screenShareChannel.invokeMethod('startService');
      } catch (e) {
        debugPrint('Error starting native screen share service: $e');
      }
    }
  }

  Future<void> _stopNativeScreenShareService() async {
    if (Platform.isAndroid) {
      try {
        await _screenShareChannel.invokeMethod('stopService');
      } catch (e) {
        debugPrint('Error stopping native screen share service: $e');
      }
    }
  }

  void _toggleScreenShare() async {
    final nextState = !_isScreenSharing;
    try {
      if (_room.localParticipant != null) {
        if (nextState) {
          if (Platform.isAndroid) {
            // Android 14+ MediaProjection permission request
            final hasPermission = await rtc.Helper.requestCapturePermission();
            if (!hasPermission) {
              debugPrint('User dismissed or denied screen capture prompt.');
              return;
            }
            // Start foreground service with mediaProjection type BEFORE WebRTC invokes getMediaProjection
            await _startNativeScreenShareService();
          }
          await _room.localParticipant!.setScreenShareEnabled(true, captureScreenAudio: true);
        } else {
          await _room.localParticipant!.setScreenShareEnabled(false);
          await _stopNativeScreenShareService();
        }

        if (mounted) {
          setState(() {
            _isScreenSharing = nextState;
          });
        }
      }
    } catch (e) {
      if (nextState) {
        await _stopNativeScreenShareService();
      }
      final info = ErrorUtils.parseMeetingError(e);
      if (!info.isCancellation) {
        debugPrint('Failed to toggle screen share: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(info.message),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  Future<void> _toggleRecording() async {
    if (!_effectiveIsHost) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recording is restricted to meeting hosts.', style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    if (_isRecording) {
      // Stop recording
      setState(() => _isRecording = false);
      String? savedPath;
      try {
        if (_audioRecorder != null) {
          savedPath = await _audioRecorder!.stop();
        }
      } catch (e) {
        debugPrint('Error stopping audio recorder: $e');
      }

      if (_egressId != null) {
        ApiService.stopRecording(_egressId!).catchError((_) => false);
        _egressId = null;
      }

      final finalPath = savedPath ?? _localRecordingPath;
      if (finalPath != null && File(finalPath).existsSync()) {
        if (mounted) {
          _showRecordingSavedDialog(finalPath);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Recording stopped.', style: TextStyle(color: Colors.white)),
              backgroundColor: Color(0xFF5C00FF),
            ),
          );
        }
      }
    } else {
      // Start recording
      try {
        _audioRecorder ??= AudioRecorder();
        final hasPermission = await _audioRecorder!.hasPermission();
        if (!hasPermission) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Microphone permission is required to record audio.', style: TextStyle(color: Colors.white)),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
          return;
        }

        final appDir = await getApplicationDocumentsDirectory();
        final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
        final recordingPath = '${appDir.path}/meeting_${widget.roomName}_$timestamp.m4a';

        await _audioRecorder!.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 128000,
            sampleRate: 44100,
          ),
          path: recordingPath,
        );

        _localRecordingPath = recordingPath;
        setState(() => _isRecording = true);

        // Also initiate server egress if available
        ApiService.startRecording(widget.roomName).then((egressId) {
          if (egressId != null) {
            _egressId = egressId;
          }
        }).catchError((_) => null);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Recording started successfully! Audio is being captured.', style: TextStyle(color: Colors.white)),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        setState(() => _isRecording = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to start recording: $e', style: const TextStyle(color: Colors.white)),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  Future<void> _showRecordingSavedDialog(String filePath) async {
    final fileName = filePath.split(Platform.pathSeparator).last;
    final file = File(filePath);
    final sizeKb = file.existsSync() ? (file.lengthSync() / 1024).toStringAsFixed(1) : '0';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF070B19),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E5FF).withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF00E5FF), size: 28),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Recording Finished', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          SizedBox(height: 2),
                          Text('Choose where to save your meeting audio', style: TextStyle(color: Colors.white60, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.audio_file_rounded, color: Color(0xFF00E5FF), size: 30),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(fileName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text('$sizeKb KB • AAC M4A Format', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Button 1: Save File (Storage Access Framework)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.download_rounded, color: Colors.black),
                    label: const Text('Save Recording to Device', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5FF),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () async {
                      Navigator.pop(sheetContext);
                      try {
                        final bytes = await file.readAsBytes();
                        final result = await FilePicker.saveFile(
                          dialogTitle: 'Save Meeting Recording',
                          fileName: fileName,
                          type: FileType.custom,
                          allowedExtensions: ['m4a'],
                          bytes: bytes,
                        );

                        if (result != null) {
                          try {
                            final destFile = File(result);
                            if (!await destFile.exists() || await destFile.length() == 0) {
                              await destFile.writeAsBytes(bytes);
                            }
                          } catch (_) {}

                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Recording saved successfully: $fileName', style: const TextStyle(color: Colors.white)),
                                backgroundColor: const Color(0xFF00C853),
                                duration: const Duration(seconds: 4),
                              ),
                            );
                          }
                        }
                      } catch (e) {
                        debugPrint("SAF save error: $e");
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Opening Share to save file...'),
                              backgroundColor: Color(0xFF00E5FF),
                              duration: Duration(seconds: 3),
                            ),
                          );
                          Share.shareXFiles(
                            [XFile(filePath)],
                            text: 'La-Vie Meeting Audio Recording - ${widget.roomName}',
                          );
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(height: 10),
                // Button 1.5: Generate AI Meeting Summary & Notes (Gemini)
                SizedBox(
                  width: double.infinity,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF9B51E0), Color(0xFF00E5FF)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                      label: const Text('Generate AI Summary & Notes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _triggerAiMeetingSummary(filePath);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Button 2: Share / Export Audio
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.share_rounded, color: Color(0xFF00E5FF)),
                    label: const Text('Export / Share Audio File', style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF00E5FF)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      Share.shareXFiles(
                        [XFile(filePath)],
                        text: 'La-Vie Meeting Audio Recording - ${widget.roomName}',
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  void _triggerAiMeetingSummary(String audioPath) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Transcribing audio & generating AI summary with Gemini...',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: Color(0xFF5C00FF),
        duration: Duration(seconds: 8),
      ),
    );

    try {
      await ApiService.generateMeetingSummary(
        roomId: widget.roomName,
        title: widget.meetingTitle ?? 'Meeting ${widget.roomName}',
        audioPath: audioPath,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✨ AI Meeting Summary & Takeaways ready! Check Notifications.'),
            backgroundColor: const Color(0xFF00C853),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'View',
              textColor: Colors.black,
              onPressed: () {
                // Summary is available in Firestore and Notifications
              },
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("AI summary generation error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AI Summary Notice: $e'),
            backgroundColor: const Color(0xFFFF5252),
          ),
        );
      }
    }
  }

  void _showPoorNetworkDialog() {
    setState(() {
      _isNetworkPopupShowing = true;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF070B19),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: const Color(0xFF00E5FF).withOpacity(0.3)),
          ),
          title: const Text('Unstable Network', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: const Text(
            'Your network connection is unstable. Would you like to turn off your video to improve call quality?',
            style: TextStyle(color: Colors.white54),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                if (mounted) {
                  setState(() {
                    _isNetworkPopupShowing = false;
                    _networkPopupSnoozedUntil = DateTime.now().add(const Duration(minutes: 2));
                  });
                }
              },
              child: const Text('Keep Video On', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                if (mounted) {
                  setState(() {
                    _isNetworkPopupShowing = false;
                  });
                  _toggleCamera();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5C00FF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Turn Off Video', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showReactionsBottomSheet() {
    final emojis = [
      '❤️', '👍', '👏', '🔥', '🎉', '😂',
      '😮', '🚀', '🙌', '💡', '💯', '🤝',
      '⚡', '🥳', '✨', '🤩',
    ];

    Timer? autoDismissTimer;

    void resetDismissTimer(BuildContext ctx) {
      autoDismissTimer?.cancel();
      autoDismissTimer = Timer(const Duration(milliseconds: 3200), () {
        if (Navigator.canPop(ctx)) {
          Navigator.pop(ctx);
        }
      });
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black26,
      isScrollControlled: true,
      builder: (bottomSheetContext) {
        resetDismissTimer(bottomSheetContext);

        return StatefulBuilder(
          builder: (context, setSheetState) {
            return ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF070B19).withOpacity(0.92),
                    border: Border(top: BorderSide(color: const Color(0xFF00E5FF).withOpacity(0.35))),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white30,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Text('Live Reactions', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                              SizedBox(width: 8),
                              Text('• Tap rapidly for mass burst!', style: TextStyle(color: Color(0xFF00E5FF), fontSize: 11)),
                            ],
                          ),
                          GestureDetector(
                            onTap: () {
                              autoDismissTimer?.cancel();
                              Navigator.pop(bottomSheetContext);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.white12,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, color: Colors.white70, size: 16),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 14,
                        runSpacing: 14,
                        children: emojis.map((emoji) {
                          return _ReactionTapButton(
                            emoji: emoji,
                            onTap: () {
                              resetDismissTimer(bottomSheetContext);
                              _sendReaction(emoji);
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      autoDismissTimer?.cancel();
    });
  }

  // ──────────────────────────────────────────────
  // AUDIO OUTPUT ROUTING
  // ──────────────────────────────────────────────

  Future<void> _refreshAudioDevices() async {
    try {
      final outputs = await Hardware.instance.enumerateDevices(type: 'audiooutput');
      if (mounted) {
        setState(() {
          _availableAudioOutputs = outputs;
        });
      }
    } catch (e) {
      debugPrint('Could not enumerate audio outputs: $e');
    }
  }

  IconData _audioRouteIcon([AudioRoute? route]) {
    switch (route ?? _currentAudioRoute) {
      case AudioRoute.bluetooth:
        return Icons.bluetooth_audio;
      case AudioRoute.wiredHeadset:
        return Icons.headset;
      case AudioRoute.earpiece:
        return Icons.hearing_rounded;
      case AudioRoute.speaker:
        return Icons.volume_up_rounded;
    }
  }

  String _audioRouteLabel([AudioRoute? route]) {
    switch (route ?? _currentAudioRoute) {
      case AudioRoute.bluetooth:
        return 'Bluetooth';
      case AudioRoute.wiredHeadset:
        return 'Wired Headset';
      case AudioRoute.earpiece:
        return 'Earpiece';
      case AudioRoute.speaker:
        return 'Speaker';
    }
  }

  Future<void> _applyAudioRoute(AudioRoute route) async {
    try {
      switch (route) {
        case AudioRoute.speaker:
          await Hardware.instance.setSpeakerphoneOn(true);
          break;
        case AudioRoute.earpiece:
          await Hardware.instance.setSpeakerphoneOn(false);
          break;
        case AudioRoute.bluetooth:
          // Prefer Bluetooth if available, falls back to earpiece on Android/iOS
          try {
            await rtc.Helper.setSpeakerphoneOnButPreferBluetooth();
          } catch (_) {
            await Hardware.instance.setSpeakerphoneOn(false);
          }
          break;
        case AudioRoute.wiredHeadset:
          // Wired headset: disable speakerphone, OS routes to wired output
          await Hardware.instance.setSpeakerphoneOn(false);
          break;
      }
      if (mounted) {
        setState(() {
          _currentAudioRoute = route;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(_audioRouteIcon(route), color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text(
                  'Audio: ${_audioRouteLabel(route)}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF131728),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error applying audio route: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to switch audio output: $e',
                style: const TextStyle(color: Colors.white)),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showAudioOutputPicker() {
    // Determine which routes to show.
    // We always show Speaker + Earpiece.
    // Show Bluetooth only if a BT device appears in enumerated outputs.
    // Show Wired Headset only if one is enumerated.
    final hasBluetooth = _availableAudioOutputs.any((d) =>
        d.label.toLowerCase().contains('bluetooth') ||
        d.label.toLowerCase().contains('bt') ||
        d.label.toLowerCase().contains('wireless'));
    final hasWired = _availableAudioOutputs.any((d) =>
        d.label.toLowerCase().contains('wired') ||
        d.label.toLowerCase().contains('headset') ||
        d.label.toLowerCase().contains('headphone'));

    final routes = [
      AudioRoute.speaker,
      AudioRoute.earpiece,
      if (hasBluetooth) AudioRoute.bluetooth,
      if (hasWired) AudioRoute.wiredHeadset,
    ];

    // Always show at minimum Speaker + Earpiece + Bluetooth option
    // even if BT not currently detected, so the user can try.
    if (!hasBluetooth) routes.add(AudioRoute.bluetooth);
    if (!hasWired && _availableAudioOutputs.length > 2) routes.add(AudioRoute.wiredHeadset);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A1F3A), Color(0xFF0D1020)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                decoration: BoxDecoration(
                  color: Colors.white30,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Row(
                  children: [
                    const Icon(Icons.settings_input_component_rounded,
                        color: Color(0xFF00E5FF), size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      'Audio Output',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const Spacer(),
                    if (_availableAudioOutputs.isNotEmpty)
                      Text(
                        '${_availableAudioOutputs.length} device${_availableAudioOutputs.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(color: Colors.white10, height: 16),
              ...routes.map((route) {
                final isActive = _currentAudioRoute == route;
                final label = _audioRouteLabel(route);
                final icon = _audioRouteIcon(route);
                String subtitle = '';
                switch (route) {
                  case AudioRoute.speaker:
                    subtitle = 'Play audio through the loudspeaker';
                    break;
                  case AudioRoute.earpiece:
                    subtitle = 'Play audio through the earpiece';
                    break;
                  case AudioRoute.bluetooth:
                    subtitle = hasBluetooth
                        ? 'Bluetooth device connected'
                        : 'Connect a Bluetooth device first';
                    break;
                  case AudioRoute.wiredHeadset:
                    subtitle = hasWired
                        ? 'Wired headset connected'
                        : 'Connect a wired headset first';
                    break;
                }
                final isAvailable = route == AudioRoute.speaker ||
                    route == AudioRoute.earpiece ||
                    (route == AudioRoute.bluetooth && hasBluetooth) ||
                    (route == AudioRoute.wiredHeadset && hasWired);

                return InkWell(
                  onTap: isAvailable
                      ? () {
                          Navigator.pop(ctx);
                          _applyAudioRoute(route);
                        }
                      : null,
                  child: Opacity(
                    opacity: isAvailable ? 1.0 : 0.45,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isActive
                            ? const Color(0xFF00E5FF).withOpacity(0.12)
                            : Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isActive
                              ? const Color(0xFF00E5FF).withOpacity(0.5)
                              : Colors.white.withOpacity(0.06),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: isActive
                                  ? const Color(0xFF00E5FF).withOpacity(0.18)
                                  : Colors.white.withOpacity(0.08),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              icon,
                              color: isActive
                                  ? const Color(0xFF00E5FF)
                                  : Colors.white70,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  label,
                                  style: TextStyle(
                                    color: isActive
                                        ? const Color(0xFF00E5FF)
                                        : Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  subtitle,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.5),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isActive)
                            const Icon(Icons.check_circle_rounded,
                                color: Color(0xFF00E5FF), size: 20),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Future<void> _toggleRoomLock() async {
    if (!_effectiveIsHost) return;
    final nextLockState = !_isRoomLocked;
    setState(() {
      _isRoomLocked = nextLockState;
    });

    final success = await ApiService.toggleRoomLock(widget.roomName, nextLockState);
    if (!success && mounted) {
      setState(() {
        _isRoomLocked = !nextLockState;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update meeting lock status.', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.redAccent,
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(nextLockState ? Icons.lock : Icons.lock_open, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  nextLockState ? 'Meeting Locked. New attendees cannot join.' : 'Meeting Unlocked. Attendees can join freely.',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: nextLockState ? Colors.amber.shade900 : const Color(0xFF00E5FF).withOpacity(0.85),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  void _showParticipantsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (bottomSheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final allParticipants = <Participant>[
              if (_room.localParticipant != null) _room.localParticipant!,
              ..._room.remoteParticipants.values,
            ];

            return ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.78,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF070B19).withOpacity(0.94),
                    border: Border(
                      top: BorderSide(color: const Color(0xFF00E5FF).withOpacity(0.35)),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white30,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.people_alt, color: Color(0xFF00E5FF), size: 22),
                                const SizedBox(width: 10),
                                Text(
                                  'Participants (${allParticipants.length})',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.white70),
                              onPressed: () => Navigator.pop(bottomSheetContext),
                            ),
                          ],
                        ),
                      ),
                      const Divider(color: Colors.white12, height: 1),
                      if (_effectiveIsHost)
                        StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('meetings')
                              .doc(widget.roomName.split('#').first.trim())
                              .collection('waiting_room')
                              .where('status', isEqualTo: 'pending')
                              .snapshots(),
                          builder: (ctx, snap) {
                            final docs = snap.data?.docs ?? [];
                            if (docs.isEmpty) return const SizedBox.shrink();
                            return Container(
                              margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.4)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.meeting_room_outlined, color: Colors.amber, size: 18),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Waiting Room (${docs.length})',
                                            style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13.5),
                                          ),
                                        ],
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          _decideWaitingGuest('', 'admit_all');
                                          setSheetState(() {});
                                        },
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          backgroundColor: const Color(0xFF00FFA3).withOpacity(0.18),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                        child: const Text(
                                          'Admit All',
                                          style: TextStyle(color: Color(0xFF00FFA3), fontWeight: FontWeight.bold, fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ...docs.map((doc) {
                                    final d = doc.data() as Map<String, dynamic>;
                                    final guestUid = (d['uid'] ?? doc.id).toString();
                                    final guestName = (d['name'] ?? 'Guest').toString();
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 15,
                                            backgroundColor: Colors.amber.withOpacity(0.25),
                                            child: Text(
                                              guestName.isNotEmpty ? guestName[0].toUpperCase() : 'G',
                                              style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              guestName,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w500),
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: () {
                                              _decideWaitingGuest(guestUid, 'deny');
                                              setSheetState(() {});
                                            },
                                            style: TextButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              minimumSize: Size.zero,
                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            ),
                                            child: const Text('Deny', style: TextStyle(color: Colors.redAccent, fontSize: 12.5, fontWeight: FontWeight.w600)),
                                          ),
                                          const SizedBox(width: 4),
                                          ElevatedButton(
                                            onPressed: () {
                                              _decideWaitingGuest(guestUid, 'admit');
                                              setSheetState(() {});
                                            },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFF00FFA3),
                                              foregroundColor: const Color(0xFF070B19),
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                              minimumSize: Size.zero,
                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            ),
                                            child: const Text('Admit', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            );
                          },
                        ),
                      Flexible(
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shrinkWrap: true,
                          itemCount: allParticipants.length,
                          separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1, indent: 68),
                          itemBuilder: (context, index) {
                            final p = allParticipants[index];
                            final isLocal = p == _room.localParticipant;
                            final isHost = p.identity == _room.localParticipant?.identity ? _effectiveIsHost : false;
                            final isHandRaised = _raisedHands.contains(p.identity);
                            final isMicOn = p.isMicrophoneEnabled();
                            final isVideoOn = p.isCameraEnabled();

                            return ListTile(
                              leading: Stack(
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: const Color(0xFF5C00FF).withOpacity(0.4),
                                    backgroundImage: (_getParticipantAvatar(p) != null && _getParticipantAvatar(p)!.isNotEmpty)
                                        ? NetworkImage(_getParticipantAvatar(p)!)
                                        : null,
                                    child: (_getParticipantAvatar(p) != null && _getParticipantAvatar(p)!.isNotEmpty)
                                        ? null
                                        : Text(
                                            (p.name.isNotEmpty ? p.name[0] : (isLocal ? 'Y' : 'P')).toUpperCase(),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                  ),
                                  if (isHandRaised)
                                    Positioned(
                                      bottom: 0,
                                      right: 0,
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: const BoxDecoration(
                                          color: Colors.amber,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.front_hand, size: 10, color: Colors.black),
                                      ),
                                    ),
                                ],
                              ),
                              title: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      isLocal
                                          ? '${p.name.isNotEmpty ? p.name : widget.participantName} (You)'
                                          : (p.name.isNotEmpty ? p.name : 'Participant'),
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isHost) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF00E5FF).withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.6)),
                                      ),
                                      child: const Text('Host', style: TextStyle(color: Color(0xFF00E5FF), fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ],
                              ),
                              subtitle: Row(
                                children: [
                                  Icon(
                                    isMicOn ? Icons.mic : Icons.mic_off,
                                    size: 13,
                                    color: isMicOn ? const Color(0xFF00E5FF) : Colors.redAccent,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isMicOn ? 'Active' : 'Muted',
                                    style: TextStyle(
                                      color: isMicOn ? Colors.white70 : Colors.redAccent.withOpacity(0.85),
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Icon(
                                    isVideoOn ? Icons.videocam : Icons.videocam_off,
                                    size: 13,
                                    color: isVideoOn ? const Color(0xFF00E5FF) : Colors.white38,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isVideoOn ? 'Video on' : 'Video off',
                                    style: TextStyle(
                                      color: isVideoOn ? Colors.white70 : Colors.white38,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_effectiveIsHost && !isLocal) ...[
                                    if (isMicOn)
                                      ElevatedButton.icon(
                                        onPressed: () {
                                          _muteParticipant(p.identity);
                                          setSheetState(() {});
                                        },
                                        icon: const Icon(Icons.mic_off, size: 14, color: Colors.white),
                                        label: const Text('Mute', style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red.shade700,
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                      )
                                    else
                                      OutlinedButton.icon(
                                        onPressed: () {
                                          _requestUnmute(p.identity);
                                        },
                                        icon: const Icon(Icons.mic, size: 14, color: Color(0xFF00E5FF)),
                                        label: const Text('Ask Unmute', style: TextStyle(fontSize: 11, color: Color(0xFF00E5FF), fontWeight: FontWeight.bold)),
                                        style: OutlinedButton.styleFrom(
                                          side: BorderSide(color: const Color(0xFF00E5FF).withOpacity(0.6)),
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                      ),
                                    const SizedBox(width: 4),
                                  ],
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert, color: Colors.white60, size: 20),
                                    color: const Color(0xFF131B30),
                                    onSelected: (val) {
                                      if (val == 'mute' && _effectiveIsHost) {
                                        _muteParticipant(p.identity);
                                        setSheetState(() {});
                                      } else if (val == 'unmute_request' && _effectiveIsHost) {
                                        _requestUnmute(p.identity);
                                      } else if (val == 'pin') {
                                        setState(() {
                                          _pinnedParticipant = (_pinnedParticipant == p) ? null : p;
                                        });
                                      } else if (val == 'lower_hand' && _effectiveIsHost) {
                                        setState(() {
                                          _raisedHands.remove(p.identity);
                                        });
                                        setSheetState(() {});
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      if (_effectiveIsHost && !isLocal && isMicOn)
                                        const PopupMenuItem(
                                          value: 'mute',
                                          child: Row(
                                            children: [
                                              Icon(Icons.mic_off, color: Colors.redAccent, size: 18),
                                              SizedBox(width: 8),
                                              Text('Mute Microphone', style: TextStyle(color: Colors.white)),
                                            ],
                                          ),
                                        ),
                                      if (_effectiveIsHost && !isLocal && !isMicOn)
                                        const PopupMenuItem(
                                          value: 'unmute_request',
                                          child: Row(
                                            children: [
                                              Icon(Icons.mic, color: Color(0xFF00E5FF), size: 18),
                                              SizedBox(width: 8),
                                              Text('Ask to Unmute', style: TextStyle(color: Colors.white)),
                                            ],
                                          ),
                                        ),
                                      PopupMenuItem(
                                        value: 'pin',
                                        child: Row(
                                          children: [
                                            Icon(_pinnedParticipant == p ? Icons.push_pin : Icons.push_pin_outlined, color: const Color(0xFF00E5FF), size: 18),
                                            const SizedBox(width: 8),
                                            Text(_pinnedParticipant == p ? 'Unpin Video' : 'Pin Video', style: const TextStyle(color: Colors.white)),
                                          ],
                                        ),
                                      ),
                                      if (_effectiveIsHost && isHandRaised)
                                        const PopupMenuItem(
                                          value: 'lower_hand',
                                          child: Row(
                                            children: [
                                              Icon(Icons.pan_tool_outlined, color: Colors.amber, size: 18),
                                              SizedBox(width: 8),
                                              Text('Lower Hand', style: TextStyle(color: Colors.white)),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      if (_effectiveIsHost)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          decoration: const BoxDecoration(
                            border: Border(top: BorderSide(color: Colors.white10)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(bottomSheetContext);
                                    _muteAll();
                                  },
                                  icon: const Icon(Icons.volume_off, color: Colors.white),
                                  label: const Text('Mute All Participants', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF5C00FF),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF070B19).withOpacity(0.8),
                border: Border(top: BorderSide(color: const Color(0xFF00E5FF).withOpacity(0.3))),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white30,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildOptionTile(
                      icon: Icons.copy,
                      title: 'Copy Room ID',
                      subtitle: widget.roomName,
                      onTap: () {
                        Navigator.pop(context);
                        Clipboard.setData(ClipboardData(text: widget.roomName));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Room ID copied! Share it with others to join.', style: TextStyle(color: Colors.white)),
                            backgroundColor: Color(0xFF5C00FF),
                          ),
                        );
                      },
                    ),
                    _buildOptionTile(
                      icon: _audioRouteIcon(),
                      title: 'Audio Output',
                      subtitle: 'Choose speaker, earpiece or Bluetooth',
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E5FF).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.4)),
                        ),
                        child: Text(
                          _audioRouteLabel(),
                          style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _showAudioOutputPicker();
                      },
                    ),
                    if (_effectiveIsHost)
                      _buildOptionTile(
                        icon: Icons.live_tv,
                        title: 'vMix / Live Ingest',
                        subtitle: 'Stream live RTMP feed into this meeting',
                        onTap: () {
                          Navigator.pop(context);
                          _showVmixDialog();
                        },
                      ),
                    if (_effectiveIsHost)
                      _buildOptionTile(
                        icon: Icons.mic_off,
                        title: 'Mute All Participants',
                        onTap: () {
                          Navigator.pop(context);
                          _muteAll();
                        },
                      ),
                    if (_effectiveIsHost)
                      _buildOptionTile(
                        icon: _isRoomLocked ? Icons.lock : Icons.lock_open,
                        iconColor: _isRoomLocked ? Colors.amber : const Color(0xFF00E5FF),
                        title: _isRoomLocked ? 'Unlock Meeting' : 'Lock Meeting',
                        subtitle: _isRoomLocked ? 'Room is locked to new attendees' : 'Allow attendees to join freely',
                        trailing: Switch(
                          value: _isRoomLocked,
                          activeColor: Colors.amber,
                          activeTrackColor: Colors.amber.withOpacity(0.4),
                          inactiveThumbColor: Colors.white60,
                          inactiveTrackColor: Colors.white12,
                          onChanged: (val) {
                            Navigator.pop(context);
                            _toggleRoomLock();
                          },
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _toggleRoomLock();
                        },
                      ),
                    if (_effectiveIsHost)
                      _buildOptionTile(
                        icon: Icons.admin_panel_settings_outlined,
                        iconColor: _isWaitingRoomEnabled ? const Color(0xFF00FFA3) : const Color(0xFF00E5FF),
                        title: 'Private Waiting Room',
                        subtitle: _isWaitingRoomEnabled ? 'Host approval required to join' : 'Guests can enter without approval',
                        trailing: Switch(
                          value: _isWaitingRoomEnabled,
                          activeColor: const Color(0xFF00FFA3),
                          activeTrackColor: const Color(0xFF00FFA3).withOpacity(0.4),
                          inactiveThumbColor: Colors.white60,
                          inactiveTrackColor: Colors.white12,
                          onChanged: (val) {
                            Navigator.pop(context);
                            _toggleWaitingRoom();
                          },
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _toggleWaitingRoom();
                        },
                      ),
                    _buildOptionTile(
                      icon: Icons.people_outline,
                      title: 'Participants',
                      subtitle: _effectiveIsHost && _waitingGuests.isNotEmpty
                          ? '${_room.remoteParticipants.length + 1} in room • ${_waitingGuests.length} waiting'
                          : '${_room.remoteParticipants.length + 1} in the room',
                      onTap: () {
                        Navigator.pop(context);
                        _showParticipantsSheet();
                      },
                    ),
                    if (_effectiveIsHost)
                      _buildOptionTile(
                        icon: _isRecording ? Icons.stop_circle : Icons.fiber_manual_record,
                        title: _isRecording ? 'Stop Recording' : 'Record Audio',
                        subtitle: _isRecording ? 'Recording in progress' : 'Host only',
                        iconColor: _isRecording ? Colors.redAccent : const Color(0xFF00E5FF),
                        onTap: () {
                          Navigator.pop(context);
                          _toggleRecording();
                        },
                      ),
                    _buildOptionTile(
                      icon: _isScreenSharing ? Icons.stop_screen_share : Icons.screen_share,
                      title: _isScreenSharing ? 'Stop Screen Share' : 'Share Screen',
                      onTap: () {
                        Navigator.pop(context);
                        _toggleScreenShare();
                      },
                    ),
                    _buildOptionTile(
                      icon: Icons.share,
                      title: 'Share Meeting Link',
                      onTap: () {
                        Navigator.pop(context);
                        final url = 'https://la-vie.lifechangerstouch.org/static/index.html?room=${widget.roomName}';
                        Share.share('Join my La-Vie Premium meeting via this link: $url');
                      },
                    ),
                    _buildOptionTile(
                      icon: Icons.data_saver_on,
                      iconColor: _isDataSaverMode ? const Color(0xFFF59E0B) : const Color(0xFF00E5FF),
                      title: 'Data Saver Mode',
                      subtitle: _isDataSaverMode ? 'Active: Video paused to save data' : 'Disable incoming video to conserve data',
                      trailing: Switch(
                        value: _isDataSaverMode,
                        activeColor: const Color(0xFFF59E0B),
                        activeTrackColor: const Color(0xFFF59E0B).withOpacity(0.4),
                        onChanged: (val) {
                          Navigator.pop(context);
                          _setDataSaverMode(val);
                        },
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _setDataSaverMode(!_isDataSaverMode);
                      },
                    ),
                    _buildOptionTile(
                      icon: _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                      title: _isFullScreen ? 'Exit Full Screen' : 'Full Screen Mode',
                      subtitle: _isFullScreen ? 'Show all on-screen controls' : 'Double-tap video to toggle anytime',
                      onTap: () {
                        Navigator.pop(context);
                        _toggleFullScreen();
                      },
                    ),
                    _buildOptionTile(
                      icon: Icons.picture_in_picture_alt,
                      title: 'Picture-in-Picture',
                      subtitle: 'Minimize call to floating overlay window',
                      onTap: () {
                        Navigator.pop(context);
                        SimplePip().enterPipMode();
                      },
                    ),
                    _buildOptionTile(
                      icon: Icons.settings_outlined,
                      title: 'Settings',
                      onTap: () {
                        Navigator.pop(context);
                        _showSettingsDialog();
                      },
                    ),
                    const SizedBox(height: 16),
                ],
              ),
            ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _setDataSaverMode(bool enable) async {
    setState(() {
      _isDataSaverMode = enable;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('dataSaverMode', enable);
    } catch (_) {}

    // Unsubscribe or re-subscribe from all remote video tracks at the network level
    if (_isRoomInitialized) {
      for (final p in _room.remoteParticipants.values) {
        for (final pub in p.videoTrackPublications) {
          try {
            if (enable) {
              pub.unsubscribe();
            } else {
              pub.subscribe();
            }
          } catch (e) {
            debugPrint('[DataSaver] Error setting track subscription: $e');
          }
        }
      }
    }

    if (enable && !_isVideoOff) {
      _toggleCamera(); // Turn off local camera automatically
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data Saver enabled: video streaming paused to conserve data.'),
            backgroundColor: Color(0xFFF59E0B),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } else if (!enable && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Data Saver disabled: full video streaming resumed.'),
          backgroundColor: Color(0xFF10B981),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _showSettingsDialog() {
    String localVideoQuality = 'Adaptive'; // Default value for dialog
    bool localNoiseCancellation = true; // Default value for dialog

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF070B19),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: const Color(0xFF00E5FF).withOpacity(0.3)),
              ),
              title: const Row(
                children: [
                  Icon(Icons.settings, color: Color(0xFF00E5FF)),
                  SizedBox(width: 8),
                  Text('Room Settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.videocam, color: Colors.white70),
                    title: const Text('Video Quality', style: TextStyle(color: Colors.white)),
                    subtitle: Text(localVideoQuality, style: const TextStyle(color: Colors.white54)),
                    trailing: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: const Color(0xFF070B19),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                        ),
                        builder: (context) {
                          return SafeArea(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: ['Adaptive', '720p', '1080p'].map((quality) {
                                return ListTile(
                                  title: Text(quality, style: const TextStyle(color: Colors.white)),
                                  trailing: localVideoQuality == quality
                                      ? const Icon(Icons.check, color: Color(0xFF00E5FF))
                                      : null,
                                  onTap: () {
                                    setState(() => localVideoQuality = quality);
                                    Navigator.pop(context);
                                  },
                                );
                              }).toList(),
                            ),
                          );
                        },
                      );
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.security, color: Colors.white70),
                    title: const Text('End-to-End Encryption', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Enabled', style: TextStyle(color: Colors.green)),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('E2EE is locked on for all Premium meetings.')),
                      );
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.mic, color: Colors.white70),
                    title: const Text('Noise Cancellation', style: TextStyle(color: Colors.white)),
                    trailing: Switch(
                      value: localNoiseCancellation,
                      onChanged: (val) => setState(() => localNoiseCancellation = val),
                      activeColor: const Color(0xFF00E5FF),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.data_saver_on, color: Colors.white70),
                    title: const Text('Data Saver Mode', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Disables incoming video', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    trailing: Switch(
                      value: _isDataSaverMode,
                      onChanged: (val) {
                        setState(() {
                          _isDataSaverMode = val;
                        });
                        _setDataSaverMode(val);
                      },
                      activeColor: const Color(0xFF00E5FF),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close', style: TextStyle(color: Color(0xFF00E5FF))),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    Widget? trailing,
    Color? iconColor,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: (iconColor ?? const Color(0xFF00E5FF)).withOpacity(0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: iconColor ?? const Color(0xFF00E5FF)),
      ),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      subtitle: subtitle != null ? Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.5))) : null,
      trailing: trailing ?? const Icon(Icons.arrow_forward_ios, color: Colors.white30, size: 16),
    );
  }

  void _showChat() {
    setState(() {
      _unreadCount = 0;
      _isChatOpen = true;
    });

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                height: MediaQuery.of(context).size.height * 0.6,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF070B19).withOpacity(0.8),
                  border: Border(top: BorderSide(color: const Color(0xFF00E5FF).withOpacity(0.3))),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white30,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'In-Call Messages',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ValueListenableBuilder<List<ChatMessage>>(
                        valueListenable: _messagesNotifier,
                        builder: (context, messages, _) {
                          if (messages.isEmpty) {
                            return Center(
                              child: Text(
                                'No messages yet.',
                                style: TextStyle(color: Colors.white.withOpacity(0.5)),
                              ),
                            );
                          }
                          return ListView.builder(
                            itemCount: messages.length,
                            itemBuilder: (context, index) {
                              final msg = messages[index];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: msg.isLocal ? const Color(0xFF00E5FF).withOpacity(0.1) : Colors.white.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: msg.isLocal ? const Color(0xFF00E5FF).withOpacity(0.3) : Colors.transparent,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      msg.sender,
                                      style: TextStyle(
                                        color: msg.isLocal ? const Color(0xFF00E5FF) : Colors.white54,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      msg.message,
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    // Chat Input
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _chatController,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: 'Send a message...',
                                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () async {
                              final text = _chatController.text.trim();
                              if (text.isEmpty) return;
                              
                              _chatController.clear();
                              
                              final data = utf8.encode(text);
                              try {
                                await _room.localParticipant?.publishData(data);
                                final newMsg = ChatMessage(
                                  sender: 'Me',
                                  message: text,
                                  timestamp: DateTime.now(),
                                  isLocal: true,
                                );
                                _messagesNotifier.value = List.from(_messagesNotifier.value)..add(newMsg);
                              } catch (e) {
                                // ignore
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: Color(0xFF00E5FF),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.send, color: Color(0xFF070B19), size: 20),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ).whenComplete(() {
      setState(() {
        _isChatOpen = false;
      });
    });
  }

  @override
  Widget _buildPipVideo() {
    final allParticipants = <Participant>[
      if (_room.localParticipant != null) _room.localParticipant!,
      ..._room.remoteParticipants.values,
    ];

    Participant? primary = _pinnedParticipant;
    if (primary == null || !allParticipants.contains(primary)) {
      if (_activeSpeakerIdentity != null) {
        primary = allParticipants.where((p) => p.identity == _activeSpeakerIdentity).firstOrNull;
      }
      primary ??= allParticipants.where((p) => p != _room.localParticipant).firstOrNull;
      primary ??= _room.localParticipant;
    }

    if (primary == null) return const Center(child: CircularProgressIndicator());

    final isLocal = primary == _room.localParticipant;
    if (isLocal && _isScreenSharing) {
      return Container(
        color: const Color(0xFF131728),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.screen_share_rounded, color: Color(0xFF00E5FF), size: 30),
              SizedBox(height: 4),
              Text(
                'Sharing Screen',
                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );
    }

    final videoTrack = primary.videoTrackPublications.firstOrNull?.track;
    if (videoTrack != null && !_isDataSaverMode) {
      return VideoTrackRenderer(videoTrack as VideoTrack);
    }
    return Container(
      color: Colors.black,
      child: const Center(
        child: Icon(Icons.person, color: Colors.white, size: 50),
      ),
    );
  }

  void _showPollBottomSheet() {
    if (_activePoll == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2C),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Poll', style: TextStyle(color: Color(0xFF00E5FF), fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Text(_activePoll!['question'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 16)),
              const SizedBox(height: 20),
              ...((_activePoll!['options'] as List<dynamic>? ?? []).asMap().entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white10,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    onPressed: () {
                      final payload = jsonEncode({'type': 'poll_vote', 'optionIdx': entry.key});
                      _room.localParticipant?.publishData(utf8.encode(payload), topic: 'chat');
                      Navigator.pop(context);
                      setState(() { _activePoll = null; });
                    },
                    child: Text(entry.value.toString()),
                  ),
                );
              }).toList()),
            ],
          ),
        );
      },
    );
  }

  void _showQaBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2C),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Q&A', style: TextStyle(color: Color(0xFF00E5FF), fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  if (_qaQuestions.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20.0),
                      child: Text('No questions yet.', style: TextStyle(color: Colors.white54)),
                    ),
                  ..._qaQuestions.map((q) {
                    return ListTile(
                      title: Text(q['text'] ?? '', style: const TextStyle(color: Colors.white)),
                      subtitle: Text(q['author'] ?? 'Anonymous', style: const TextStyle(color: Colors.white54)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${q['upvotes'] ?? 0}', style: const TextStyle(color: Colors.white)),
                          IconButton(
                            icon: const Icon(Icons.thumb_up, color: Color(0xFF00E5FF)),
                            onPressed: () {
                              final payload = jsonEncode({'type': 'qa_upvote', 'questionId': q['id']});
                              _room.localParticipant?.publishData(utf8.encode(payload), topic: 'chat');
                              setModalState(() {
                                q['upvotes'] = (q['upvotes'] ?? 0) + 1;
                              });
                            },
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Text('Close'),
                  )
                ],
              ),
            );
          }
        );
      },
    );
  }

  Widget _buildQaPopup() {
    if (!_showQaPopup || _qaQuestions.isEmpty) return const SizedBox();
    final latestQ = _qaQuestions.first;
    return Positioned(
      top: 100,
      left: 20,
      right: 20,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2C).withOpacity(0.9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF00E5FF), width: 1),
          ),
          child: Row(
            children: [
              const Icon(Icons.question_answer, color: Color(0xFF00E5FF)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('New Q&A: ${latestQ['author'] ?? 'Anonymous'}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    Text(latestQ['text'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 14)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () {
                  setState(() {
                    _showQaPopup = false;
                  });
                },
              )
            ],
          ),
        ),
      ),
    );
  }



  Widget _buildAlreadyInMeetingView(AlreadyInMeetingException conflict) {
    final activeRoomName = conflict.activeRoom.isNotEmpty ? conflict.activeRoom : 'Current Meeting';
    final targetRoomName = conflict.targetRoom.isNotEmpty ? conflict.targetRoom : widget.roomName;

    return Scaffold(
      backgroundColor: const Color(0xFF070B19),
      body: Stack(
        children: [
          // Ambient background glow
          Positioned(
            top: 100,
            left: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF5C00FF).withOpacity(0.25),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF5C00FF).withOpacity(0.3),
                    blurRadius: 100,
                    spreadRadius: 20,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 100,
            right: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF00E5FF).withOpacity(0.2),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00E5FF).withOpacity(0.25),
                    blurRadius: 100,
                    spreadRadius: 20,
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A).withOpacity(0.8),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: const Color(0xFF00E5FF).withOpacity(0.3),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 30,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Glowing Header Badge
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF00E5FF).withOpacity(0.12),
                              border: Border.all(
                                color: const Color(0xFF00E5FF).withOpacity(0.4),
                                width: 2,
                              ),
                            ),
                            child: const Icon(
                              Icons.phone_in_talk_rounded,
                              size: 40,
                              color: Color(0xFF00E5FF),
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Active Meeting in Progress',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'You are already participating in another conference call.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.65),
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 24),
                          
                          // Current Meeting Box
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFF5C00FF).withOpacity(0.4),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF5C00FF).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.meeting_room_rounded, color: Color(0xFF9D65FF), size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Current Meeting',
                                        style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        activeRoomName,
                                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text('ACTIVE', style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Target Meeting Box
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFF00E5FF).withOpacity(0.4),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00E5FF).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.arrow_forward_rounded, color: Color(0xFF00E5FF), size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'New Meeting To Join',
                                        style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        targetRoomName,
                                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),

                          // Action 1: Leave & Switch
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00E5FF),
                                foregroundColor: const Color(0xFF070B19),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () => _connectToRoom(force: true),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.swap_horiz_rounded, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'Leave & Join New Meeting',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Action 2: Return to Current Meeting
                          if (conflict.activeRoom.isNotEmpty)
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: BorderSide(color: const Color(0xFF5C00FF).withOpacity(0.6), width: 1.5),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                onPressed: () {
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => VideoRoomScreen(
                                        roomName: conflict.activeRoom,
                                        participantName: widget.participantName,
                                      ),
                                    ),
                                  );
                                },
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.arrow_back_rounded, size: 18, color: Color(0xFF9D65FF)),
                                    SizedBox(width: 8),
                                    Text(
                                      'Return to Current Meeting',
                                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          const SizedBox(height: 8),

                          // Action 3: Cancel
                          TextButton(
                            onPressed: () {
                              if (Navigator.canPop(context)) {
                                Navigator.pop(context);
                              }
                            },
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget build(BuildContext context) {
    if (_isFullScreen) {
      return _buildFullScreenView();
    }

    if (_conflictException != null) {
      return _buildAlreadyInMeetingView(_conflictException!);
    }

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF070B19),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF))),
      );
    }

    if (_error != null) {
      final errorInfo = ErrorUtils.parseMeetingError(_error);
      return Scaffold(
        backgroundColor: const Color(0xFF070B19),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: errorInfo.iconColor.withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: errorInfo.iconColor.withOpacity(0.4),
                    ),
                  ),
                  child: Icon(
                    errorInfo.icon,
                    color: errorInfo.iconColor,
                    size: 48,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  errorInfo.title,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  errorInfo.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: 28),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => _exitMeetingScreen(),
                      child: const Text('Return to Dashboard'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E5FF),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => _connectToRoom(),
                      child: const Text('Retry Connection', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_isWaitingForHostApproval) {
      return Scaffold(
        backgroundColor: const Color(0xFF070B19),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withOpacity(0.92),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: (_isDeniedByHost ? Colors.redAccent : const Color(0xFF00E5FF)).withOpacity(0.35),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: (_isDeniedByHost ? Colors.redAccent : const Color(0xFF00E5FF)).withOpacity(0.14),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isDeniedByHost ? Icons.block_rounded : Icons.admin_panel_settings_outlined,
                          color: _isDeniedByHost ? Colors.redAccent : const Color(0xFF00E5FF),
                          size: 46,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        _displayMeetingTitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: (_isDeniedByHost ? Colors.redAccent : Colors.amber).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _isDeniedByHost ? 'ACCESS DECLINED' : 'WAITING FOR HOST APPROVAL',
                          style: TextStyle(
                            color: _isDeniedByHost ? Colors.redAccent : Colors.amber,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _waitingRoomMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.45),
                      ),
                      if (!_isDeniedByHost) ...[
                        const SizedBox(height: 22),
                        const SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF00E5FF)),
                        ),
                      ],
                      const SizedBox(height: 26),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => _exitMeetingScreen(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: const BorderSide(color: Colors.white24),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Text(_isDeniedByHost ? 'Return to Dashboard' : 'Leave Waiting Room'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        try {
          bool isPipSupported = await SimplePip.isPipAvailable;
          if (isPipSupported) {
            SimplePip().enterPipMode(aspectRatio: const (16, 9));
          } else {
            if (context.mounted) Navigator.of(context).pop();
          }
        } catch (e) {
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: PipWidget(
        pipChild: Scaffold(
          backgroundColor: const Color(0xFF070B19),
          body: _buildPipVideo(),
        ),
      child: Scaffold(
        backgroundColor: const Color(0xFF070B19),
        body: ReactionParticleOverlay(
          key: _reactionOverlayKey,
          child: Stack(
            children: [
          // Background Glows
          Positioned(
            top: 200,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF5C00FF).withOpacity(0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
                  child: Row(
                    children: [
                      // Left: Minimize (PiP) + Participant Count Dropdown
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () => SimplePip().enterPipMode(),
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white12),
                              ),
                              child: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                          PopupMenuButton<String>(
                            color: const Color(0xFF070B19).withOpacity(0.95),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: const Color(0xFF00E5FF).withOpacity(0.3)),
                            ),
                            offset: const Offset(0, 40),
                            icon: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.people, color: Color(0xFF00E5FF), size: 15),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${_room.remoteParticipants.length + (_room.localParticipant != null ? 1 : 0)}',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                            itemBuilder: (context) {
                              final List<Participant> allParticipants = _room.remoteParticipants.values.cast<Participant>().toList();
                              if (_room.localParticipant != null) {
                                allParticipants.insert(0, _room.localParticipant!);
                              }
                              return allParticipants.map((p) {
                                final isLocal = p == _room.localParticipant;
                                return PopupMenuItem<String>(
                                  value: p.identity,
                                  child: Text(
                                    (p.name.isNotEmpty ? p.name : p.identity) + (isLocal ? ' (You)' : ''),
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                );
                              }).toList();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),

                      // Center: Meeting Title & Clean Subtitle
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (_isRecording)
                                  Container(
                                    margin: const EdgeInsets.only(right: 6),
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.redAccent,
                                          blurRadius: 6,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                  ),
                                Flexible(
                                  child: Text(
                                    _displayMeetingTitle.isNotEmpty ? _displayMeetingTitle : widget.roomName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Color(0xFF00E5FF),
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                                if (_isRoomLocked) ...[
                                  const SizedBox(width: 5),
                                  const Icon(Icons.lock, color: Colors.amber, size: 12),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _isWaitingForScheduledStart ? Icons.hourglass_bottom_rounded : Icons.schedule,
                                  color: _isWaitingForScheduledStart ? Colors.amber : Colors.white54,
                                  size: 11,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  _meetingDurationText,
                                  style: TextStyle(
                                    color: _isWaitingForScheduledStart ? Colors.amber : Colors.white70,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                                if (_isDataSaverMode) ...[
                                  const SizedBox(width: 6),
                                  GestureDetector(
                                    onTap: () => _setDataSaverMode(false),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF59E0B).withOpacity(0.18),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.5), width: 0.8),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.bolt, color: Color(0xFFF59E0B), size: 10),
                                          SizedBox(width: 2),
                                          Text(
                                            'SAVER',
                                            style: TextStyle(
                                              color: Color(0xFFF59E0B),
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Right: Quick Actions (Audio Route + Flip Camera)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: _showAudioOutputPicker,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Icon(
                                _audioRouteIcon(),
                                color: const Color(0xFF00E5FF),
                                size: 19,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: _flipCamera,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Icon(
                                Icons.flip_camera_ios,
                                color: _isVideoOff ? Colors.white38 : const Color(0xFF00E5FF),
                                size: 19,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Host Live Waiting Room Knock Alert Banner
                if (_effectiveIsHost && _waitingGuests.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A).withOpacity(0.92),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.amber.withOpacity(0.6), width: 1.2),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 12),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.18),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.meeting_room_outlined, color: Colors.amber, size: 18),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: GestureDetector(
                              onTap: _showParticipantsSheet,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${_waitingGuests.first['name']} wants to join',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    _waitingGuests.length > 1
                                        ? '+${_waitingGuests.length - 1} more waiting • Tap to review all'
                                        : 'Waiting Room • Approve entry',
                                    style: const TextStyle(color: Colors.amber, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => _decideWaitingGuest(_waitingGuests.first['uid'].toString(), 'deny'),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('Deny', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                          const SizedBox(width: 4),
                          ElevatedButton(
                            onPressed: () => _decideWaitingGuest(_waitingGuests.first['uid'].toString(), 'admit'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00FFA3),
                              foregroundColor: const Color(0xFF070B19),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('Admit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Video Grid
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: _buildVideoGrid(),
                  ),
                ),
                
                // Glassmorphic FAB
                Padding(
                  padding: const EdgeInsets.only(left: 24.0, right: 24.0, bottom: 30.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(40),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(40),
                          border: Border.all(color: Colors.white.withOpacity(0.15)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            // Mic Button
                            GestureDetector(
                              onTap: _toggleMute,
                              child: Container(
                                decoration: BoxDecoration(
                                  boxShadow: _isMuted ? [] : [
                                    BoxShadow(
                                      color: const Color(0xFF00E5FF).withOpacity(0.15),
                                      blurRadius: 4,
                                      spreadRadius: 0,
                                    )
                                  ],
                                ),
                                child: Icon(
                                  _isMuted ? Icons.mic_off : Icons.mic_none,
                                  color: _isMuted ? Colors.white54 : const Color(0xFF00E5FF),
                                  size: 28,
                                ),
                              ),
                            ),
                            // Video Button
                            GestureDetector(
                              onTap: _toggleCamera,
                              child: Container(
                                decoration: BoxDecoration(
                                  boxShadow: _isVideoOff ? [] : [
                                    BoxShadow(
                                      color: const Color(0xFF00E5FF).withOpacity(0.15),
                                      blurRadius: 4,
                                      spreadRadius: 0,
                                    )
                                  ],
                                ),
                                child: Icon(
                                  _isVideoOff ? Icons.videocam_off : Icons.videocam_outlined,
                                  color: _isVideoOff ? Colors.white54 : const Color(0xFF00E5FF),
                                  size: 28,
                                ),
                              ),
                            ),
                            // Chat Button
                            GestureDetector(
                              onTap: _showChat,
                              child: Container(
                                decoration: BoxDecoration(
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF00E5FF).withOpacity(0.15),
                                      blurRadius: 4,
                                      spreadRadius: 0,
                                    )
                                  ],
                                ),
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    const Icon(
                                      Icons.chat_bubble_outline,
                                      color: Color(0xFF00E5FF),
                                      size: 26,
                                    ),
                                    if (_unreadCount > 0)
                                      Positioned(
                                        top: -6,
                                        right: -8,
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF00E5FF),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Text(
                                            '$_unreadCount',
                                            style: const TextStyle(
                                              color: Color(0xFF070B19),
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      )
                                  ],
                                ),
                              ),
                            ),
                            // Hand Raise Button
                            GestureDetector(
                              onTap: _toggleHandRaise,
                              child: Container(
                                decoration: BoxDecoration(
                                  boxShadow: _raisedHands.contains(_room.localParticipant?.identity) ? [
                                    BoxShadow(
                                      color: const Color(0xFF00E5FF).withOpacity(0.15),
                                      blurRadius: 4,
                                      spreadRadius: 0,
                                    )
                                  ] : [],
                                ),
                                child: Icon(
                                  _raisedHands.contains(_room.localParticipant?.identity) ? Icons.front_hand : Icons.front_hand_outlined,
                                  color: _raisedHands.contains(_room.localParticipant?.identity) ? const Color(0xFF00E5FF) : Colors.white54,
                                  size: 26,
                                ),
                              ),
                            ),
                            // Reactions Button
                            GestureDetector(
                              onTap: _showReactionsBottomSheet,
                              child: Container(
                                decoration: const BoxDecoration(),
                                child: const Icon(
                                  Icons.add_reaction_outlined,
                                  color: Color(0xFF00E5FF),
                                  size: 26,
                                ),
                              ),
                            ),
                            // More Options Button
                            GestureDetector(
                              onTap: _showMoreOptions,
                              child: Container(
                                decoration: const BoxDecoration(),
                                child: const Icon(
                                  Icons.more_vert,
                                  color: Color(0xFF00E5FF),
                                  size: 26,
                                ),
                              ),
                            ),
                            // Subtle Separator
                            Container(
                              width: 1,
                              height: 24,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              color: Colors.white.withOpacity(0.15),
                            ),
                            // End Call Button (Solid Red with Call End Icon)
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _endCall,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF3B30),
                                  borderRadius: BorderRadius.circular(22),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFFF3B30).withOpacity(0.45),
                                      blurRadius: 12,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.call_end,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Q&A Popup Overlay
          _buildQaPopup(),
        ],
      ),
      ),
      ),
    ));
  }

  Widget _buildNetworkIndicator(Participant p, {double height = 10.0}) {
    final quality = _connectionQualities[p.identity] ?? p.connectionQuality;

    int activeBars = 3;
    Color activeColor = const Color(0xFF00FFA3);
    String label = 'Excellent connection';

    switch (quality) {
      case ConnectionQuality.excellent:
        activeBars = 3;
        activeColor = const Color(0xFF00FFA3);
        label = 'Excellent connection';
        break;
      case ConnectionQuality.good:
        activeBars = 2;
        activeColor = const Color(0xFF00E5FF);
        label = 'Good connection';
        break;
      case ConnectionQuality.poor:
        activeBars = 1;
        activeColor = const Color(0xFFFFB800);
        label = 'Weak / unstable connection';
        break;
      case ConnectionQuality.lost:
        activeBars = 0;
        activeColor = const Color(0xFFFF4B4B);
        label = 'Connection lost';
        break;
      case ConnectionQuality.unknown:
        activeBars = 3;
        activeColor = const Color(0xFF00FFA3).withOpacity(0.6);
        label = 'Connection stable';
        break;
    }

    return Tooltip(
      message: label,
      preferBelow: false,
      child: Padding(
        padding: const EdgeInsets.only(right: 4.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Bar 1 (Shortest)
            Container(
              width: 2.2,
              height: height * 0.45,
              decoration: BoxDecoration(
                color: activeBars >= 1 ? activeColor : Colors.white24,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            const SizedBox(width: 1.5),
            // Bar 2 (Medium)
            Container(
              width: 2.2,
              height: height * 0.72,
              decoration: BoxDecoration(
                color: activeBars >= 2 ? activeColor : Colors.white24,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            const SizedBox(width: 1.5),
            // Bar 3 (Tallest)
            Container(
              width: 2.2,
              height: height,
              decoration: BoxDecoration(
                color: activeBars >= 3 ? activeColor : Colors.white24,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParticipantVideo(
    Participant p, {
    bool isPrimary = false,
    bool isThumbnail = false,
  }) {
    final screenTrackPub = p.videoTrackPublications.where((pub) => pub.source == TrackSource.screenShareVideo).firstOrNull;
    final cameraTrackPub = p.videoTrackPublications.where((pub) => pub.source == TrackSource.camera).firstOrNull;
    final trackPub = screenTrackPub ?? cameraTrackPub ?? p.videoTrackPublications.firstOrNull;
    final track = trackPub?.track;
    final isMuted = trackPub?.muted ?? true;
    final isLocal = p == _room.localParticipant;
    final forceAvatar = isLocal && _isVideoOff;
    final showAvatar = forceAvatar || isMuted || track == null || (_isDataSaverMode && !isLocal);
    final initial = p.name.isNotEmpty ? p.name.substring(0, 1).toUpperCase() : 'U';
    final isActiveSpeaker = p.identity == _activeSpeakerIdentity;
    final isPinned = _pinnedParticipant == p;

    final avatarSize = isThumbnail ? 46.0 : (isPrimary ? 90.0 : 64.0);
    final fontSize = isThumbnail ? 20.0 : (isPrimary ? 36.0 : 26.0);

    return GestureDetector(
      onTap: () {
        if (isThumbnail) {
          setState(() {
            _pinnedParticipant = p;
          });
        }
      },
      onDoubleTap: () => _toggleFullScreen(participant: p),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(isThumbnail ? 16 : 20),
          border: Border.all(
            color: isActiveSpeaker
                ? const Color(0xFF00E5FF)
                : (isPinned ? const Color(0xFF5C00FF) : Colors.white.withOpacity(0.12)),
            width: isActiveSpeaker ? 2.0 : 1.0,
          ),
          boxShadow: isActiveSpeaker
              ? [
                  BoxShadow(
                    color: const Color(0xFF00E5FF).withOpacity(0.35),
                    blurRadius: 14,
                    spreadRadius: 1.5,
                  )
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  )
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(isThumbnail ? 15 : 19),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background (Video, Presenter Card, or Avatar)
              Container(
                color: const Color(0xFF131728),
                child: (isLocal && _isScreenSharing)
                    ? _buildLocalScreenSharePresenterTile(isThumbnail: isThumbnail)
                    : (showAvatar
                        ? _buildParticipantAvatarWidget(p, avatarSize, fontSize, initial)
                        : VideoTrackRenderer(track as VideoTrack)),
              ),

              // Bottom Name & Status Pill
              Positioned(
                bottom: isThumbnail ? 6 : 10,
                left: isThumbnail ? 6 : 10,
                right: isThumbnail ? 6 : null,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isThumbnail ? 6 : 8,
                        vertical: isThumbnail ? 3 : 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.65),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildNetworkIndicator(p, height: isThumbnail ? 8.0 : 10.0),
                          if (_effectiveIsHost && p is RemoteParticipant)
                            GestureDetector(
                              onTap: () => _muteParticipant(p.identity),
                              child: Icon(
                                p.isMicrophoneEnabled() ? Icons.mic : Icons.mic_off,
                                color: p.isMicrophoneEnabled() ? const Color(0xFF00E5FF) : Colors.redAccent,
                                size: isThumbnail ? 12 : 14,
                              ),
                            )
                          else
                            Icon(
                              p.isMicrophoneEnabled() ? Icons.mic : Icons.mic_off,
                              color: p.isMicrophoneEnabled() ? const Color(0xFF00E5FF) : Colors.redAccent,
                              size: isThumbnail ? 12 : 14,
                            ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              isLocal ? 'You' : (p.name.isNotEmpty ? p.name : 'Participant'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: isThumbnail ? 10 : 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Top Right Actions (Pin button, Hand Raise indicator)
              Positioned(
                top: 8,
                right: 8,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_effectiveIsHost && p is RemoteParticipant)
                      GestureDetector(
                        onTap: () {
                          if (p.isMicrophoneEnabled()) {
                            _muteParticipant(p.identity);
                          } else {
                            _requestUnmute(p.identity);
                          }
                        },
                        child: Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: p.isMicrophoneEnabled()
                                ? const Color(0xFFFF3B30).withOpacity(0.85)
                                : Colors.black.withOpacity(0.55),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: p.isMicrophoneEnabled() ? Colors.redAccent : Colors.white24,
                            ),
                          ),
                          child: Icon(
                            p.isMicrophoneEnabled() ? Icons.mic : Icons.mic_off,
                            color: Colors.white,
                            size: 13,
                          ),
                        ),
                      ),
                    if (_raisedHands.contains(p.identity))
                      Container(
                        margin: const EdgeInsets.only(right: 4),
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade700,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 4),
                          ],
                        ),
                        child: const Icon(Icons.front_hand, color: Colors.white, size: 12),
                      ),
                    if (!isThumbnail)
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            if (_pinnedParticipant == p) {
                              _pinnedParticipant = null;
                            } else {
                              _pinnedParticipant = p;
                            }
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: _pinnedParticipant == p
                                ? const Color(0xFF00E5FF)
                                : Colors.black.withOpacity(0.55),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Icon(
                            _pinnedParticipant == p ? Icons.push_pin : Icons.push_pin_outlined,
                            color: _pinnedParticipant == p ? Colors.black : Colors.white70,
                            size: 13,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Floating Reactions
              if (_activeReactions.containsKey(p.identity))
                Positioned(
                  bottom: 24,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 1000),
                      builder: (context, value, child) {
                        return Transform.translate(
                          offset: Offset(0, -70 * value),
                          child: Opacity(
                            opacity: 1.0 - value,
                            child: Text(
                              _activeReactions[p.identity]!,
                              style: TextStyle(
                                fontSize: isThumbnail ? 28 : 42,
                                shadows: const [
                                  Shadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 2))
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoGrid() {
    final allParticipants = <Participant>[
      if (_room.localParticipant != null) _room.localParticipant!,
      ..._room.remoteParticipants.values,
    ];

    if (allParticipants.isEmpty) {
      return const Center(
        child: Text('Connecting to room...', style: TextStyle(color: Colors.white54)),
      );
    }

    // --- CASE 1: A participant is pinned (Spotlight Mode) ---
    if (_pinnedParticipant != null && allParticipants.contains(_pinnedParticipant)) {
      final primary = _pinnedParticipant!;
      final thumbnails = allParticipants.where((p) => p != primary).toList();

      return Column(
        children: [
          // Spotlight Hero Card
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10.0),
              child: _buildParticipantVideo(primary, isPrimary: true),
            ),
          ),
          // Active Speaker & Unpin status
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.push_pin, color: Color(0xFF00E5FF), size: 14),
                const SizedBox(width: 4),
                Text(
                  primary == _room.localParticipant ? 'You (Pinned)' : '${primary.name.isNotEmpty ? primary.name : "Participant"} (Pinned)',
                  style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() => _pinnedParticipant = null),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Text('Unpin', style: TextStyle(color: Colors.white, fontSize: 11)),
                  ),
                ),
              ],
            ),
          ),
          // Thumbnails row
          if (thumbnails.isNotEmpty)
            SizedBox(
              height: 105,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                itemCount: thumbnails.length,
                itemBuilder: (context, index) {
                  final p = thumbnails[index];
                  return Container(
                    width: 105,
                    margin: const EdgeInsets.only(right: 8, bottom: 4),
                    child: _buildParticipantVideo(p, isThumbnail: true),
                  );
                },
              ),
            ),
        ],
      );
    }

    // --- CASE 2: Single Participant (Full View) ---
    if (allParticipants.length == 1) {
      return _buildParticipantVideo(allParticipants.first, isPrimary: true);
    }

    // --- CASE 3: 2 Participants (Split 50/50 vertical) ---
    if (allParticipants.length == 2) {
      return Column(
        children: allParticipants.map((p) {
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: _buildParticipantVideo(p, isPrimary: false),
            ),
          );
        }).toList(),
      );
    }

    // --- CASE 4: 3 or 4 Participants (2x2 Balanced Grid, No scrolling needed) ---
    if (allParticipants.length <= 4) {
      return GridView.count(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.88,
        physics: const NeverScrollableScrollPhysics(),
        children: allParticipants.map((p) {
          return _buildParticipantVideo(p, isPrimary: false);
        }).toList(),
      );
    }

    // --- CASE 5: 5+ Participants (2-column Grid with Smooth Vertical Scroll) ---
    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.88,
      ),
      itemCount: allParticipants.length,
      itemBuilder: (context, index) {
        return _buildParticipantVideo(allParticipants[index], isPrimary: false);
      },
    );
  }

  // --- FULL SCREEN LANDSCAPE IMMERSIVE VIEW ---
  Widget _buildFullScreenView() {
    final allParticipants = <Participant>[
      if (_room.localParticipant != null) _room.localParticipant!,
      ..._room.remoteParticipants.values,
    ];
    Participant? primary = _pinnedParticipant;
    if (primary == null || !allParticipants.contains(primary)) {
      if (_activeSpeakerIdentity != null) {
        primary = allParticipants.where((p) => p.identity == _activeSpeakerIdentity).firstOrNull;
      }
      primary ??= allParticipants.firstOrNull;
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _onFullScreenTap,
        onDoubleTap: () => _toggleFullScreen(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video stream full bleed
            if (primary != null)
              _buildFullScreenVideo(primary)
            else
              const Center(child: Text('Waiting for video...', style: TextStyle(color: Colors.white54))),

            // Floating Top Bar
            AnimatedOpacity(
              opacity: _showFullScreenControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 250),
              child: IgnorePointer(
                ignoring: !_showFullScreenControls,
                child: SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (primary != null) ...[
                                  _buildNetworkIndicator(primary, height: 11.0),
                                  const SizedBox(width: 6),
                                ],
                                const Icon(Icons.videocam, color: Color(0xFF00E5FF), size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  primary != null
                                      ? (primary == _room.localParticipant
                                          ? 'You'
                                          : (primary.name.isNotEmpty ? primary.name : 'Participant'))
                                      : widget.roomName,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                const SizedBox(width: 8),
                                Container(width: 1, height: 12, color: Colors.white24),
                                const SizedBox(width: 8),
                                const Icon(Icons.schedule, color: Color(0xFF00E5FF), size: 12),
                                const SizedBox(width: 3),
                                Text(
                                  _meetingDurationText,
                                  style: const TextStyle(
                                    color: Color(0xFF00E5FF),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                    fontFeatures: [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: _showAudioOutputPicker,
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  margin: const EdgeInsets.only(right: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.6),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Icon(
                                    _audioRouteIcon(),
                                    color: const Color(0xFF00E5FF),
                                    size: 20,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: _flipCamera,
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  margin: const EdgeInsets.only(right: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.6),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: const Icon(Icons.flip_camera_ios, color: Color(0xFF00E5FF), size: 20),
                                ),
                              ),
                              GestureDetector(
                                onTap: () => _toggleFullScreen(),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00E5FF).withOpacity(0.2),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: const Color(0xFF00E5FF)),
                                  ),
                                  child: const Icon(Icons.fullscreen_exit, color: Color(0xFF00E5FF), size: 22),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Floating Bottom Controls
            AnimatedOpacity(
              opacity: _showFullScreenControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 250),
              child: IgnorePointer(
                ignoring: !_showFullScreenControls,
                child: SafeArea(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.65),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(color: Colors.white.withOpacity(0.15)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(_isMuted ? Icons.mic_off : Icons.mic,
                                      color: _isMuted ? Colors.white54 : const Color(0xFF00E5FF)),
                                  onPressed: _toggleMute,
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: Icon(_isVideoOff ? Icons.videocam_off : Icons.videocam,
                                      color: _isVideoOff ? Colors.white54 : const Color(0xFF00E5FF)),
                                  onPressed: _toggleCamera,
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.chat_bubble_outline, color: Color(0xFF00E5FF)),
                                  onPressed: _showChat,
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.front_hand, color: Color(0xFF00E5FF)),
                                  onPressed: _toggleHandRaise,
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.call_end, color: Colors.white),
                                  style: IconButton.styleFrom(backgroundColor: Colors.red),
                                  onPressed: _endCall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullScreenVideo(Participant p) {
    final screenTrackPub = p.videoTrackPublications.where((pub) => pub.source == TrackSource.screenShareVideo).firstOrNull;
    final cameraTrackPub = p.videoTrackPublications.where((pub) => pub.source == TrackSource.camera).firstOrNull;
    final trackPub = screenTrackPub ?? cameraTrackPub ?? p.videoTrackPublications.firstOrNull;
    final track = trackPub?.track;
    final isMuted = trackPub?.muted ?? true;
    final isLocal = p == _room.localParticipant;
    if (isLocal && _isScreenSharing) {
      return _buildLocalScreenSharePresenterTile(isThumbnail: false);
    }
    final forceAvatar = isLocal && _isVideoOff;
    final showAvatar = forceAvatar || isMuted || track == null || (_isDataSaverMode && !isLocal);
    final initial = p.name.isNotEmpty ? p.name.substring(0, 1).toUpperCase() : 'U';

    if (showAvatar) {
      return _buildParticipantAvatarWidget(p, 100.0, 42.0, initial);
    }
    return VideoTrackRenderer(track as VideoTrack);
  }

  Widget _buildLocalScreenSharePresenterTile({bool isThumbnail = false}) {
    if (isThumbnail) {
      return Container(
        color: const Color(0xFF131728),
        padding: const EdgeInsets.all(8),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5FF).withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF00E5FF).withOpacity(0.5),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.screen_share_rounded,
                  color: Color(0xFF00E5FF),
                  size: 22,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Presenting',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: const Color(0xFF0D111A),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF00E5FF).withOpacity(0.2),
                      const Color(0xFF5C00FF).withOpacity(0.2),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: const Color(0xFF00E5FF).withOpacity(0.6),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E5FF).withOpacity(0.25),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.screen_share_rounded,
                  color: Color(0xFF00E5FF),
                  size: 38,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "You're presenting to everyone",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Your screen is visible to all participants. Switch to any app to share content.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _toggleScreenShare,
                    icon: const Icon(Icons.stop_screen_share_rounded, size: 18, color: Colors.white),
                    label: const Text(
                      'Stop Sharing',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF3B30),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 3,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      try {
                        SimplePip().enterPipMode();
                      } catch (_) {}
                    },
                    icon: const Icon(Icons.picture_in_picture_alt_rounded, size: 18, color: Color(0xFF00E5FF)),
                    label: const Text(
                      'Minimize App',
                      style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF00E5FF)),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReactionTapButton extends StatefulWidget {
  final String emoji;
  final VoidCallback onTap;

  const _ReactionTapButton({
    required this.emoji,
    required this.onTap,
  });

  @override
  State<_ReactionTapButton> createState() => _ReactionTapButtonState();
}

class _ReactionTapButtonState extends State<_ReactionTapButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      reverseDuration: const Duration(milliseconds: 140),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.35).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    _controller.forward().then((_) {
      if (mounted) _controller.reverse();
    });
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: Text(
            widget.emoji,
            style: const TextStyle(fontSize: 28),
          ),
        ),
      ),
    );
  }
}


