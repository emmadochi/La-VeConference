import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_theme.dart';
import '../services/media_storage_service.dart';
import '../services/ai_service.dart';
import '../screens/video_viewer_screen.dart';

/// Interactive Voice Note Player Bubble (WhatsApp style)
class VoiceNoteBubble extends StatefulWidget {
  final String? mediaUrl;
  final String? localPath;
  final String? fileName;
  final int? durationSeconds;
  final bool isMe;
  final String messageId;

  const VoiceNoteBubble({
    super.key,
    required this.mediaUrl,
    this.localPath,
    this.fileName,
    this.durationSeconds,
    required this.isMe,
    required this.messageId,
  });

  @override
  State<VoiceNoteBubble> createState() => _VoiceNoteBubbleState();
}

class _VoiceNoteBubbleState extends State<VoiceNoteBubble> {
  late final AudioPlayer _player;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _totalDuration = Duration.zero;
  String? _cachedPath;
  bool _isTranscribing = false;
  String? _transcript;
  String? _summary;
  bool _showTranscript = false;
  double _playbackSpeed = 1.0;
  static const List<double> _speedSteps = [1.0, 1.5, 2.0];

  // Pseudo-waveform bar heights (fixed seed for deterministic look per messageId)
  late final List<double> _barHeights;
  final _waveformKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    if (widget.durationSeconds != null && widget.durationSeconds! > 0) {
      _totalDuration = Duration(seconds: widget.durationSeconds!);
    }

    // Generate deterministic pseudo-waveform heights from message ID hash
    final seed = widget.messageId.codeUnits.fold(0, (a, b) => a ^ b);
    _barHeights = List.generate(28, (i) {
      final v = ((seed * (i + 7) * 1103515245 + 12345) & 0x7fffffff) % 100;
      return 0.15 + (v / 100.0) * 0.85;
    });

    _checkLocalCache();

