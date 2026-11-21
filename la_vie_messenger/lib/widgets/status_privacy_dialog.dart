import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/contact_service.dart';
import '../services/media_storage_service.dart';
import '../theme/app_theme.dart';

class StatusPrivacySettings {
  final String privacy; // 'all', 'exclude', 'include'
  final List<String> selectedUids;

  const StatusPrivacySettings({
    required this.privacy,
    this.selectedUids = const [],
  });

  String get label {
    switch (privacy) {
      case 'exclude':
        return selectedUids.isEmpty
            ? 'My contacts'
            : 'My contacts except (${selectedUids.length})';
      case 'include':
        return selectedUids.isEmpty
            ? 'Only share with...'
            : 'Only share with (${selectedUids.length})';
      case 'all':
      default:
        return 'My contacts';
    }
  }

  static Future<StatusPrivacySettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final p = prefs.getString('status_privacy_mode') ?? 'all';
      final uids = prefs.getStringList('status_privacy_uids') ?? [];
      return StatusPrivacySettings(privacy: p, selectedUids: uids);
    } catch (_) {
      return const StatusPrivacySettings(privacy: 'all');
    }
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('status_privacy_mode', privacy);
      await prefs.setStringList('status_privacy_uids', selectedUids);
    } catch (_) {}
  }
}

class StatusPrivacyDialog extends StatefulWidget {
  final StatusPrivacySettings currentSettings;

  const StatusPrivacyDialog({
    super.key,
    required this.currentSettings,
  });

  static Future<StatusPrivacySettings?> show(
    BuildContext context,
    StatusPrivacySettings current,
  ) {
    return showModalBottomSheet<StatusPrivacySettings>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF151226),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => StatusPrivacyDialog(currentSettings: current),
    );
  }

  @override
  State<StatusPrivacyDialog> createState() => _StatusPrivacyDialogState();
}

class _StatusPrivacyDialogState extends State<StatusPrivacyDialog> {
  late String _selectedPrivacy;
  late Set<String> _selectedUids;
  final String? _myUid = FirebaseAuth.instance.currentUser?.uid;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedPrivacy = widget.currentSettings.privacy;
    _selectedUids = Set<String>.from(widget.currentSettings.selectedUids);
  }

  void _saveAndClose() {
    final settings = StatusPrivacySettings(
      privacy: _selectedPrivacy,
      selectedUids: _selectedUids.toList(),
    );
    settings.save();
    Navigator.pop(context, settings);
  }

  @override
  Widget build(BuildContext context) {
    final bool needsContactList = _selectedPrivacy != 'all';

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        top: 20,
        left: 20,
        right: 20,
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
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
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Status Privacy',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton(
                onPressed: _saveAndClose,
                child: const Text(
                  'Done',
                  style: TextStyle(
                    color: AppTheme.mint,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const Text(
            'Who can see your status updates',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 16),

          // Radio options
          _buildRadioTile(
            title: 'My contacts',
            subtitle: 'Share with all contacts',
            value: 'all',
          ),
          _buildRadioTile(
            title: 'My contacts except...',
            subtitle: 'Hide status from selected contacts',
            value: 'exclude',
          ),
          _buildRadioTile(
            title: 'Only share with...',
            subtitle: 'Share only with selected contacts',
            value: 'include',
          ),

          if (needsContactList) ...[
            const SizedBox(height: 12),
            const Divider(color: Colors.white12),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: TextField(
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: const InputDecoration(
                          hintText: 'Search contacts...',
                          hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                          border: InputBorder.none,
                          icon: Icon(Icons.search, color: Colors.white38, size: 18),
                        ),
                        onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_selectedUids.length} selected',
                    style: const TextStyle(color: AppTheme.mint, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _buildContactsPicker(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRadioTile({
    required String title,
    required String subtitle,
    required String value,
  }) {
    final isSelected = _selectedPrivacy == value;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedPrivacy = value;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.mint.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.mint.withValues(alpha: 0.4) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? AppTheme.mint : Colors.white38,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 14.5,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactsPicker() {
    if (_myUid == null) {
      return const Center(child: Text('Please log in', style: TextStyle(color: Colors.white54)));
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: ContactService.streamContacts(_myUid),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.mint));
        }

        var contacts = snapshot.data ?? [];
        if (_searchQuery.isNotEmpty) {
          contacts = contacts.where((c) {
            final name = (c['name'] as String? ?? '').toLowerCase();
            return name.contains(_searchQuery);
          }).toList();
        }

        if (contacts.isEmpty) {
          return const Center(
            child: Text(
              'No contacts found',
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
          );
        }

        return ListView.builder(
          itemCount: contacts.length,
          itemBuilder: (context, idx) {
            final contact = contacts[idx];
            final uid = contact['uid'] as String? ?? '';
            final name = contact['name'] as String? ?? 'Contact';
            final avatar = contact['avatar'] as String?;
            final isChecked = _selectedUids.contains(uid);

            return CheckboxListTile(
              value: isChecked,
              activeColor: _selectedPrivacy == 'exclude' ? AppTheme.callRed : AppTheme.mint,
              checkColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
              secondary: CircleAvatar(
                radius: 18,
                backgroundColor: AppTheme.surface,
                backgroundImage: MediaStorageService.getAvatarProvider(avatar),
                child: (avatar == null || avatar.isEmpty)
                    ? const Icon(Icons.person, color: AppTheme.mint, size: 18)
                    : null,
              ),
              title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 14)),
              onChanged: (val) {
                setState(() {
                  if (val == true) {
                    _selectedUids.add(uid);
                  } else {
                    _selectedUids.remove(uid);
                  }
                });
              },
            );
          },
        );
      },
    );
  }
}
