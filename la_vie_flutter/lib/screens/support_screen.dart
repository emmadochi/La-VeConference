import 'dart:ui';
import 'package:flutter/material.dart';
import '../api_service.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({Key? key}) : super(key: key);

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // New Ticket Form State
  final _formKey = GlobalKey<FormState>();
  String _selectedCategory = 'audio_video';
  String _selectedPriority = 'normal';
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  bool _isSubmitting = false;

  // My Tickets State
  List<Map<String, dynamic>> _myTickets = [];
  bool _isLoadingTickets = false;

  final Map<String, String> _categories = {
    'audio_video': '🎤 Audio & Video / Permissions',
    'broadcast': '📡 Broadcast & OBS/vMix Ingress',
    'billing': '💎 Subscription & Plan Upgrades',
    'account': '🔒 Account & Meeting Access',
    'general': '💬 General Question / Feedback',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadMyTickets();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadMyTickets() async {
    setState(() => _isLoadingTickets = true);
    try {
      final tickets = await ApiService.getMySupportTickets();
      if (mounted) {
        setState(() {
          _myTickets = tickets;
          _isLoadingTickets = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingTickets = false);
      }
    }
  }

  Future<void> _submitTicket() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final res = await ApiService.createSupportTicket(
        category: _selectedCategory,
        subject: _subjectController.text.trim(),
        message: _messageController.text.trim(),
        priority: _selectedPriority,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF00FFA3),
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Color(0xFF070B19)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Ticket #${res['ticket_id']} Created! Check your email for confirmation.',
                    style: const TextStyle(color: Color(0xFF070B19), fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );

        _subjectController.clear();
        _messageController.clear();
        _loadMyTickets();
        _tabController.animateTo(1); // Switch to "My Tickets"
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('Failed to submit ticket: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B19),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Help & Support',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 22,
            letterSpacing: 1.1,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF00E5FF),
          indicatorWeight: 3,
          labelColor: const Color(0xFF00E5FF),
          unselectedLabelColor: Colors.white54,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(text: 'New Ticket', icon: Icon(Icons.edit_note, size: 20)),
            Tab(text: 'My Tickets', icon: Icon(Icons.all_inbox, size: 20)),
            Tab(text: 'Guides & FAQ', icon: Icon(Icons.help_outline, size: 20)),
          ],
        ),
      ),
      body: Stack(
        children: [
          // Ambient Glow Background
          Positioned(
            top: -60,
            right: -60,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [const Color(0xFF5C00FF).withOpacity(0.2), Colors.transparent],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            left: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [const Color(0xFF00E5FF).withOpacity(0.15), Colors.transparent],
                ),
              ),
            ),
          ),

          TabBarView(
            controller: _tabController,
            children: [
              _buildNewTicketTab(),
              _buildMyTicketsTab(),
              _buildFaqTab(),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 1: NEW TICKET FORM
  // ==========================================
  Widget _buildNewTicketTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Header Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E5FF).withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.support_agent, color: Color(0xFF00E5FF), size: 28),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'We are here to help!',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Submit your question and our team will respond directly via email & notification.',
                          style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Category Selector
            _buildFieldLabel('Issue Category'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.15)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedCategory,
                  dropdownColor: const Color(0xFF0D1226),
                  icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF00E5FF)),
                  isExpanded: true,
                  items: _categories.entries.map((e) {
                    return DropdownMenuItem<String>(
                      value: e.key,
                      child: Text(e.value, style: const TextStyle(color: Colors.white, fontSize: 14)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedCategory = val);
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Subject Input
            _buildFieldLabel('Subject *'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _subjectController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: _buildInputDecoration(
                hint: 'e.g. Cannot hear host in Sunday Fellowship room',
                icon: Icons.title,
              ),
              validator: (v) => v == null || v.trim().isEmpty ? 'Please enter a subject' : null,
            ),
            const SizedBox(height: 20),

            // Priority Selector
            _buildFieldLabel('Urgency / Priority'),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildPriorityChip('normal', '🟡 Normal', const Color(0xFF00E5FF)),
                const SizedBox(width: 10),
                _buildPriorityChip('high', '🟠 High', const Color(0xFFFFB300)),
                const SizedBox(width: 10),
                _buildPriorityChip('urgent', '🔴 Live Service', const Color(0xFFFF5555)),
              ],
            ),
            const SizedBox(height: 20),

            // Message Input
            _buildFieldLabel('Detailed Message *'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _messageController,
              maxLines: 5,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: _buildInputDecoration(
                hint: 'Describe what happened or the exact help you need...',
                icon: Icons.message_outlined,
              ),
              validator: (v) => v == null || v.trim().isEmpty ? 'Please describe your request' : null,
            ),
            const SizedBox(height: 30),

            // Submit Button
            GestureDetector(
              onTap: _isSubmitting ? null : _submitTicket,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00E5FF), Color(0xFF5C00FF)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E5FF).withOpacity(0.35),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Center(
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.send, color: Color(0xFF070B19), size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Submit Support Ticket',
                              style: TextStyle(
                                color: Color(0xFF070B19),
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
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
    );
  }

  // ==========================================
  // TAB 2: MY TICKETS LIST
  // ==========================================
  Widget _buildMyTicketsTab() {
    if (_isLoadingTickets) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
    }

    if (_myTickets.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadMyTickets,
        color: const Color(0xFF00E5FF),
        child: ListView(
          padding: const EdgeInsets.all(40),
          children: [
            const SizedBox(height: 60),
            Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.inbox_outlined, size: 64, color: Colors.white38),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No Support Tickets Yet',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'When you submit an inquiry or question, your ticket history and agent replies will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 24),
            Center(
              child: ElevatedButton.icon(
                onPressed: () => _tabController.animateTo(0),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF),
                  foregroundColor: const Color(0xFF070B19),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Open a New Ticket', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadMyTickets,
      color: const Color(0xFF00E5FF),
      child: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: _myTickets.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (context, index) {
          final t = _myTickets[index];
          return _buildTicketCard(t);
        },
      ),
    );
  }

  Widget _buildTicketCard(Map<String, dynamic> ticket) {
    final status = (ticket['status'] ?? 'open').toString().toLowerCase();
    final replies = (ticket['replies'] as List<dynamic>?) ?? [];
    
    Color statusColor = const Color(0xFFFFB300);
    String statusText = '🟡 Open';
    if (status == 'in_progress') {
      statusColor = const Color(0xFF00E5FF);
      statusText = '🔵 In Progress';
    } else if (status == 'resolved') {
      statusColor = const Color(0xFF00FFA3);
      statusText = '🟢 Resolved';
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: ExpansionTile(
            collapsedIconColor: Colors.white54,
            iconColor: const Color(0xFF00E5FF),
            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            title: Row(
              children: [
                Text(
                  '#${ticket['ticketId'] ?? ticket['id'] ?? ''}',
                  style: const TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                ticket['subject'] ?? 'No Subject',
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(color: Colors.white12),
                    const SizedBox(height: 8),
                    // Original Message
                    const Text('YOUR MESSAGE:', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    const SizedBox(height: 4),
                    Text(
                      ticket['message'] ?? '',
                      style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 14),

                    // Agent Replies
                    if (replies.isNotEmpty) ...[
                      const Text('SUPPORT RESPONSES:', style: TextStyle(color: Color(0xFF00E5FF), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      const SizedBox(height: 8),
                      ...replies.map((r) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E5FF).withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.25)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.support_agent, color: Color(0xFF00E5FF), size: 16),
                                  const SizedBox(width: 6),
                                  Text(
                                    r['senderName'] ?? 'Support Team',
                                    style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                r['message'] ?? '',
                                style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ] else
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.hourglass_empty, color: Colors.white38, size: 16),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Awaiting agent review. You will receive an alert once updated.',
                                style: TextStyle(color: Colors.white54, fontSize: 12),
                              ),
                            ),
                          ],
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

  // ==========================================
  // TAB 3: GUIDES & FAQS
  // ==========================================
  Widget _buildFaqTab() {
    final faqs = [
      {
        'title': '🎤 How do I fix Camera & Microphone permissions?',
        'body': '1. Go to your Phone Settings -> Apps -> La-Vie Conference -> Permissions.\n2. Ensure both Camera and Microphone are set to "Allow".\n3. Return to the meeting room and tap the microphone/camera toggle button.'
      },
      {
        'title': '📡 How to connect OBS or vMix live streaming feed?',
        'body': '1. In your room settings on the Web dashboard, tap "Multi-Streaming / Ingress".\n2. Copy your RTMP Server URL and Stream Key.\n3. Paste them into OBS (Settings -> Stream -> Custom) or vMix.\n4. Click "Start Streaming" and your feed will immediately display on the conference stage.'
      },
      {
        'title': '💎 What are the benefits of the Ministry & Pro plan?',
        'body': 'Pro & Ministry plans allow simultaneous multistreaming to YouTube, Facebook, and custom RTMP channels, uncompressed audio recording, and unlimited broadcast duration.'
      },
      {
        'title': '🔇 How do I reduce audio echo in large conference rooms?',
        'body': '1. Enable "Data Saver Mode" or "Noise Cancellation" in call settings.\n2. We strongly recommend wearing earphones or headphones if you are near another speaker.'
      },
    ];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'FREQUENTLY ASKED QUESTIONS',
          style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5),
        ),
        const SizedBox(height: 14),
        ...faqs.map((faq) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: ExpansionTile(
              collapsedIconColor: Colors.white54,
              iconColor: const Color(0xFF00E5FF),
              tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              title: Text(
                faq['title']!,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    faq['body']!,
                    style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
    );
  }

  InputDecoration _buildInputDecoration({required String hint, required IconData icon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
      prefixIcon: Icon(icon, color: const Color(0xFF00E5FF), size: 20),
      filled: true,
      fillColor: Colors.white.withOpacity(0.05),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF00E5FF)),
      ),
      contentPadding: const EdgeInsets.all(16),
    );
  }

  Widget _buildPriorityChip(String value, String label, Color color) {
    final isSelected = _selectedPriority == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedPriority = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.2) : Colors.white.withOpacity(0.04),
            border: Border.all(color: isSelected ? color : Colors.white.withOpacity(0.1)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? color : Colors.white70,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
