import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import '../services/status_upload_queue.dart';
import '../theme/app_theme.dart';
import '../widgets/status_privacy_dialog.dart';

class CreateAudioStatusScreen extends StatefulWidget {
  const CreateAudioStatusScreen({super.key});

  @override
  State<CreateAudioStatusScreen> createState() => _CreateAudioStatusScreenState();
}

class _CreateAudioStatusScreenState extends State<CreateAudioStatusScreen>
    with SingleTickerProviderStateMixin {
  final AudioRecorder _recorder = AudioRecorder();
  late final AudioPlayer _player;
  late final AnimationController _pulseController;

  final TextEditingController _captionController = TextEditingController();
  StatusPrivacySettings _privacy = const StatusPrivacySettings(privacy: 'all');
  int _durationHours = 24;

  bool _isRecording = false;
  bool _isPlayingPreview = false;
  bool _isPosting = false;
  String? _recordedFilePath;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  static const int _maxDurationSeconds = 60;

  // Waveform bars simulation
  final List<double> _waveformHeights = List.generate(32, (i) => 0.2);
  Timer? _waveformTimer;

  final List<List<int>> _gradientPresets = [
    [0xFF7C3AED, 0xFF9333EA], // Lilac / Amethyst
    [0xFF065F46, 0xFF10B981], // Emerald Teal
    [0xFF1E3A8A, 0xFF3B82F6], // Ocean Blue
    [0xFF9D174D, 0xFFF43F5E], // Rose Crimson
    [0xFFB45309, 0xFFF59E0B], // Warm Amber
    [0xFF18181B, 0xFF3F3F46], // Deep Carbon
  ];
  int _selectedGradientIndex = 0;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _player.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _isPlayingPreview = state == PlayerState.playing);
      }
    });

    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() => _isPlayingPreview = false);
      }
    });

    StatusPrivacySettings.load().then((p) {
      if (mounted) setState(() => _privacy = p);
    });
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _waveformTimer?.cancel();
    _recorder.dispose();
    _player.dispose();
    _pulseController.dispose();
    _captionController.dispose();
    if (_recordedFilePath != null) {
      final f = File(_recordedFilePath!);
      if (f.existsSync()) f.delete().catchError((_) => f);
    }
    super.dispose();
  }

  void _cycleGradient() {
    setState(() {
      _selectedGradientIndex = (_selectedGradientIndex + 1) % _gradientPresets.length;
    });
  }

  Future<void> _openPrivacyPicker() async {
    final updated = await StatusPrivacyDialog.show(context, _privacy);
    if (updated != null && mounted) {
      setState(() => _privacy = updated);
    }
  }

  Future<void> _openDurationPicker() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppTheme.surfaceColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final textPrim = AppTheme.text(ctx);
        final textSec = AppTheme.textSec(ctx);
        final mint = AppTheme.mintColor(ctx);

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.borderColor(ctx),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Icon(Icons.hourglass_bottom_rounded, color: mint, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'Status Longevity',
                      style: TextStyle(color: textPrim, fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Select how long your status remains visible before disappearing:',
                  style: TextStyle(color: textSec, fontSize: 13),
                ),
                const SizedBox(height: 16),
                for (final hours in [4, 12, 24, 48])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _durationHours == hours ? mint.withValues(alpha: 0.15) : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        hours == 24 ? Icons.timer_rounded : Icons.schedule_rounded,
                        color: _durationHours == hours ? mint : textSec,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      '$hours Hours${hours == 24 ? ' (Standard 24h)' : ''}',
                      style: TextStyle(
                        color: _durationHours == hours ? mint : textPrim,
                        fontWeight: _durationHours == hours ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                    trailing: _durationHours == hours
                        ? Icon(Icons.check_circle_rounded, color: mint, size: 22)
                        : null,
                    onTap: () => Navigator.pop(ctx, hours),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (selected != null && mounted) {
      setState(() => _durationHours = selected);
    }
  }

  Future<void> _startRecording() async {
    try {
      if (await _recorder.hasPermission()) {
        final tempDir = await getTemporaryDirectory();
        final path = '${tempDir.path}/status_audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
        _recordedFilePath = path;

        await _recorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000),
          path: path,
        );

        setState(() {
          _isRecording = true;
          _recordSeconds = 0;
        });

        _pulseController.repeat(reverse: true);

        // Start duration counter
        _recordTimer?.cancel();
        _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) return;
          setState(() {
            _recordSeconds++;
          });
          if (_recordSeconds >= _maxDurationSeconds) {
            _stopRecording();
          }
        });

        // Animate waveform bars randomly during recording
        final random = Random();
        _waveformTimer?.cancel();
        _waveformTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
          if (!mounted || !_isRecording) return;
          setState(() {
            for (int i = 0; i < _waveformHeights.length; i++) {
              _waveformHeights[i] = 0.15 + random.nextDouble() * 0.85;
            }
          });
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission required for audio status')),
          );
        }
      }
    } catch (e) {
      debugPrint("Error starting recording: $e");
    }
  }

  Future<void> _stopRecording() async {
    _recordTimer?.cancel();
    _waveformTimer?.cancel();
    _pulseController.stop();
    _pulseController.reset();

    try {
      final path = await _recorder.stop();
      setState(() {
        _isRecording = false;
        if (path != null) _recordedFilePath = path;
      });
    } catch (e) {
      debugPrint("Error stopping recording: $e");
      setState(() => _isRecording = false);
    }
  }

  Future<void> _togglePreviewPlay() async {
    if (_recordedFilePath == null) return;
    if (_isPlayingPreview) {
      await _player.pause();
    } else {
      await _player.play(DeviceFileSource(_recordedFilePath!));
    }
  }

  Future<void> _resetRecording() async {
    await _player.stop();
    if (_recordedFilePath != null) {
      final f = File(_recordedFilePath!);
      if (await f.exists()) await f.delete();
    }
    setState(() {
      _recordedFilePath = null;
      _recordSeconds = 0;
      _isPlayingPreview = false;
      for (int i = 0; i < _waveformHeights.length; i++) {
        _waveformHeights[i] = 0.2;
      }
    });
  }

  void _postAudioStatus() async {
    if (_recordedFilePath == null || _recordSeconds < 1) return;
    final file = File(_recordedFilePath!);
    if (!await file.exists()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final filePathToUpload = _recordedFilePath!;
    _recordedFilePath = null; // Prevent dispose from deleting file while queue uploads
    setState(() => _isPosting = true);

    StatusUploadQueue.instance.enqueueAudioStatus(
      uid: user.uid,
      userName: user.displayName ?? 'Me',
      userAvatar: user.photoURL,
      audioFile: File(filePathToUpload),
      durationSeconds: _recordSeconds,
      gradientColors: _gradientPresets[_selectedGradientIndex],
      caption: _captionController.text.trim().isEmpty ? null : _captionController.text.trim(),
      privacy: _privacy.privacy,
      privacyUids: _privacy.selectedUids,
      durationHours: _durationHours,
    );

    if (mounted) {
      Navigator.pop(context, true);
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
              Text('Sending voice status...'),
            ],
          ),
          backgroundColor: Color(0xFF1E1A36),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  String _formatTimer(int totalSecs) {
    final m = (totalSecs ~/ 60).toString();
    final s = (totalSecs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final colors = _gradientPresets[_selectedGradientIndex].map((c) => Color(c)).toList();
    final user = FirebaseAuth.instance.currentUser;
    final bool hasRecorded = _recordedFilePath != null && !_isRecording;

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top Action Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                      tooltip: 'Discard',
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    const Text(
                      'Voice Status',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    // Color Palette Button
                    IconButton(
                      icon: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.25),
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.palette_rounded, color: Colors.white, size: 18),
                      ),
                      tooltip: 'Change Color',
                      onPressed: _cycleGradient,
                    ),
                  ],
                ),
              ),

              // Main Center Content
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Avatar Card with Pulsing Sound Waves
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        if (_isRecording)
                          AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, child) {
                              return Container(
                                width: 140 + (_pulseController.value * 30),
                                height: 140 + (_pulseController.value * 30),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withValues(alpha: 0.15 * (1.0 - _pulseController.value)),
                                ),
                              );
                            },
                          ),
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.2),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Center(
                            child: CircleAvatar(
                              radius: 50,
                              backgroundColor: Colors.white10,
                              backgroundImage: user?.photoURL != null
                                  ? NetworkImage(user!.photoURL!)
                                  : null,
                              child: user?.photoURL == null
                                  ? const Icon(Icons.mic_rounded, color: Colors.white, size: 48)
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 28),

                    // Duration Counter
                    Text(
                      _formatTimer(_recordSeconds),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isRecording
                          ? 'Recording... (Max 1 min)'
                          : hasRecorded
                              ? 'Voice Note Ready'
                              : 'Tap to record voice status',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Waveform Visualizer Bar
                    Container(
                      height: 50,
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: _waveformHeights.map((heightFactor) {
                          return Container(
                            width: 3.5,
                            height: 48 * heightFactor,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: (_isRecording || _isPlayingPreview)
                                  ? Colors.white
                                  : Colors.white38,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Action Controls
                    if (!hasRecorded) ...[
                      // Big Record / Stop Button
                      GestureDetector(
                        onTap: _isRecording ? _stopRecording : _startRecording,
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isRecording ? Colors.redAccent : Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 15,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Icon(
                            _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                            color: _isRecording ? Colors.white : AppTheme.lilacDeep,
                            size: 36,
                          ),
                        ),
                      ),
                    ] else ...[
                      // Preview & Delete Controls
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Delete / Reset
                          IconButton(
                            onPressed: _resetRecording,
                            icon: Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                              child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 24),
                            ),
                            tooltip: 'Re-record',
                          ),
                          const SizedBox(width: 24),

                          // Play / Pause preview
                          GestureDetector(
                            onTap: _togglePreviewPlay,
                            child: Container(
                              width: 64,
                              height: 64,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                              ),
                              child: Icon(
                                _isPlayingPreview ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: AppTheme.lilacDeep,
                                size: 36,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Caption input (optional)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: TextField(
                    controller: _captionController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    cursorColor: Colors.white,
                    decoration: const InputDecoration(
                      hintText: 'Add a caption (optional)...',
                      hintStyle: TextStyle(color: Colors.white54, fontSize: 14),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),

              // Bottom Bar: Privacy Pill + Post Button
              Padding(
                padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20, top: 4),
                child: Row(
                  children: [
                    // Privacy Pill
                    GestureDetector(
                      onTap: _openPrivacyPicker,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.lock_outline_rounded, color: Colors.white70, size: 14),
                            const SizedBox(width: 6),
                            Text(
                              _privacy.label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_drop_down_rounded, color: Colors.white70, size: 18),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Duration Longevity Pill
                    GestureDetector(
                      onTap: _openDurationPicker,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.timer_outlined, color: Colors.white70, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              '${_durationHours}h',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(Icons.arrow_drop_down_rounded, color: Colors.white70, size: 16),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    FloatingActionButton(
                      heroTag: 'post_audio_status_fab',
                      onPressed: (!hasRecorded || _isPosting) ? null : _postAudioStatus,
                      backgroundColor: hasRecorded ? Colors.white : Colors.white24,
                      elevation: 4,
                      child: _isPosting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: AppTheme.lilacDeep,
                              ),
                            )
                          : Icon(
                              Icons.send_rounded,
                              color: hasRecorded ? AppTheme.lilacDeep : Colors.white38,
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
  }
}
