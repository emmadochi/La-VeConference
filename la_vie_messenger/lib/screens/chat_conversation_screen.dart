import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:record/record.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../theme/app_theme.dart';
import '../services/chat_service.dart';
import '../services/contact_service.dart';
import '../services/call_signaling_service.dart';
import '../services/presence_service.dart';
import '../services/media_storage_service.dart';
import '../services/sound_service.dart';
import '../services/local_db_service.dart';
import '../widgets/chat_media_bubbles.dart';
import '../widgets/emoji_picker_sheet.dart';
import '../widgets/forward_message_dialog.dart';
import '../widgets/create_poll_dialog.dart';
import '../widgets/poll_message_bubble.dart';
import '../widgets/media_gallery_bubble.dart';
import '../widgets/jumbo_emoji_view.dart';
import 'call_screens.dart';
import 'image_viewer_screen.dart';
import 'contact_profile_screen.dart';
import 'starred_messages_screen.dart';
import 'group_info_screen.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/share_to_status_dialog.dart';
import '../widgets/message_info_sheet.dart';
import '../services/ai_service.dart';
import '../services/twin_service.dart';
import '../widgets/schedule_call_dialog.dart';
import '../widgets/scheduled_call_card.dart';
import '../widgets/chat_digest_sheet.dart';
import '../widgets/chat_vault_header.dart';
import '../widgets/twin_reply_bar.dart';

class ChatConversationScreen extends StatefulWidget {
  final String peerUid;
  final String peerName;
  final String? peerAvatar;
  final bool isGroup;
  final String? chatIdOverride;
  final List<String>? groupParticipants;
  final bool showBackButton;
  final String? initialText;
  final List<String>? initialFiles;

  const ChatConversationScreen({
    super.key,
    required this.peerUid,
    required this.peerName,
    this.peerAvatar,
    this.isGroup = false,
    this.chatIdOverride,
    this.groupParticipants,
    this.showBackButton = true,
    this.initialText,
    this.initialFiles,
  });

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  late String _chatId;
  late String _displayName;
  String? _myUid;
  String? _myName;
  bool _isPeerTyping = false;
  List<String>? _groupParticipants;
  String? _groupCreatorId;
  bool _isGroupAdmin = false;
  bool _isChannel = false;
  bool _onlyAdminsCanPost = false;

  // UX & Feature States
  Map<String, dynamic>? _replyingTo;
  bool _showEmojiPicker = false;
  bool _showScrollToBottom = false;

  // In-Chat Message Search State
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int _currentMatchIndex = 0;
  List<int> _matchedIndices = [];
  AISchedulingIntent? _detectedIntent;

  // AI Twin State
  TwinSettings _twinSettings = const TwinSettings();
  List<String> _twinReplyCandidates = [];
  bool _showTwinReplyBar = false;
  StreamSubscription<TwinSettings>? _twinSettingsSub;

  // Audio Recording State
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  bool _isRecordingLocked = false; // lock-to-record mode — no hold needed
  int _recordDuration = 0;
  Timer? _recordTimer;
  String? _recordTempPath;

  // Incoming Shared Files
  List<File> _pendingShareFiles = [];

  // Optimistic UI State (Instant 0ms message insertion like WhatsApp)
  final List<Map<String, dynamic>> _optimisticMessages = [];
  final Set<String> _readMarkedMessageIds = {};
  bool _hasInitialMessageSnapshotLoaded = false;
  List<Map<String, dynamic>> _localCachedMessages = [];
  bool _hasStreamTimedOut = false;