    _player.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });

    _player.onDurationChanged.listen((dur) {
      if (mounted && dur > Duration.zero) setState(() => _totalDuration = dur);
    });

    _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
    });

    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      }
    });
  }

  Future<void> _checkLocalCache() async {
    final fileName = widget.fileName ?? 'vn_${widget.messageId}.m4a';
    final file = await MediaStorageService.findLocalFile(
      category: 'VoiceNotes',
      fileName: fileName,
      knownLocalPath: widget.localPath,
    );
    if (file != null && await file.exists()) {
      if (mounted) {
        setState(() => _cachedPath = file.path);
      }
    } else if (widget.mediaUrl != null && widget.mediaUrl!.startsWith('data:')) {
      // Decode inline data URI to local storage immediately
      final downloaded = await MediaStorageService.downloadMediaToLocal(
        remoteUrl: widget.mediaUrl!,
        category: 'VoiceNotes',
        targetFileName: fileName,
      );
      if (downloaded != null && mounted) {
        setState(() => _cachedPath = downloaded.path);
      }
    }
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _player.pause();
      return;
    }

    // 1. Play from local device file if already present
    if (_cachedPath != null && await File(_cachedPath!).exists()) {
      await _player.play(DeviceFileSource(_cachedPath!));
      return;
    }

    // 2. Play from base64 Data URI or remote relay URL
    if (widget.mediaUrl != null && widget.mediaUrl!.isNotEmpty) {
      final fileName = widget.fileName ?? 'vn_${widget.messageId}.m4a';

      if (widget.mediaUrl!.startsWith('data:')) {
        final localFile = await MediaStorageService.downloadMediaToLocal(
          remoteUrl: widget.mediaUrl!,
          category: 'VoiceNotes',
          targetFileName: fileName,
        );
        if (localFile != null && await localFile.exists()) {
          if (mounted) setState(() => _cachedPath = localFile.path);
          await _player.play(DeviceFileSource(localFile.path));
          return;
        }
      }

      await _player.play(UrlSource(widget.mediaUrl!));

      // Cache locally in background so future plays are 100% offline
      MediaStorageService.downloadMediaToLocal(
        remoteUrl: widget.mediaUrl!,
        category: 'VoiceNotes',
        targetFileName: fileName,
      ).then((downloaded) {
        if (downloaded != null && mounted) {
          setState(() => _cachedPath = downloaded.path);
        }
      });
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  void _toggleTranscribe() async {
    if (_transcript != null) {
      setState(() => _showTranscript = !_showTranscript);
      return;
    }

    setState(() {
      _isTranscribing = true;
      _showTranscript = true;
    });

    try {
      final res = await AIService.transcribeVoiceNote(
        localPath: _cachedPath ?? widget.localPath,
        mediaUrl: widget.mediaUrl,
        durationSeconds: widget.durationSeconds,
      );
      if (mounted) {
        setState(() {
          _transcript = res.transcript;
          _summary = res.summary;
          _isTranscribing = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isTranscribing = false);
      }
    }
  }

  void _cycleSpeed() async {
    final nextIdx = (_speedSteps.indexOf(_playbackSpeed) + 1) % _speedSteps.length;
    final newSpeed = _speedSteps[nextIdx];
    setState(() => _playbackSpeed = newSpeed);
    await _player.setPlaybackRate(newSpeed);
  }

  @override
  Widget build(BuildContext context) {
    final maxSeconds = _totalDuration.inSeconds > 0
        ? _totalDuration.inSeconds.toDouble()
        : (widget.durationSeconds?.toDouble() ?? 10.0);
    final progressRatio = maxSeconds > 0
        ? (_position.inSeconds.toDouble() / maxSeconds).clamp(0.0, 1.0)
        : 0.0;

    final displayDuration = _isPlaying
        ? MediaStorageService.formatDuration(_position.inSeconds)
        : MediaStorageService.formatDuration(
            _totalDuration.inSeconds > 0 ? _totalDuration.inSeconds : (widget.durationSeconds ?? 0));

    final activeColor = widget.isMe ? Colors.white : AppTheme.mint;
    final inactiveColor = Colors.white.withValues(alpha: 0.25);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 280),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Play / Pause Circle
              GestureDetector(
                onTap: _togglePlay,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: widget.isMe ? Colors.black26 : AppTheme.mint.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: widget.isMe ? Colors.white : AppTheme.mint,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Waveform bars + duration row
              Expanded(
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    final box = _waveformKey.currentContext?.findRenderObject() as RenderBox?;
                    if (box != null) {
                      final localX = box.globalToLocal(details.globalPosition).dx;
                      final ratio = (localX / box.size.width).clamp(0.0, 1.0);
                      if (_totalDuration > Duration.zero) {
                        _player.seek(Duration(milliseconds: (ratio * _totalDuration.inMilliseconds).toInt()));
                      }
                    }
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Waveform bar visualization
                      SizedBox(
                        key: _waveformKey,
                        height: 32,
                        child: LayoutBuilder(builder: (ctx, constraints) {
                          final barCount = _barHeights.length;
                          final barWidth = (constraints.maxWidth - (barCount - 1) * 2) / barCount;
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: List.generate(barCount, (i) {
                              final played = i / barCount <= progressRatio;
                              return Padding(
                                padding: EdgeInsets.only(right: i < barCount - 1 ? 2 : 0),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 120),
                                  width: barWidth.clamp(2.0, 8.0),
                                  height: 32 * _barHeights[i],
                                  decoration: BoxDecoration(
                                    color: played ? activeColor : inactiveColor,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              );
                            }),
                          );
                        }),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            displayDuration,
                            style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
                          ),
                          Row(
                            children: [
                              // Variable speed button
                              GestureDetector(
                                onTap: _cycleSpeed,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: activeColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: activeColor.withValues(alpha: 0.4)),
                                  ),
                                  child: Text(
                                    '${_playbackSpeed == 1.0 ? '1' : _playbackSpeed.toString()}x',
                                    style: TextStyle(color: activeColor, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              if (_cachedPath != null)
                                const Icon(Icons.download_done_rounded, color: AppTheme.mint, size: 13)
                              else
                                const Icon(Icons.cloud_outlined, color: Colors.white38, size: 13),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // AI Transcribe Trigger & Result
          const SizedBox(height: 4),
          GestureDetector(
            onTap: _toggleTranscribe,
            child: Container(
              margin: const EdgeInsets.only(top: 2, left: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.mint.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isTranscribing)
                    const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(color: AppTheme.mint, strokeWidth: 1.5),
                    )
                  else
                    const Icon(Icons.auto_awesome, color: AppTheme.mint, size: 11),
                  const SizedBox(width: 4),
                  Text(
                    _isTranscribing
                        ? 'Transcribing...'
                        : (_transcript != null
                            ? (_showTranscript ? 'Hide transcript' : 'Show transcript')
                            : 'Transcribe'),
                    style: const TextStyle(color: AppTheme.mint, fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),

          // Transcribed Text Container
          if (_showTranscript && _transcript != null)
            Container(
              margin: const EdgeInsets.only(top: 6, left: 4, right: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_summary != null) ...[
                    Text(
                      'TL;DR: $_summary',
                      style: const TextStyle(color: AppTheme.mint, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 3),
                  ],
                  Text(
                    _transcript!,
                    style: const TextStyle(color: Colors.white, fontSize: 11.5, height: 1.3),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Document / File Message Bubble (WhatsApp style with manual download control)
class FileMessageBubble extends StatefulWidget {
  final String? mediaUrl;
  final String? localPath;
  final String fileName;
  final int? fileSize;
  final bool isMe;
  final bool isUploading;
  final double uploadProgress;
  final bool uploadFailed;
  final VoidCallback? onRetry;

  const FileMessageBubble({
    super.key,
    required this.mediaUrl,
    this.localPath,
    required this.fileName,
    this.fileSize,
    required this.isMe,
    this.isUploading = false,
    this.uploadProgress = 0.0,
    this.uploadFailed = false,
    this.onRetry,
  });

  @override
  State<FileMessageBubble> createState() => _FileMessageBubbleState();
}

class _FileMessageBubbleState extends State<FileMessageBubble> {
  bool _isDownloading = false;
  String? _cachedPath;

  @override
  void initState() {
    super.initState();
    _checkLocalCache();
  }

  Future<void> _checkLocalCache() async {
    final file = await MediaStorageService.findLocalFile(
      category: 'Documents',
      fileName: widget.fileName,
      knownLocalPath: widget.localPath,
    );
    if (file != null && await file.exists()) {
      if (mounted) {
        setState(() => _cachedPath = file.path);
      }
    }
  }

  Future<void> _downloadFile() async {
    if (widget.mediaUrl == null || widget.mediaUrl!.isEmpty) return;
    setState(() => _isDownloading = true);
    try {
      final downloaded = await MediaStorageService.downloadMediaToLocal(
        remoteUrl: widget.mediaUrl!,
        category: 'Documents',
        targetFileName: widget.fileName,
      );
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _cachedPath = downloaded?.path;
        });
        if (downloaded != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Downloaded "${widget.fileName}"'),
              backgroundColor: AppTheme.bubbleMe,
              action: SnackBarAction(
                label: 'Save to Downloads',
                textColor: Colors.white,
                onPressed: () => _saveToDownloadsFolder(downloaded),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDownloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e'), backgroundColor: AppTheme.callRed),
        );
      }
    }
  }

  Future<void> _saveToDownloadsFolder(File sourceFile) async {
    try {
      Directory? targetDir;
      if (Platform.isAndroid) {
        final publicDownload = Directory('/storage/emulated/0/Download');
        if (await publicDownload.exists()) targetDir = publicDownload;
      }
      targetDir ??= await getApplicationDocumentsDirectory();

      final destination = File('${targetDir.path}/LiChat_${widget.fileName}');
      await sourceFile.copy(destination.path);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to Downloads: ${destination.path.split('/').last}'),
            backgroundColor: AppTheme.bubbleMe,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save error: $e'), backgroundColor: AppTheme.callRed),
        );
      }
    }
  }

  void _showFileOptions(File file) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.file_open_rounded, color: AppTheme.mint),
                title: const Text('Open / View File', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: Text(widget.fileName, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  MediaStorageService.openOrShareFile(file.path, widget.fileName);
                },
              ),
              ListTile(
                leading: const Icon(Icons.download_rounded, color: Colors.blueAccent),
                title: const Text('Save to Downloads Folder', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: const Text('Accessible in phone File Manager / Downloads app', style: TextStyle(color: Colors.white60, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _saveToDownloadsFolder(file);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_rounded, color: Colors.amberAccent),
                title: const Text('Share File', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(ctx);
                  SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: widget.fileName));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleAction() async {
    if (_cachedPath != null && await File(_cachedPath!).exists()) {
      _showFileOptions(File(_cachedPath!));
      return;
    }

    // Explicit user tap to download
    await _downloadFile();
  }

  IconData _getFileIcon(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx':
      case 'txt':
        return Icons.description_rounded;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return Icons.table_chart_rounded;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Color _getFileColor(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return Colors.redAccent;
      case 'doc':
      case 'docx':
        return Colors.blueAccent;
      case 'xls':
      case 'xlsx':
        return Colors.greenAccent;
      case 'zip':
      case 'rar':
        return Colors.amberAccent;
      default:
        return AppTheme.mint;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ext = widget.fileName.contains('.') ? widget.fileName.split('.').last : '';
    final fileIcon = _getFileIcon(ext);
    final fileColor = _getFileColor(ext);
    final sizeText = widget.fileSize != null ? MediaStorageService.formatFileSize(widget.fileSize!) : '';

    return InkWell(
      onTap: _handleAction,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        constraints: const BoxConstraints(minWidth: 200, maxWidth: 280),
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: fileColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(fileIcon, color: fileColor, size: 24),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  if (widget.isUploading) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: widget.uploadProgress > 0 ? widget.uploadProgress : null,
                        minHeight: 4,
                        backgroundColor: Colors.white12,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.lilacLight),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.uploadProgress > 0
                          ? '${(widget.uploadProgress * 100).toInt()}% • $sizeText'
                          : 'Uploading... $sizeText',
                      style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ] else if (widget.uploadFailed) ...[
                    const Text(
                      'Upload failed • Tap to retry',
                      style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ] else ...[
                    Text(
                      sizeText.isNotEmpty
                          ? '$sizeText • ${_cachedPath != null ? 'Downloaded' : 'Tap to download'}'
                          : (_cachedPath != null ? 'Downloaded' : 'Tap to download'),
                      style: const TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (widget.isUploading)
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  value: widget.uploadProgress > 0 ? widget.uploadProgress : null,
                  strokeWidth: 2.2,
                  color: AppTheme.lilacLight,
                ),
              )
            else if (widget.uploadFailed)
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.amberAccent, size: 22),
                tooltip: 'Tap to retry upload',
                onPressed: widget.onRetry,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              )
            else if (_isDownloading)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.mint),
              )
            else if (_cachedPath != null)
              IconButton(
                icon: const Icon(Icons.more_vert_rounded, color: Colors.white70, size: 20),
                onPressed: () {
                  if (_cachedPath != null) _showFileOptions(File(_cachedPath!));
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              )
            else
              IconButton(
                icon: const Icon(Icons.arrow_downward_rounded, color: AppTheme.mint, size: 22),
                tooltip: 'Download file',
                onPressed: _downloadFile,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
          ],
        ),
      ),
    );
  }
}

/// Video Message Bubble with rich preview, play button, and manual download control
class VideoMessageBubble extends StatefulWidget {
  final String? mediaUrl;
  final String? localPath;
  final String? fileName;
  final int? fileSize;
  final int? durationSeconds;
  final bool isMe;
  final String? senderName;
  final String? timeString;
  final bool isUploading;
  final double uploadProgress;
  final bool uploadFailed;
  final VoidCallback? onRetry;

  const VideoMessageBubble({
    super.key,
    required this.mediaUrl,
    this.localPath,
    this.fileName,
    this.fileSize,
    this.durationSeconds,
    required this.isMe,
    this.senderName,
    this.timeString,
    this.isUploading = false,
    this.uploadProgress = 0.0,
    this.uploadFailed = false,
    this.onRetry,
  });

  @override
  State<VideoMessageBubble> createState() => _VideoMessageBubbleState();
}

class _VideoMessageBubbleState extends State<VideoMessageBubble> {
  bool _isDownloading = false;
  String? _cachedPath;

  @override
  void initState() {
    super.initState();
    _checkLocalCache();
  }

  Future<void> _checkLocalCache() async {
    final cleanName = widget.fileName ?? 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final file = await MediaStorageService.findLocalFile(
      category: 'Videos',
      fileName: cleanName,
      knownLocalPath: widget.localPath,
    );
    if (file != null && await file.exists()) {
      if (mounted) setState(() => _cachedPath = file.path);
    }
  }

  Future<void> _downloadVideo() async {
    if (widget.mediaUrl == null || widget.mediaUrl!.isEmpty) return;
    setState(() => _isDownloading = true);
    final cleanName = widget.fileName ?? 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';

    try {
      final downloaded = await MediaStorageService.downloadMediaToLocal(
        remoteUrl: widget.mediaUrl!,
        category: 'Videos',
        targetFileName: cleanName,
      );
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _cachedPath = downloaded?.path;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDownloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e'), backgroundColor: AppTheme.callRed),
        );
      }
    }
  }

  void _openViewer() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoViewerScreen(
          videoUrl: widget.mediaUrl,
          localPath: _cachedPath ?? widget.localPath,
          fileName: widget.fileName,
          title: widget.senderName ?? 'Video',
          subtitle: widget.timeString,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sizeText = widget.fileSize != null ? MediaStorageService.formatFileSize(widget.fileSize!) : '';
    final durText = widget.durationSeconds != null && widget.durationSeconds! > 0
        ? MediaStorageService.formatDuration(widget.durationSeconds!)
        : '';

    return Container(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Video Thumbnail / Play Hero
            GestureDetector(
              onTap: _openViewer,
              child: Container(
                height: 150,
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1E1035), Color(0xFF0F0C20)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Video watermark icon
                    Icon(
                      Icons.videocam_rounded,
                      size: 64,
                      color: Colors.white.withValues(alpha: 0.12),
                    ),

                    // Uploading Progress OR Play Button OR Retry Button
                    if (widget.isUploading)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24, width: 2),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 44,
                              height: 44,
                              child: CircularProgressIndicator(
                                value: widget.uploadProgress > 0 ? widget.uploadProgress : null,
                                strokeWidth: 3.5,
                                color: AppTheme.lilacLight,
                              ),
                            ),
                            Text(
                              '${(widget.uploadProgress * 100).toInt()}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (widget.uploadFailed)
                      GestureDetector(
                        onTap: widget.onRetry,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.refresh_rounded, color: Colors.amberAccent, size: 36),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.mint.withValues(alpha: 0.6), width: 2),
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: AppTheme.mint,
                          size: 36,
                        ),
                      ),

                    // Top Bar with Duration Badge
                    if (durText.isNotEmpty)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.schedule_rounded, color: Colors.white70, size: 12),
                              const SizedBox(width: 4),
                              Text(
                                durText,
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Bottom file info badge
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          sizeText.isNotEmpty ? sizeText : 'Video',
                          style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom Action Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.movie_creation_outlined, color: AppTheme.mint, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.fileName ?? 'Video',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (_isDownloading)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: AppTheme.mint, strokeWidth: 2),
                    )
                  else if (_cachedPath == null)
                    IconButton(
                      icon: const Icon(Icons.download_rounded, color: AppTheme.mint, size: 20),
                      tooltip: 'Download video',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _downloadVideo,
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.fullscreen_rounded, color: Colors.white70, size: 22),
                      tooltip: 'Play fullscreen',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _openViewer,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

