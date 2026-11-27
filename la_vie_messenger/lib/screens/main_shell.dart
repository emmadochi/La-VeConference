import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../theme/app_theme.dart';
import '../services/call_signaling_service.dart';
import '../services/presence_service.dart';
import '../services/contact_service.dart';
import '../services/theme_service.dart';
import '../services/auth_service.dart';
import '../services/media_storage_service.dart';
import 'chat_list_screen.dart';
import 'chat_conversation_screen.dart';
import 'contacts_screen.dart';
import 'call_history_screen.dart';
import 'call_screens.dart';
import 'profile_screen.dart';
import 'create_group_screen.dart';
import 'qr_connect_screen.dart';
import 'status_list_screen.dart';
import '../services/status_service.dart';
import '../models/status_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/active_call_manager.dart';
import '../services/lcm_bridge.dart';
import '../services/sound_service.dart';
import '../widgets/incoming_share_dialog.dart';

class _ActiveChatDesktop {
  final String peerUid;
  final String peerName;
  final String? peerAvatar;
  final bool isGroup;
  final String? chatId;
  final List<String>? participants;

  const _ActiveChatDesktop({
    required this.peerUid,
    required this.peerName,
    this.peerAvatar,
    this.isGroup = false,
    this.chatId,
    this.participants,
  });
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _currentIndex = 0;
  _ActiveChatDesktop? _selectedChat;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _incomingCallSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _missedCallSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _unreadChatsSubscription;
  StreamSubscription<List<UserStatusGroup>>? _unreadStatusSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _pendingContactRequestsSubscription;
  bool _isIncomingCallShowing = false;
  String? _currentHandledCallId;
  int _unreadMissedCalls = 0;
  int _totalUnreadChats = 0;
  int _pendingContactRequestsCount = 0;
  bool _hasUnreadStatuses = false;

  void _selectChat({
    required String peerUid,
    required String peerName,
    String? peerAvatar,
    bool isGroup = false,
    String? chatId,
    List<String>? participants,
  }) {
    setState(() {
      _selectedChat = _ActiveChatDesktop(
        peerUid: peerUid,
        peerName: peerName,
        peerAvatar: peerAvatar,
        isGroup: isGroup,
        chatId: chatId,
        participants: participants,
      );
    });
  }

  static const MethodChannel _overlayChannel =
      MethodChannel('org.lifechangerstouch.lavie.messenger/call_overlay');

  final List<Widget> _pages = const [
    ChatListScreen(),       // 0: Chats
    StatusListScreen(),     // 1: Status / Updates
    CallHistoryScreen(),    // 2: Calls
    ContactsScreen(),       // 3: Contacts
    ProfileScreen(),        // 4: Profile
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      PresenceService.startTracking(user.uid);
      _startMissedCallTracking(user.uid);
      _startUnreadChatsTracking(user.uid);
      _startUnreadStatusTracking(user.uid);
      _startPendingContactRequestsTracking(user.uid);
    }

    // Setup native channel FIRST so any pending call/chat from a notification
    // tap is handled as early as possible on the very first rendered frame.
    _setupNativeCallOverlayListener();
    _initFcmAndRegisterToken();
    _startIncomingCallListener();

    // Warm up the sound player pool so first sound fires instantly
    SoundService.instance.init();

