import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_theme.dart';
import '../services/call_signaling_service.dart';
import '../services/media_storage_service.dart';
import '../services/active_call_manager.dart';
import 'call_screens.dart';

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({Key? key}) : super(key: key);

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _myUid;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _myUid = FirebaseAuth.instance.currentUser?.uid;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _redial(Map<String, dynamic> callData) async {
    final isCaller = callData['callerId'] == _myUid;
    final targetUid = isCaller ? callData['receiverId'] : callData['callerId'];
    final targetName = isCaller ? callData['receiverName'] : callData['callerName'];
    final isVideo = callData['isVideo'] == true;

    final callId = await CallSignalingService.initiateCall(
      callerId: _myUid!,
      callerName: FirebaseAuth.instance.currentUser?.displayName ?? 'User',
      callerAvatar: FirebaseAuth.instance.currentUser?.photoURL,
      receiverId: targetUid,
      receiverName: targetName,
      isVideo: isVideo,
    );

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OutgoingCallScreen(
            callId: callId,
            peerName: targetName,
            isVideo: isVideo,
          ),
        ),
      );
    }
  }

  String _formatCallDuration(int seconds) {
    if (seconds <= 0) return '';
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m < 60) {
      return s > 0 ? '${m}m ${s}s' : '${m}m';
    }
    final h = m ~/ 60;
    final remM = m % 60;
    return '${h}h ${remM}m';
  }

  Future<void> _deleteCallItem(String callId) async {
    await CallSignalingService.deleteCallHistoryItem(callId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Call log deleted'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = AppTheme.bg(context);
    final textPrim = AppTheme.text(context);
    final textSec = AppTheme.textSec(context);
    final mint = AppTheme.mintColor(context);

    if (_myUid == null) {
      return Scaffold(
        backgroundColor: bg,
        body: Center(child: Text('Please log in to view calls', style: TextStyle(color: textPrim))),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Text(
          'Calls',
          style: TextStyle(fontWeight: FontWeight.bold, color: textPrim, fontSize: 22, letterSpacing: -0.3),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.add_link_rounded, color: mint),
            tooltip: 'Join with call link',
            onPressed: () => _showJoinCallDialog(context),
          ),
          const SizedBox(width: 4),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: mint,
          labelColor: mint,
          unselectedLabelColor: textSec,
          indicatorSize: TabBarIndicatorSize.tab,
          isScrollable: false,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Missed'),
            Tab(text: 'Incoming'),
            Tab(text: 'Outgoing'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCallList(filter: 'all'),
          _buildCallList(filter: 'missed'),
          _buildCallList(filter: 'incoming'),
          _buildCallList(filter: 'outgoing'),
        ],
      ),
    );
  }

  Widget _buildUpcomingScheduledCallsSection() {
    if (_myUid == null) return const SizedBox.shrink();
    final mint = AppTheme.mintColor(context);
    final isDark = AppTheme.isDarkMode(context);
    final textPrim = AppTheme.text(context);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('scheduled_calls')
          .where('participants', arrayContains: _myUid)
          .where('status', isEqualTo: 'scheduled')
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141126) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.alarm_on_rounded, color: AppTheme.primary, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Upcoming Scheduled Calls (' + docs.length.toString() + ')',
                    style: TextStyle(
                      color: textPrim,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...docs.map((d) {
                final data = d.data();
                final topic = data['topic'] ?? 'Scheduled Call';
                final isVideo = data['isVideo'] == true;
                final schedStr = data['scheduledTime'];
                DateTime? dt;
                if (schedStr != null) {
                  try {
                    dt = DateTime.parse(schedStr).toLocal();
                  } catch (_) {}
                }
                final formatted = dt != null
                    ? DateFormat('EEE, MMM d • h:mm a').format(dt)
                    : 'Upcoming';

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                        color: mint,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              topic,
                              style: TextStyle(color: textPrim, fontWeight: FontWeight.w600, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              formatted,
                              style: const TextStyle(color: Colors.amberAccent, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          final callId = data['callId'] ?? d.id;
                          final roomName = data['roomName'] ?? ('call_' + callId.toString());
                          ActiveCallManager.instance.connect(
                            callId: callId,
                            roomName: roomName,
                            isVideo: isVideo,
                            peerName: topic,
                          );
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ActiveCallScreen(
                                callId: callId,
                                roomName: roomName,
                                isVideo: isVideo,
                                peerName: topic,
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.greenAccent.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Join', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCreateCallLinkCard() {
    final mint = AppTheme.mintColor(context);
    final textPrim = AppTheme.text(context);
    final textMuted = AppTheme.textMut(context);
    final isDark = AppTheme.isDarkMode(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141126) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _showCreateCallLinkSheet(context),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: mint.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.link_rounded, color: mint, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Create call link',
                      style: TextStyle(
                        color: textPrim,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Share a link for your LiChat video or voice call',
                      style: TextStyle(
                        color: textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateCallLinkSheet(BuildContext context) {
    final mint = AppTheme.mintColor(context);
    final textPrim = AppTheme.text(context);
    final textMuted = AppTheme.textMut(context);
    final isDark = AppTheme.isDarkMode(context);

    final roomCode = 'lc-${DateTime.now().millisecondsSinceEpoch % 1000000}';
    final callUrl = 'https://lichat.app/call/$roomCode';
    bool isVideo = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF141126) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white24 : Colors.black12,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: mint.withValues(alpha: 0.16),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.link_rounded, color: mint, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'LiChat Call Link',
                              style: TextStyle(
                                color: textPrim,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Anyone with this link can join your call',
                              style: TextStyle(color: textMuted, fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Call Type Selector (Video / Voice)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF4F4F6),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isVideo ? Icons.videocam_rounded : Icons.phone_rounded,
                                color: mint,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Call type',
                                style: TextStyle(color: textPrim, fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          DropdownButtonHideUnderline(
                            child: DropdownButton<bool>(
                              value: isVideo,
                              dropdownColor: isDark ? const Color(0xFF1B1633) : Colors.white,
                              style: TextStyle(color: mint, fontWeight: FontWeight.bold, fontSize: 14),
                              icon: Icon(Icons.arrow_drop_down, color: mint),
                              items: const [
                                DropdownMenuItem(value: true, child: Text('Video Call')),
                                DropdownMenuItem(value: false, child: Text('Voice Call')),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setSheetState(() => isVideo = val);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Link Box
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1B1633) : const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: mint.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              callUrl,
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.copy_rounded, color: mint, size: 20),
                            tooltip: 'Copy link',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: callUrl));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Call link copied to clipboard!'),
                                  duration: Duration(seconds: 2),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Actions
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: mint),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            icon: Icon(Icons.share_rounded, color: mint, size: 18),
                            label: Text('Share Link', style: TextStyle(color: mint, fontWeight: FontWeight.bold)),
                            onPressed: () {
                              Share.share(
                                'Join my LiChat ${isVideo ? 'video' : 'voice'} call: $callUrl',
                                subject: 'LiChat Call Invitation',
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: mint,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            icon: Icon(
                              isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                              size: 18,
                            ),
                            label: const Text('Start Call', style: TextStyle(fontWeight: FontWeight.bold)),
                            onPressed: () {
                              Navigator.pop(sheetCtx);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ActiveCallScreen(
                                    callId: roomCode,
                                    roomName: 'call_link_$roomCode',
                                    isVideo: isVideo,
                                    peerName: 'Call Link ($roomCode)',
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
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

  void _showJoinCallDialog(BuildContext context) {
    final textController = TextEditingController();
    final mint = AppTheme.mintColor(context);
    final textPrim = AppTheme.text(context);
    final isDark = AppTheme.isDarkMode(context);
    bool isVideo = true;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF141126) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Row(
                children: [
                  Icon(Icons.add_link_rounded, color: mint),
                  const SizedBox(width: 8),
                  Text('Join with Call Link', style: TextStyle(color: textPrim, fontSize: 18)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Enter or paste a LiChat call link or room code to join:',
                    style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: textController,
                    style: TextStyle(color: textPrim, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'e.g. lc-123456 or https://lichat.app/call/lc-123456',
                      hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38, fontSize: 12),
                      filled: true,
                      fillColor: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF4F4F6),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Join as:', style: TextStyle(color: textPrim, fontSize: 13, fontWeight: FontWeight.w600)),
                      Row(
                        children: [
                          ChoiceChip(
                            label: const Text('Video'),
                            selected: isVideo,
                            selectedColor: mint.withValues(alpha: 0.25),
                            labelStyle: TextStyle(color: isVideo ? mint : textPrim, fontSize: 12),
                            onSelected: (val) => setDialogState(() => isVideo = true),
                          ),
                          const SizedBox(width: 6),
                          ChoiceChip(
                            label: const Text('Voice'),
                            selected: !isVideo,
                            selectedColor: mint.withValues(alpha: 0.25),
                            labelStyle: TextStyle(color: !isVideo ? mint : textPrim, fontSize: 12),
                            onSelected: (val) => setDialogState(() => isVideo = false),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: mint,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () {
                    final raw = textController.text.trim();
                    if (raw.isEmpty) return;
                    Navigator.pop(dialogCtx);
                    String roomCode = raw;
                    if (raw.contains('/call/')) {
                      roomCode = raw.split('/call/').last.split('?').first.trim();
                    } else if (raw.startsWith('http')) {
                      roomCode = raw.split('/').last.trim();
                    }
                    if (roomCode.isEmpty) roomCode = 'lc-${DateTime.now().millisecondsSinceEpoch % 1000000}';

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ActiveCallScreen(
                          callId: roomCode,
                          roomName: 'call_link_$roomCode',
                          isVideo: isVideo,
                          peerName: 'Call Link ($roomCode)',
                        ),
                      ),
                    );
                  },
                  child: const Text('Join Call', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildCallList({required String filter}) {
    final surfaceElevated = AppTheme.surfaceElevatedColor(context);
    final textPrim = AppTheme.text(context);
    final textMuted = AppTheme.textMut(context);
    final mint = AppTheme.mintColor(context);
    final isDark = AppTheme.isDarkMode(context);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: CallSignalingService.streamCallHistory(_myUid!),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return Center(child: CircularProgressIndicator(color: mint));
        }

        var docs = (snapshot.data?.docs ?? []).toList();
        docs.sort((a, b) {
          final tA = (a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          final tB = (b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          return tB.compareTo(tA);
        });

        // Filter by tab
        if (filter == 'missed') {
          docs = docs.where((doc) {
            final status = doc.data()['status'];
            final isReceiver = doc.data()['receiverId'] == _myUid;
            return isReceiver && (status == 'missed' || status == 'declined');
          }).toList();
        } else if (filter == 'incoming') {
          docs = docs.where((doc) {
            final isReceiver = doc.data()['receiverId'] == _myUid;
            final status = doc.data()['status'];
            return isReceiver && status != 'missed' && status != 'declined';
          }).toList();
        } else if (filter == 'outgoing') {
          docs = docs.where((doc) {
            return doc.data()['callerId'] == _myUid;
          }).toList();
        }

        final showCallLink = filter == 'all';

        if (docs.isEmpty) {
          String emptyMessage = 'No call history yet';
          if (filter == 'missed') emptyMessage = 'No missed calls';
          if (filter == 'incoming') emptyMessage = 'No incoming calls';
          if (filter == 'outgoing') emptyMessage = 'No outgoing calls';

          if (showCallLink) {
            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _buildCreateCallLinkCard(),
                _buildUpcomingScheduledCallsSection(),
                const SizedBox(height: 30),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.call_end_outlined, size: 56, color: textMuted.withValues(alpha: 0.35)),
                      const SizedBox(height: 12),
                      Text(
                        emptyMessage,
                        style: TextStyle(color: textMuted, fontSize: 15),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }

          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.call_end_outlined, size: 56, color: textMuted.withValues(alpha: 0.35)),
                const SizedBox(height: 12),
                Text(
                  emptyMessage,
                  style: TextStyle(color: textMuted, fontSize: 15),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 100),
          itemCount: showCallLink ? docs.length + 1 : docs.length,
          itemBuilder: (context, index) {
            if (showCallLink && index == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCreateCallLinkCard(),
                  _buildUpcomingScheduledCallsSection(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
                    child: Text(
                      'Recent Calls',
                      style: TextStyle(color: textMuted, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                    ),
                  ),
                ],
              );
            }

            final doc = showCallLink ? docs[index - 1] : docs[index];
            final data = doc.data();
            final callId = doc.id;
            final isCaller = data['callerId'] == _myUid;
            final isVideo = data['isVideo'] == true;
            final targetName = isCaller
                ? (data['receiverName'] ?? 'Contact')
                : (data['callerName'] ?? 'Contact');
            final targetAvatar = isCaller
                ? (data['receiverAvatar'] as String?)
                : (data['callerAvatar'] as String?);
            final status = data['status'] as String? ?? 'ended';
            final isMissed = !isCaller && (status == 'missed' || status == 'declined');
            final created = (data['createdAt'] as Timestamp?)?.toDate();
            final timeString = created != null ? DateFormat('MMM d, h:mm a').format(created) : '';
            final durationSeconds = data['duration'] as int? ?? 0;
            final durationString = _formatCallDuration(durationSeconds);

            // Subtitle string with duration log
            String statusSubtitle = timeString;
            if (isMissed) {
              statusSubtitle = '$timeString • Missed';
            } else if (durationString.isNotEmpty) {
              statusSubtitle = '$timeString • $durationString';
            }

            return Dismissible(
              key: Key('call_$callId'),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                color: AppTheme.callRed.withValues(alpha: 0.8),
                child: const Icon(Icons.delete_rounded, color: Colors.white),
              ),
              onDismissed: (_) => _deleteCallItem(callId),
              child: ListTile(
                leading: CircleAvatar(
                  radius: 24,
                  backgroundColor: surfaceElevated,
                  backgroundImage: MediaStorageService.getAvatarProvider(targetAvatar),
                  child: (targetAvatar == null || targetAvatar.isEmpty)
                      ? Text(
                          targetName.isNotEmpty ? targetName[0].toUpperCase() : 'U',
                          style: TextStyle(
                            color: isMissed ? AppTheme.callRed : mint,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                title: Text(
                  targetName,
                  style: TextStyle(
                    color: isMissed ? AppTheme.callRed : textPrim,
                    fontWeight: FontWeight.bold,
                    fontSize: 15.5,
                  ),
                ),
                subtitle: Row(
                  children: [
                    Icon(
                      isCaller
                          ? Icons.call_made_rounded
                          : (isMissed ? Icons.call_missed_rounded : Icons.call_received_rounded),
                      size: 14,
                      color: isMissed
                          ? AppTheme.callRed
                          : (isCaller ? mint : (isDark ? Colors.white60 : Colors.black45)),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        statusSubtitle,
                        style: TextStyle(
                          color: isMissed ? AppTheme.callRed.withValues(alpha: 0.85) : textMuted,
                          fontSize: 12.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                        color: mint,
                        size: 22,
                      ),
                      tooltip: isVideo ? 'Video Call' : 'Voice Call',
                      onPressed: () => _redial(data),
                    ),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert_rounded, color: textMuted, size: 18),
                      onSelected: (val) {
                        if (val == 'delete') _deleteCallItem(callId);
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline_rounded, color: AppTheme.callRed, size: 18),
                              SizedBox(width: 8),
                              Text('Delete log', style: TextStyle(color: AppTheme.callRed)),
                            ],
                          ),
                        ),
                      ],
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
}