  @override
  void initState() {
    super.initState();
    _displayName = widget.peerName;
    final user = FirebaseAuth.instance.currentUser;
    _myUid = user?.uid ?? 'guest';
    _myName = user?.displayName ?? 'User';
    _chatId = widget.chatIdOverride ?? (widget.isGroup ? widget.peerUid : ChatService.getConversationId(_myUid!, widget.peerUid));
    _groupParticipants = widget.groupParticipants;

    // Safety timeout: Never hang in infinite loading spinner if Firestore is slow or offline
    Timer(const Duration(seconds: 3), () {
      if (mounted && !_hasInitialMessageSnapshotLoaded) {
        setState(() => _hasStreamTimedOut = true);
      }
    });

    // WhatsApp-grade 0ms cold start: load SQLite cache immediately
    LocalDbService.loadMessages(_chatId).then((cached) {
      if (mounted && cached.isNotEmpty && !_hasInitialMessageSnapshotLoaded) {
        setState(() {
          _localCachedMessages = cached.reversed.toList();
        });
      }
    });

    // Prefill shared text or files if arriving from external app share sheet
    if (widget.initialText != null && widget.initialText!.isNotEmpty) {
      _messageController.text = widget.initialText!;
    }
    if (widget.initialFiles != null && widget.initialFiles!.isNotEmpty) {
      _pendingShareFiles = widget.initialFiles!
          .map((p) => File(p))
          .where((f) => f.existsSync())
          .toList();
    }

    if (widget.isGroup) {
      FirebaseFirestore.instance.collection('chats').doc(_chatId).get().then((doc) {
        if (doc.exists && mounted) {
          final data = doc.data() ?? {};
          setState(() {
            _groupParticipants = List<String>.from(data['participants'] ?? []);
            _groupCreatorId = data['creatorId'] as String?;
            final admins = List<String>.from(data['admins'] ?? []);
            _isGroupAdmin = admins.contains(_myUid) || _groupCreatorId == _myUid || (_groupParticipants?.isNotEmpty == true && _groupParticipants!.first == _myUid);
            _isChannel = data['isChannel'] == true;
            _onlyAdminsCanPost = data['onlyAdminsCanPost'] == true;
            final fetchedName = data['name'] ?? data['groupName'];
            if (fetchedName != null && (fetchedName as String).isNotEmpty) {
              _displayName = fetchedName;
            }
          });
        }
      });
    }

    // Mark conversation as read
    ChatService.markAsRead(_chatId, _myUid!);

    // Listen to typing status
    _messageController.addListener(_onTextChanged);

    // Scroll listener for floating jump-to-bottom FAB
    _scrollController.addListener(_onScroll);

    // AI Twin — subscribe to live settings stream
    _twinSettingsSub = TwinService.streamSettings().listen((settings) {
      if (mounted) setState(() => _twinSettings = settings);
    });
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      if (_scrollController.offset > 240 && !_showScrollToBottom) {
        setState(() => _showScrollToBottom = true);
      } else if (_scrollController.offset <= 240 && _showScrollToBottom) {
        setState(() => _showScrollToBottom = false);
      }
    }
  }

  void _onTextChanged() {
    final isTyping = _messageController.text.trim().isNotEmpty;
    ChatService.setTypingStatus(_chatId, _myUid!, isTyping);
    final text = _messageController.text;
    final intent = AIService.detectSchedulingIntent(text);
    if (intent?.matchedPhrase != _detectedIntent?.matchedPhrase) {
      _detectedIntent = intent;
    }
    if (mounted) setState(() {});
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      final textToPaste = clipboardData?.text;
      if (textToPaste != null && textToPaste.isNotEmpty) {
        final currentText = _messageController.text;
        final selection = _messageController.selection;
        if (selection.isValid && selection.start >= 0 && selection.end <= currentText.length) {
          final newText = currentText.replaceRange(selection.start, selection.end, textToPaste);
          _messageController.value = TextEditingValue(
            text: newText,
            selection: TextSelection.collapsed(offset: selection.start + textToPaste.length),
          );
        } else {
          final newText = currentText + textToPaste;
          _messageController.value = TextEditingValue(
            text: newText,
            selection: TextSelection.collapsed(offset: newText.length),
          );
        }
        _focusNode.requestFocus();
        _onTextChanged();
      }
    } catch (e) {
      debugPrint('Error pasting from clipboard: $e');
    }
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _audioRecorder.dispose();
    _twinSettingsSub?.cancel();
    TwinService.flushTraining(); // flush any pending training batch on exit
    ChatService.setTypingStatus(_chatId, _myUid!, false);
    _messageController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Detects URLs in [text] and renders them as tappable coloured spans.
  /// Also applies search-highlight spans when [query] is non-empty.
  Widget _buildRichText(
    String text,
    String query,
    TextStyle defaultStyle,
    Color highlightColor,
  ) {
    // URL regex that matches http/https and bare www. links
    final urlRegex = RegExp(
      r'(https?://[^\s]+|www\.[^\s]+)',
      caseSensitive: false,
    );

    // Split the text into segments: links vs plain
    final segments = <_TextSegment>[];
    int cursor = 0;
    for (final match in urlRegex.allMatches(text)) {
      if (match.start > cursor) {
        segments.add(_TextSegment(text.substring(cursor, match.start), isLink: false));
      }
      segments.add(_TextSegment(match.group(0)!, isLink: true));
      cursor = match.end;
    }
    if (cursor < text.length) {
      segments.add(_TextSegment(text.substring(cursor), isLink: false));
    }

    // Build TextSpan list with optional search highlight
    final spans = <InlineSpan>[];
    final linkStyle = defaultStyle.copyWith(
      color: const Color(0xFF67D7D7), // Teal / mint-ish link colour
      decoration: TextDecoration.underline,
      decorationColor: const Color(0xFF67D7D7),
    );

    for (final seg in segments) {
      if (seg.isLink) {
        final url = seg.text.startsWith('http') ? seg.text : 'https://${seg.text}';
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: GestureDetector(
              onTap: () async {
                final uri = Uri.tryParse(url);
                if (uri != null && await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: Text(seg.text, style: linkStyle),
            ),
          ),
        );
      } else if (query.isEmpty) {
        spans.add(TextSpan(text: seg.text, style: defaultStyle));
      } else {
        // Apply search highlights within non-link segment
        final lowerSeg = seg.text.toLowerCase();
        final lowerQuery = query.toLowerCase();
        int start = 0;
        while (true) {
          final idx = lowerSeg.indexOf(lowerQuery, start);
          if (idx == -1) {
            if (start < seg.text.length) {
              spans.add(TextSpan(text: seg.text.substring(start), style: defaultStyle));
            }
            break;
          }
          if (idx > start) {
            spans.add(TextSpan(text: seg.text.substring(start, idx), style: defaultStyle));
          }
          spans.add(TextSpan(
            text: seg.text.substring(idx, idx + query.length),
            style: defaultStyle.copyWith(
              backgroundColor: highlightColor,
              color: Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ));
          start = idx + query.length;
        }
      }
    }

    return RichText(text: TextSpan(children: spans));
  }

  void _scrollToMatchedIndex(int listIndex) {
    if (_scrollController.hasClients) {
      final targetOffset = listIndex * 70.0;
      _scrollController.animateTo(
        targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _editGroupOrContactName() {
    if (widget.isGroup) {
      final isCreatorOrAdmin = _isGroupAdmin || _groupCreatorId == _myUid || (_groupParticipants?.isNotEmpty == true && _groupParticipants!.first == _myUid);
      if (!isCreatorOrAdmin) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Only the group creator can edit the group name.'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
        return;
      }

      final controller = TextEditingController(text: _displayName);
      showDialog(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: AppTheme.border),
          ),
          title: const Text('Edit Group Name', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Enter group name...',
              hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
              filled: true,
              fillColor: AppTheme.surfaceElevated,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.mint)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.mint,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final newName = controller.text.trim();
                if (newName.isNotEmpty && _myUid != null) {
                  await ChatService.updateGroupName(
                    chatId: _chatId,
                    newName: newName,
                    updaterUid: _myUid!,
                    updaterName: _myName ?? 'Creator',
                  );
                  if (mounted) setState(() => _displayName = newName);
                }
                if (context.mounted) Navigator.pop(dialogCtx);
              },
              child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      return;
    }

    final controller = TextEditingController(text: _displayName);
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppTheme.border),
        ),
        title: const Text('Edit Contact Nickname', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Enter nickname...',
            hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
            filled: true,
            fillColor: AppTheme.surfaceElevated,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.mint)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.mint,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && _myUid != null) {
                await ContactService.updateContactNickname(
                  myUid: _myUid!,
                  peerUid: widget.peerUid,
                  newNickname: newName,
                );
                if (mounted) setState(() => _displayName = newName);
              }
              if (context.mounted) Navigator.pop(dialogCtx);
            },
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showAddGroupMembersSheet() {
    if (_myUid == null) return;
    final Set<String> newlySelectedUids = {};
    final Map<String, String> newlySelectedNames = {};
    final existingUids = Set<String>.from(_groupParticipants ?? widget.groupParticipants ?? []);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Container(
                height: MediaQuery.of(context).size.height * 0.75,
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.group_add_rounded, color: AppTheme.mint, size: 22),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Add Members to Group',
                              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (newlySelectedUids.isNotEmpty)
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.mint,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              onPressed: () async {
                                final uids = newlySelectedUids.toList();
                                final names = uids.map((id) => newlySelectedNames[id] ?? 'Contact').toList();
                                Navigator.pop(sheetCtx);

                                try {
                                  await ChatService.addParticipantsToGroup(
                                    chatId: _chatId,
                                    newMemberUids: uids,
                                    newMemberNames: names,
                                    adderUid: _myUid!,
                                    adderName: _myName ?? 'Member',
                                  );

                                  if (mounted) {
                                    setState(() {
                                      _groupParticipants = [...?_groupParticipants, ...uids];
                                    });
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Added ${names.join(", ")} to the group!'),
                                          backgroundColor: AppTheme.mintDark,
                                        ),
                                      );
                                    }
                                  }
                                } catch (e) {
                                  if (mounted && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Failed to add members: $e'),
                                        backgroundColor: Colors.redAccent,
                                      ),
                                    );
                                  }
                                }
                              },
                              child: Text(
                                'Add (${newlySelectedUids.length})',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Divider(color: AppTheme.border),

                    Expanded(
                      child: StreamBuilder<List<Map<String, dynamic>>>(
                        stream: ContactService.streamContacts(_myUid!),
                        builder: (context, snap) {
                          final contacts = snap.data ?? [];
                          if (contacts.isEmpty) {
                            return const Center(
                              child: Text(
                                'No paired contacts found.',
                                style: TextStyle(color: AppTheme.textMuted),
                              ),
                            );
                          }

                          return ListView.builder(
                            itemCount: contacts.length,
                            itemBuilder: (context, idx) {
                              final c = contacts[idx];
                              final uid = c['uid'] as String? ?? '';
                              final name = c['name'] as String? ?? 'Contact';
                              final avatar = c['avatar'] as String?;
                              final isAlreadyInGroup = existingUids.contains(uid);
                              final isSelected = newlySelectedUids.contains(uid);

                              return ListTile(
                                enabled: !isAlreadyInGroup,
                                onTap: isAlreadyInGroup
                                    ? null
                                    : () {
                                        setSheetState(() {
                                          if (isSelected) {
                                            newlySelectedUids.remove(uid);
                                            newlySelectedNames.remove(uid);
                                          } else {
                                            newlySelectedUids.add(uid);
                                            newlySelectedNames[uid] = name;
                                          }
                                        });
                                      },
                                leading: CircleAvatar(
                                  backgroundColor: isAlreadyInGroup
                                      ? Colors.white12
                                      : (isSelected ? AppTheme.mint : AppTheme.surfaceElevated),
                                  backgroundImage: MediaStorageService.getAvatarProvider(avatar),
                                  child: (avatar == null || avatar.isEmpty)
                                      ? Text(
                                          name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                          style: TextStyle(
                                            color: isAlreadyInGroup
                                                ? AppTheme.textMuted
                                                : (isSelected ? Colors.black : AppTheme.mint),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        )
                                      : null,
                                ),
                                title: Text(
                                  name,
                                  style: TextStyle(
                                    color: isAlreadyInGroup ? AppTheme.textMuted : Colors.white,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  ),
                                ),
                                subtitle: isAlreadyInGroup
                                    ? const Text(
                                        'Already in group',
                                        style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                                      )
                                    : null,
                                trailing: isAlreadyInGroup
                                    ? const Icon(Icons.check_circle_rounded, color: Colors.white24, size: 20)
                                    : Icon(
                                        isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                                        color: isSelected ? AppTheme.mint : AppTheme.textMuted,
                                        size: 22,
                                      ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatusTick(String? status, bool isMe, {dynamic rawReadBy, dynamic rawDeliveredTo}) {
    if (!isMe) return const SizedBox.shrink();

    final readBy = rawReadBy is Map ? Map<String, dynamic>.from(rawReadBy) : null;
    final deliveredTo = rawDeliveredTo is Map ? Map<String, dynamic>.from(rawDeliveredTo) : null;

    bool hasOthersRead = false;
    if (readBy != null && _myUid != null) {
      hasOthersRead = readBy.keys.any((uid) => uid != _myUid);
    }

    bool hasOthersDelivered = false;
    if (deliveredTo != null && _myUid != null) {
      hasOthersDelivered = deliveredTo.keys.any((uid) => uid != _myUid);
    }

    if (status == 'read' || hasOthersRead) {
      return const Icon(Icons.done_all_rounded, color: Color(0xFF38BDF8), size: 15.5);
    } else if (status == 'delivered' || hasOthersDelivered) {
      return const Icon(Icons.done_all_rounded, color: Colors.white70, size: 15.5);
    } else if (status == 'sent') {
      return const Icon(Icons.done_rounded, color: Colors.white60, size: 15.5);
    } else if (status == 'failed') {
      return const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 13.5);
    } else {
      return const Icon(Icons.access_time_rounded, color: Colors.white38, size: 12.5);
    }
  }

  void _onEmojiSelected(String emoji) {
    final text = _messageController.text;
    final textSelection = _messageController.selection;
    final newText = textSelection.isValid
        ? text.replaceRange(textSelection.start, textSelection.end, emoji)
        : text + emoji;
    final newSelectionIndex = textSelection.isValid
        ? textSelection.start + emoji.length
        : newText.length;

    _messageController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newSelectionIndex),
    );
    _onTextChanged();
  }

  void _onBackspacePressed() {
    final text = _messageController.text;
    if (text.isEmpty) return;

    final characters = text.characters;
    final newText = characters.take(characters.length - 1).toString();
    _messageController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
    _onTextChanged();
  }

  Future<void> _sendPendingFile(File file, {String? caption}) async {
    try {
      final path = file.path.toLowerCase();
      final fileName = file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : 'file_${DateTime.now().millisecondsSinceEpoch}';
      final fileSize = await file.length();
      final replyPayload = _replyingTo;

      String type = 'file';
      String category = 'Documents';
      String mime = 'application/octet-stream';

      if (path.endsWith('.jpg') || path.endsWith('.jpeg') || path.endsWith('.png') || path.endsWith('.webp') || path.endsWith('.gif')) {
        type = 'image';
        category = 'Images';
        mime = 'image/jpeg';
      } else if (path.endsWith('.mp4') || path.endsWith('.mkv') || path.endsWith('.mov') || path.endsWith('.3gp')) {
        type = 'video';
        category = 'Videos';
        mime = 'video/mp4';
      } else if (path.endsWith('.mp3') || path.endsWith('.m4a') || path.endsWith('.wav') || path.endsWith('.aac') || path.endsWith('.ogg')) {
        type = 'audio';
        category = 'VoiceNotes';
        mime = 'audio/m4a';
      }

      final localFile = await MediaStorageService.saveOutgoingFile(
        sourceFile: file,
        category: category,
        targetFileName: fileName,
      );

      final remoteUrl = await MediaStorageService.uploadEphemeralMedia(
        file: localFile,
        chatId: _chatId,
        fileName: fileName,
        contentType: mime,
      );

      ChatService.sendMessage(
        chatId: _chatId,
        senderId: _myUid!,
        senderName: _myName!,
        receiverId: widget.peerUid,
        text: caption ?? (type == 'image' ? 'Photo' : type == 'video' ? 'Video' : fileName),
        type: type,
        mediaUrl: remoteUrl,
        fileName: fileName,
        fileSize: fileSize,
        localPath: localFile.path,
        replyTo: replyPayload,
        isGroup: widget.isGroup,
        groupParticipants: _groupParticipants ?? widget.groupParticipants,
      );
    } catch (e) {
      debugPrint("Error sending pending file: $e");
    }
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty && _pendingShareFiles.isEmpty) return;
    final replyPayload = _replyingTo;

    // Immediate tactile feedback (WhatsApp haptic response)
    HapticFeedback.lightImpact();
    SoundService.instance.playMessageSent();

    _messageController.clear();
    ChatService.setTypingStatus(_chatId, _myUid!, false);

    if (_pendingShareFiles.isNotEmpty) {
      setState(() => _replyingTo = null);
      final filesToSend = List<File>.from(_pendingShareFiles);
      setState(() => _pendingShareFiles.clear());

      for (int i = 0; i < filesToSend.length; i++) {
        final isLast = i == filesToSend.length - 1;
        await _sendPendingFile(
          filesToSend[i],
          caption: (isLast && text.isNotEmpty) ? text : null,
        );
      }
      return;
    }

    // 0ms Optimistic UI Insertion: The bubble appears IMMEDIATELY with clock icon (Icons.access_time_rounded)
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}_${_myUid != null && _myUid!.length >= 4 ? _myUid!.substring(0, 4) : 'usr'}';
    final optimisticMessage = <String, dynamic>{
      'id': tempId,
      'clientTempId': tempId,
      'senderId': _myUid,
      'senderName': _myName,
      'receiverId': widget.peerUid,
      'text': text,
      'type': 'text',
      'mediaUrl': null,
      'fileName': null,
      'fileSize': null,
      'duration': null,
      'localPath': null,
      'replyTo': replyPayload,
      'poll': null,
      'timestamp': Timestamp.now(),
      'status': 'sending', // Renders the clock icon (Icons.access_time_rounded)
      'isGroup': widget.isGroup,
      'isOptimistic': true,
      'readBy': {_myUid!: Timestamp.now()},
      'deliveredTo': {_myUid!: Timestamp.now()},
    };

    setState(() {
      _optimisticMessages.insert(0, optimisticMessage);
      _replyingTo = null;
    });

    // Instant smooth scroll to bottom
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    }

    // Fire network send concurrently in background without blocking UI
    ChatService.sendMessage(
      chatId: _chatId,
      senderId: _myUid!,
      senderName: _myName!,
      receiverId: widget.peerUid,
      text: text,
      replyTo: replyPayload,
      isGroup: widget.isGroup,
      groupParticipants: _groupParticipants ?? widget.groupParticipants,
      clientTempId: tempId,
    ).catchError((err) {
      debugPrint("Error sending message: $err");
      if (mounted) {
        setState(() {
          final idx = _optimisticMessages.indexWhere((m) => m['clientTempId'] == tempId);
          if (idx != -1) {
            _optimisticMessages[idx]['status'] = 'error';
          }
        });
      }
      return '';
    });

    // ── AI Twin: silently learn from every outgoing message ────────────────
    if (_twinSettings.isEnabled) {
      TwinService.learnFromMessage(text); // fire & forget — never blocks UI
    }

    // Dismiss twin bar if user manually typed and sent
    if (_showTwinReplyBar) {
      setState(() {
        _showTwinReplyBar = false;
        _twinReplyCandidates = [];
      });
    }
  }

  /// Called when a new incoming peer message arrives — triggers twin reply generation
  Future<void> _onIncomingMessageForTwin(Map<String, dynamic> message) async {
    if (!_twinSettings.isEnabled) return;
    if (_twinSettings.excludedChatIds.contains(_chatId)) return;
    final senderId = message['senderId'] as String? ?? '';
    if (senderId == _myUid || senderId.isEmpty) return;
    final msgText = message['text'] as String? ?? '';
    if (msgText.trim().isEmpty) return;

    setState(() {
      _twinReplyCandidates = [];
    });

    final context = _localCachedMessages.take(10).toList().reversed.toList();
    final replies = await TwinService.generateReplies(
      incomingMessage: msgText,
      context: context,
      senderName: widget.peerName,
      chatTitle: _displayName,
      isGroup: widget.isGroup,
    );

    if (!mounted) return;
    setState(() {
      _twinReplyCandidates = replies;
      _showTwinReplyBar = replies.isNotEmpty;
    });

    // Autonomous mode: auto-send top candidate after a natural ~2s pause
    if (_twinSettings.isAutonomousActive && replies.isNotEmpty) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      final autoReply = replies.first;
      ChatService.sendMessage(
        chatId: _chatId,
        senderId: _myUid!,
        senderName: _myName!,
        receiverId: widget.peerUid,
        text: autoReply,
        isGroup: widget.isGroup,
        groupParticipants: _groupParticipants ?? widget.groupParticipants,
      ).catchError((e) {
        debugPrint('Twin auto-send failed: $e');
        return '';
      });
      TwinService.learnFromMessage(autoReply);
      if (mounted) {
        setState(() {
          _showTwinReplyBar = false;
          _twinReplyCandidates = [];
        });
      }
    }
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    final tempId = 'temp_img_${DateTime.now().millisecondsSinceEpoch}';
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 65,
      );
      if (picked == null) return;

      final sourceFile = File(picked.path);
      final fileName = 'img_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final replyPayload = _replyingTo;
      if (_replyingTo != null) setState(() => _replyingTo = null);

      // 1. Save local copy first for immediate 0ms offline rendering
      final localFile = await MediaStorageService.saveOutgoingFile(
        sourceFile: sourceFile,
        category: 'Images',
        targetFileName: fileName,
      );
      final fileSize = await localFile.length();

      // 2. Immediately insert 0ms optimistic message bubble into chat
      final optimisticMsg = <String, dynamic>{
        'id': tempId,
        'clientTempId': tempId,
        'senderId': _myUid,
        'senderName': _myName,
        'receiverId': widget.peerUid,
        'text': 'Photo',
        'type': 'image',
        'mediaUrl': null,
        'fileName': fileName,
        'fileSize': fileSize,
        'localPath': localFile.path,
        'replyTo': replyPayload,
        'timestamp': Timestamp.now(),
        'status': 'uploading',
        'isUploading': true,
        'uploadProgress': 0.0,
        'isGroup': widget.isGroup,
        'isOptimistic': true,
        'readBy': {_myUid!: Timestamp.now()},
        'deliveredTo': {_myUid!: Timestamp.now()},
      };

      setState(() {
        _optimisticMessages.insert(0, optimisticMsg);
      });

      if (_scrollController.hasClients) {
        _scrollController.animateTo(0.0, duration: const Duration(milliseconds: 120), curve: Curves.easeOut);
      }

      // 3. Upload with real-time percentage progress hook
      final downloadUrl = await MediaStorageService.uploadEphemeralMedia(
        file: localFile,
        chatId: _chatId,
        fileName: fileName,
        contentType: 'image/jpeg',
        onProgress: (sent, total) {
          if (total > 0 && mounted) {
            final pct = (sent / total).clamp(0.0, 1.0);
            final idx = _optimisticMessages.indexWhere((m) => m['clientTempId'] == tempId);
            if (idx != -1 && mounted) {
              setState(() {
                _optimisticMessages[idx]['uploadProgress'] = pct;
              });
            }
          }
        },
      );

      final idx = _optimisticMessages.indexWhere((m) => m['clientTempId'] == tempId);
      if (idx != -1 && mounted) {
        setState(() {
          _optimisticMessages[idx]['mediaUrl'] = downloadUrl;
          _optimisticMessages[idx]['isUploading'] = false;
          _optimisticMessages[idx]['status'] = 'sent';
        });
      }

      // 4. Send message to Firestore
      await ChatService.sendMessage(
        chatId: _chatId,
        senderId: _myUid!,
        senderName: _myName!,
        receiverId: widget.peerUid,
        text: 'Photo',
        type: 'image',
        mediaUrl: downloadUrl,
        fileName: fileName,
        fileSize: fileSize,
        localPath: localFile.path,
        replyTo: replyPayload,
        isGroup: widget.isGroup,
        groupParticipants: _groupParticipants ?? widget.groupParticipants,
        clientTempId: tempId,
      );
    } catch (e) {
      debugPrint("Failed to upload image: $e");
      final idx = _optimisticMessages.indexWhere((m) => m['clientTempId'] == tempId);
      if (idx != -1 && mounted) {
        setState(() {
          _optimisticMessages[idx]['isUploading'] = false;
          _optimisticMessages[idx]['status'] = 'failed';
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload image: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  /// Picks multiple images from gallery with HD/Standard quality toggle, then sends as a gallery bubble.
  Future<void> _pickAndSendGallery() async {
    try {
      final picker = ImagePicker();

      // Quality picker dialog
      bool useHD = false;
      if (mounted) {
        final choice = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppTheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: AppTheme.border)),
            title: const Text('Photo Quality', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            content: const Text('Choose quality before picking photos.', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
            actions: [
              TextButton.icon(
                icon: const Icon(Icons.hd_rounded, color: AppTheme.mint),
                label: const Text('HD', style: TextStyle(color: AppTheme.mint, fontWeight: FontWeight.bold)),
                onPressed: () => Navigator.pop(ctx, true),
              ),
              TextButton.icon(
                icon: const Icon(Icons.sd_rounded, color: Colors.white60),
                label: const Text('Standard', style: TextStyle(color: Colors.white60)),
                onPressed: () => Navigator.pop(ctx, false),
              ),
            ],
          ),
        );
        if (choice == null) return;
        useHD = choice;
      }

      final picked = await picker.pickMultiImage(
        imageQuality: useHD ? 92 : 65,
        maxWidth: useHD ? 1920 : 800,
        maxHeight: useHD ? 1920 : 800,
      );
      if (picked.isEmpty) return;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Uploading ${picked.length} photo${picked.length == 1 ? '' : 's'}...'),
            backgroundColor: AppTheme.mintDark,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      final replyPayload = _replyingTo;
      if (_replyingTo != null) setState(() => _replyingTo = null);

      final List<Map<String, dynamic>> imageEntries = [];
      for (int i = 0; i < picked.length; i++) {
        final sourceFile = File(picked[i].path);
        final fileName = 'img_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
        final localFile = await MediaStorageService.saveOutgoingFile(
          sourceFile: sourceFile, category: 'Images', targetFileName: fileName,
        );
        final url = await MediaStorageService.uploadEphemeralMedia(
          file: localFile, chatId: _chatId, fileName: fileName, contentType: 'image/jpeg',
        );
        imageEntries.add({'url': url, 'localPath': localFile.path, 'fileName': fileName});
      }

      // If only one photo picked, send as normal image bubble
      if (imageEntries.length == 1) {
        final e = imageEntries.first;
        ChatService.sendMessage(
          chatId: _chatId, senderId: _myUid!, senderName: _myName!,
          receiverId: widget.peerUid, text: 'Photo', type: 'image',
          mediaUrl: e['url'] as String?, fileName: e['fileName'] as String?,
          localPath: e['localPath'] as String?,
          replyTo: replyPayload, isGroup: widget.isGroup,
          groupParticipants: _groupParticipants ?? widget.groupParticipants,
        );
        return;
      }

      ChatService.sendGallery(
        chatId: _chatId, senderId: _myUid!, senderName: _myName!,
        receiverId: widget.peerUid, images: imageEntries,
        isGroup: widget.isGroup,
        groupParticipants: _groupParticipants ?? widget.groupParticipants,
      );
    } catch (e) {
      debugPrint("Failed to pick/send gallery: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload photos: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final tempDir = await getTemporaryDirectory();
        final path = '${tempDir.path}/vn_${DateTime.now().millisecondsSinceEpoch}.m4a';
        _recordTempPath = path;

        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000),
          path: path,
        );

        SoundService.instance.playRecordStart();

        setState(() {
          _isRecording = true;
          _recordDuration = 0;
          _showEmojiPicker = false;
        });

        _recordTimer?.cancel();
        _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (mounted) {
            setState(() => _recordDuration++);
          }
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission is required to record voice notes.')),
          );
        }
      }
    } catch (e) {
      debugPrint("Error starting audio recording: $e");
    }
  }

  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    try {
      await _audioRecorder.stop();
      SoundService.instance.playRecordStop();
      if (_recordTempPath != null) {
        final f = File(_recordTempPath!);
        if (await f.exists()) await f.delete();
      }
    } catch (e) {
      debugPrint("Error cancelling recording: $e");
    }
    if (mounted) {
      setState(() {
        _isRecording = false;
        _isRecordingLocked = false;
        _recordDuration = 0;
        _recordTempPath = null;
      });
    }
  }

  Future<void> _stopAndSendRecording() async {
    _recordTimer?.cancel();
    final recordedSeconds = _recordDuration;
    try {
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        _isRecordingLocked = false;
        _recordDuration = 0;
      });

      if (path == null || recordedSeconds < 1) {
        return;
      }

      final recordedFile = File(path);
      final fileName = 'vn_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final replyPayload = _replyingTo;
      if (_replyingTo != null) setState(() => _replyingTo = null);

      // 1. Save locally to LiChat/VoiceNotes
      final localFile = await MediaStorageService.saveOutgoingFile(
        sourceFile: recordedFile,
        category: 'VoiceNotes',
        targetFileName: fileName,
      );

      // 2. Upload ephemeral copy to Firebase Storage
      final remoteUrl = await MediaStorageService.uploadEphemeralMedia(
        file: localFile,
        chatId: _chatId,
        fileName: fileName,
        contentType: 'audio/m4a',
      );

      // 3. Send message with localPath and remoteUrl
      ChatService.sendMessage(
        chatId: _chatId,
        senderId: _myUid!,
        senderName: _myName!,
        receiverId: widget.peerUid,
        text: 'Voice note (${MediaStorageService.formatDuration(recordedSeconds)})',
        type: 'audio',
        mediaUrl: remoteUrl,
        fileName: fileName,
        fileSize: await localFile.length(),
        duration: recordedSeconds,
        localPath: localFile.path,
        replyTo: replyPayload,
        isGroup: widget.isGroup,
        groupParticipants: _groupParticipants ?? widget.groupParticipants,
      );
    } catch (e) {
      debugPrint("Error sending voice note: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send voice note: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _pickAndSendFile() async {
    final tempId = 'temp_file_${DateTime.now().millisecondsSinceEpoch}';
    try {
      final result = await FilePicker.pickFiles();
      if (result == null || result.files.isEmpty) return;

      final pickedFile = result.files.single;
      if (pickedFile.path == null) return;

      final sourceFile = File(pickedFile.path!);
      final fileName = pickedFile.name;
      final fileSize = pickedFile.size;
      final replyPayload = _replyingTo;
      if (_replyingTo != null) setState(() => _replyingTo = null);

      // 1. Save locally to LiChat/Documents
      final localFile = await MediaStorageService.saveOutgoingFile(
        sourceFile: sourceFile,
        category: 'Documents',
        targetFileName: fileName,
      );

      // 2. Immediately insert 0ms optimistic message bubble into chat
      final optimisticMsg = <String, dynamic>{
        'id': tempId,
        'clientTempId': tempId,
        'senderId': _myUid,
        'senderName': _myName,
        'receiverId': widget.peerUid,
        'text': fileName,
        'type': 'file',
        'mediaUrl': null,
        'fileName': fileName,
        'fileSize': fileSize,
        'localPath': localFile.path,
        'replyTo': replyPayload,
        'timestamp': Timestamp.now(),
        'status': 'uploading',
        'isUploading': true,
        'uploadProgress': 0.0,
        'isGroup': widget.isGroup,
        'isOptimistic': true,
        'readBy': {_myUid!: Timestamp.now()},
        'deliveredTo': {_myUid!: Timestamp.now()},
      };

      setState(() {
        _optimisticMessages.insert(0, optimisticMsg);
      });

      if (_scrollController.hasClients) {
        _scrollController.animateTo(0.0, duration: const Duration(milliseconds: 120), curve: Curves.easeOut);
      }

      // 3. Upload with real-time percentage progress hook
      final remoteUrl = await MediaStorageService.uploadEphemeralMedia(
        file: localFile,
        chatId: _chatId,
        fileName: fileName,
        contentType: 'application/octet-stream',
        onProgress: (sent, total) {
          if (total > 0 && mounted) {
            final pct = (sent / total).clamp(0.0, 1.0);
            final idx = _optimisticMessages.indexWhere((m) => m['clientTempId'] == tempId);
            if (idx != -1 && mounted) {
              setState(() {
                _optimisticMessages[idx]['uploadProgress'] = pct;
              });
            }
          }
        },
      );

      final idx = _optimisticMessages.indexWhere((m) => m['clientTempId'] == tempId);
      if (idx != -1 && mounted) {
        setState(() {
          _optimisticMessages[idx]['mediaUrl'] = remoteUrl;
          _optimisticMessages[idx]['isUploading'] = false;
          _optimisticMessages[idx]['status'] = 'sent';
        });
      }

      // 4. Send message to Firestore
      await ChatService.sendMessage(
        chatId: _chatId,
        senderId: _myUid!,
        senderName: _myName!,
        receiverId: widget.peerUid,
        text: fileName,
        type: 'file',
        mediaUrl: remoteUrl,
        fileName: fileName,
        fileSize: fileSize,
        localPath: localFile.path,
        replyTo: replyPayload,
        isGroup: widget.isGroup,
        groupParticipants: _groupParticipants ?? widget.groupParticipants,
        clientTempId: tempId,
      );
    } catch (e) {
      debugPrint("Error picking and sending file: $e");
      final idx = _optimisticMessages.indexWhere((m) => m['clientTempId'] == tempId);
      if (idx != -1 && mounted) {
        setState(() {
          _optimisticMessages[idx]['isUploading'] = false;
          _optimisticMessages[idx]['status'] = 'failed';
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send file: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _pickAndSendVideo(ImageSource source) async {
    final tempId = 'temp_vid_${DateTime.now().millisecondsSinceEpoch}';
    try {
      final picker = ImagePicker();
      final picked = await picker.pickVideo(
        source: source,
        maxDuration: const Duration(minutes: 10),
      );
      if (picked == null) return;

      final sourceFile = File(picked.path);
      final fileSize = await sourceFile.length();

      // Check 100 MB limit (server supports up to 100 MB after Nginx update)
      if (fileSize > 100 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Video exceeds 100 MB limit. Please select a shorter or compressed video.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      final fileName = 'vid_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final replyPayload = _replyingTo;
      if (_replyingTo != null) setState(() => _replyingTo = null);

      // 1. Save local copy first for immediate 0ms preview
      final localFile = await MediaStorageService.saveOutgoingFile(
        sourceFile: sourceFile,
        category: 'Videos',
        targetFileName: fileName,
      );

      // 2. Immediately insert 0ms optimistic message bubble into chat
      final optimisticMsg = <String, dynamic>{
        'id': tempId,
        'clientTempId': tempId,
        'senderId': _myUid,
        'senderName': _myName,
        'receiverId': widget.peerUid,
        'text': 'Video',
        'type': 'video',
        'mediaUrl': null,
        'fileName': fileName,
        'fileSize': fileSize,
        'localPath': localFile.path,
        'replyTo': replyPayload,
        'timestamp': Timestamp.now(),
        'status': 'uploading',
        'isUploading': true,
        'uploadProgress': 0.0,
        'isGroup': widget.isGroup,
        'isOptimistic': true,
        'readBy': {_myUid!: Timestamp.now()},
        'deliveredTo': {_myUid!: Timestamp.now()},
      };

      setState(() {
        _optimisticMessages.insert(0, optimisticMsg);
      });

      if (_scrollController.hasClients) {
        _scrollController.animateTo(0.0, duration: const Duration(milliseconds: 120), curve: Curves.easeOut);
      }

      // 3. Chunked streaming upload with live inline progress update
      final downloadUrl = await MediaStorageService.uploadEphemeralMedia(
        file: localFile,
        chatId: _chatId,
        fileName: fileName,
        contentType: 'video/mp4',
        onProgress: (sent, total) {
          if (total > 0 && mounted) {
            final pct = (sent / total).clamp(0.0, 1.0);
            final idx = _optimisticMessages.indexWhere((m) => m['clientTempId'] == tempId);
            if (idx != -1 && mounted) {
              setState(() {
                _optimisticMessages[idx]['uploadProgress'] = pct;
              });
            }
          }
        },
      );

      final idx = _optimisticMessages.indexWhere((m) => m['clientTempId'] == tempId);
      if (idx != -1 && mounted) {
        setState(() {
          _optimisticMessages[idx]['mediaUrl'] = downloadUrl;
          _optimisticMessages[idx]['isUploading'] = false;
          _optimisticMessages[idx]['status'] = 'sent';
        });
      }

      // 4. Send message to Firestore
      await ChatService.sendMessage(
        chatId: _chatId,
        senderId: _myUid!,
        senderName: _myName!,
        receiverId: widget.peerUid,
        text: 'Video',
        type: 'video',
        mediaUrl: downloadUrl,
        fileName: fileName,
        fileSize: fileSize,
        localPath: localFile.path,
        replyTo: replyPayload,
        isGroup: widget.isGroup,
        groupParticipants: _groupParticipants ?? widget.groupParticipants,
        clientTempId: tempId,
      );
    } catch (e) {
      debugPrint("Failed to upload video: $e");
      final idx = _optimisticMessages.indexWhere((m) => m['clientTempId'] == tempId);
      if (idx != -1 && mounted) {
        setState(() {
          _optimisticMessages[idx]['isUploading'] = false;
          _optimisticMessages[idx]['status'] = 'failed';
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload video: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _showVideoSourceDialog() {
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
                leading: const Icon(Icons.videocam_rounded, color: Colors.orangeAccent),
                title: const Text('Record Video', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndSendVideo(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.video_library_rounded, color: Colors.pinkAccent),
                title: const Text('Choose from Gallery', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndSendVideo(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAttachmentSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildAttachOption(
                      icon: Icons.insert_drive_file_rounded,
                      label: 'Document',
                      color: Colors.deepPurpleAccent,
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndSendFile();
                      },
                    ),
                    _buildAttachOption(
                      icon: Icons.camera_alt_rounded,
                      label: 'Camera',
                      color: Colors.pinkAccent,
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndSendImage(ImageSource.camera);
                      },
                    ),
                    _buildAttachOption(
                      icon: Icons.image_rounded,
                      label: 'Gallery',
                      color: Colors.purpleAccent,
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndSendImage(ImageSource.gallery);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildAttachOption(
                      icon: Icons.videocam_rounded,
                      label: 'Video',
                      color: Colors.redAccent,
                      onTap: () {
                        Navigator.pop(ctx);
                        _showVideoSourceDialog();
                      },
                    ),
                    _buildAttachOption(
                      icon: Icons.photo_library_rounded,
                      label: 'Multi-Photo',
                      color: Colors.tealAccent,
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndSendGallery();
                      },
                    ),
                    _buildAttachOption(
                      icon: Icons.poll_rounded,
                      label: 'Poll',
                      color: Colors.amberAccent,
                      onTap: () {
                        Navigator.pop(ctx);
                        CreatePollDialog.show(
                          context,
                          onPollCreated: (question, options, allowMultiple) {
                            if (_myUid == null) return;
                            ChatService.sendPoll(
                              chatId: _chatId,
                              senderId: _myUid!,
                              senderName: _myName ?? 'Me',
                              receiverId: widget.peerUid,
                              question: question,
                              options: options,
                              allowMultiple: allowMultiple,
                              isGroup: widget.isGroup,
                              groupParticipants: _groupParticipants ?? widget.groupParticipants,
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildAttachOption(
                      icon: Icons.calendar_month_rounded,
                      label: 'Schedule Call',
                      color: Colors.lightBlueAccent,
                      onTap: () {
                        Navigator.pop(ctx);
                        _openScheduleCallDialog();
                      },
                    ),
                    const SizedBox(width: 80),
                    const SizedBox(width: 80),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAttachOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  void _startCall({required bool isVideo}) async {
    if (widget.isGroup) {
      List<String> memberUids = List<String>.from(_groupParticipants ?? widget.groupParticipants ?? []);
      if (memberUids.isEmpty) {
        final doc = await FirebaseFirestore.instance.collection('chats').doc(_chatId).get();
        if (doc.exists) {
          memberUids = List<String>.from(doc.data()?['participants'] ?? []);
        }
      }

      final roomName = await CallSignalingService.initiateGroupCall(
        callerId: _myUid!,
        callerName: _myName!,
        callerAvatar: FirebaseAuth.instance.currentUser?.photoURL,
        groupId: _chatId,
        groupName: widget.peerName,
        memberUids: memberUids,
        isVideo: isVideo,
      );

      if (mounted) {
        // Pre-warm LiveKit token for instant connection on group call join
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          CallSignalingService.getOrFetchToken(
            roomName: roomName,
            userId: user.uid,
            userName: _myName ?? 'User',
          );
        }
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ActiveCallScreen(
              callId: roomName, // roomName is unique per group call session
              roomName: roomName,
              isVideo: isVideo,
              peerName: widget.peerName,
            ),
          ),
        );
      }
      return;
    }

    if (!widget.isGroup && _myUid != null) {
      final isContact = await ContactService.isContactVerified(_myUid!, widget.peerUid);
      if (!isContact) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Cannot call ${widget.peerName}. You must be verified contacts.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }
    }

    final callId = await CallSignalingService.initiateCall(
      callerId: _myUid!,
      callerName: _myName!,
      callerAvatar: FirebaseAuth.instance.currentUser?.photoURL,
      receiverId: widget.peerUid,
      receiverName: widget.peerName,
      receiverAvatar: widget.peerAvatar,
      isVideo: isVideo,
    );

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OutgoingCallScreen(
            callId: callId,
            peerName: widget.peerName,
            peerAvatar: widget.peerAvatar,
            isVideo: isVideo,
          ),
        ),
      );
    }
  }

  void _openScheduleCallDialog({
    String? initialTopic,
    DateTime? initialDateTime,
    bool initialIsVideo = true,
  }) async {
    if (_myUid == null) return;
    final result = await ScheduleCallDialog.show(
      context,
      chatId: _chatId,
      callerId: _myUid!,
      callerName: _myName ?? 'Me',
      callerAvatar: FirebaseAuth.instance.currentUser?.photoURL,
      receiverId: widget.peerUid,
      receiverName: _displayName,
      isGroup: widget.isGroup,
      participants: _groupParticipants ?? widget.groupParticipants,
      initialTopic: initialTopic,
      initialDateTime: initialDateTime,
      initialIsVideo: initialIsVideo,
    );
    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Call scheduled: \"${result['topic']}\" 📅"),
          backgroundColor: AppTheme.primary,
        ),
      );
    }
  }

  void _openChatDigest() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('chats')
          .doc(_chatId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(40)
          .get();

      final list = snap.docs.reversed.map((doc) => doc.data()).toList();
      if (list.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("No messages yet to summarize")),
          );
        }
        return;
      }

      if (mounted) {
        ChatDigestSheet.show(
          context,
          messages: list,
          targetUserName: _myName ?? 'You',
          chatTitle: _displayName,
          onShareToChat: (text) {
            if (_myUid != null) {
              ChatService.sendMessage(
                chatId: _chatId,
                senderId: _myUid!,
                senderName: _myName ?? 'Me',
                receiverId: widget.peerUid,
                text: text,
                isGroup: widget.isGroup,
                groupParticipants: _groupParticipants ?? widget.groupParticipants,
              );
            }
          },
        );
      }
    } catch (e) {
      debugPrint("Error opening chat digest: $e");
    }
  }

  void _showMagicComposerMenu() {
    final currentText = _messageController.text.trim();
    if (currentText.isEmpty) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded, color: AppTheme.mint, size: 20),
                    SizedBox(width: 8),
                    Text(
                      "Magic Composer (AI Polish)",
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildComposeOption(ctx, "💼 Executive & Professional", "professional"),
                _buildComposeOption(ctx, "⚡ Punchy & Concise (TL;DR)", "concise"),
                _buildComposeOption(ctx, "😊 Friendly & Warm", "friendly"),
                _buildComposeOption(ctx, "🔤 Fix Grammar & Spelling", "fix_grammar"),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildComposeOption(BuildContext ctx, String label, String mode) {
    return ListTile(
      title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
      onTap: () async {
        Navigator.pop(ctx);
        final currentText = _messageController.text;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                SizedBox(width: 12),
                Text("Polishing draft with Gemini AI..."),
              ],
            ),
            duration: Duration(seconds: 4),
          ),
        );
        final refined = await AIService.refineDraft(text: currentText, mode: mode);
        if (mounted && refined.isNotEmpty) {
          setState(() {
            _messageController.text = refined;
            _messageController.selection = TextSelection.fromPosition(
              TextPosition(offset: refined.length),
            );
          });
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Draft updated with AI ✨")),
          );
        }
      },
    );
  }

  void _translateMessageText(String messageText) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            SizedBox(width: 12),
            Text("Translating message with AI..."),
          ],
        ),
        duration: Duration(seconds: 3),
      ),
    );

    final res = await AIService.translateMessage(text: messageText, targetLang: 'English');
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.translate_rounded, color: AppTheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    "AI Translation (${res['source'] ?? 'auto'} → English)",
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Text(
                  res['text'] ?? messageText,
                  style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: res['text'] ?? messageText));
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Translation copied")),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16, color: Colors.white70),
                    label: const Text("Copy", style: TextStyle(color: Colors.white70)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMessageOptions(String messageId, bool isMe, Map<String, dynamic> data) {
    final emojis = ['👍', '❤️', '😂', '😮', '😢', '🙏', '🔥'];
    final text = data['text'] as String? ?? '';
    final senderName = data['senderName'] as String? ?? (isMe ? 'You' : _displayName);
    final type = data['type'] as String? ?? 'text';
    if (data['isOptimistic'] == true) return;

    HapticFeedback.mediumImpact();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Quick Reaction Emoji Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: emojis.map((emoji) {
                      return InkWell(
                        onTap: () {
                          Navigator.pop(modalCtx);
                          ChatService.setReaction(_chatId, messageId, emoji, myUid: _myUid);
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          child: Text(emoji, style: const TextStyle(fontSize: 26)),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 14),

                // 2. Action Tiles (Hick's Law: 4 core primary actions)
                if (isMe && type != 'deleted' && type != 'system')
                  ListTile(
                    leading: const Icon(Icons.info_outline_rounded, color: AppTheme.mint),
                    title: const Text('Info', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    subtitle: widget.isGroup
                        ? const Text('See who has read this message', style: TextStyle(color: AppTheme.textMuted, fontSize: 11.5))
                        : null,
                    onTap: () {
                      Navigator.pop(modalCtx);
                      MessageInfoSheet.show(
                        context,
                        chatId: _chatId,
                        messageId: messageId,
                        messageData: data,
                        isGroup: widget.isGroup,
                        groupParticipants: _groupParticipants,
                      );
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.reply_rounded, color: AppTheme.mint),
                  title: const Text('Reply', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(modalCtx);
                    setState(() {
                      _replyingTo = {
                        'id': messageId,
                        'senderName': senderName,
                        'text': text.isNotEmpty ? text : (type == 'audio' ? '🎤 Voice note' : (type == 'image' ? '📷 Photo' : '📄 Document')),
                        'type': type,
                      };
                    });
                    _focusNode.requestFocus();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.forward_rounded, color: AppTheme.mint),
                  title: const Text('Forward', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(modalCtx);
                    ForwardMessageDialog.show(context, data);
                  },
                ),
                // Share to Status
                if (type != 'deleted' && type != 'system')
                  ListTile(
                    leading: const Icon(Icons.auto_stories_rounded, color: AppTheme.mint),
                    title: const Text('Share to Status', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Post as your 24h status update', style: TextStyle(color: AppTheme.textMuted, fontSize: 11.5)),
                    onTap: () {
                      Navigator.pop(modalCtx);
                      ShareToStatusDialog.show(context, data);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.share_rounded, color: AppTheme.mint),
                  title: const Text('Share to Other Apps', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  onTap: () async {
                    Navigator.pop(modalCtx);
                    if (type == 'text' && text.isNotEmpty) {
                      SharePlus.instance.share(ShareParams(text: text));
                    } else {
                      final localPath = data['localPath'] as String?;
                      final mediaUrl = data['mediaUrl'] as String?;
                      final fileName = data['fileName'] as String? ?? 'media';
                      if (localPath != null && await File(localPath).exists()) {
                        SharePlus.instance.share(ShareParams(files: [XFile(localPath)], text: fileName));
                      } else if (mediaUrl != null && mediaUrl.isNotEmpty) {
                        final downloaded = await MediaStorageService.downloadMediaToLocal(
                          remoteUrl: mediaUrl,
                          category: type == 'image' ? 'Images' : (type == 'audio' ? 'VoiceNotes' : (type == 'video' ? 'Videos' : 'Documents')),
                          targetFileName: fileName,
                        );
                        if (downloaded != null) {
                          SharePlus.instance.share(ShareParams(files: [XFile(downloaded.path)], text: fileName));
                        }
                      }
                    }
                  },
                ),
                if (type != 'text')
                  ListTile(
                    leading: const Icon(Icons.download_rounded, color: AppTheme.mint),
                    title: const Text('Save to Device', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    onTap: () async {
                      Navigator.pop(modalCtx);
                      final localPath = data['localPath'] as String?;
                      final mediaUrl = data['mediaUrl'] as String?;
                      final fileName = data['fileName'] as String? ?? 'media_${DateTime.now().millisecondsSinceEpoch}.jpg';
                      File? fileToSave;
                      if (localPath != null && await File(localPath).exists()) {
                        fileToSave = File(localPath);
                      } else if (mediaUrl != null && mediaUrl.isNotEmpty) {
                        fileToSave = await MediaStorageService.downloadMediaToLocal(
                          remoteUrl: mediaUrl,
                          category: type == 'image' ? 'Images' : (type == 'audio' ? 'VoiceNotes' : (type == 'video' ? 'Videos' : 'Documents')),
                          targetFileName: fileName,
                        );
                      }
                      if (fileToSave != null && await fileToSave.exists()) {
                        Directory? targetDir;
                        if (Platform.isAndroid) {
                          final extDir = Directory('/storage/emulated/0/Download');
                          if (await extDir.exists()) targetDir = extDir;
                        }
                        targetDir ??= await getApplicationDocumentsDirectory();
                        final saved = await fileToSave.copy('${targetDir.path}/LiChat_$fileName');
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: AppTheme.surfaceElevated,
                              content: Text('Saved to ${saved.path}'),
                            ),
                          );
                        }
                      }
                    },
                  ),
                if (text.isNotEmpty && type == 'text' && type != 'deleted')
                  ListTile(
                    leading: const Icon(Icons.copy_rounded, color: AppTheme.textSecondary),
                    title: const Text('Copy Text', style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(modalCtx);
                      Clipboard.setData(ClipboardData(text: text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Message copied to clipboard'), duration: Duration(seconds: 1)),
                      );
                    },
                  ),
                if (text.isNotEmpty && type == 'text' && type != 'deleted')
                  ListTile(
                    leading: const Icon(Icons.translate_rounded, color: AppTheme.primary),
                    title: const Text('Translate (AI)', style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(modalCtx);
                      _translateMessageText(text);
                    },
                  ),
                if (isMe && type == 'text' && type != 'deleted')
                  ListTile(
                    leading: const Icon(Icons.edit_rounded, color: AppTheme.mint),
                    title: const Text('Edit Message', style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(modalCtx);
                      _showEditMessageDialog(messageId, text);
                    },
                  ),
                // Star / Unstar Message
                if (type != 'deleted' && type != 'system')
                  FutureBuilder<bool>(
                    future: ChatService.isMessageStarred(
                      myUid: _myUid ?? '',
                      messageId: messageId,
                    ),
                    builder: (context, snap) {
                      final isStarred = snap.data ?? false;
                      return ListTile(
                        leading: Icon(
                          isStarred ? Icons.star_rounded : Icons.star_outline_rounded,
                          color: const Color(0xFFF59E0B),
                        ),
                        title: Text(
                          isStarred ? 'Unstar Message' : 'Star Message',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                        onTap: () async {
                          Navigator.pop(modalCtx);
                          if (_myUid == null) return;
                          // Capture context-dependent objects before the async gap
                          final messenger = ScaffoldMessenger.of(context);
                          final nav = Navigator.of(context);
                          await ChatService.toggleStarMessage(
                            myUid: _myUid!,
                            chatId: _chatId,
                            messageId: messageId,
                            messageData: data,
                            currentlyStarred: isStarred,
                          );
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                backgroundColor: AppTheme.surfaceElevated,
                                behavior: SnackBarBehavior.floating,
                                content: Row(
                                  children: [
                                    Icon(
                                      isStarred ? Icons.star_outline_rounded : Icons.star_rounded,
                                      color: const Color(0xFFF59E0B),
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      isStarred ? 'Message unstarred' : 'Message starred!',
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                    if (!isStarred) ...[
                                      const Spacer(),
                                      GestureDetector(
                                        onTap: () {
                                          messenger.hideCurrentSnackBar();
                                          nav.push(
                                            MaterialPageRoute(
                                              builder: (_) => const StarredMessagesScreen(),
                                            ),
                                          );
                                        },
                                        child: const Text(
                                          'VIEW ALL',
                                          style: TextStyle(
                                            color: AppTheme.mint,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                duration: const Duration(seconds: 3),
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),
                if (type != 'deleted')
                  ListTile(
                    leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                    title: const Text('Delete Message', style: TextStyle(color: Colors.redAccent)),
                    onTap: () {
                      Navigator.pop(modalCtx);
                      if (isMe) {
                        showDialog(
                          context: context,
                          builder: (deleteCtx) => AlertDialog(
                            backgroundColor: AppTheme.surfaceElevatedColor(context),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                            title: Text('Delete Message?', style: TextStyle(color: AppTheme.text(context), fontWeight: FontWeight.bold)),
                            content: Text(
                              'Do you want to delete this message for everyone or only for yourself?',
                              style: TextStyle(color: AppTheme.textMut(context), fontSize: 14),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(deleteCtx);
                                  ChatService.deleteMessage(_chatId, messageId);
                                },
                                child: Text('Delete for Me', style: TextStyle(color: AppTheme.textMut(context))),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.callRed,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: () {
                                  Navigator.pop(deleteCtx);
                                  ChatService.deleteMessageForEveryone(_chatId, messageId);
                                },
                                child: const Text('Delete for Everyone', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        );
                      } else {
                        ChatService.deleteMessage(_chatId, messageId);
                      }
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showEditMessageDialog(String messageId, String initialText) {
    final editController = TextEditingController(text: initialText);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppTheme.surfaceElevatedColor(context),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(
            'Edit Message',
            style: TextStyle(color: AppTheme.text(context), fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: editController,
            autofocus: true,
            maxLines: null,
            style: TextStyle(color: AppTheme.text(context)),
            decoration: InputDecoration(
              hintText: 'Edit your message...',
              hintStyle: TextStyle(color: AppTheme.textMut(context)),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: AppTheme.mint),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: AppTheme.textMut(context))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.mintColor(context),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                final newText = editController.text.trim();
                Navigator.pop(ctx);
                if (newText.isNotEmpty && newText != initialText) {
                  ChatService.editMessage(_chatId, messageId, newText);
                }
              },
              child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _confirmDeleteContact() {
    final myUid = _myUid;
    if (widget.isGroup || myUid == null) return;
    final surface = AppTheme.surfaceElevatedColor(context);
    final border = AppTheme.borderColor(context);
    final textPrim = AppTheme.text(context);
    final textSec = AppTheme.textSec(context);
    final textMuted = AppTheme.textMut(context);

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: border),
        ),
        title: Text('Delete Contact?', style: TextStyle(color: textPrim, fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text(
          'Remove $_displayName from your verified contacts list? You will no longer see them in your contacts.',
          style: TextStyle(color: textSec, fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('Cancel', style: TextStyle(color: textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await ContactService.deleteContact(myUid, widget.peerUid);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Removed $_displayName from contacts.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmBlockContact() {
    final myUid = _myUid;
    if (widget.isGroup || myUid == null) return;
    final surface = AppTheme.surfaceElevatedColor(context);
    final border = AppTheme.borderColor(context);
    final textPrim = AppTheme.text(context);
    final textSec = AppTheme.textSec(context);
    final textMuted = AppTheme.textMut(context);

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: border),
        ),
        title: Text('Block $_displayName?', style: TextStyle(color: textPrim, fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text(
          'Blocked contacts cannot send you messages or calls, and are removed from your contacts list.',
          style: TextStyle(color: textSec, fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('Cancel', style: TextStyle(color: textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await ContactService.blockContact(myUid, widget.peerUid);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Blocked $_displayName.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Block', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = AppTheme.bg(context);
    final surface = AppTheme.surfaceColor(context);
    final surfaceElevated = AppTheme.surfaceElevatedColor(context);
    final textPrim = AppTheme.text(context);
    final textMuted = AppTheme.textMut(context);
    final textSec = AppTheme.textSec(context);
    final border = AppTheme.borderColor(context);
    final mint = AppTheme.mintColor(context);
    final isDark = AppTheme.isDarkMode(context);
    final bubbleMe = AppTheme.bubbleMeColor(context);
    final bubbleOther = AppTheme.bubbleOtherColor(context);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        titleSpacing: 0,
        backgroundColor: surface,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: _isSearching
            ? IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: textPrim),
                onPressed: () {
                  setState(() {
                    _isSearching = false;
                    _searchQuery = '';
                    _searchController.clear();
                    _matchedIndices.clear();
                    _currentMatchIndex = 0;
                  });
                },
              )
            : (widget.showBackButton && Navigator.of(context).canPop()
                ? IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: textPrim),
                    onPressed: () => Navigator.pop(context),
                  )
                : null),
        title: _isSearching
            ? Container(
                height: 40,
                decoration: BoxDecoration(
                  color: surfaceElevated,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: mint.withValues(alpha: 0.4)),
                ),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: TextStyle(color: textPrim, fontSize: 14.5),
                  decoration: InputDecoration(
                    hintText: 'Search in conversation...',
                    hintStyle: TextStyle(color: textMuted, fontSize: 13.5),
                    prefixIcon: Icon(Icons.search_rounded, color: mint, size: 18),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.close_rounded, color: textMuted, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                                _matchedIndices.clear();
                                _currentMatchIndex = 0;
                              });
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val.trim();
                      _currentMatchIndex = 0;
                    });
                  },
                ),
              )
            : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: ChatService.streamChatMeta(_chatId),
                builder: (context, metaSnap) {
                  final meta = metaSnap.data?.data();
                  final typingMap = meta?['typing'] as Map<String, dynamic>?;
                  _isPeerTyping = typingMap?[widget.peerUid] == true;

                  if (widget.isGroup && meta != null) {
                    final liveName = meta['name'] ?? meta['groupName'];
                    if (liveName != null && (liveName as String).isNotEmpty && liveName != _displayName) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _displayName = liveName);
                      });
                    }
                  }

                  final canEdit = !widget.isGroup ||
                      _isGroupAdmin ||
                      _groupCreatorId == _myUid ||
                      (_groupParticipants?.isNotEmpty == true && _groupParticipants!.first == _myUid);

                  return Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          if (widget.peerAvatar != null && widget.peerAvatar!.isNotEmpty) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ImageViewerScreen(
                                  imageUrl: widget.peerAvatar,
                                  title: _displayName,
                                  subtitle: widget.isGroup ? 'Group Avatar' : 'Profile Picture',
                                ),
                              ),
                            );
                          } else if (!widget.isGroup) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ContactProfileScreen(
                                  peerUid: widget.peerUid,
                                  peerName: _displayName,
                                  peerAvatar: widget.peerAvatar,
                                ),
                              ),
                            );
                          }
                        },
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: mint.withValues(alpha: 0.2),
                          backgroundImage: MediaStorageService.getAvatarProvider(widget.peerAvatar),
                          child: (widget.peerAvatar == null || widget.peerAvatar!.isEmpty)
                              ? Text(
                                  _displayName.isNotEmpty ? _displayName[0].toUpperCase() : 'U',
                                  style: TextStyle(color: mint, fontWeight: FontWeight.bold, fontSize: 16),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            if (!widget.isGroup) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ContactProfileScreen(
                                    peerUid: widget.peerUid,
                                    peerName: _displayName,
                                    peerAvatar: widget.peerAvatar,
                                  ),
                                ),
                              );
                            } else {
                              _editGroupOrContactName();
                            }
                          },
                          behavior: HitTestBehavior.opaque,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      _displayName,
                                      style: TextStyle(color: textPrim, fontSize: 16, fontWeight: FontWeight.bold),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (canEdit) ...[
                                    const SizedBox(width: 5),
                                    Icon(Icons.edit_outlined, color: textMuted, size: 13),
                                  ],
                                ],
                              ),
                              if (widget.isGroup)
                                Text(
                                  _isChannel
                                      ? '${_groupParticipants?.length ?? widget.groupParticipants?.length ?? 0} subscribers'
                                      : '${_groupParticipants?.length ?? widget.groupParticipants?.length ?? 0} members',
                                  style: TextStyle(color: mint, fontSize: 11.5),
                                )
                              else if (_isPeerTyping)
                                Text(
                                  'typing...',
                                  style: TextStyle(
                                    color: mint,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              else
                                StreamBuilder<UserPresence>(
                                  stream: PresenceService.streamUserPresence(widget.peerUid),
                                  builder: (context, presenceSnap) {
                                    final presence = presenceSnap.data;
                                    final isOnline = presence?.isOnline == true;
                                    final statusText = presence?.statusText ?? 'Offline';

                                    return Row(
                                      children: [
                                        if (isOnline) ...[
                                          Container(
                                            width: 7,
                                            height: 7,
                                            margin: const EdgeInsets.only(right: 5),
                                            decoration: BoxDecoration(
                                              color: mint,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        ],
                                        Text(
                                          statusText,
                                          style: TextStyle(
                                            color: isOnline ? mint : textMuted,
                                            fontSize: 12,
                                            fontWeight: isOnline ? FontWeight.w600 : FontWeight.normal,
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
        actions: _isSearching
            ? [
                if (_matchedIndices.isNotEmpty) ...[
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        '${_currentMatchIndex + 1}/${_matchedIndices.length}',
                        style: TextStyle(color: mint, fontSize: 12.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.keyboard_arrow_up_rounded, color: mint, size: 24),
                    tooltip: 'Previous match',
                    onPressed: () {
                      if (_matchedIndices.isNotEmpty) {
                        setState(() {
                          _currentMatchIndex = (_currentMatchIndex - 1 + _matchedIndices.length) % _matchedIndices.length;
                        });
                        _scrollToMatchedIndex(_matchedIndices[_currentMatchIndex]);
                      }
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.keyboard_arrow_down_rounded, color: mint, size: 24),
                    tooltip: 'Next match',
                    onPressed: () {
                      if (_matchedIndices.isNotEmpty) {
                        setState(() {
                          _currentMatchIndex = (_currentMatchIndex + 1) % _matchedIndices.length;
                        });
                        _scrollToMatchedIndex(_matchedIndices[_currentMatchIndex]);
                      }
                    },
                  ),
                ] else if (_searchQuery.isNotEmpty) ...[
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: Text(
                        '0 matches',
                        style: TextStyle(color: textMuted, fontSize: 12),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 4),
              ]
            : (widget.isGroup
                ? [
                    IconButton(
                      icon: const Icon(Icons.auto_awesome_rounded, color: AppTheme.mint, size: 20),
                      tooltip: 'Catch Me Up (AI Digest)',
                      onPressed: _openChatDigest,
                    ),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert_rounded, color: mint),
                      color: AppTheme.surfaceElevatedColor(context),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      onSelected: (val) {
                        if (val == 'schedule_call') {
                          _openScheduleCallDialog();
                        } else 
                        if (val == 'info') {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GroupInfoScreen(
                                chatId: _chatId,
                                groupName: _displayName,
                                groupAvatar: widget.peerAvatar,
                                isCurrentUserAdmin: _isGroupAdmin,
                              ),
                            ),
                          );
                        } else if (val == 'add') {
                          _showAddGroupMembersSheet();
                        } else if (val == 'search') {
                          setState(() => _isSearching = true);
                        } else if (val == 'voice_call') {
                          _startCall(isVideo: false);
                        } else if (val == 'video_call') {
                          _startCall(isVideo: true);
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'info',
                          child: Row(children: [
                            Icon(Icons.info_outline_rounded, color: mint, size: 18),
                            const SizedBox(width: 10),
                            Text(_isChannel ? 'Channel Info' : 'Group Info', style: TextStyle(color: AppTheme.text(context))),
                          ]),
                        ),
                        if (!_isChannel) ...[
                          PopupMenuItem(
                            value: 'voice_call',
                            child: Row(children: [
                              Icon(Icons.call_rounded, color: mint, size: 18),
                              const SizedBox(width: 10),
                              Text('Voice Call', style: TextStyle(color: AppTheme.text(context))),
                            ]),
                          ),
                          PopupMenuItem(
                            value: 'video_call',
                            child: Row(children: [
                              Icon(Icons.videocam_rounded, color: mint, size: 18),
                              const SizedBox(width: 10),
                              Text('Video Call', style: TextStyle(color: AppTheme.text(context))),
                            ]),
                          ),
                        ],
                        PopupMenuItem(
                          value: 'schedule_call',
                          child: Row(children: [
                            Icon(Icons.calendar_month_rounded, color: mint, size: 18),
                            const SizedBox(width: 10),
                            Text('Schedule Call', style: TextStyle(color: AppTheme.text(context))),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'search',
                          child: Row(children: [
                            Icon(Icons.search_rounded, color: mint, size: 18),
                            const SizedBox(width: 10),
                            Text('Search Messages', style: TextStyle(color: AppTheme.text(context))),
                          ]),
                        ),
                        if (_isGroupAdmin || !_isChannel)
                          PopupMenuItem(
                            value: 'add',
                            child: Row(children: [
                              Icon(Icons.person_add_alt_1_rounded, color: mint, size: 18),
                              const SizedBox(width: 10),
                              Text(_isChannel ? 'Add Subscribers' : 'Add Members', style: TextStyle(color: AppTheme.text(context))),
                            ]),
                          ),
                      ],
                    ),
                    const SizedBox(width: 6),
                  ]
                : [
                    IconButton(
                      icon: const Icon(Icons.auto_awesome_rounded, color: AppTheme.mint, size: 20),
                      tooltip: 'Catch Me Up (AI Digest)',
                      onPressed: _openChatDigest,
                    ),
                    IconButton(
                      icon: Icon(Icons.call_rounded, color: mint),
                      tooltip: 'Voice Call',
                      onPressed: () => _startCall(isVideo: false),
                    ),
                    IconButton(
                      icon: Icon(Icons.videocam_rounded, color: mint),
                      tooltip: 'Video Call',
                      onPressed: () => _startCall(isVideo: true),
                    ),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert_rounded, color: mint),
                      color: AppTheme.surfaceElevatedColor(context),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      onSelected: (val) {
                        if (val == 'schedule_call') {
                          _openScheduleCallDialog();
                        } else if (val == 'search') {
                          setState(() => _isSearching = true);
                        } else if (val == 'profile') {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ContactProfileScreen(
                                peerUid: widget.peerUid,
                                peerName: widget.peerName,
                                peerAvatar: widget.peerAvatar,
                              ),
                            ),
                          );
                        } else if (val == 'delete_contact') {
                          _confirmDeleteContact();
                        } else if (val == 'block_contact') {
                          _confirmBlockContact();
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'profile',
                          child: Row(children: [
                            Icon(Icons.person_outline_rounded, color: mint, size: 18),
                            const SizedBox(width: 10),
                            Text('View Profile', style: TextStyle(color: AppTheme.text(context))),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'schedule_call',
                          child: Row(children: [
                            Icon(Icons.calendar_month_rounded, color: mint, size: 18),
                            const SizedBox(width: 10),
                            Text('Schedule Call', style: TextStyle(color: AppTheme.text(context))),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'search',
                          child: Row(children: [
                            Icon(Icons.search_rounded, color: mint, size: 18),
                            const SizedBox(width: 10),
                            Text('Search Messages', style: TextStyle(color: AppTheme.text(context))),
                          ]),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'delete_contact',
                          child: const Row(children: [
                            Icon(Icons.person_remove_rounded, color: Colors.redAccent, size: 18),
                            SizedBox(width: 10),
                            Text('Delete Contact', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'block_contact',
                          child: Row(children: [
                            Icon(Icons.block_rounded, color: Colors.red.shade400, size: 18),
                            const SizedBox(width: 10),
                            Text('Block Contact', style: TextStyle(color: Colors.red.shade400, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ],
                    ),
                    const SizedBox(width: 6),
                  ]
              ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              ChatVaultHeader(
                chatId: _chatId,
                chatTitle: _displayName,
                currentUserId: _myUid ?? '',
                recentMessages: _localCachedMessages,
              ),
              // Messages Stream
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: ChatService.streamMessages(_chatId),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      debugPrint('Message stream error: ${snapshot.error}');
                    }

                    if (!snapshot.hasData && _optimisticMessages.isEmpty && _localCachedMessages.isEmpty) {
                      if (_hasStreamTimedOut || snapshot.hasError) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.chat_bubble_outline_rounded, color: mint.withValues(alpha: 0.5), size: 48),
                              const SizedBox(height: 12),
                              Text('No messages yet', style: TextStyle(color: textPrim, fontSize: 16, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text('Send a message to start the conversation!', style: TextStyle(color: textMuted, fontSize: 13)),
                            ],
                          ),
                        );
                      }
                      return Center(child: CircularProgressIndicator(color: mint));
                    }

                    final docs = snapshot.data?.docs ?? [];

                    // WhatsApp-grade local persistence: cache incoming messages in local SQLite asynchronously
                    if (docs.isNotEmpty) {
                      ChatService.syncMessagesToLocalDb(_chatId, docs);
                    }

                    // Remove optimistic messages that have been confirmed by Firestore
                    if (_optimisticMessages.isNotEmpty && docs.isNotEmpty) {
                      final confirmedClientTempIds = <String>{};
                      final confirmedTexts = <String>{};
                      for (final d in docs) {
                        final data = d.data();
                        if (data['senderId'] == _myUid) {
                          final cId = data['clientTempId'] as String?;
                          if (cId != null && cId.isNotEmpty) {
                            confirmedClientTempIds.add(cId);
                          }
                          confirmedTexts.add('${data['text']}_${data['type']}');
                        }
                      }
                      _optimisticMessages.removeWhere((opt) =>
                          confirmedClientTempIds.contains(opt['clientTempId']) ||
                          confirmedTexts.contains('${opt['text']}_${opt['type']}'));
                    }

                    // Build unified display list (falling back to SQLite local cache for instant 0ms cold-start)
                    final List<Map<String, dynamic>> sourceList = docs.isNotEmpty
                        ? docs.map((d) {
                            final map = Map<String, dynamic>.from(d.data());
                            map['id'] = d.id;
                            return map;
                          }).toList()
                        : _localCachedMessages;

                    if (docs.isNotEmpty && _localCachedMessages.length != sourceList.length) {
                      _localCachedMessages = sourceList;
                    }

                    final displayMessages = <Map<String, dynamic>>[
                      ..._optimisticMessages,
                      ...sourceList,
                    ];

                    // Automatically mark unread incoming messages as read (both 1-on-1 and groups)
                    final unreadIncoming = docs.where((d) {
                      final data = d.data();
                      final isIncoming = data['senderId'] != _myUid;
                      final rawReadBy = data['readBy'];
                      final readBy = rawReadBy is Map ? Map<String, dynamic>.from(rawReadBy) : <String, dynamic>{};
                      final isRead = data['status'] == 'read' || readBy.containsKey(_myUid);
                      return isIncoming && !isRead && !_readMarkedMessageIds.contains(d.id);
                    }).toList();

                    if (unreadIncoming.isNotEmpty && _myUid != null) {
                      // Play WhatsApp-style incoming pop for new messages arriving live
                      if (_hasInitialMessageSnapshotLoaded) {
                        SoundService.instance.playMessageReceived();

                        // ── Trigger AI Twin for the latest incoming message ──
                        final newestIncoming = unreadIncoming.first.data();
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _onIncomingMessageForTwin(newestIncoming);
                        });
                      }
                      for (final d in unreadIncoming) {
                        _readMarkedMessageIds.add(d.id);
                      }
                      final refs = unreadIncoming.map((d) => d.reference).toList();
                      WidgetsBinding.instance.addPostFrameCallback((_) async {
                        try {
                          await ChatService.markMessagesAsReadDirectly(_chatId, _myUid!, refs);
                        } catch (_) {
                          for (final d in unreadIncoming) {
                            _readMarkedMessageIds.remove(d.id);
                          }
                        }
                      });
                    }

                    if (!_hasInitialMessageSnapshotLoaded && snapshot.hasData) {
                      _hasInitialMessageSnapshotLoaded = true;
                    }

                    // Compute matching indices for search
                    if (_searchQuery.isNotEmpty) {
                      final newMatches = <int>[];
                      for (int i = 0; i < displayMessages.length; i++) {
                        final txt = (displayMessages[i]['text'] ?? '').toString().toLowerCase();
                        if (txt.contains(_searchQuery.toLowerCase())) {
                          newMatches.add(i);
                        }
                      }
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && (_matchedIndices.length != newMatches.length || !_listEquals(_matchedIndices, newMatches))) {
                          setState(() {
                            _matchedIndices = newMatches;
                            if (_currentMatchIndex >= newMatches.length) {
                              _currentMatchIndex = 0;
                            }
                          });
                        }
                      });
                    }

                    if (displayMessages.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.mark_chat_read_outlined, size: 48, color: textMuted.withValues(alpha: 0.5)),
                            const SizedBox(height: 12),
                            Text('Say hello! Tap below to start conversation.', style: TextStyle(color: textMuted)),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemCount: displayMessages.length,
                      itemBuilder: (context, index) {
                        final data = displayMessages[index];
                        final messageId = data['id'] as String? ?? 'temp_$index';
                        final isMe = data['senderId'] == _myUid;
                        final senderName = data['senderName'] as String? ?? 'Member';
                        final text = data['text'] ?? '';
                        final type = data['type'] as String? ?? 'text';
                        final mediaUrl = data['mediaUrl'] as String?;
                        final fileName = data['fileName'] as String?;
                        final fileSize = data['fileSize'] as int?;
                        final duration = data['duration'] as int?;
                        final localPath = data['localPath'] as String?;
                        final reaction = data['reaction'] as String?;
                        final reactions = Map<String, dynamic>.from(data['reactions'] ?? {});
                        final status = data['status'] as String?;
                        final replyTo = data['replyTo'] as Map<String, dynamic>?;
                        final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
                        final timeString = timestamp != null ? DateFormat('h:mm a').format(timestamp) : '';
                        final isMatch = _searchQuery.isNotEmpty && text.toString().toLowerCase().contains(_searchQuery.toLowerCase());
                        final isCurrentMatch = _matchedIndices.isNotEmpty &&
                            _currentMatchIndex < _matchedIndices.length &&
                            _matchedIndices[_currentMatchIndex] == index;
                        final bool isText = (type == 'text' || type.isEmpty);
                        final int emojiCount = isText ? EmojiHelper.getEmojiCount(text.toString()) : 0;
                        final bool isPureEmoji = emojiCount > 0 && emojiCount <= 3 && replyTo == null;

                        if (type == 'system') {
                          return Center(
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.black.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.1)
                                      : Colors.black.withValues(alpha: 0.08),
                                ),
                              ),
                              child: Text(
                                text.toString(),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppTheme.textMut(context),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          );
                        }

                        return Align(
                          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                          child: Dismissible(
                            key: ValueKey('swipe_reply_$messageId'),
                            direction: DismissDirection.startToEnd,
                            confirmDismiss: (direction) async {
                              HapticFeedback.lightImpact();
                              setState(() {
                                _replyingTo = {
                                  'id': messageId,
                                  'senderName': senderName,
                                  'text': text.isNotEmpty ? text : (type == 'audio' ? '🎤 Voice note' : (type == 'image' ? '📷 Photo' : (type == 'video' ? '🎥 Video' : '📄 Document'))),
                                  'type': type,
                                };
                              });
                              _focusNode.requestFocus();
                              return false;
                            },
                            background: Container(
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.only(left: 12),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: mint.withValues(alpha: 0.18),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.reply_rounded, color: mint, size: 20),
                              ),
                            ),
                            child: GestureDetector(
                              onLongPress: () {
                                _showMessageOptions(messageId, isMe, data);
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Container(
                                      padding: isPureEmoji
                                          ? const EdgeInsets.symmetric(horizontal: 4, vertical: 2)
                                          : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      decoration: isPureEmoji
                                          ? (isMatch
                                              ? BoxDecoration(
                                                  color: Colors.amberAccent.withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(16),
                                                  border: Border.all(color: Colors.amberAccent, width: 1.5),
                                                )
                                              : const BoxDecoration(color: Colors.transparent))
                                          : BoxDecoration(
                                              color: isMe ? bubbleMe : bubbleOther,
                                              borderRadius: BorderRadius.only(
                                                topLeft: const Radius.circular(18),
                                                topRight: const Radius.circular(18),
                                                bottomLeft: Radius.circular(isMe ? 18 : 4),
                                                bottomRight: Radius.circular(isMe ? 4 : 18),
                                              ),
                                              border: Border.all(
                                                color: isCurrentMatch
                                                    ? Colors.amberAccent
                                                    : (isMatch
                                                        ? mint.withValues(alpha: 0.7)
                                                        : (isMe ? Colors.transparent : border.withValues(alpha: 0.5))),
                                                width: isCurrentMatch ? 2.0 : 1.0,
                                              ),
                                            ),
                                      child: Column(
                                        crossAxisAlignment: isPureEmoji
                                            ? (isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start)
                                            : CrossAxisAlignment.start,
                                        children: [
                                          // Group Sender Label
                                          if (widget.isGroup && !isMe)
                                            Padding(
                                              padding: const EdgeInsets.only(bottom: 4),
                                              child: Text(
                                                senderName,
                                                style: TextStyle(
                                                  color: mint,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),

                                          // Quoted Message Box (if reply)
                                          if (replyTo != null) ...[
                                            Container(
                                              margin: const EdgeInsets.only(bottom: 8),
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withValues(alpha: 0.25),
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border(
                                                  left: BorderSide(color: mint, width: 3.5),
                                                ),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    replyTo['senderName'] ?? 'Reply',
                                                    style: TextStyle(
                                                      color: mint,
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    replyTo['text'] ?? '',
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: Colors.white.withValues(alpha: 0.75),
                                                      fontSize: 12.5,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],

                                          // Gallery (multi-image collage) Bubble
                                          if (type == 'gallery')
                                            MediaGalleryBubble(
                                              images: () {
                                                final urls = (mediaUrl ?? '').split('|||');
                                                final paths = (fileName ?? '').split('|||');
                                                return List.generate(
                                                  urls.length,
                                                  (i) => {
                                                    'url': urls.length > i ? urls[i] : '',
                                                    'localPath': paths.length > i ? paths[i] : '',
                                                  },
                                                );
                                              }(),
                                              isMe: isMe,
                                              senderName: senderName,
                                              caption: text.isNotEmpty && !text.startsWith('📷') ? text : null,
                                            )
                                          // Image Bubble (Zoomable on Tap + Inline Progress Overlay)
                                          else if (type == 'image' && (mediaUrl != null || localPath != null))
                                            Builder(
                                              builder: (ctx) {
                                                final bool isUploading = data['isUploading'] == true || status == 'uploading';
                                                final double uploadProgress = (data['uploadProgress'] as num?)?.toDouble() ?? 0.0;
                                                final bool isFailed = status == 'failed';

                                                return GestureDetector(
                                                  onTap: isUploading ? null : () {
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (_) => ImageViewerScreen(
                                                          imageUrl: mediaUrl,
                                                          localPath: localPath,
                                                          title: senderName,
                                                          subtitle: timeString,
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                  child: Padding(
                                                    padding: const EdgeInsets.only(bottom: 6),
                                                    child: Stack(
                                                      alignment: Alignment.center,
                                                      children: [
                                                        ClipRRect(
                                                          borderRadius: BorderRadius.circular(12),
                                                          child: (localPath != null && File(localPath).existsSync())
                                                              ? Image.file(File(localPath), fit: BoxFit.cover)
                                                              : (mediaUrl != null && mediaUrl.startsWith('data:')
                                                                  ? Image.memory(
                                                                      base64Decode(mediaUrl.substring(mediaUrl.indexOf(',') + 1)),
                                                                      fit: BoxFit.cover,
                                                                    )
                                                                  : Image.network(
                                                                      mediaUrl ?? '',
                                                                      fit: BoxFit.cover,
                                                                      loadingBuilder: (context, child, progress) {
                                                                        if (progress == null) return child;
                                                                        return Container(
                                                                          height: 180,
                                                                          color: Colors.black26,
                                                                          child: Center(
                                                                            child: CircularProgressIndicator(color: mint),
                                                                          ),
                                                                        );
                                                                      },
                                                                      errorBuilder: (context, error, stackTrace) => Container(
                                                                        height: 140,
                                                                        color: Colors.black26,
                                                                        child: const Center(
                                                                          child: Icon(Icons.broken_image_rounded, color: Colors.white54, size: 36),
                                                                        ),
                                                                      ),
                                                                    )),
                                                        ),
                                                        if (isUploading)
                                                          Container(
                                                            padding: const EdgeInsets.all(12),
                                                            decoration: BoxDecoration(
                                                              color: Colors.black.withValues(alpha: 0.7),
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
                                                                    value: uploadProgress > 0 ? uploadProgress : null,
                                                                    strokeWidth: 3.5,
                                                                    color: AppTheme.lilacLight,
                                                                  ),
                                                                ),
                                                                Text(
                                                                  '${(uploadProgress * 100).toInt()}%',
                                                                  style: const TextStyle(
                                                                    color: Colors.white,
                                                                    fontSize: 11,
                                                                    fontWeight: FontWeight.bold,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          )
                                                        else if (isFailed)
                                                          Container(
                                                            padding: const EdgeInsets.all(10),
                                                            decoration: BoxDecoration(
                                                              color: Colors.black.withValues(alpha: 0.75),
                                                              shape: BoxShape.circle,
                                                            ),
                                                            child: const Icon(Icons.refresh_rounded, color: Colors.amberAccent, size: 32),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                );
                                              },
                                            )
                                          // Interactive Video Message Bubble
                                          else if (type == 'video')
                                            VideoMessageBubble(
                                              mediaUrl: mediaUrl,
                                              localPath: localPath,
                                              fileName: fileName,
                                              fileSize: fileSize,
                                              durationSeconds: duration,
                                              isMe: isMe,
                                              senderName: senderName,
                                              timeString: timeString,
                                              isUploading: data['isUploading'] == true || status == 'uploading',
                                              uploadProgress: (data['uploadProgress'] as num?)?.toDouble() ?? 0.0,
                                              uploadFailed: status == 'failed',
                                            )
                                          // Interactive Voice Note Bubble
                                          else if (type == 'audio')
                                            VoiceNoteBubble(
                                              mediaUrl: mediaUrl,
                                              localPath: localPath,
                                              fileName: fileName,
                                              durationSeconds: duration,
                                              isMe: isMe,
                                              messageId: messageId,
                                            )
                                          // Document / File Message Bubble
                                          else if (type == 'file')
                                            FileMessageBubble(
                                              mediaUrl: mediaUrl,
                                              localPath: localPath,
                                              fileName: fileName ?? 'Document',
                                              fileSize: fileSize,
                                              isMe: isMe,
                                              isUploading: data['isUploading'] == true || status == 'uploading',
                                              uploadProgress: (data['uploadProgress'] as num?)?.toDouble() ?? 0.0,
                                              uploadFailed: status == 'failed',
                                            )
                                          // Interactive In-Chat Poll Bubble
                                          else if (type == 'poll')
                                            PollMessageBubble(
                                              chatId: _chatId,
                                              messageId: messageId,
                                              pollData: Map<String, dynamic>.from(data['poll'] ?? {}),
                                              isMe: isMe,
                                            )
                                          // Interactive Scheduled Call Card
                                          else if (type == 'scheduled_call')
                                            ScheduledCallCard(
                                              messageData: data,
                                              currentUserId: _myUid ?? '',
                                              isMe: isMe,
                                            )
                                          // Deleted Message Tombstone
                                          else if (type == 'deleted')
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.block_rounded, size: 14, color: isMe ? Colors.white60 : textMuted),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'This message was deleted',
                                                  style: TextStyle(
                                                    fontStyle: FontStyle.italic,
                                                    color: isMe ? Colors.white70 : textMuted,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ],
                                            )
                                          // Text Message Bubble (with link detection + search highlight OR JumboEmoji)
                                          else if (isPureEmoji)
                                            JumboEmojiView(
                                              text: text.toString(),
                                              count: emojiCount,
                                              isMe: isMe,
                                            )
                                          else
                                            _buildRichText(
                                              text,
                                              _searchQuery,
                                              TextStyle(
                                                color: isMe ? Colors.white : (isDark ? Colors.white : textPrim),
                                                fontSize: 15,
                                              ),
                                              Colors.amberAccent.withValues(alpha: 0.75),
                                            ),

                                          const SizedBox(height: 4),
                                          if (isPureEmoji)
                                            Container(
                                              margin: const EdgeInsets.only(top: 2),
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                              decoration: BoxDecoration(
                                                color: isDark ? Colors.black54 : Colors.black38,
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (data['isEdited'] == true) ...[
                                                    const Text(
                                                      'edited ',
                                                      style: TextStyle(
                                                        fontStyle: FontStyle.italic,
                                                        color: Colors.white70,
                                                        fontSize: 10,
                                                      ),
                                                    ),
                                                  ],
                                                  Text(
                                                    timeString,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                  if (isMe) ...[
                                                    const SizedBox(width: 4),
                                                    _buildStatusTick(status, isMe, rawReadBy: data['readBy'], rawDeliveredTo: data['deliveredTo']),
                                                  ],
                                                ],
                                              ),
                                            )
                                          else
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment: MainAxisAlignment.end,
                                              children: [
                                                if (data['isEdited'] == true) ...[
                                                  Text(
                                                    'edited ',
                                                    style: TextStyle(
                                                      fontStyle: FontStyle.italic,
                                                      color: isMe ? Colors.white60 : (isDark ? Colors.white54 : textMuted),
                                                      fontSize: 10.5,
                                                    ),
                                                  ),
                                                ],
                                                Text(
                                                  timeString,
                                                  style: TextStyle(
                                                    color: isMe ? Colors.white70 : (isDark ? Colors.white60 : textMuted),
                                                    fontSize: 11,
                                                  ),
                                                ),
                                                if (isMe) ...[
                                                  const SizedBox(width: 4),
                                                  _buildStatusTick(status, isMe, rawReadBy: data['readBy'], rawDeliveredTo: data['deliveredTo']),
                                                ],
                                              ],
                                            ),
                                        ],
                                      ),
                                    ),

                                    // Floating Reaction Badge (WhatsApp Multi-Reaction Style)
                                    if (reactions.isNotEmpty || reaction != null)
                                      Positioned(
                                        bottom: -10,
                                        right: isMe ? null : 8,
                                        left: isMe ? 8 : null,
                                        child: GestureDetector(
                                          onTap: () {
                                            _showMessageOptions(messageId, isMe, data);
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: surfaceElevated,
                                              borderRadius: BorderRadius.circular(14),
                                              border: Border.all(color: border),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withValues(alpha: 0.18),
                                                  blurRadius: 4,
                                                  offset: const Offset(0, 1),
                                                ),
                                              ],
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                ...() {
                                                  final uniqueEmojis = reactions.values.map((e) => e.toString()).toSet().toList();
                                                  if (uniqueEmojis.isEmpty && reaction != null) {
                                                    uniqueEmojis.add(reaction);
                                                  }
                                                  return uniqueEmojis.take(3).map((e) => Padding(
                                                    padding: const EdgeInsets.only(right: 2),
                                                    child: Text(e, style: const TextStyle(fontSize: 13)),
                                                  ));
                                                }(),
                                                if (reactions.length > 1)
                                                  Text(
                                                    '${reactions.length}',
                                                    style: TextStyle(
                                                      color: isDark ? Colors.white : textPrim,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              // Quoted Reply Preview Bar above input
              if (_replyingTo != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: surfaceElevated,
                    border: Border(
                      top: BorderSide(color: border.withValues(alpha: 0.8)),
                      left: BorderSide(color: mint, width: 4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.reply_rounded, color: mint, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Replying to ${_replyingTo!['senderName'] ?? 'Message'}',
                              style: TextStyle(color: mint, fontSize: 12.5, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              _replyingTo!['text'] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: textSec, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded, size: 18, color: textMuted),
                        onPressed: () => setState(() => _replyingTo = null),
                      ),
                    ],
                  ),
                ),

              // Pending Shared Files Preview Bar
              if (_pendingShareFiles.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: surfaceElevated,
                    border: Border(top: BorderSide(color: border.withValues(alpha: 0.6))),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.share_rounded, size: 14, color: mint),
                          const SizedBox(width: 6),
                          Text(
                            'Shared items (${_pendingShareFiles.length})',
                            style: TextStyle(color: mint, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => setState(() => _pendingShareFiles.clear()),
                            child: Text(
                              'Clear All',
                              style: TextStyle(color: textMuted, fontSize: 11.5),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 64,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _pendingShareFiles.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, idx) {
                            final file = _pendingShareFiles[idx];
                            final pathLower = file.path.toLowerCase();
                            final isImage = pathLower.endsWith('.jpg') || pathLower.endsWith('.jpeg') || pathLower.endsWith('.png') || pathLower.endsWith('.webp');
                            final isVideo = pathLower.endsWith('.mp4') || pathLower.endsWith('.mkv') || pathLower.endsWith('.mov');
                            final isAudio = pathLower.endsWith('.mp3') || pathLower.endsWith('.m4a') || pathLower.endsWith('.wav');

                            return Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    color: surface,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: border),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: isImage
                                      ? Image.file(file, fit: BoxFit.cover)
                                      : Center(
                                          child: Icon(
                                            isVideo
                                                ? Icons.videocam_rounded
                                                : isAudio
                                                    ? Icons.audiotrack_rounded
                                                    : Icons.insert_drive_file_rounded,
                                            color: mint,
                                            size: 26,
                                          ),
                                        ),
                                ),
                                Positioned(
                                  top: -4,
                                  right: -4,
                                  child: GestureDetector(
                                    onTap: () => setState(() => _pendingShareFiles.removeAt(idx)),
                                    child: Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: BoxDecoration(
                                        color: Colors.black87,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white24, width: 1),
                                      ),
                                      child: const Icon(Icons.close_rounded, size: 12, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),

              // ── AI Twin Reply Bar (slides up above the input box) ──────
              if (_showTwinReplyBar && _twinReplyCandidates.isNotEmpty)
                TwinReplyBar(
                  candidates: _twinReplyCandidates,
                  onDismiss: () => setState(() {
                    _showTwinReplyBar = false;
                    _twinReplyCandidates = [];
                  }),
                  onReplyChosen: (reply, autoSend) {
                    setState(() {
                      _showTwinReplyBar = false;
                      _twinReplyCandidates = [];
                    });
                    if (autoSend) {
                      // Send immediately as user's message
                      _messageController.text = reply;
                      _sendMessage();
                    } else {
                      // Pre-fill the input box so user can tweak before sending
                      _messageController.text = reply;
                      _messageController.selection = TextSelection.fromPosition(
                        TextPosition(offset: reply.length),
                      );
                      _focusNode.requestFocus();
                    }
                  },
                ),

              // Bottom Input Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: surface,
                  border: Border(top: BorderSide(color: border.withValues(alpha: 0.6))),
                ),
                child: SafeArea(
                  top: false,
                  child: _isRecording
                      ? _buildRecordingBar(textPrim, textMuted, mint, isDark)
                      : (!widget.isGroup && _myUid != null)
                          ? StreamBuilder<bool>(
                              stream: ContactService.streamIsContactVerified(_myUid!, widget.peerUid),
                              builder: (context, verifiedSnap) {
                                final isVerified = verifiedSnap.data ?? false;
                                if (!isVerified) {
                                  return _buildUnverifiedGatekeeper(
                                    context: context,
                                    surface: surfaceElevated,
                                    border: border,
                                    textPrim: textPrim,
                                    textSec: textSec,
                                    mint: mint,
                                    isDark: isDark,
                                  );
                                }
                                return _buildInputRow(context, textPrim, textSec, textMuted, border, surfaceElevated, mint, isDark);
                              },
                            )
                          : (_isChannel || _onlyAdminsCanPost) && !_isGroupAdmin
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                  decoration: BoxDecoration(
                                    color: surfaceElevated,
                                    border: Border(top: BorderSide(color: border)),
                                  ),
                                  alignment: Alignment.center,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: mint.withValues(alpha: 0.15),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(Icons.campaign_rounded, color: mint, size: 18),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        'Only channel admins can post messages',
                                        style: TextStyle(
                                          color: textSec,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : _buildInputRow(context, textPrim, textSec, textMuted, border, surfaceElevated, mint, isDark),
                ),
              ),

              // Built-in Emoji Picker Sheet
              if (_showEmojiPicker)
                EmojiPickerSheet(
                  onEmojiSelected: _onEmojiSelected,
                  onBackspacePressed: _onBackspacePressed,
                  onClose: () => setState(() => _showEmojiPicker = false),
                ),
            ],
          ),

          // Scroll to bottom floating action button
          if (_showScrollToBottom)
            Positioned(
              bottom: 90,
              right: 16,
              child: GestureDetector(
                onTap: () {
                  _scrollController.animateTo(
                    0.0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: surfaceElevated,
                    shape: BoxShape.circle,
                    border: Border.all(color: border),
                    boxShadow: [
                      BoxShadow(
                        color: isDark ? Colors.black.withValues(alpha: 0.4) : Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(Icons.keyboard_double_arrow_down_rounded, color: mint, size: 22),
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Modern recording bar with lock-to-record mode, pulse animation, and send.
  Widget _buildRecordingBar(
      Color textPrim, Color textMuted, Color mint, bool isDark) {
    return Row(
      children: [
        // Cancel / Trash
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded,
              color: Colors.redAccent, size: 26),
          onPressed: _cancelRecording,
        ),
        const SizedBox(width: 4),

        // Pulse dot
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.6, end: 1.0),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeInOut,
          builder: (_, scale, __) => Transform.scale(
            scale: scale,
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                  color: Colors.redAccent, shape: BoxShape.circle),
            ),
          ),
          onEnd: () {
            if (mounted && _isRecording) setState(() {});
          },
        ),
        const SizedBox(width: 8),

        // Duration counter
        Text(
          MediaStorageService.formatDuration(_recordDuration),
          style: TextStyle(
              color: textPrim, fontSize: 16, fontWeight: FontWeight.bold),
        ),

        const Spacer(),

        // Lock toggle button
        GestureDetector(
          onTap: () => setState(() => _isRecordingLocked = !_isRecordingLocked),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _isRecordingLocked
                  ? mint.withValues(alpha: 0.18)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: _isRecordingLocked
                      ? mint
                      : textMuted.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isRecordingLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                  color: _isRecordingLocked ? mint : textMuted,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  _isRecordingLocked ? 'Locked' : 'Lock',
                  style: TextStyle(
                      color: _isRecordingLocked ? mint : textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(width: 10),

        // Send button
        GestureDetector(
          onTap: _stopAndSendRecording,
          child: Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: mint,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: mint.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 2)),
              ],
            ),
            child: Icon(Icons.send_rounded,
                color: isDark ? Colors.black : Colors.white, size: 20),
          ),
        ),
      ],
    );
  }

  Widget _buildInputRow(
    BuildContext context,
    Color textPrim,
    Color textSec,
    Color textMuted,
    Color border,
    Color surfaceElevated,
    Color mint,
    bool isDark,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_detectedIntent != null)
          Container(
            margin: const EdgeInsets.only(bottom: 6, left: 12, right: 12),
            child: InkWell(
              onTap: () {
                final intent = _detectedIntent!;
                setState(() => _detectedIntent = null);
                _openScheduleCallDialog(
                  initialTopic: intent.proposedTopic,
                  initialDateTime: intent.suggestedDateTime,
                  initialIsVideo: intent.isVideo,
                );
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E3A8A), Color(0xFF0D9488)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 15),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        "Schedule: " + _detectedIntent!.proposedTopic,
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_forward_rounded, color: Colors.white70, size: 13),
                  ],
                ),
              ),
            ),
          ),
        Row(
          children: [
            // Emoji Keyboard Toggle Button
        IconButton(
          icon: Icon(
            _showEmojiPicker ? Icons.keyboard_rounded : Icons.sentiment_satisfied_alt_rounded,
            color: _showEmojiPicker ? mint : textSec,
            size: 24,
          ),
          onPressed: () {
            if (_showEmojiPicker) {
              setState(() => _showEmojiPicker = false);
              _focusNode.requestFocus();
            } else {
              FocusScope.of(context).unfocus();
              setState(() => _showEmojiPicker = true);
            }
          },
        ),

        // Attachment Button (+)
        IconButton(
          icon: Icon(Icons.attach_file_rounded, color: textSec, size: 24),
          onPressed: _showAttachmentSheet,
        ),

        // Text Field (Multiline with newline Enter key & quick clipboard paste)
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: surfaceElevated,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    focusNode: _focusNode,
                    style: TextStyle(color: textPrim, fontSize: 15),
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    maxLines: 5,
                    minLines: 1,
                    onTap: () {
                      if (_showEmojiPicker) {
                        setState(() => _showEmojiPicker = false);
                      }
                    },
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: TextStyle(color: textMuted),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                if (_messageController.text.isEmpty)
                  GestureDetector(
                    onTap: _pasteFromClipboard,
                    child: Tooltip(
                      message: 'Paste from clipboard',
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4, right: 2),
                        child: Icon(
                          Icons.content_paste_rounded,
                          color: textMuted,
                          size: 19,
                        ),
                      ),
                    ),
                  )
                else
                  GestureDetector(
                    onTap: _showMagicComposerMenu,
                    child: Tooltip(
                      message: 'Magic Composer (AI Polish)',
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4, right: 2),
                        child: Icon(
                          Icons.auto_awesome_rounded,
                          color: mint,
                          size: 19,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),

        // Mic or Send Button
        if (_messageController.text.trim().isEmpty && _pendingShareFiles.isEmpty)
          GestureDetector(
            onTap: _startRecording,
            onLongPress: () async {
              await _startRecording();
              if (mounted) setState(() => _isRecordingLocked = true);
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: mint.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: mint.withValues(alpha: 0.4)),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.mic_rounded, color: mint, size: 20),
                ],
              ),
            ),
          )
        else
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: mint,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.send_rounded, color: isDark ? Colors.black : Colors.white, size: 18),
            ),
          ),
      ],
    ),
      ],
    );
  }

  Widget _buildUnverifiedGatekeeper({
    required BuildContext context,
    required Color surface,
    required Color border,
    required Color textPrim,
    required Color textSec,
    required Color mint,
    required bool isDark,
  }) {
    if (_myUid == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(_myUid)
          .collection('contact_requests')
          .doc(widget.peerUid)
          .snapshots(),
      builder: (context, incomingSnap) {
        final hasIncoming = incomingSnap.data?.exists == true;

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(_myUid)
              .collection('outgoing_requests')
              .doc(widget.peerUid)
              .snapshots(),
          builder: (context, outgoingSnap) {
            final hasOutgoing = outgoingSnap.data?.exists == true;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: (hasIncoming ? mint : Colors.amber).withValues(alpha: 0.4)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: (hasIncoming ? mint : (hasOutgoing ? Colors.blueAccent : Colors.amber)).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          hasIncoming
                              ? Icons.person_add_rounded
                              : (hasOutgoing ? Icons.hourglass_top_rounded : Icons.lock_outline_rounded),
                          color: hasIncoming ? mint : (hasOutgoing ? Colors.blueAccent : Colors.amber),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              hasIncoming
                                  ? 'Incoming Contact Request'
                                  : (hasOutgoing ? 'Request Pending Approval' : 'Verified Contact Required'),
                              style: TextStyle(color: textPrim, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              hasIncoming
                                  ? '${widget.peerName} wants to connect. Accept to start chatting.'
                                  : (hasOutgoing
                                      ? 'Waiting for ${widget.peerName} to accept your contact request.'
                                      : 'You can only chat with verified mutual contacts on LiChat.'),
                              style: TextStyle(color: textSec, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 38,
                    child: hasIncoming
                        ? ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: mint,
                              foregroundColor: isDark ? Colors.black : Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 0,
                            ),
                            icon: const Icon(Icons.check_circle_rounded, size: 16),
                            label: const Text('Accept Contact Request', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                            onPressed: () async {
                              final res = await ContactService.respondToContactRequest(
                                responderUid: _myUid!,
                                responderName: _myName ?? 'LiChat User',
                                responderAvatar: FirebaseAuth.instance.currentUser?.photoURL,
                                senderUid: widget.peerUid,
                                action: 'accept',
                              );
                              if (context.mounted && res['success'] == true) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Contact accepted! You can now chat.')),
                                );
                              }
                            },
                          )
                        : hasOutgoing
                            ? Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Colors.blueAccent.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.hourglass_bottom_rounded, size: 15, color: Colors.blueAccent),
                                    const SizedBox(width: 6),
                                    Text('Request Sent • Waiting for Approval', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w600, fontSize: 12)),
                                  ],
                                ),
                              )
                            : ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: mint,
                                  foregroundColor: isDark ? Colors.black : Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  elevation: 0,
                                ),
                                icon: const Icon(Icons.person_add_rounded, size: 16),
                                label: const Text('Send Contact Request', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                                onPressed: () async {
                                  final res = await ContactService.sendContactRequest(
                                    senderUid: _myUid!,
                                    senderName: _myName ?? 'LiChat User',
                                    senderAvatar: FirebaseAuth.instance.currentUser?.photoURL,
                                    targetUid: widget.peerUid,
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(res['message'] ?? 'Request sent!')),
                                    );
                                  }
                                },
                              ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}


/// Simple data class used by [_ChatConversationScreenState._buildRichText]
/// to split a message string into link and non-link segments.
class _TextSegment {
  const _TextSegment(this.text, {required this.isLink});
  final String text;
  final bool isLink;
}