    // Show any pending incoming call on the first frame — this covers the case
    // where the app was killed and relaunched via an FCM notification tap.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndPromptUpfrontPermissions();
      LcmBridge.checkForUpdates(
        context,
        packageName: 'org.lifechangerstouch.lavie.messenger',
        currentVersion: '1.2.4',
      );
    });
  }

  Future<void> _checkAndPromptUpfrontPermissions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alreadyPrompted = prefs.getBool('has_prompted_call_permissions') ?? false;
      if (!alreadyPrompted && mounted) {
        await prefs.setBool('has_prompted_call_permissions', true);
        await [
          Permission.microphone,
          Permission.camera,
          Permission.notification,
        ].request();
      }

      // Check battery optimization exemption on Android to ensure incoming calls wake device reliably
      if (defaultTargetPlatform == TargetPlatform.android && mounted) {
        final bool isBatteryIgnored =
            await _overlayChannel.invokeMethod<bool>('isBatteryOptimizationIgnored') ?? true;
        if (!isBatteryIgnored) {
          final batteryPrompted = prefs.getBool('has_prompted_battery_optimization') ?? false;
          if (!batteryPrompted && mounted) {
            await prefs.setBool('has_prompted_battery_optimization', true);
            _showBatteryOptimizationDialog();
          }
        }
      }
    } catch (e) {
      debugPrint("Error checking upfront permissions: $e");
    }
  }

  void _showBatteryOptimizationDialog() {
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.surface : AppTheme.lightSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.lilac.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.battery_charging_full_rounded, color: AppTheme.lilac, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Reliable Incoming Calls',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'To ensure you never miss voice and video calls when your phone is asleep or locked, please allow La-Vie to run in the background without battery restrictions.',
          style: TextStyle(
            fontSize: 14,
            height: 1.45,
            color: isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Later',
              style: TextStyle(
                color: isDark ? AppTheme.textMuted : AppTheme.lightTextMuted,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.lilacDark,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _overlayChannel.invokeMethod('requestIgnoreBatteryOptimization');
            },
            child: const Text('Allow', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _startMissedCallTracking(String myUid) {
    _missedCallSubscription = FirebaseFirestore.instance
        .collection('calls')
        .where('receiverId', isEqualTo: myUid)
        .where('status', isEqualTo: 'missed')
        .where('seen', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() => _unreadMissedCalls = snapshot.docs.length);
      }
    });
  }

  void _startUnreadChatsTracking(String myUid) {
    _unreadChatsSubscription = FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: myUid)
        .snapshots()
        .listen((snapshot) {
      int count = 0;
      for (final doc in snapshot.docs) {
        final unreadCounts = Map<String, dynamic>.from(doc.data()['unreadCounts'] ?? {});
        final myUnread = (unreadCounts[myUid] as num?)?.toInt() ?? 0;
        count += myUnread;
      }
      if (mounted) {
        setState(() => _totalUnreadChats = count);
      }
    });
  }

  void _startUnreadStatusTracking(String myUid) {
    _unreadStatusSubscription = StatusService.streamActiveStatusGroups(myUid: myUid).listen((groups) {
      final hasUnread = groups.any((g) => g.uid != myUid && g.hasUnseenBy(myUid));
      if (mounted) {
        setState(() => _hasUnreadStatuses = hasUnread);
      }
    });
  }

  void _startPendingContactRequestsTracking(String myUid) {
    _pendingContactRequestsSubscription?.cancel();
    _pendingContactRequestsSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(myUid)
        .collection('contact_requests')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() => _pendingContactRequestsCount = snapshot.docs.length);
      }
    }, onError: (e) {
      debugPrint("Error tracking pending contact requests: $e");
    });
  }

  Future<void> _markMissedCallsAsSeen() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final unreadDocs = await FirebaseFirestore.instance
          .collection('calls')
          .where('receiverId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'missed')
          .where('seen', isEqualTo: false)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in unreadDocs.docs) {
        batch.update(doc.reference, {'seen': true});
      }
      await batch.commit();
      if (mounted) setState(() => _unreadMissedCalls = 0);
    } catch (e) {
      debugPrint("Error marking missed calls as seen: $e");
    }
  }

  void _onTabSelected(int index) {
    setState(() => _currentIndex = index);
    if (index == 2) {
      _markMissedCallsAsSeen();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (state == AppLifecycleState.resumed) {
      PresenceService.startTracking(user.uid);
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      PresenceService.setOffline(user.uid);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      PresenceService.setOffline(user.uid);
    }
    _incomingCallSubscription?.cancel();
    _missedCallSubscription?.cancel();
    _unreadChatsSubscription?.cancel();
    _unreadStatusSubscription?.cancel();
    _pendingContactRequestsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _setupNativeCallOverlayListener() async {
    _overlayChannel.setMethodCallHandler((call) async {
      if (call.method == 'onIncomingCall') {
        final data = Map<String, dynamic>.from(call.arguments);
        _handleCallPayload(data);
      } else if (call.method == 'onOpenChat') {
        final data = Map<String, dynamic>.from(call.arguments);
        _handleOpenChat(data);
      } else if (call.method == 'onPairContact') {
        final data = Map<String, dynamic>.from(call.arguments);
        _handlePairContact(data);
      } else if (call.method == 'onReceiveShare') {
        final data = Map<String, dynamic>.from(call.arguments);
        _handleIncomingShare(data);
      } else if (call.method == 'onEndCallAction') {
        // Native ongoing call notification "End Call" button pressed
        await ActiveCallManager.instance.endCall();
      } else if (call.method == 'onReturnToCall') {
        // PiP window tapped or notification "Return to Call" pressed
        if (mounted) {
          ActiveCallManager.instance.maximize(context);
        }
      }
    });

    try {
      final initialCall = await _overlayChannel.invokeMethod<Map>('getInitialCall');
      if (initialCall != null) {
        final data = Map<String, dynamic>.from(initialCall);
        _handleCallPayload(data);
      }
      final initialChat = await _overlayChannel.invokeMethod<Map>('getInitialChat');
      if (initialChat != null) {
        final data = Map<String, dynamic>.from(initialChat);
        _handleOpenChat(data);
      }
      final initialContact = await _overlayChannel.invokeMethod<Map>('getInitialContact');
      if (initialContact != null) {
        final data = Map<String, dynamic>.from(initialContact);
        _handlePairContact(data);
      }
      final initialShare = await _overlayChannel.invokeMethod<Map>('getInitialShare');
      if (initialShare != null) {
        final data = Map<String, dynamic>.from(initialShare);
        _handleIncomingShare(data);
      }
    } catch (e) {
      debugPrint("Native overlay initial call/chat/contact/share check: $e");
    }
  }

  void _handleIncomingShare(Map<String, dynamic> data) {
    final mimeType = data['mimeType'] as String? ?? '*/*';
    final text = data['text'] as String? ?? '';
    final files = List<String>.from(data['files'] ?? []);

    if (files.isEmpty && text.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        IncomingShareDialog.show(
          context,
          mimeType: mimeType,
          text: text,
          files: files,
        );
      }
    });
  }

  void _handlePairContact(Map<String, dynamic> data) async {
    final peerUid = data['peerUid'] as String?;
    final peerName = data['peerName'] as String? ?? 'Contact';
    final peerAvatar = data['peerAvatar'] as String?;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || peerUid == null || peerUid.isEmpty || peerUid == user.uid) return;

    final success = await ContactService.pairContacts(
      myUid: user.uid,
      myName: user.displayName ?? 'LiChat User',
      myAvatar: user.photoURL,
      peerUid: peerUid,
      peerName: peerName,
      peerAvatar: peerAvatar,
    );

    if (mounted && success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connected with $peerName on LiChat!'),
          backgroundColor: AppTheme.mintDark,
        ),
      );

      final isDesktop = MediaQuery.of(context).size.width >= 800;
      if (isDesktop) {
        _selectChat(
          peerUid: peerUid,
          peerName: peerName,
          peerAvatar: peerAvatar,
        );
        setState(() => _currentIndex = 0);
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatConversationScreen(
              peerUid: peerUid,
              peerName: peerName,
              peerAvatar: peerAvatar,
            ),
          ),
        );
      }
    }
  }

  void _handleCallPayload(Map<String, dynamic> data) async {
    final callId = data['call_id'] ?? data['callId'];
    if (callId == null || callId.toString().isEmpty) return;

    // Staleness Guard: Check if caller hung up or call is already ended/missed
    try {
      final doc = await FirebaseFirestore.instance.collection('calls').doc(callId.toString()).get();
      if (doc.exists) {
        final status = doc.data()?['status'];
        final createdAt = (doc.data()?['createdAt'] as Timestamp?)?.toDate();
        if (status == 'ended' || status == 'missed' || status == 'declined' || status == 'offline') {
          debugPrint("Ignoring stale/ended call $callId with status $status");
          return;
        }
        if (createdAt != null && DateTime.now().difference(createdAt).inSeconds > 35) {
          debugPrint("Call $callId created >35s ago. Marking missed silently.");
          CallSignalingService.markMissed(callId.toString());
          return;
        }
      }
    } catch (e) {
      debugPrint("Error checking call staleness: $e");
    }

    final roomName = data['room_name'] ?? data['roomName'] ?? 'call_${callId.toString()}';
    final callerName = data['caller_name'] ?? data['callerName'] ?? 'Contact';
    final callerAvatar = data['caller_avatar'] ?? data['callerAvatar'];
    final isVideo = data['is_video'] == 'true' || data['isVideo'] == 'true' || data['isVideo'] == true;
    final isGroup = data['is_group'] == 'true' || data['isGroup'] == 'true' || data['isGroup'] == true;
    final groupName = (data['group_name'] ?? data['groupName'])?.toString();
    final action = data['action'];

    // Pre-warm LiveKit token in background so call starts with zero latency
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      CallSignalingService.getOrFetchToken(
        roomName: roomName.toString(),
        userId: user.uid,
        userName: user.displayName ?? 'User',
      );
    }

    final callIdStr = callId.toString();

    if (action == 'answer') {
      if (!mounted) return;
      if (ActiveCallManager.instance.hasActiveCall && ActiveCallManager.instance.callId == callIdStr) {
        ActiveCallManager.instance.maximize(context);
        return;
      }
      _currentHandledCallId = callIdStr;
      await CallSignalingService.acceptCall(callIdStr);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ActiveCallScreen(
            callId: callIdStr,
            roomName: roomName.toString(),
            isVideo: isVideo,
            peerName: callerName.toString(),
          ),
        ),
      );
      return;
    }

    if (ActiveCallManager.instance.hasActiveCall || _isIncomingCallShowing || _currentHandledCallId == callIdStr) {
      return;
    }

    if (!mounted) return;
    _showIncomingCallModal(
      callId: callIdStr,
      roomName: roomName.toString(),
      callerName: callerName.toString(),
      callerAvatar: callerAvatar?.toString(),
      isVideo: isVideo,
      isGroup: isGroup,
      groupName: groupName,
    );
  }

  Future<void> _initFcmAndRegisterToken() async {
    if (kIsWeb || (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      // iOS: show banner + play sound even while app is in foreground.
      // Without this, iOS silently drops FCM messages when the app is active.
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      final token = await messaging.getToken();
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final profileData = <String, dynamic>{
          'displayName': user.displayName ?? '',
          'email': user.email ?? '',
          'photoURL': user.photoURL ?? '',
        };
        if (token != null) profileData['fcmToken'] = token;
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
          profileData,
          SetOptions(merge: true),
        );
        debugPrint("User profile & FCM token synced for ${user.uid}");
      }

      messaging.onTokenRefresh.listen((newToken) async {
        final u = FirebaseAuth.instance.currentUser;
        if (u != null) {
          await FirebaseFirestore.instance.collection('users').doc(u.uid).set(
            {'fcmToken': newToken},
            SetOptions(merge: true),
          );
        }
      });

      // 1. App opened from background/terminated by tapping notification
      final initialMsg = await messaging.getInitialMessage();
      if (initialMsg != null) {
        final type = initialMsg.data['type'];
        if (type == 'incoming_call') {
          _handleCallPayload(initialMsg.data);
        } else if (type == 'chat_message' || type == 'chat') {
          _handleOpenChat(initialMsg.data);
        }
      }

      // 2. App resumed from background by notification click
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        final type = message.data['type'];
        if (type == 'incoming_call') {
          _handleCallPayload(message.data);
        } else if (type == 'chat_message' || type == 'chat') {
          _handleOpenChat(message.data);
        }
      });

      // 3. Foreground message received
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final msgType = message.data['type'];
        if (msgType == 'incoming_call') {
          _handleCallPayload(message.data);
        } else if (msgType == 'chat_message' || msgType == 'chat') {
          // Play received-message sound when a chat FCM arrives in foreground
          SoundService.instance.playMessageReceived();
        } else if (msgType == 'delivered') {
          // Silent delivery ACK — no UI sound needed here
        } else {
          // Generic notification sound for other types
          SoundService.instance.playNotification();
        }
      });
    } catch (e) {
      debugPrint("FCM registration error: $e");
    }
  }

  void _handleOpenChat(Map<String, dynamic> data) async {
    final senderId = data['sender_id'] ?? data['senderId'] ?? '';
    if (senderId.isEmpty) return;

    final myUid = FirebaseAuth.instance.currentUser?.uid;
    String senderName = data['sender_name'] ?? data['senderName'] ?? 'Contact';
    String? senderAvatar = data['sender_avatar'] ?? data['senderAvatar'];

    // Check contact nickname or cached profile
    if (myUid != null) {
      final profile = await ContactService.fetchContactOrProfile(myUid, senderId);
      if (profile != null && (profile['name'] as String?)?.isNotEmpty == true) {
        senderName = profile['name'];
        senderAvatar = profile['avatar'] ?? senderAvatar;
      }
    }

    if (mounted) {
      final isDesktop = MediaQuery.of(context).size.width >= 800;
      if (isDesktop) {
        _selectChat(
          peerUid: senderId,
          peerName: senderName,
          peerAvatar: senderAvatar,
        );
        setState(() => _currentIndex = 0);
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatConversationScreen(
              peerUid: senderId,
              peerName: senderName,
              peerAvatar: senderAvatar,
            ),
          ),
        );
      }
    }
  }

  void _showIncomingCallModal({
    required String callId,
    required String roomName,
    required String callerName,
    String? callerAvatar,
    required bool isVideo,
    bool isGroup = false,
    String? groupName,
  }) {
    if (_isIncomingCallShowing || _currentHandledCallId == callId || ActiveCallManager.instance.hasActiveCall) return;
    _currentHandledCallId = callId;
    setState(() => _isIncomingCallShowing = true);

    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => IncomingCallScreen(
          callId: callId,
          roomName: roomName,
          callerName: callerName,
          callerAvatar: callerAvatar,
          isVideo: isVideo,
          isGroup: isGroup,
          groupName: groupName,
        ),
      ),
    ).then((_) {
      if (mounted) {
        setState(() => _isIncomingCallShowing = false);
      }
    });
  }

  void _startIncomingCallListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _incomingCallSubscription = CallSignalingService.streamIncomingCalls(user.uid).listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        final data = doc.data();
        final callId = doc.id;

        // Skip if this call is already showing or an active call is ongoing
        if (_isIncomingCallShowing ||
            _currentHandledCallId == callId ||
            (ActiveCallManager.instance.hasActiveCall && ActiveCallManager.instance.callId == callId)) {
          return;
        }

        final roomName = data['roomName'] ?? 'call_$callId';
        final callerName = data['callerName'] ?? 'Contact';
        final callerAvatar = data['callerAvatar'];
        final isVideo = data['isVideo'] == true;
        final isGroup = data['isGroup'] == true || data['is_group'] == true || data['isGroup'] == 'true' || data['is_group'] == 'true';
        final groupName = (data['groupName'] ?? data['group_name']) as String?;
        final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

        // Staleness guard: if call is > 35s old, do not ring!
        if (createdAt != null && DateTime.now().difference(createdAt).inSeconds > 35) {
          debugPrint("Incoming call $callId stream >35s old. Marking missed.");
          CallSignalingService.markMissed(callId);
          return;
        }

        _showIncomingCallModal(
          callId: callId,
          roomName: roomName,
          callerName: callerName,
          callerAvatar: callerAvatar,
          isVideo: isVideo,
          isGroup: isGroup,
          groupName: groupName,
        );
      }
    });
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required String tooltip,
    int badgeCount = 0,
    Color? badgeColor,
    bool showDot = false,
  }) {
    final isSelected = _currentIndex == index;
    final isDark = AppTheme.isDark(context);
    final mint = AppTheme.mintColor(context);
    final textMuted = AppTheme.textMut(context);
    final surfaceElevated = AppTheme.surfaceElevatedColor(context);
    final unselectedIconColor = isDark ? textMuted : const Color(0xFF2B2544);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _onTabSelected(index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: isSelected
              ? BoxDecoration(
                  color: mint.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(18),
                )
              : null,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                icon,
                color: isSelected ? mint : unselectedIconColor,
                size: 24,
              ),
              if (badgeCount > 0)
                Positioned(
                  top: -5,
                  right: -8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: badgeColor ?? AppTheme.callRed,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: surfaceElevated, width: 1.5),
                    ),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      badgeCount > 99 ? '99+' : '$badgeCount',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: badgeColor != null && !AppTheme.isDarkMode(context) ? Colors.white : (badgeColor != null ? Colors.black : Colors.white),
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                )
              else if (showDot)
                Positioned(
                  top: -2,
                  right: -3,
                  child: Container(
                    width: 8.5,
                    height: 8.5,
                    decoration: BoxDecoration(
                      color: mint,
                      shape: BoxShape.circle,
                      border: Border.all(color: surfaceElevated, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmSignOut() async {
    final textPrim = AppTheme.text(context);
    final textMuted = AppTheme.textMut(context);
    final surface = AppTheme.surfaceColor(context);
    final border = AppTheme.borderColor(context);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border),
        ),
        title: Text('Sign Out', style: TextStyle(color: textPrim, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to sign out of LiChat?', style: TextStyle(color: textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await AuthService.signOut(context);
    }
  }

  Widget _buildRailAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    final textMuted = AppTheme.textMut(context);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          child: Icon(
            icon,
            color: iconColor ?? textMuted,
            size: 22,
          ),
        ),
      ),
    );
  }

  Widget _buildRailItem({
    required int index,
    required IconData icon,
    required IconData inactiveIcon,
    required String tooltip,
    int badgeCount = 0,
    Color? badgeColor,
    bool showDot = false,
  }) {
    final isSelected = _currentIndex == index;
    final mint = AppTheme.mintColor(context);
    final textMuted = AppTheme.textMut(context);
    final surfaceElevated = AppTheme.surfaceElevatedColor(context);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _onTabSelected(index),
        child: Container(
          width: 48,
          height: 48,
          decoration: isSelected
              ? BoxDecoration(
                  color: mint.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                )
              : null,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              if (isSelected)
                Positioned(
                  left: 0,
                  child: Container(
                    width: 3.5,
                    height: 22,
                    decoration: BoxDecoration(
                      color: mint,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              Icon(
                isSelected ? icon : inactiveIcon,
                color: isSelected ? mint : textMuted,
                size: 23,
              ),
              if (badgeCount > 0)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: badgeColor ?? AppTheme.callRed,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: surfaceElevated, width: 1.5),
                    ),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      badgeCount > 99 ? '99+' : '$badgeCount',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: badgeColor != null && !AppTheme.isDarkMode(context)
                            ? Colors.white
                            : (badgeColor != null ? Colors.black : Colors.white),
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                )
              else if (showDot)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: mint,
                      shape: BoxShape.circle,
                      border: Border.all(color: surfaceElevated, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopNavRail(BuildContext context) {
    final surfaceElevated = AppTheme.surfaceElevatedColor(context);
    final border = AppTheme.borderColor(context);
    final mint = AppTheme.mintColor(context);
    final isDark = AppTheme.isDarkMode(context);
    final user = FirebaseAuth.instance.currentUser;

    return Container(
      width: 68,
      decoration: BoxDecoration(
        color: surfaceElevated,
        border: Border(right: BorderSide(color: border.withValues(alpha: 0.8), width: 1)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          // LiChat App Icon
          Tooltip(
            message: 'LiChat',
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: mint.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset('assets/images/lichat_logo.png', fit: BoxFit.cover),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Main Tabs
          _buildRailItem(
            index: 0,
            icon: Icons.chat_bubble_rounded,
            inactiveIcon: Icons.chat_bubble_outline_rounded,
            tooltip: 'Chats',
            badgeCount: _totalUnreadChats,
            badgeColor: mint,
          ),
          const SizedBox(height: 8),
          _buildRailItem(
            index: 1,
            icon: Icons.donut_large_rounded,
            inactiveIcon: Icons.circle_outlined,
            tooltip: 'Updates',
            showDot: _hasUnreadStatuses,
          ),
          const SizedBox(height: 8),
          _buildRailItem(
            index: 2,
            icon: Icons.call_rounded,
            inactiveIcon: Icons.call_outlined,
            tooltip: 'Calls',
            badgeCount: _unreadMissedCalls,
            badgeColor: AppTheme.callRed,
          ),
          const SizedBox(height: 8),
          _buildRailItem(
            index: 3,
            icon: Icons.people_alt_rounded,
            inactiveIcon: Icons.people_outline_rounded,
            tooltip: 'Contacts',
          ),
          const SizedBox(height: 12),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Divider(color: border.withValues(alpha: 0.6), height: 1),
          ),
          const SizedBox(height: 12),

          // Quick Action: New Group
          _buildRailAction(
            icon: Icons.group_add_outlined,
            tooltip: 'New Group',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (ctx) => const CreateGroupScreen()),
              );
            },
          ),
          const SizedBox(height: 8),

          // Quick Action: QR Connect
          _buildRailAction(
            icon: Icons.qr_code_scanner_rounded,
            tooltip: 'QR Connect',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (ctx) => const QrConnectScreen()),
              );
            },
          ),

          const Spacer(),

          // Theme Switcher
          _buildRailAction(
            icon: isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            tooltip: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            onTap: () => ThemeService.toggle(),
          ),
          const SizedBox(height: 8),

          // Profile / Settings Tab
          Tooltip(
            message: user?.displayName ?? 'Profile & Settings',
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _onTabSelected(4),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: _currentIndex == 4 ? Border.all(color: mint, width: 2) : null,
                ),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: AppTheme.surfaceColor(context),
                  backgroundImage: MediaStorageService.getAvatarProvider(user?.photoURL),
                  child: (user?.photoURL == null || user!.photoURL!.isEmpty)
                      ? Icon(
                          Icons.person_rounded,
                          color: _currentIndex == 4 ? mint : AppTheme.textMut(context),
                          size: 22,
                        )
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Sign Out
          _buildRailAction(
            icon: Icons.logout_rounded,
            tooltip: 'Sign Out',
            iconColor: Colors.redAccent.withValues(alpha: 0.8),
            onTap: _confirmSignOut,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildDesktopMasterPane(BuildContext context) {
    switch (_currentIndex) {
      case 0:
        return ChatListScreen(
          onChatSelected: ({
            required peerUid,
            required peerName,
            peerAvatar,
            required isGroup,
            chatId,
            participants,
          }) {
            _selectChat(
              peerUid: peerUid,
              peerName: peerName,
              peerAvatar: peerAvatar,
              isGroup: isGroup,
              chatId: chatId,
              participants: participants,
            );
          },
          selectedChatId: _selectedChat != null
              ? (_selectedChat!.isGroup ? _selectedChat!.chatId : _selectedChat!.peerUid)
              : null,
          isDesktop: true,
        );
      case 1:
        return const StatusListScreen();
      case 2:
        return const CallHistoryScreen();
      case 3:
        return ContactsScreen(
          onContactChatSelected: (peerUid, peerName, peerAvatar) {
            _selectChat(
              peerUid: peerUid,
              peerName: peerName,
              peerAvatar: peerAvatar,
              isGroup: false,
            );
          },
        );
      case 4:
      default:
        return const ProfileScreen();
    }
  }

  Widget _buildDesktopEmptyDetailPlaceholder(BuildContext context) {
    final textPrim = AppTheme.text(context);
    final textMuted = AppTheme.textMut(context);
    final mint = AppTheme.mintColor(context);
    final isDark = AppTheme.isDarkMode(context);

    return Container(
      color: AppTheme.bg(context),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Ambient glow behind logo
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: mint.withValues(alpha: isDark ? 0.12 : 0.08),
                  boxShadow: [
                    BoxShadow(
                      color: mint.withValues(alpha: 0.18),
                      blurRadius: 36,
                      spreadRadius: 8,
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(18),
                child: Image.asset(
                  'assets/images/lichat_logo.png',
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 24),

              Text(
                'LiChat for Windows',
                style: TextStyle(
                  color: textPrim,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 10),

              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Text(
                  'Send and receive messages, make high-definition voice and video calls seamlessly without keeping your phone connected.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textMuted,
                    fontSize: 14.5,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Feature Badges
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 10,
                children: [
                  _buildFeatureBadge(
                    context,
                    icon: Icons.lock_outline_rounded,
                    label: 'End-to-End Encrypted',
                  ),
                  _buildFeatureBadge(
                    context,
                    icon: Icons.videocam_outlined,
                    label: 'HD Voice & Video Calls',
                  ),
                  _buildFeatureBadge(
                    context,
                    icon: Icons.cloud_done_outlined,
                    label: 'Cross-device Sync',
                  ),
                ],
              ),
              const SizedBox(height: 48),

              // Security footer
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_rounded, size: 14, color: textMuted.withValues(alpha: 0.7)),
                  const SizedBox(width: 6),
                  Text(
                    'Your personal messages and calls are private and secure',
                    style: TextStyle(
                      color: textMuted.withValues(alpha: 0.7),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureBadge(BuildContext context, {required IconData icon, required String label}) {
    final surfaceElevated = AppTheme.surfaceElevatedColor(context);
    final border = AppTheme.borderColor(context);
    final textMuted = AppTheme.textMut(context);
    final mint = AppTheme.mintColor(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: surfaceElevated.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: mint),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: textMuted,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = AppTheme.bg(context);
    final surfaceElevated = AppTheme.surfaceElevatedColor(context);
    final border = AppTheme.borderColor(context);
    final isDark = AppTheme.isDarkMode(context);
    final mint = AppTheme.mintColor(context);
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {},
      child: Scaffold(
        backgroundColor: bg,
        body: isDesktop
            ? Row(
                children: [
                  // 1. WhatsApp Desktop Style Left Navigation Rail
                  _buildDesktopNavRail(context),

                  // 2. Master Pane (Chats / Calls / Contacts / Profile)
                  SizedBox(
                    width: 380,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(
                            color: border.withValues(alpha: 0.8),
                            width: 1,
                          ),
                        ),
                      ),
                      child: _buildDesktopMasterPane(context),
                    ),
                  ),

                  // 3. Detail Pane (Active Chat Conversation or Branded Welcome Placeholder)
                  Expanded(
                    child: _selectedChat != null
                        ? KeyedSubtree(
                            key: ValueKey(
                              _selectedChat!.isGroup
                                  ? (_selectedChat!.chatId ?? _selectedChat!.peerUid)
                                  : _selectedChat!.peerUid,
                            ),
                            child: ChatConversationScreen(
                              peerUid: _selectedChat!.peerUid,
                              peerName: _selectedChat!.peerName,
                              peerAvatar: _selectedChat!.peerAvatar,
                              isGroup: _selectedChat!.isGroup,
                              chatIdOverride: _selectedChat!.chatId,
                              groupParticipants: _selectedChat!.participants,
                              showBackButton: false,
                            ),
                          )
                        : _buildDesktopEmptyDetailPlaceholder(context),
                  ),
                ],
              )
            : Stack(
                children: [
                  IndexedStack(
                    index: _currentIndex,
                    children: _pages,
                  ),

                  // Floating Bottom Navigation Capsule (LiChat Uniform Style for Mobile)
                  Positioned(
                    bottom: 24,
                    left: 24,
                    right: 24,
                    child: Container(
                      height: 60,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: surfaceElevated.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: border.withValues(alpha: 0.8)),
                        boxShadow: [
                          BoxShadow(
                            color: isDark
                                ? Colors.black.withValues(alpha: 0.45)
                                : Colors.black.withValues(alpha: 0.08),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          // 1. Chats Tab (with lilac total unread badge)
                          _buildNavItem(
                            index: 0,
                            icon: _currentIndex == 0
                                ? Icons.chat_bubble_rounded
                                : Icons.chat_bubble_outline_rounded,
                            tooltip: 'Chats',
                            badgeCount: _totalUnreadChats,
                            badgeColor: mint,
                          ),

                          // 2. Status / Updates Tab
                          _buildNavItem(
                            index: 1,
                            icon: _currentIndex == 1
                                ? Icons.donut_large_rounded
                                : Icons.circle_outlined,
                            tooltip: 'Updates',
                            showDot: _hasUnreadStatuses,
                          ),

                          // 3. Calls Tab (with red unread missed call badge)
                          _buildNavItem(
                            index: 2,
                            icon: _currentIndex == 2
                                ? Icons.call_rounded
                                : Icons.call_outlined,
                            tooltip: 'Calls',
                            badgeCount: _unreadMissedCalls,
                          ),

                          // 4. Contacts Tab (with live pending requests badge)
                          _buildNavItem(
                            index: 3,
                            icon: _currentIndex == 3
                                ? Icons.people_alt_rounded
                                : Icons.people_outline_rounded,
                            tooltip: 'Contacts',
                            badgeCount: _pendingContactRequestsCount,
                            badgeColor: mint,
                          ),

                          // 5. Profile Tab
                          _buildNavItem(
                            index: 4,
                            icon: _currentIndex == 4
                                ? Icons.person_rounded
                                : Icons.person_outline_rounded,
                            tooltip: 'Profile',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
