import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:flutter_background/flutter_background.dart';
import '../api_service.dart';

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
  final bool initialAudioOn;
  final bool initialVideoOn;
  final bool isHost;

  const VideoRoomScreen({
    Key? key,
    required this.roomName,
    required this.participantName,
    this.initialAudioOn = true,
    this.initialVideoOn = true,
    this.isHost = false,
  }) : super(key: key);

  @override
  State<VideoRoomScreen> createState() => _VideoRoomScreenState();
}

class _VideoRoomScreenState extends State<VideoRoomScreen> {
  late final Room _room;
  bool _isLoading = true;
  String? _error;
  late bool _isMuted;
  late bool _isVideoOff;
  bool _isScreenSharing = false;
  bool _isRecording = false;
  String? _egressId;
  Participant? _pinnedParticipant;

  // PHASE D: Active Speaker tracking
  /// The identity of the participant who is currently the loudest speaker.
  String? _activeSpeakerIdentity;

  late final EventsListener<RoomEvent> _listener;
  
  final ValueNotifier<List<ChatMessage>> _messagesNotifier = ValueNotifier([]);
  int _unreadCount = 0;
  bool _isChatOpen = false;
  final TextEditingController _chatController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _isMuted = !widget.initialAudioOn;
    _isVideoOff = !widget.initialVideoOn;
    _connectToRoom();
  }

  Future<void> _connectToRoom() async {
    try {
      final token = await ApiService.getToken(widget.roomName, widget.participantName);
      final livekitUrl = await ApiService.getLiveKitUrl();
      
      _room = Room();
      _listener = _room.createListener();
      _listener.on<RoomEvent>((event) async {
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

        if (event is DataReceivedEvent) {
          final decoded = utf8.decode(event.data);

          if (decoded == '__MUTE_ALL__') {
            if (_room.localParticipant != null && _room.localParticipant!.isMicrophoneEnabled()) {
              await _room.localParticipant!.setMicrophoneEnabled(false);
              if (mounted) {
                setState(() {
                  _isMuted = true;
                });
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('The host has muted your microphone.', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red));
              }
            }
            return;
          } else if (decoded.startsWith('__MUTE_PARTICIPANT__:')) {
            final targetId = decoded.substring('__MUTE_PARTICIPANT__:'.length);
            if (_room.localParticipant?.identity == targetId) {
              if (_room.localParticipant != null && _room.localParticipant!.isMicrophoneEnabled()) {
                await _room.localParticipant!.setMicrophoneEnabled(false);
                if (mounted) {
                  setState(() {
                    _isMuted = true;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('The host has muted your microphone.', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red));
                }
              }
            }
            return;
          } else if (decoded == '__END_MEETING__') {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('The host has ended the meeting for everyone.', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red));
              Navigator.pop(context);
            }
            return;
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
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
        ),
        connectOptions: const ConnectOptions(
          timeouts: Timeouts(
            connection: Duration(seconds: 30),
            debounce: Duration(milliseconds: 20),
            publish: Duration(seconds: 10),
            subscribe: Duration(seconds: 10),
            peerConnection: Duration(seconds: 10),
            iceRestart: Duration(seconds: 10),
          ),
        ),
      );
      
      await _room.localParticipant?.setCameraEnabled(widget.initialVideoOn);
      await _room.localParticipant?.setMicrophoneEnabled(widget.initialAudioOn);

      if (mounted) {
        setState(() {
          _isLoading = false;
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

  @override
  void dispose() {
    _chatController.dispose();
    _messagesNotifier.dispose();
    _listener.dispose();
    _room.disconnect().catchError((_) {});
    _room.dispose();
    super.dispose();
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Muted participant', style: TextStyle(color: Colors.white)), backgroundColor: Color(0xFF5C00FF)));
      }
    } catch (e) {
      debugPrint('Failed to mute participant: $e');
    }
  }

  void _toggleMute() async {
    if (_room.localParticipant == null) return;
    final isEnabled = _room.localParticipant!.isMicrophoneEnabled();
    await _room.localParticipant!.setMicrophoneEnabled(!isEnabled);
    setState(() {
      _isMuted = isEnabled;
    });
  }

  void _toggleCamera() async {
    if (_room.localParticipant == null) return;
    final isEnabled = _room.localParticipant!.isCameraEnabled();
    await _room.localParticipant!.setCameraEnabled(!isEnabled);
    setState(() {
      _isVideoOff = isEnabled;
    });
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
    if (!widget.isHost) {
      Navigator.pop(context);
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
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
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context); // close dialog
                Navigator.pop(context); // close meeting
              },
              child: const Text('Leave Meeting', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context); // close dialog
                final data = utf8.encode('__END_MEETING__');
                try {
                  await _room.localParticipant?.publishData(data);
                } catch (e) {
                  debugPrint('Failed to broadcast end meeting: $e');
                }
                if (mounted) {
                  Navigator.pop(context); // close meeting
                }
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

  void _toggleScreenShare() async {
    final enabled = !_isScreenSharing;
    try {
      if (enabled) {
        const androidConfig = FlutterBackgroundAndroidConfig(
          notificationTitle: "Screen Sharing",
          notificationText: "LiveKit screen sharing is running in the background",
          notificationImportance: AndroidNotificationImportance.normal,
          notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
        );
        bool initialized = await FlutterBackground.initialize(androidConfig: androidConfig);
        if (initialized) {
          await FlutterBackground.enableBackgroundExecution();
        }
      }

      if (_room.localParticipant != null) {
        await _room.localParticipant!.setScreenShareEnabled(enabled);
        setState(() {
          _isScreenSharing = enabled;
        });
      }

      if (!enabled) {
        try {
          await FlutterBackground.disableBackgroundExecution();
        } catch (e) {
          debugPrint('Failed to disable background: $e');
        }
      }
    } catch (e) {
      debugPrint('Failed to toggle screen share: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to share screen: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      // Stop recording
      if (_egressId != null) {
        final success = await ApiService.stopRecording(_egressId!);
        if (success) {
          setState(() {
            _isRecording = false;
            _egressId = null;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recording stopped and saved', style: TextStyle(color: Colors.white)), backgroundColor: Color(0xFF5C00FF)));
          }
        }
      }
    } else {
      // Start recording
      setState(() => _isRecording = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Starting recording...', style: TextStyle(color: Colors.white)), backgroundColor: Color(0xFF5C00FF)));
      try {
        final egressId = await ApiService.startRecording(widget.roomName);
        if (egressId != null) {
          setState(() {
            _isRecording = true;
            _egressId = egressId;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recording started successfully!', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
          }
        } else {
          setState(() => _isRecording = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to start recording', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red));
          }
        }
      } catch (e) {
        setState(() => _isRecording = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red));
        }
      }
    }
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
                    if (widget.isHost)
                      _buildOptionTile(
                        icon: Icons.mic_off,
                        title: 'Mute All Participants',
                        onTap: () {
                          Navigator.pop(context);
                          _muteAll();
                        },
                      ),
                    _buildOptionTile(
                    icon: Icons.people_outline,
                    title: 'Participants',
                    subtitle: '${_room.remoteParticipants.length + 1} in the room',
                    onTap: () {
                      Navigator.pop(context);
                    },
                  ),
                  _buildOptionTile(
                    icon: _isRecording ? Icons.stop_circle : Icons.fiber_manual_record,
                    title: _isRecording ? 'Stop Recording' : 'Record Audio',
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
                    icon: Icons.settings_outlined,
                    title: 'Settings',
                    onTap: () {
                      Navigator.pop(context);
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

  Widget _buildOptionTile({required IconData icon, required String title, String? subtitle, required VoidCallback onTap}) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: const Color(0xFF00E5FF)),
      ),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      subtitle: subtitle != null ? Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.5))) : null,
      trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white30, size: 16),
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
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF070B19),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF))),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF070B19),
        body: Center(
          child: Text(
            'Error: $_error',
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF070B19),
      body: Stack(
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
                  padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 24.0),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: PopupMenuButton<String>(
                          color: const Color(0xFF070B19).withOpacity(0.9),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: const Color(0xFF00E5FF).withOpacity(0.3)),
                          ),
                          offset: const Offset(0, 40),
                          icon: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.people, color: Color(0xFF00E5FF), size: 18),
                                const SizedBox(width: 6),
                                Text(
                                  '${_room.remoteParticipants.length + (_room.localParticipant != null ? 1 : 0)}',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
                                  p.identity + (isLocal ? ' (You)' : ''),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              );
                            }).toList();
                          },
                        ),
                      ),
                      Align(
                        alignment: Alignment.center,
                        child: Column(
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_isRecording)
                                  Container(
                                    margin: const EdgeInsets.only(right: 8),
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
                                const Text(
                                  'LA-VIE',
                                  style: TextStyle(
                                    color: Color(0xFF00E5FF),
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2.0,
                                  ),
                                ),
                              ],
                            ),
                            const Text(
                              'Premium',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: _flipCamera,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.flip_camera_ios, color: Color(0xFF00E5FF), size: 24),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Video Grid
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: _buildVideoGrid(),
                  ),
                ),
                
                // Status Indicators
                Padding(
                  padding: const EdgeInsets.only(top: 16.0, bottom: 20.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(Icons.signal_cellular_4_bar, color: Color(0xFF00E5FF), size: 16),
                      const SizedBox(width: 4),
                      const Text(
                        '5',
                        style: TextStyle(
                          color: Color(0xFF00E5FF),
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    ],
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
                            // More Options Button
                            GestureDetector(
                              onTap: _showMoreOptions,
                              child: Container(
                                decoration: const BoxDecoration(),
                                child: const Icon(
                                  Icons.more_vert,
                                  color: Color(0xFF00E5FF),
                                  size: 28,
                                ),
                              ),
                            ),
                            // End Call Button
                            GestureDetector(
                              onTap: _endCall,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.redAccent.withOpacity(0.4),
                                      blurRadius: 12,
                                      spreadRadius: 2,
                                    )
                                  ],
                                ),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.redAccent,
                                  size: 24,
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
        ],
      ),
    );
  }

  /// PHASE D: isPrimary controls whether this tile is the spotlighted large tile.
  /// It's passed down but currently used for future fine-grained rendering control.
  Widget _buildParticipantVideo(Participant p, {bool isPrimary = false}) {
    final screenTrackPub = p.videoTrackPublications.where((pub) => pub.source == TrackSource.screenShareVideo).firstOrNull;
    final cameraTrackPub = p.videoTrackPublications.where((pub) => pub.source == TrackSource.camera).firstOrNull;
    final trackPub = screenTrackPub ?? cameraTrackPub ?? p.videoTrackPublications.firstOrNull;
    final track = trackPub?.track;
    final isMuted = trackPub?.muted ?? true;
    final isLocal = p == _room.localParticipant;
    final forceAvatar = isLocal && _isVideoOff;
    final showAvatar = forceAvatar || isMuted || track == null;
    final location = isLocal ? 'Seattle, WA' : 'London, UK'; // Mock locations based on UI
    final initial = p.name.isNotEmpty ? p.name.substring(0, 1).toUpperCase() : 'U';
    
    return GestureDetector(
      onDoubleTap: () {
        setState(() {
          if (_pinnedParticipant == p) {
            _pinnedParticipant = null;
          } else {
            _pinnedParticipant = p;
          }
        });
      },
      child: Container(
        decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF00E5FF), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00E5FF).withOpacity(0.2),
            blurRadius: 15,
            spreadRadius: 2,
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              color: const Color(0xFF1E1E30),
              child: showAvatar
                  ? Center(
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF5C00FF), Color(0xFF00E5FF)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF00E5FF).withOpacity(0.3),
                              blurRadius: 15,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            initial,
                            style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    )
                  : VideoTrackRenderer(track as VideoTrack),
            ),
            // Overlay User Info
            Positioned(
              top: 16,
              left: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        p.name.isNotEmpty ? p.name : 'Participant',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 1))
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (widget.isHost && p is RemoteParticipant)
                        GestureDetector(
                          onTap: () => _muteParticipant(p.identity),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              p.isMicrophoneEnabled() ? Icons.mic : Icons.mic_off, 
                              color: p.isMicrophoneEnabled() ? Colors.white70 : Colors.red, 
                              size: 16,
                            ),
                          ),
                        )
                      else
                        Icon(
                          p.isMicrophoneEnabled() ? Icons.mic : Icons.mic_off,
                          color: p.isMicrophoneEnabled() ? Colors.white70 : Colors.red,
                          size: 16,
                        ),
                    ],
                  ),
                  Text(
                    location,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      shadows: [
                        Shadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 1))
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ));
  }

  // PHASE D: Speaker View — promotes the active speaker to a large primary tile.
  // Thumbnails of all other participants appear in a horizontal scrollable row below.
  // Adaptive quality: primary tile gets HIGH quality, thumbnails get LOW quality.
  Widget _buildVideoGrid() {
    final allParticipants = <Participant>[
      if (_room.localParticipant != null) _room.localParticipant!,
      ..._room.remoteParticipants.values,
    ];

    // --- Determine primary (spotlighted) participant ---
    Participant? primary = _pinnedParticipant;
    if (primary == null || !allParticipants.contains(primary)) {
      // Auto-select: active speaker, or first remote, or local as fallback
      if (_activeSpeakerIdentity != null) {
        primary = allParticipants
            .where((p) => p.identity == _activeSpeakerIdentity)
            .firstOrNull;
      }
      primary ??= allParticipants.firstOrNull;
    }

    // If only 1 participant (just us), show full screen
    if (allParticipants.length <= 1) {
      return primary != null
          ? _buildParticipantVideo(primary, isPrimary: true)
          : const Center(
              child: Text('Waiting for others to join...',
                  style: TextStyle(color: Colors.white54)));
    }

    // --- 2 participants: classic split view ---
    if (allParticipants.length == 2) {
      return Column(
        children: allParticipants.map((p) {
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: _buildParticipantVideo(p, isPrimary: p == primary),
            ),
          );
        }).toList(),
      );
    }

    // --- 3+ participants: SPEAKER VIEW ---
    // Primary tile takes the majority of the screen.
    // Thumbnails scroll horizontally below.
    final thumbnails = allParticipants.where((p) => p != primary).toList();

    // PHASE D: Apply adaptive quality hints to remote track publications
    for (final p in _room.remoteParticipants.values) {
      for (final pub in p.videoTrackPublications) {
        final isPrimaryParticipant = p == primary;
        // setVideoQuality is called on the subscription object in livekit_client
        try {
          if (isPrimaryParticipant) {
            pub.setVideoQuality(VideoQuality.HIGH);
          } else {
            pub.setVideoQuality(VideoQuality.LOW);
          }
        } catch (_) {
          // setVideoQuality may not be available on all pub types; ignore
        }
      }
    }

    return Column(
      children: [
        // --- Primary Tile ---
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: primary != null
                ? _buildParticipantVideo(primary, isPrimary: true)
                : const SizedBox.shrink(),
          ),
        ),

        // --- Active Speaker label ---
        if (primary != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: _activeSpeakerIdentity == primary.identity
                        ? const Color(0xFF00E5FF)
                        : Colors.white24,
                    shape: BoxShape.circle,
                    boxShadow: _activeSpeakerIdentity == primary.identity
                        ? [
                            BoxShadow(
                              color: const Color(0xFF00E5FF).withOpacity(0.6),
                              blurRadius: 8,
                              spreadRadius: 2,
                            )
                          ]
                        : [],
                  ),
                ),
                Text(
                  primary == _room.localParticipant
                      ? 'You'
                      : (primary.name.isNotEmpty ? primary.name : 'Participant'),
                  style: TextStyle(
                    color: _activeSpeakerIdentity == primary.identity
                        ? const Color(0xFF00E5FF)
                        : Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                if (_pinnedParticipant != null)
                  GestureDetector(
                    onTap: () => setState(() => _pinnedParticipant = null),
                    child: Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('Unpin',
                          style: TextStyle(color: Colors.white54, fontSize: 11)),
                    ),
                  ),
              ],
            ),
          ),

        // --- Thumbnail Strip ---
        SizedBox(
          height: 110,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(bottom: 8),
            itemCount: thumbnails.length,
            itemBuilder: (context, index) {
              final p = thumbnails[index];
              final isActiveSpeaker = p.identity == _activeSpeakerIdentity;
              return GestureDetector(
                onTap: () => setState(() => _pinnedParticipant = p),
                child: Container(
                  width: 90,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isActiveSpeaker
                          ? const Color(0xFF00E5FF)
                          : Colors.white12,
                      width: isActiveSpeaker ? 2.5 : 1,
                    ),
                    boxShadow: isActiveSpeaker
                        ? [
                            BoxShadow(
                              color: const Color(0xFF00E5FF).withOpacity(0.4),
                              blurRadius: 12,
                              spreadRadius: 1,
                            )
                          ]
                        : [],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: _buildParticipantVideo(p, isPrimary: false),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
