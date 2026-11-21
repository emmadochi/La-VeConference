import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_plus/share_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:la_vie_messenger/theme/app_theme.dart';
import 'package:la_vie_messenger/services/contact_service.dart';
import 'package:la_vie_messenger/services/media_storage_service.dart';
import 'package:la_vie_messenger/screens/chat_conversation_screen.dart';

class QrConnectScreen extends StatefulWidget {
  final VoidCallback? onContactAdded;

  const QrConnectScreen({Key? key, this.onContactAdded}) : super(key: key);

  @override
  State<QrConnectScreen> createState() => _QrConnectScreenState();
}

class _QrConnectScreenState extends State<QrConnectScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  MobileScannerController? _scannerController;
  final GlobalKey _qrCardKey = GlobalKey();
  final TextEditingController _codeController = TextEditingController();
  String _myLichatCode = '';
  bool _isProcessingScan = false;
  bool _isSharingImage = false;
  bool _isConnectingByCode = false;
  bool _hasCopiedPin = false;
  bool _hasCopiedLink = false;
  String? _codeError;

  void _copyPin() {
    if (_myLichatCode.isNotEmpty) {
      HapticFeedback.lightImpact();
      Clipboard.setData(ClipboardData(text: _myLichatCode));
      setState(() => _hasCopiedPin = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _hasCopiedPin = false);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 18),
              const SizedBox(width: 8),
              Text('Copied PIN "$_myLichatCode" to clipboard!'),
            ],
          ),
          backgroundColor: AppTheme.surfaceElevatedColor(context),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _copyInviteLink({required String uid, required String name}) {
    HapticFeedback.lightImpact();
    final link = 'https://la-vie.lifechangerstouch.org/connect?uid=$uid&name=${Uri.encodeComponent(name)}';
    final codeText = _myLichatCode.isNotEmpty ? 'My LiChat PIN: $_myLichatCode\n' : '';
    final fullText = 'Connect with me on LiChat!\n$codeText$link';
    Clipboard.setData(ClipboardData(text: fullText));
    setState(() => _hasCopiedLink = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _hasCopiedLink = false);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.link_rounded, color: Colors.greenAccent, size: 18),
            SizedBox(width: 8),
            Text('Invite link copied to clipboard!'),
          ],
        ),
        backgroundColor: AppTheme.surfaceElevatedColor(context),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
      _scannerController = MobileScannerController();
    }
    _loadMyCode();
  }

  void _loadMyCode() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final code = await ContactService.ensureUserLiChatCode(user.uid, displayName: user.displayName);
      if (mounted) setState(() => _myLichatCode = code);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scannerController?.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _connectByCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _codeError = 'Please enter a LiChat PIN or handle.');
      return;
    }
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    setState(() {
      _isConnectingByCode = true;
      _codeError = null;
    });

    final res = await ContactService.pairByUniqueCode(
      myUid: currentUser.uid,
      myName: currentUser.displayName ?? 'LiChat User',
      myAvatar: currentUser.photoURL,
      code: code,
    );

    if (mounted) {
      setState(() => _isConnectingByCode = false);
      final status = res['status'] as String? ?? '';
      if (res['success'] == true) {
        _codeController.clear();
        widget.onContactAdded?.call();
        if (status == 'request_sent' || status == 'success') {
          _showRequestSentDialog(contactName: res['peerName'] ?? 'Contact');
        } else {
          _showSuccessDialog(
            peerUid: res['peerUid'] ?? '',
            contactName: res['peerName'] ?? 'Contact',
            peerAvatar: res['peerAvatar'],
          );
        }
      } else {
        setState(() => _codeError = res['message'] ?? 'Could not connect with that code.');
      }
    }
  }

  Future<void> _handleBarcode(BarcodeCapture capture) async {
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final rawValue = barcodes.first.rawValue;
    if (rawValue == null || rawValue.isEmpty) return;

    final parsed = ContactService.parseQrPayload(rawValue);
    if (parsed == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid QR Code. Please scan a LiChat barcode.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    final peerUid = parsed['uid'] as String;
    final peerName = (parsed['name'] as String?)?.isNotEmpty == true ? parsed['name'] as String : 'Contact';
    final peerAvatar = parsed['avatar'] as String?;

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    if (peerUid == currentUser.uid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This is your own QR code!'), backgroundColor: Colors.amber),
        );
      }
      return;
    }

    setState(() => _isProcessingScan = true);

    final result = await ContactService.sendContactRequest(
      senderUid:    currentUser.uid,
      senderName:   currentUser.displayName ?? 'LiChat User',
      senderAvatar: currentUser.photoURL,
      targetUid:    peerUid,
    );

    if (mounted) {
      final status = result['status'] as String? ?? '';
      if (result['success'] == true) {
        widget.onContactAdded?.call();
        if (status == 'request_sent' || status == 'success') {
          _showRequestSentDialog(contactName: peerName);
        } else {
          // already_contacts fallback
          _showSuccessDialog(peerUid: peerUid, contactName: peerName, peerAvatar: peerAvatar);
        }
      } else if (status == 'already_contacts') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('You are already contacts with $peerName.'), backgroundColor: Colors.amber),
        );
      } else if (status == 'already_sent') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Request already sent to $peerName — awaiting their approval.'), backgroundColor: Colors.blueAccent),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send request. Please try again.')),
        );
      }
      setState(() => _isProcessingScan = false);
    }
  }

  Future<void> _shareQrImage() async {
    setState(() => _isSharingImage = true);
    try {
      final boundary = _qrCardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final pngBytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/lichat_qr_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(filePath);
      await file.writeAsBytes(pngBytes);

      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid ?? '';
      final name = user?.displayName ?? 'LiChat User';
      final link = 'https://la-vie.lifechangerstouch.org/connect?uid=$uid&name=${Uri.encodeComponent(name)}';

      await SharePlus.instance.share(ShareParams(
        files: [XFile(filePath, mimeType: 'image/png', name: 'lichat_qr.png')],
        text: 'Connect with me on LiChat!\n$link',
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to share image: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isSharingImage = false);
    }
  }

  Future<void> _scanFromGallery() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      setState(() => _isProcessingScan = true);

      if (_scannerController == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('On Windows Desktop, please use the 6-digit PIN tab to connect with contacts.'),
              backgroundColor: Colors.blueAccent,
            ),
          );
        }
        return;
      }

      final barcodeCapture = await _scannerController!.analyzeImage(picked.path);
      if (barcodeCapture != null && barcodeCapture.barcodes.isNotEmpty) {
        await _handleBarcode(barcodeCapture);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No valid LiChat barcode found in this image. Please choose a clearer picture.'),
              backgroundColor: Colors.orangeAccent,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error analyzing photo: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessingScan = false);
    }
  }

  /// Shown after a contact request is successfully sent (not yet accepted).
  void _showRequestSentDialog({required String contactName}) {
    final surface = AppTheme.surfaceColor(context);
    final border = AppTheme.borderColor(context);
    final textPrim = AppTheme.text(context);
    final textSec = AppTheme.textSec(context);
    final mint = AppTheme.mintColor(context);
    final isDark = AppTheme.isDarkMode(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: border)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: mint.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.send_rounded, color: mint, size: 48),
              ),
              const SizedBox(height: 18),
              Text(
                'Request Sent!',
                textAlign: TextAlign.center,
                style: TextStyle(color: textPrim, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                '$contactName will receive a notification and must Accept before you\'re connected.',
                textAlign: TextAlign.center,
                style: TextStyle(color: textSec, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: mint,
                    foregroundColor: isDark ? Colors.black : Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Shown when two users are already contacts (e.g. both opened a chat).
  void _showSuccessDialog({
    required String peerUid,
    required String contactName,
    String? peerAvatar,
  }) {
    final surface = AppTheme.surfaceColor(context);
    final border = AppTheme.borderColor(context);
    final textPrim = AppTheme.text(context);
    final textSec = AppTheme.textSec(context);
    final mint = AppTheme.mintColor(context);
    final isDark = AppTheme.isDarkMode(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: border)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: mint.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check_circle_rounded, color: mint, size: 48),
              ),
              const SizedBox(height: 18),
              Text(
                'Connected with $contactName!',
                textAlign: TextAlign.center,
                style: TextStyle(color: textPrim, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                'Both of you are now paired and can chat and call anytime.',
                textAlign: TextAlign.center,
                style: TextStyle(color: textSec, fontSize: 13),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: mint,
                    foregroundColor: isDark ? Colors.black : Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChatConversationScreen(
                          peerUid: peerUid,
                          peerName: contactName,
                          peerAvatar: peerAvatar,
                        ),
                      ),
                    );
                  },
                  child: const Text('Start Chatting', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = AppTheme.bg(context);
    final surface = AppTheme.surfaceColor(context);
    final surfaceElevated = AppTheme.surfaceElevatedColor(context);
    final border = AppTheme.borderColor(context);
    final textPrim = AppTheme.text(context);
    final textSec = AppTheme.textSec(context);
    final textMuted = AppTheme.textMut(context);
    final mint = AppTheme.mintColor(context);
    final isDark = AppTheme.isDarkMode(context);

    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? 'guest_user';
    final name = user?.displayName ?? 'My Profile';
    final qrPayload = ContactService.generateQrPayload(
      uid: uid,
      name: name,
      avatar: user?.photoURL,
    );

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: textPrim),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
        title: Text(
          'Add & Connect Contacts',
          style: TextStyle(color: textPrim, fontWeight: FontWeight.bold, fontSize: 19),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              icon: Icon(Icons.photo_library_rounded, color: mint),
              tooltip: 'Scan from Gallery',
              onPressed: _isProcessingScan ? null : _scanFromGallery,
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 440),
              margin: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 8),
              padding: const EdgeInsets.all(3.5),
              decoration: BoxDecoration(
                color: surfaceElevated,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: border.withValues(alpha: 0.7)),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: mint,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: mint.withValues(alpha: 0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 1.5),
                    ),
                  ],
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: isDark ? Colors.black : Colors.white,
                unselectedLabelColor: isDark ? textSec : const Color(0xFF64748B),
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                tabs: const [
                  Tab(
                    height: 34,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.qr_code_rounded, size: 15),
                        SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            'My Code',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Tab(
                    height: 34,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.pin_rounded, size: 15),
                        SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            'Enter PIN',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Tab(
                    height: 34,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.qr_code_scanner_rounded, size: 15),
                        SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            'Scan QR',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // TAB 1: MY QR CODE
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  children: [
                    // Top Subtitle Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: mint.withValues(alpha: isDark ? 0.12 : 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: mint.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.qr_code_2_rounded, size: 16, color: mint),
                          const SizedBox(width: 8),
                          Text(
                            'Scan barcode or enter PIN to connect',
                            style: TextStyle(
                              color: isDark ? mint : const Color(0xFF6D28D9),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Card with QR Code (Wrapped in RepaintBoundary for picture sharing)
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        // Ambient radial glow behind card to eliminate empty void
                        Positioned.fill(
                          child: Container(
                            margin: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(32),
                              boxShadow: [
                                BoxShadow(
                                  color: mint.withValues(alpha: isDark ? 0.15 : 0.10),
                                  blurRadius: 40,
                                  spreadRadius: 8,
                                ),
                              ],
                            ),
                          ),
                        ),

                        RepaintBoundary(
                          key: _qrCardKey,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
                            decoration: BoxDecoration(
                              color: surface,
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: isDark ? border.withValues(alpha: 0.8) : const Color(0xFFE2E8F0),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.07),
                                  blurRadius: 28,
                                  offset: const Offset(0, 10),
                                  spreadRadius: 2,
                                ),
                                if (!isDark)
                                  BoxShadow(
                                    color: mint.withValues(alpha: 0.06),
                                    blurRadius: 18,
                                    offset: const Offset(0, 4),
                                  ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // User Avatar with gradient border
                                Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [mint, mint.withValues(alpha: 0.4)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  ),
                                  child: CircleAvatar(
                                    radius: 32,
                                    backgroundColor: mint.withValues(alpha: 0.2),
                                    backgroundImage: MediaStorageService.getAvatarProvider(user?.photoURL),
                                    child: (user?.photoURL == null || user!.photoURL!.isEmpty)
                                        ? Text(
                                            name.isNotEmpty ? name.substring(0, 1).toUpperCase() : 'U',
                                            style: TextStyle(color: mint, fontSize: 26, fontWeight: FontWeight.bold),
                                          )
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  name,
                                  style: TextStyle(color: textPrim, fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                if (user?.email != null && user!.email!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      user.email!,
                                      style: TextStyle(color: textMuted, fontSize: 12.5),
                                    ),
                                  ),
                                const SizedBox(height: 16),

                                // QR Code Box with Branded Styling & Center Logo
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.05),
                                        blurRadius: 14,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: QrImageView(
                                    data: qrPayload,
                                    version: QrVersions.auto,
                                    size: 185.0,
                                    embeddedImage: const AssetImage('assets/images/lichat_logo.png'),
                                    embeddedImageStyle: const QrEmbeddedImageStyle(
                                      size: Size(38, 38),
                                    ),
                                    eyeStyle: const QrEyeStyle(
                                      eyeShape: QrEyeShape.square,
                                      color: Color(0xFF1E1B4B),
                                    ),
                                    dataModuleStyle: const QrDataModuleStyle(
                                      dataModuleShape: QrDataModuleShape.square,
                                      color: Color(0xFF111827),
                                    ),
                                    backgroundColor: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Interactive PIN Display Badge with 1-tap Copy
                                InkWell(
                                  onTap: _copyPin,
                                  borderRadius: BorderRadius.circular(16),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                                    decoration: BoxDecoration(
                                      color: _hasCopiedPin
                                          ? (isDark ? Colors.green.withValues(alpha: 0.2) : const Color(0xFFECFDF5))
                                          : (isDark ? surfaceElevated : const Color(0xFFF1F5F9)),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: _hasCopiedPin
                                            ? Colors.greenAccent
                                            : (isDark ? mint.withValues(alpha: 0.4) : const Color(0xFFCBD5E1)),
                                        width: 1.2,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _hasCopiedPin ? Icons.check_circle_rounded : Icons.tag_rounded,
                                          color: _hasCopiedPin ? Colors.green : mint,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _myLichatCode.isNotEmpty ? _myLichatCode : 'PIN: Loading...',
                                          style: TextStyle(
                                            color: textPrim,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 16,
                                            fontFamily: 'monospace',
                                            letterSpacing: 1.6,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: _hasCopiedPin
                                                ? Colors.green
                                                : mint.withValues(alpha: isDark ? 0.25 : 0.15),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                _hasCopiedPin ? Icons.check_rounded : Icons.copy_rounded,
                                                size: 12,
                                                color: _hasCopiedPin ? Colors.white : mint,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                _hasCopiedPin ? 'Copied' : 'Copy',
                                                style: TextStyle(
                                                  color: _hasCopiedPin ? Colors.white : mint,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Primary Action Buttons: Share Picture & Share Link
                    Row(
                      children: [
                        // 1. Share QR Picture Button
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: mint,
                              foregroundColor: isDark ? Colors.black : Colors.white,
                              elevation: 2,
                              shadowColor: mint.withValues(alpha: 0.4),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: _isSharingImage ? null : _shareQrImage,
                            icon: _isSharingImage
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      color: isDark ? Colors.black : Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.photo_camera_back_rounded, size: 18),
                            label: const Text(
                              'Share Picture',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // 2. Share Invite Link Button
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: mint,
                              side: BorderSide(color: mint, width: 1.5),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: () {
                              final link = 'https://la-vie.lifechangerstouch.org/connect?uid=$uid&name=${Uri.encodeComponent(name)}';
                              final codeText = _myLichatCode.isNotEmpty ? 'My LiChat PIN: $_myLichatCode\n' : '';
                              SharePlus.instance.share(ShareParams(
                                text: 'Connect with me on LiChat!\n$codeText$link',
                              ));
                            },
                            icon: const Icon(Icons.share_rounded, size: 18),
                            label: const Text(
                              'Share Link',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // 3. Quick Copy Invite Link
                    Center(
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: textSec,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        onPressed: () => _copyInviteLink(uid: uid, name: name),
                        icon: Icon(
                          _hasCopiedLink ? Icons.check_circle_rounded : Icons.link_rounded,
                          size: 16,
                          color: _hasCopiedLink ? Colors.green : mint,
                        ),
                        label: Text(
                          _hasCopiedLink ? 'Invite Link Copied!' : 'Copy Direct Invite Link',
                          style: TextStyle(
                            color: _hasCopiedLink ? Colors.green : textSec,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // TAB 2: ENTER LICHAT PIN
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Container(
                  padding: const EdgeInsets.all(26),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: border.withValues(alpha: 0.9)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: mint.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.pin_rounded, color: mint, size: 36),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Connect via LiChat PIN',
                        style: TextStyle(color: textPrim, fontSize: 19, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Enter a contact\'s 6-digit LiChat code (e.g. LC-84920) or custom handle to pair instantly.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: textSec, fontSize: 13.5, height: 1.4),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _codeController,
                        textCapitalization: TextCapitalization.characters,
                        style: TextStyle(
                          color: textPrim,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.0,
                          fontFamily: 'monospace',
                        ),
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          hintText: 'e.g. LC-78492',
                          hintStyle: TextStyle(color: textMuted, letterSpacing: 1.0, fontSize: 14.5),
                          filled: true,
                          fillColor: surfaceElevated,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: mint, width: 1.5),
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(Icons.paste_rounded, color: mint, size: 20),
                            tooltip: 'Paste from clipboard',
                            onPressed: () async {
                              final data = await Clipboard.getData(Clipboard.kTextPlain);
                              if (data?.text != null && data!.text!.isNotEmpty) {
                                _codeController.text = data.text!.trim().toUpperCase();
                              }
                            },
                          ),
                        ),
                      ),
                      if (_codeError != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _codeError!,
                                  style: const TextStyle(color: Colors.redAccent, fontSize: 12.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: mint,
                            foregroundColor: isDark ? Colors.black : Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            padding: const EdgeInsets.symmetric(vertical: 15),
                          ),
                          onPressed: _isConnectingByCode ? null : _connectByCode,
                          icon: _isConnectingByCode
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    color: isDark ? Colors.black : Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.person_add_rounded, size: 19),
                          label: Text(
                            _isConnectingByCode ? 'Connecting...' : 'Connect Now',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // TAB 3: SCANNER CAMERA
          _scannerController == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: surfaceElevated,
                            shape: BoxShape.circle,
                            border: Border.all(color: mint.withValues(alpha: 0.3), width: 2),
                          ),
                          child: Icon(Icons.qr_code_scanner_rounded, size: 56, color: mint),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Desktop QR Connect',
                          style: TextStyle(color: textPrim, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Camera QR scanning is optimized for mobile phones. On Windows Desktop, connect instantly using your 6-digit LiChat PIN or upload an image file.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: textSec, fontSize: 13.5, height: 1.5),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: mint,
                            foregroundColor: isDark ? Colors.black : Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: _isProcessingScan ? null : _scanFromGallery,
                          icon: const Icon(Icons.file_open_rounded, size: 20),
                          label: const Text('Select Barcode / QR Image File', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      controller: _scannerController!,
                      onDetect: _handleBarcode,
                    ),

                    // Viewfinder Overlay
                    Center(
                      child: Container(
                        width: 250,
                        height: 250,
                        decoration: BoxDecoration(
                          border: Border.all(color: mint, width: 3),
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                    ),

                    // Bottom Actions (Gallery button + Instruction)
                    Positioned(
                      bottom: 30,
                      left: 20,
                      right: 20,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: surfaceElevated.withValues(alpha: 0.9),
                              foregroundColor: mint,
                              side: BorderSide(color: mint, width: 1.2),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                            onPressed: _isProcessingScan ? null : _scanFromGallery,
                            icon: const Icon(Icons.photo_library_rounded, size: 18),
                            label: const Text(
                              'Scan Barcode from Gallery',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Text(
                              'Align barcode inside the frame to connect',
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ],
      ),
    );
  }
}
