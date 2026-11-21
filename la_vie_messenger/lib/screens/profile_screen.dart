import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../services/contact_service.dart';
import '../services/theme_service.dart';
import '../services/media_storage_service.dart';
import '../services/auth_service.dart';
import '../services/lcm_bridge.dart';
import '../services/sound_service.dart';
import '../widgets/verified_badge.dart';
import 'qr_connect_screen.dart';
import 'twin_settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get _currentUser => _auth.currentUser;
  String _displayName = 'User';
  String _statusBio = 'Available on LiChat';
  String? _avatarUrl;
  String _lichatCode = '';
  bool _isLoading = true;
  bool _isUploadingPhoto = false;
  bool _isVerified = false;
  String? _verifiedBadgeType;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final user = _currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    _displayName = user.displayName?.isNotEmpty == true ? user.displayName! : 'User';

    // 1. Check local persistent cache in SharedPreferences first for instant display
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedAvatar = prefs.getString('user_avatar_cache_${user.uid}');
      if (cachedAvatar != null && cachedAvatar.isNotEmpty) {
        _avatarUrl = cachedAvatar;
      }
    } catch (_) {}

    if (_avatarUrl == null || _avatarUrl!.isEmpty) {
      _avatarUrl = user.photoURL;
    }

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data();
        if (data != null) {
          if ((data['displayName'] as String?)?.isNotEmpty == true) {
            _displayName = data['displayName'];
          }
          if ((data['statusBio'] as String?)?.isNotEmpty == true) {
            _statusBio = data['statusBio'];
          }
          if ((data['lichat_code'] as String?)?.isNotEmpty == true) {
            _lichatCode = data['lichat_code'];
          }
          _isVerified = data['isVerified'] == true || data['verified'] == true;
          _verifiedBadgeType = data['verifiedType'] as String?;

          // 2. Read saved avatar/photoURL from Firestore and normalize
          final firestoreAvatar = (data['photoURL'] as String?) ??
              (data['avatar'] as String?) ??
              (data['avatarUrl'] as String?);
          if (firestoreAvatar != null && firestoreAvatar.trim().isNotEmpty) {
            String resolvedAvatar = firestoreAvatar.trim();
            if (resolvedAvatar.startsWith('/')) {
              resolvedAvatar = 'https://la-vie.lifechangerstouch.org$resolvedAvatar';
            }
            _avatarUrl = resolvedAvatar;

            // Cache in SharedPreferences
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('user_avatar_cache_${user.uid}', resolvedAvatar);
            } catch (_) {}
          }
        }
      }

      if (_lichatCode.isEmpty) {
        _lichatCode = await ContactService.ensureUserLiChatCode(user.uid, displayName: _displayName);
      }
    } catch (e) {
      debugPrint("Error loading profile: $e");
      if (_lichatCode.isEmpty) {
        _lichatCode = await ContactService.ensureUserLiChatCode(user.uid, displayName: _displayName);
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _deleteAccount() async {
    final surface = AppTheme.surfaceColor(context);
    final textPrim = AppTheme.text(context);
    final textMuted = AppTheme.textMut(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 26),
            const SizedBox(width: 10),
            Text('Delete Account?', style: TextStyle(color: textPrim, fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Text(
          'This action is irreversible. All your messages, contacts, AI Twin persona data, and account details will be permanently erased.',
          style: TextStyle(color: textMuted, fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text('Cancel', style: TextStyle(color: textMuted, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Delete Permanently', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await AuthService.deleteAccount(context);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Account deletion failed: $e. Please re-authenticate and try again.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  Future<void> _editLiChatCode() async {
    final surface = AppTheme.surfaceColor(context);
    final surfaceElevated = AppTheme.surfaceElevatedColor(context);
    final border = AppTheme.borderColor(context);
    final textPrim = AppTheme.text(context);
    final textSec = AppTheme.textSec(context);
    final textMuted = AppTheme.textMut(context);
    final mint = AppTheme.mintColor(context);
    final isDark = AppTheme.isDarkMode(context);

    final controller = TextEditingController(text: _lichatCode);
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;
    String? errorText;

    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: border),
          ),
          title: Row(
            children: [
              Icon(Icons.pin_rounded, color: mint, size: 22),
              const SizedBox(width: 8),
              Text('Customize LiChat Code', style: TextStyle(color: textPrim, fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Set a custom memorable code or handle for others to find you (e.g. LC-EMMA, MINT-99):',
                  style: TextStyle(color: textSec, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  style: TextStyle(color: textPrim, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                  decoration: InputDecoration(
                    hintText: 'e.g. LC-EMMA',
                    hintStyle: TextStyle(color: textMuted),
                    filled: true,
                    fillColor: surfaceElevated,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: mint)),
                  ),
                  validator: (val) {
                    final clean = (val ?? '').trim();
                    if (clean.length < 3) return 'Must be at least 3 characters';
                    if (clean.length > 16) return 'Must be at most 16 characters';
                    return null;
                  },
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 10),
                  Text(errorText!, style: const TextStyle(color: Colors.redAccent, fontSize: 12.5)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text('Cancel', style: TextStyle(color: textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: mint,
                foregroundColor: isDark ? Colors.black : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: isSaving ? null : () async {
                if (formKey.currentState?.validate() != true) return;
                final newCode = controller.text.trim().toUpperCase();
                final user = _currentUser;
                if (user == null) return;

                setDialogState(() {
                  isSaving = true;
                  errorText = null;
                });

                final res = await ContactService.updateCustomLiChatCode(uid: user.uid, newCode: newCode);
                if (res['success'] == true) {
                  if (!context.mounted) return;
                  Navigator.pop(dialogCtx);
                  setState(() => _lichatCode = newCode);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('LiChat code updated to $newCode!'),
                      backgroundColor: surfaceElevated,
                    ),
                  );
                } else {
                  setDialogState(() {
                    isSaving = false;
                    errorText = res['message'] ?? 'Could not update code';
                  });
                }
              },
              child: isSaving
                  ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: isDark ? Colors.black : Colors.white, strokeWidth: 2))
                  : const Text('Save Code', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateDisplayName() async {
    final surface = AppTheme.surfaceColor(context);
    final surfaceElevated = AppTheme.surfaceElevatedColor(context);
    final border = AppTheme.borderColor(context);
    final textPrim = AppTheme.text(context);
    final textMuted = AppTheme.textMut(context);
    final mint = AppTheme.mintColor(context);
    final isDark = AppTheme.isDarkMode(context);

    final controller = TextEditingController(text: _displayName);
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: border),
        ),
        title: Text('Edit Name', style: TextStyle(color: textPrim, fontSize: 17, fontWeight: FontWeight.bold)),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            style: TextStyle(color: textPrim, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Enter your name...',
              hintStyle: TextStyle(color: textMuted),
              filled: true,
              fillColor: surfaceElevated,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: mint)),
            ),
            validator: (val) => (val == null || val.trim().isEmpty) ? 'Name cannot be empty' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('Cancel', style: TextStyle(color: textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: mint,
              foregroundColor: isDark ? Colors.black : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              if (formKey.currentState?.validate() != true) return;
              final newName = controller.text.trim();
              Navigator.pop(dialogCtx);

              setState(() => _displayName = newName);
              final user = _currentUser;
              if (user != null) {
                await user.updateDisplayName(newName);
                await _firestore.collection('users').doc(user.uid).set({
                  'displayName': newName,
                  'name': newName,
                  'updatedAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));
              }
            },
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _updateStatusBio() async {
    final surface = AppTheme.surfaceColor(context);
    final surfaceElevated = AppTheme.surfaceElevatedColor(context);
    final border = AppTheme.borderColor(context);
    final textPrim = AppTheme.text(context);
    final textMuted = AppTheme.textMut(context);
    final mint = AppTheme.mintColor(context);
    final isDark = AppTheme.isDarkMode(context);

    final controller = TextEditingController(text: _statusBio);

    await showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: border),
        ),
        title: Text('Edit Status / Bio', style: TextStyle(color: textPrim, fontSize: 17, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: textPrim, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'e.g. Available, Busy, In a meeting...',
            hintStyle: TextStyle(color: textMuted),
            filled: true,
            fillColor: surfaceElevated,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: mint)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('Cancel', style: TextStyle(color: textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: mint,
              foregroundColor: isDark ? Colors.black : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              final newBio = controller.text.trim();
              Navigator.pop(dialogCtx);

              setState(() => _statusBio = newBio.isEmpty ? 'Available' : newBio);
              final user = _currentUser;
              if (user != null) {
                await _firestore.collection('users').doc(user.uid).set({
                  'statusBio': _statusBio,
                  'updatedAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));
              }
            },
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  ImageProvider? _getAvatarProvider(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    final trimmed = url.trim();
    if (trimmed.startsWith('data:')) {
      final comma = trimmed.indexOf(',');
      if (comma != -1) {
        return MemoryImage(base64Decode(trimmed.substring(comma + 1)));
      }
    }
    String resolvedUrl = trimmed;
    if (resolvedUrl.startsWith('/')) {
      resolvedUrl = 'https://la-vie.lifechangerstouch.org$resolvedUrl';
    }
    return NetworkImage(resolvedUrl);
  }

  void _showPhotoOptions() {
    final surface = AppTheme.surfaceColor(context);
    final textPrim = AppTheme.text(context);
    final mint = AppTheme.mintColor(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.borderColor(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  'Profile Photo',
                  style: TextStyle(color: textPrim, fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: mint.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.photo_library_rounded, color: mint, size: 22),
                  ),
                  title: Text('Choose from Gallery', style: TextStyle(color: textPrim, fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickAndUploadPhoto(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: mint.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.camera_alt_rounded, color: mint, size: 22),
                  ),
                  title: Text('Take a Photo (Camera)', style: TextStyle(color: textPrim, fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickAndUploadPhoto(ImageSource.camera);
                  },
                ),
                if (_avatarUrl != null && _avatarUrl!.isNotEmpty)
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
                    ),
                    title: const Text('Remove Photo', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _removePhoto();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _removePhoto() async {
    final user = _currentUser;
    if (user == null) return;

    setState(() => _isUploadingPhoto = true);
    try {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('user_avatar_cache_${user.uid}');
      } catch (_) {}

      await user.updatePhotoURL(null);
      await _firestore.collection('users').doc(user.uid).set({
        'photoURL': null,
        'avatar': null,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        setState(() {
          _avatarUrl = null;
          _isUploadingPhoto = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Profile photo removed'),
            backgroundColor: AppTheme.surfaceElevatedColor(context),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove photo: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _pickAndUploadPhoto(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        imageQuality: 75,
        maxWidth: 800,
        maxHeight: 800,
      );
      if (picked == null) return;

      setState(() => _isUploadingPhoto = true);
      final user = _currentUser;
      if (user == null) {
        setState(() => _isUploadingPhoto = false);
        return;
      }

      final file = File(picked.path);
      final rawDownloadUrl = await MediaStorageService.uploadProfilePhoto(
        file: file,
        uid: user.uid,
      );

      String downloadUrl = rawDownloadUrl.trim();
      if (downloadUrl.startsWith('/')) {
        downloadUrl = 'https://la-vie.lifechangerstouch.org$downloadUrl';
      }

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_avatar_cache_${user.uid}', downloadUrl);
      } catch (_) {}

      try {
        await user.updatePhotoURL(downloadUrl);
      } catch (authErr) {
        debugPrint("Notice: could not update Firebase Auth photoURL: $authErr");
      }

      await _firestore.collection('users').doc(user.uid).set({
        'photoURL': downloadUrl,
        'avatar': downloadUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        setState(() {
          _avatarUrl = downloadUrl;
          _isUploadingPhoto = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: AppTheme.mint, size: 20),
                const SizedBox(width: 8),
                const Text('Profile photo updated successfully!'),
              ],
            ),
            backgroundColor: AppTheme.surfaceElevatedColor(context),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint("Profile photo upload error: $e");
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not upload photo: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _showThemeSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        final current = ThemeService.instance.currentMode;

        Widget buildOption({
          required String title,
          required String subtitle,
          required IconData icon,
          required ThemeMode mode,
        }) {
          final isSelected = current == mode;
          final mint = AppTheme.mintColor(context);
          final textPrim = AppTheme.text(context);
          final textMuted = AppTheme.textMut(context);

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected ? mint.withValues(alpha: 0.15) : AppTheme.surfaceElevatedColor(context),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: isSelected ? mint : textMuted, size: 22),
            ),
            title: Text(
              title,
              style: TextStyle(
                color: textPrim,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                fontSize: 15,
              ),
            ),
            subtitle: Text(
              subtitle,
              style: TextStyle(color: textMuted, fontSize: 12.5),
            ),
            trailing: isSelected
                ? Icon(Icons.check_circle_rounded, color: mint, size: 22)
                : null,
            onTap: () {
              Navigator.pop(ctx);
              ThemeService.instance.setThemeMode(mode);
            },
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.borderColor(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  'Choose App Theme',
                  style: TextStyle(
                    color: AppTheme.text(context),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 14),
                buildOption(
                  title: 'System Default',
                  subtitle: 'Automatically match device dark/light setting',
                  icon: Icons.brightness_auto_rounded,
                  mode: ThemeMode.system,
                ),
                buildOption(
                  title: 'Dark Mode',
                  subtitle: 'Deep emerald obsidian dark theme',
                  icon: Icons.dark_mode_rounded,
                  mode: ThemeMode.dark,
                ),
                buildOption(
                  title: 'Light Mode',
                  subtitle: 'Crisp porcelain snow bright theme',
                  icon: Icons.light_mode_rounded,
                  mode: ThemeMode.light,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _signOut() async {
    final surface = AppTheme.surfaceColor(context);
    final border = AppTheme.borderColor(context);
    final textPrim = AppTheme.text(context);
    final textSec = AppTheme.textSec(context);
    final textMuted = AppTheme.textMut(context);
    final mint = AppTheme.mintColor(context);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: border),
        ),
        title: Text('Sign Out', style: TextStyle(color: textPrim, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to sign out of LiChat?', style: TextStyle(color: textSec)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.callRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: mint),
                const SizedBox(height: 16),
                Text('Signing out...', style: TextStyle(color: textPrim, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );

      await AuthService.signOut(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDarkMode(context);
    final bg = AppTheme.bg(context);
    final surface = AppTheme.surfaceColor(context);
    final surfaceElevated = AppTheme.surfaceElevatedColor(context);
    final textPrim = AppTheme.text(context);
    final textMuted = AppTheme.textMut(context);
    final textSec = AppTheme.textSec(context);
    final border = AppTheme.borderColor(context);
    final mint = AppTheme.mintColor(context);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: bg,
        body: Center(child: CircularProgressIndicator(color: mint)),
      );
    }

    final user = _currentUser;
    final email = user?.email ?? 'No email';
    final uid = user?.uid ?? '';
    final connectLink = 'https://la-vie.lifechangerstouch.org/connect?uid=$uid&name=${Uri.encodeComponent(_displayName)}';
    final qrData = connectLink;

    final themeMode = ThemeService.instance.currentMode;
    final themeTitle = themeMode == ThemeMode.system
        ? 'System Default'
        : (themeMode == ThemeMode.dark ? 'Dark Mode' : 'Light Mode');
    final themeIcon = themeMode == ThemeMode.system
        ? Icons.brightness_auto_rounded
        : (themeMode == ThemeMode.dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Text('Profile', style: TextStyle(color: textPrim, fontWeight: FontWeight.bold, fontSize: 20)),
        actions: [
          IconButton(
            icon: Icon(Icons.qr_code_scanner_rounded, color: mint),
            tooltip: 'Scan QR to Connect',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const QrConnectScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Avatar & Camera Edit Button
            Center(
              child: Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: mint.withValues(alpha: 0.5), width: 2),
                    ),
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: surfaceElevated,
                      backgroundImage: _getAvatarProvider(_avatarUrl),
                      child: (_avatarUrl == null || _avatarUrl!.isEmpty)
                          ? Text(
                              _displayName.isNotEmpty ? _displayName[0].toUpperCase() : 'U',
                              style: TextStyle(color: mint, fontSize: 38, fontWeight: FontWeight.bold),
                            )
                          : null,
                    ),
                  ),
                  if (_isUploadingPhoto)
                    Positioned.fill(
                      child: CircleAvatar(
                        backgroundColor: Colors.black54,
                        child: CircularProgressIndicator(color: mint, strokeWidth: 3),
                      ),
                    ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: _showPhotoOptions,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: mint,
                          shape: BoxShape.circle,
                          border: Border.all(color: bg, width: 2.5),
                        ),
                        child: Icon(Icons.camera_alt_rounded, color: isDark ? Colors.black : Colors.white, size: 18),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Display Name (Tap to Edit)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _updateDisplayName,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _displayName,
                      style: TextStyle(color: textPrim, fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    if (_isVerified) ...[
                      const SizedBox(width: 4),
                      VerifiedBadge(
                        type: _verifiedBadgeType == 'gold'
                            ? VerifiedType.gold
                            : _verifiedBadgeType == 'mint'
                                ? VerifiedType.mint
                                : VerifiedType.blue,
                        size: 20,
                      ),
                    ],
                    const SizedBox(width: 8),
                    Icon(Icons.edit_rounded, color: mint, size: 16),
                  ],
                ),
              ),
            ),

            // Email Badge
            Text(email, style: TextStyle(color: textMuted, fontSize: 13)),
            const SizedBox(height: 12),

            // Status Bio Pill (Tap to Edit)
            GestureDetector(
              onTap: _updateStatusBio,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: surfaceElevated,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: mint, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _statusBio,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: textSec, fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.edit_rounded, color: textMuted, size: 12),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Personal LiChat Unique Code Card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: mint.withValues(alpha: 0.3)),
                boxShadow: [
                  BoxShadow(
                    color: isDark ? Colors.black.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: mint.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.pin_rounded, color: mint, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MY LICHAT CODE',
                          style: TextStyle(
                            color: textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _lichatCode.isNotEmpty ? _lichatCode : 'Loading...',
                          style: TextStyle(
                            color: textPrim,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.copy_rounded, color: mint, size: 20),
                    tooltip: 'Copy Code',
                    onPressed: () {
                      if (_lichatCode.isNotEmpty) {
                        Clipboard.setData(ClipboardData(text: _lichatCode));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Row(
                              children: [
                                Icon(Icons.check_circle_rounded, color: mint, size: 18),
                                const SizedBox(width: 8),
                                Text('LiChat Code "$_lichatCode" copied!'),
                              ],
                            ),
                            backgroundColor: surfaceElevated,
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.edit_rounded, color: textMuted, size: 18),
                    tooltip: 'Customize Code',
                    onPressed: _editLiChatCode,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Personal LiChat QR Code Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: border),
                boxShadow: [
                  BoxShadow(
                    color: isDark ? Colors.black.withValues(alpha: 0.35) : Colors.black.withValues(alpha: 0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.qr_code_2_rounded, color: mint, size: 20),
                          const SizedBox(width: 8),
                          Text('My LiChat QR Code', style: TextStyle(color: textPrim, fontSize: 15, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      IconButton(
                        icon: Icon(Icons.share_rounded, color: mint, size: 20),
                        tooltip: 'Share Invite',
                        onPressed: () {
                          SharePlus.instance.share(ShareParams(
                            text: 'Connect with me on LiChat!\nMy Code: $_lichatCode\n$connectLink',
                            subject: 'Connect with me on LiChat',
                          ));
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: QrImageView(
                      data: qrData,
                      version: QrVersions.auto,
                      size: 190,
                      gapless: false,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Point another phone\'s LiChat scanner at this barcode to connect instantly and privately.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: textSec, fontSize: 12, height: 1.4),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // AI Digital Twin Settings Card
            Container(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: mint.withValues(alpha: 0.3)),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: mint.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text('🤖', style: TextStyle(fontSize: 22)),
                ),
                title: Row(
                  children: [
                    Text(
                      'AI Digital Twin',
                      style: TextStyle(color: textPrim, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: mint.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'NEW',
                        style: TextStyle(color: mint, fontSize: 10, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                subtitle: Text(
                  'Learns your communication style & crafts personalized replies',
                  style: TextStyle(color: textMuted, fontSize: 12.5),
                ),
                trailing: Icon(Icons.chevron_right_rounded, color: textMuted),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const TwinSettingsScreen()),
                  );
                },
              ),
            ),

            const SizedBox(height: 14),

            // Theme / Appearance Settings Card
            Container(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: border),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: mint.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(themeIcon, color: mint, size: 22),
                ),
                title: Text(
                  'Appearance & Theme',
                  style: TextStyle(color: textPrim, fontSize: 15, fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  themeTitle,
                  style: TextStyle(color: textMuted, fontSize: 12.5),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: surfaceElevated,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        themeTitle,
                        style: TextStyle(color: mint, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.chevron_right_rounded, color: textMuted),
                  ],
                ),
                onTap: _showThemeSelector,
              ),
            ),

            const SizedBox(height: 14),

            // Conversation Sounds Toggle (WhatsApp style)
            Container(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: border),
              ),
              child: SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                secondary: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: mint.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.volume_up_rounded, color: mint, size: 22),
                ),
                title: Text(
                  'Conversation Sounds',
                  style: TextStyle(color: textPrim, fontSize: 15, fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  'Play tones for incoming & outgoing messages',
                  style: TextStyle(color: textMuted, fontSize: 12.5),
                ),
                activeColor: mint,
                value: SoundService.instance.isEnabled,
                onChanged: (val) async {
                  await SoundService.instance.setEnabled(val);
                  if (val) {
                    SoundService.instance.playMessageSent();
                  }
                  setState(() {});
                },
              ),
            ),

            const SizedBox(height: 14),

            // Beta Feedback & Bug Report Card
            Container(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: border),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.bug_report_rounded, color: Colors.amber, size: 22),
                ),
                title: Text(
                  'Beta Feedback & Bug Report',
                  style: TextStyle(color: textPrim, fontSize: 15, fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  'Help us improve LiChat before launch',
                  style: TextStyle(color: textMuted, fontSize: 12.5),
                ),
                trailing: Icon(Icons.chevron_right_rounded, color: textMuted),
                onTap: () {
                  LcmBridge.showFeedbackDialog(
                    context,
                    packageName: 'org.lifechangerstouch.lavie.messenger',
                    appName: 'LiChat',
                    currentVersion: '1.2.4',
                  );
                },
              ),
            ),

            const SizedBox(height: 14),

            // App Version & Updates Card
            Container(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: border),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: mint.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.system_update_rounded, color: mint, size: 22),
                ),
                title: Text(
                  'App Version & Updates',
                  style: TextStyle(color: textPrim, fontSize: 15, fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  'Version 1.2.4 (Build 17) • Tap to check for updates',
                  style: TextStyle(color: textMuted, fontSize: 12.5),
                ),
                trailing: Icon(Icons.refresh_rounded, color: mint, size: 20),
                onTap: () {
                  LcmBridge.checkForUpdates(
                    context,
                    packageName: 'org.lifechangerstouch.lavie.messenger',
                    currentVersion: '1.2.4',
                    showToastIfLatest: true,
                  );
                },
              ),
            ),

            const SizedBox(height: 14),

            // Privacy Policy & Terms Card (App Store & Google Play Policy Requirement)
            Container(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: border),
              ),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.privacy_tip_rounded, color: Colors.blue, size: 22),
                    ),
                    title: Text(
                      'Privacy Policy',
                      style: TextStyle(color: textPrim, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'How LiChat protects and manages your data',
                      style: TextStyle(color: textMuted, fontSize: 12.5),
                    ),
                    trailing: Icon(Icons.open_in_new_rounded, color: textMuted, size: 18),
                    onTap: () async {
                      final url = Uri.parse('https://la-vie.lifechangerstouch.org/privacy');
                      try {
                        await launchUrl(url, mode: LaunchMode.externalApplication);
                      } catch (e) {
                        debugPrint('Could not launch privacy policy: $e');
                      }
                    },
                  ),
                  const Divider(height: 1, indent: 64),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.gavel_rounded, color: Colors.deepPurple, size: 22),
                    ),
                    title: Text(
                      'Terms of Service',
                      style: TextStyle(color: textPrim, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'User agreements and acceptable use policy',
                      style: TextStyle(color: textMuted, fontSize: 12.5),
                    ),
                    trailing: Icon(Icons.open_in_new_rounded, color: textMuted, size: 18),
                    onTap: () async {
                      final url = Uri.parse('https://la-vie.lifechangerstouch.org/terms');
                      try {
                        await launchUrl(url, mode: LaunchMode.externalApplication);
                      } catch (e) {
                        debugPrint('Could not launch terms: $e');
                      }
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Quick Scan Camera Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: surfaceElevated,
                  foregroundColor: textPrim,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: border),
                  ),
                ),
                icon: Icon(Icons.qr_code_scanner_rounded, color: mint, size: 20),
                label: const Text('Scan Someone\'s QR Code', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const QrConnectScreen()),
                  );
                },
              ),
            ),

            const SizedBox(height: 12),

            // Sign Out Button
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.orangeAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text('Sign Out', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                onPressed: _signOut,
              ),
            ),

            const SizedBox(height: 4),

            // Delete Account Button (Required by Apple & Google Play policies)
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.redAccent.withValues(alpha: 0.85),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                icon: const Icon(Icons.delete_forever_rounded, size: 18),
                label: const Text('Delete Account & Data', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                onPressed: _deleteAccount,
              ),
            ),
            const SizedBox(height: 110), // Clearance for the mobile floating bottom navigation capsule
          ],
        ),
      ),
    );
  }
}
