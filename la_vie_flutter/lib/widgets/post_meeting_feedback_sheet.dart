import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import '../api_service.dart';
import '../screens/notifications_screen.dart';

class PostMeetingFeedbackSheet extends StatefulWidget {
  final String roomId;
  final String meetingTitle;
  final String durationText;
  final String? chatTranscript;

  const PostMeetingFeedbackSheet({
    Key? key,
    required this.roomId,
    required this.meetingTitle,
    this.durationText = '',
    this.chatTranscript,
  }) : super(key: key);

  static Future<void> show(
    BuildContext context, {
    required String roomId,
    required String meetingTitle,
    String durationText = '',
    String? chatTranscript,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PostMeetingFeedbackSheet(
        roomId: roomId,
        meetingTitle: meetingTitle,
        durationText: durationText,
        chatTranscript: chatTranscript,
      ),
    );
  }

  @override
  State<PostMeetingFeedbackSheet> createState() => _PostMeetingFeedbackSheetState();
}

class _PostMeetingFeedbackSheetState extends State<PostMeetingFeedbackSheet> {
  int _rating = 5;
  final Set<String> _selectedChips = {};
  final TextEditingController _commentController = TextEditingController();
  bool _isSubmitting = false;
  bool _submitted = false;

  final List<String> _positiveChips = [
    'Crystal Clear Audio',
    'HD Video Quality',
    'Fast Connection',
    'Smooth Screen Share',
    'Great AI Summary',
  ];

  final List<String> _constructiveChips = [
    'Audio Delay / Lag',
    'Video Pixelation',
    'Echo / Background Noise',
    'Call Disconnected',
    'Controls Confusing',
  ];

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitFeedback() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    final comment = _commentController.text.trim();
    final tags = _selectedChips.toList();
    final wouldRecommend = _rating >= 4 ? 'yes' : (_rating == 3 ? 'neutral' : 'no');

    // 1. Submit to Backend API
    await ApiService.submitMeetingFeedback(
      roomId: widget.roomId,
      rating: _rating,
      tags: tags,
      comment: comment,
      wouldRecommend: wouldRecommend,
    );

    // 2. Direct Firestore fallback write for maximum reliability
    try {
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance.collection('meeting_feedback').add({
        'roomId': widget.roomId,
        'meetingTitle': widget.meetingTitle,
        'userId': user?.uid ?? 'anonymous',
        'userName': user?.displayName ?? 'User',
        'rating': _rating,
        'tags': tags,
        'comment': comment,
        'wouldRecommend': wouldRecommend,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isSubmitting = false;
        _submitted = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✨ Thank you! Your feedback helps us make La-Vie better for everyone.'),
          backgroundColor: Color(0xFF00FFA3),
          duration: Duration(seconds: 3),
        ),
      );

      // Auto close after brief pause if submitted
      Future.delayed(const Duration(milliseconds: 1400), () {
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      });
    }
  }

  void _shareLaVieInvite() {
    final title = widget.meetingTitle.isNotEmpty ? 'our "${widget.meetingTitle}" meeting' : 'a great meeting';
    Share.share(
      'I just had $title on La-Vie Conference! 🚀\n'
      'Host your next video meeting with crystal-clear audio, HD video, and automated AI summary notes:\n'
      'https://la-vie.lifechangerstouch.org',
      subject: 'Meet with me on La-Vie Conference',
    );
  }

  void _openMeetingNotes() {
    Navigator.pop(context); // close feedback sheet
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const NotificationsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPositive = _rating >= 4;
    final chipsToDisplay = isPositive ? _positiveChips : _constructiveChips;

    return Container(
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1322),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: const Color(0xFF00FFA3).withValues(alpha: 0.25), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Handle bar
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Header Icon Badge
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF00FFA3).withValues(alpha: 0.2),
                    const Color(0xFF00E5FF).withValues(alpha: 0.2),
                  ],
                ),
                border: Border.all(color: const Color(0xFF00FFA3).withValues(alpha: 0.4)),
              ),
              child: const Icon(
                Icons.celebration_outlined,
                color: Color(0xFF00FFA3),
                size: 28,
              ),
            ),
            const SizedBox(height: 12),

            // Meeting Title & Thank You
            const Text(
              'Thank you for joining!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.meetingTitle.isNotEmpty
                  ? widget.meetingTitle
                  : 'Meeting: ${widget.roomId}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (widget.durationText.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Duration: ${widget.durationText}',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],

            const SizedBox(height: 20),

            // Star Rating
            const Text(
              'How was your call quality?',
              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final starValue = index + 1;
                final isFilled = starValue <= _rating;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _rating = starValue;
                      _selectedChips.clear();
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      isFilled ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: isFilled ? const Color(0xFFFFC107) : Colors.white24,
                      size: 38,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),

            // Experience Chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: chipsToDisplay.map((chipText) {
                final isSelected = _selectedChips.contains(chipText);
                return FilterChip(
                  label: Text(chipText),
                  labelStyle: TextStyle(
                    color: isSelected ? const Color(0xFF070B19) : Colors.white70,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  selected: isSelected,
                  selectedColor: const Color(0xFF00FFA3),
                  backgroundColor: Colors.white.withValues(alpha: 0.05),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isSelected ? const Color(0xFF00FFA3) : Colors.white12,
                    ),
                  ),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedChips.add(chipText);
                      } else {
                        _selectedChips.remove(chipText);
                      }
                    });
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // VIRAL MARKETING SECTION / FEEDBACK INPUT
            if (isPositive) ...[
              // Viral Referral Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF00FFA3).withValues(alpha: 0.12),
                      const Color(0xFF00E5FF).withValues(alpha: 0.06),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF00FFA3).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.share_outlined, color: Color(0xFF00FFA3), size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Love using La-Vie?',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          Text(
                            'Invite team members to experience HD audio & AI notes.',
                            style: TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _shareLaVieInvite,
                      icon: const Icon(Icons.send_rounded, size: 14),
                      label: const Text('Share', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00FFA3),
                        foregroundColor: const Color(0xFF070B19),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Constructive feedback text box
              TextField(
                controller: _commentController,
                maxLines: 2,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'How can we improve your experience next time?',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF00E5FF)),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 18),

            // ACTION BUTTONS
            Row(
              children: [
                // Button 1: View AI Meeting Notes
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openMeetingNotes,
                    icon: const Icon(Icons.description_outlined, size: 16),
                    label: const Text('AI Notes & Recap', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF00E5FF),
                      side: const BorderSide(color: Color(0xFF00E5FF)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Button 2: Submit Rating & Feedback
                Expanded(
                  child: ElevatedButton(
                    onPressed: _submitted || _isSubmitting ? null : _submitFeedback,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00FFA3),
                      foregroundColor: const Color(0xFF070B19),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF070B19)),
                          )
                        : Text(
                            _submitted ? 'Submitted ✓' : 'Submit Feedback',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
