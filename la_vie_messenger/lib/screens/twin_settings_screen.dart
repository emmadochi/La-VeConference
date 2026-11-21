import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/twin_service.dart';

/// Full AI Twin settings + persona visualisation screen.
/// Accessible from Profile → "AI Digital Twin".
class TwinSettingsScreen extends StatefulWidget {
  const TwinSettingsScreen({super.key});

  @override
  State<TwinSettingsScreen> createState() => _TwinSettingsScreenState();
}

class _TwinSettingsScreenState extends State<TwinSettingsScreen> {
  TwinSettings _settings = const TwinSettings();
  TwinPersona? _persona;
  bool _isLoadingPersona = true;
  bool _isSaving = false;

  // Test-your-twin state
  final TextEditingController _testInputCtrl = TextEditingController();
  List<String> _testReplies = [];
  bool _isTestLoading = false;

  StreamSubscription<TwinSettings>? _settingsSub;
  StreamSubscription<TwinPersona?>? _personaSub;

  @override
  void initState() {
    super.initState();
    _settingsSub = TwinService.streamSettings().listen((s) {
      if (mounted) {
        setState(() => _settings = s);
      }
    });
    _personaSub = TwinService.streamPersona().listen((p) {
      if (mounted) {
        setState(() {
          _persona = p;
          _isLoadingPersona = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _settingsSub?.cancel();
    _personaSub?.cancel();
    _testInputCtrl.dispose();
    super.dispose();
  }

  Future<void> _save(TwinSettings newSettings) async {
    setState(() {
      _settings = newSettings;
      _isSaving = true;
    });
    await TwinService.saveSettings(newSettings);
    if (mounted) {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _testTwin() async {
    final msg = _testInputCtrl.text.trim();
    if (msg.isEmpty) return;
    setState(() {
      _isTestLoading = true;
      _testReplies = [];
    });
    final replies = await TwinService.generateReplies(
      incomingMessage: msg,
      context: [],
      senderName: 'Test Contact',
      chatTitle: 'Test Chat',
      isGroup: false,
    );
    if (mounted) {
      setState(() {
        _testReplies = replies;
        _isTestLoading = false;
      });
    }
  }

  Future<void> _setTimedAutonomous(Duration duration) async {
    final until = DateTime.now().add(duration);
    await _save(_settings.copyWith(
      autonomousMode: true,
      autonomousUntil: until,
    ));
    if (mounted) {
      _showSnack(
        '🤖 Autonomous mode active for ${_formatDuration(duration)}',
        AppTheme.lilac,
      );
    }
  }

  String _formatDuration(Duration d) {
    if (d.inHours >= 1) return '${d.inHours}h';
    return '${d.inMinutes}m';
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lilac = AppTheme.lilac;
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F0D1A) : const Color(0xFFF8F7FE);
    final surface = isDark ? const Color(0xFF1A1727) : Colors.white;
    final border = lilac.withValues(alpha: 0.18);
    final textPrim = theme.colorScheme.onSurface;
    final textMuted = theme.colorScheme.onSurface.withValues(alpha: 0.5);
    final textSec = theme.colorScheme.onSurface.withValues(alpha: 0.7);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textPrim, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Text('🤖', style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Text(
              'AI Digital Twin',
              style: TextStyle(
                color: textPrim,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        actions: [
          if (_isSaving)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: lilac),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          // ── PERSONA CARD ────────────────────────────────────────────────
          _SectionLabel('🧠 My AI Persona', textMuted),
          _Card(
            surface: surface,
            border: border,
            child: _isLoadingPersona
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: CircularProgressIndicator(color: lilac, strokeWidth: 2),
                    ),
                  )
                : _persona == null || !_persona!.isSufficientlyTrained
                    ? _BuildUntrained(lilac: lilac, textMuted: textMuted, textSec: textSec)
                    : _BuildPersonaStats(
                        persona: _persona!,
                        lilac: lilac,
                        textPrim: textPrim,
                        textMuted: textMuted,
                        textSec: textSec,
                        surface: surface,
                      ),
          ),

          const SizedBox(height: 20),

          // ── TWIN MODE TOGGLE ────────────────────────────────────────────
          _SectionLabel('⚡ Twin Mode', textMuted),
          _Card(
            surface: surface,
            border: border,
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              secondary: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: lilac.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.auto_awesome_rounded, color: lilac, size: 22),
              ),
              title: Text(
                'AI Twin Suggestions',
                style: TextStyle(color: textPrim, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              subtitle: Text(
                'Shows reply candidates in your voice when someone messages you',
                style: TextStyle(color: textMuted, fontSize: 12.5),
              ),
              activeColor: lilac,
              value: _settings.isEnabled,
              onChanged: (val) => _save(_settings.copyWith(isEnabled: val)),
            ),
          ),

          const SizedBox(height: 14),

          // ── AUTONOMOUS MODE ─────────────────────────────────────────────
          _SectionLabel('🤖 Autonomous Mode', textMuted),
          _Card(
            surface: surface,
            border: _settings.isAutonomousActive
                ? lilac.withValues(alpha: 0.5)
                : border,
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  secondary: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (_settings.isAutonomousActive
                              ? lilac
                              : Colors.grey)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.smart_toy_rounded,
                      color: _settings.isAutonomousActive ? lilac : Colors.grey,
                      size: 22,
                    ),
                  ),
                  title: Text(
                    'Auto-Reply on My Behalf',
                    style: TextStyle(color: textPrim, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  subtitle: Text(
                    _settings.isAutonomousActive && _settings.autonomousUntil != null
                        ? '⏱ Active until ${_formatUntil(_settings.autonomousUntil!)}'
                        : 'Twin sends replies automatically — you get a notification after each',
                    style: TextStyle(
                      color: _settings.isAutonomousActive ? lilac : textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                  activeColor: lilac,
                  value: _settings.autonomousMode,
                  onChanged: _settings.isEnabled
                      ? (val) => _save(_settings.copyWith(
                            autonomousMode: val,
                            clearTimer: !val,
                          ))
                      : null,
                ),
                if (_settings.autonomousMode) ...[
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quick timer — pause after:',
                          style: TextStyle(color: textSec, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            _TimerChip('30m', lilac, () => _setTimedAutonomous(const Duration(minutes: 30))),
                            _TimerChip('1h', lilac, () => _setTimedAutonomous(const Duration(hours: 1))),
                            _TimerChip('2h', lilac, () => _setTimedAutonomous(const Duration(hours: 2))),
                            _TimerChip('Until I turn off', lilac, () => _save(_settings.copyWith(clearTimer: true))),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ── AI BADGE (SHOW ON REQUEST) ───────────────────────────────────
          _SectionLabel('🏷 AI Badge Disclosure', textMuted),
          _Card(
            surface: surface,
            border: border,
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              secondary: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.verified_rounded, color: Colors.amber, size: 22),
              ),
              title: Text(
                'Show 🤖 Badge to Recipients',
                style: TextStyle(color: textPrim, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              subtitle: Text(
                _settings.showAiBadge
                    ? 'Recipients can see when Twin replied on your behalf'
                    : 'Badge hidden — AI replies appear as normal messages',
                style: TextStyle(color: textMuted, fontSize: 12.5),
              ),
              activeColor: Colors.amber,
              value: _settings.showAiBadge,
              onChanged: (val) => _save(_settings.copyWith(showAiBadge: val)),
            ),
          ),

          const SizedBox(height: 20),

          // ── TEST YOUR TWIN ──────────────────────────────────────────────
          _SectionLabel('🧪 Test Your Twin', textMuted),
          _Card(
            surface: surface,
            border: border,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Enter a message someone might send you:',
                    style: TextStyle(color: textSec, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _testInputCtrl,
                    decoration: InputDecoration(
                      hintText: 'e.g. "Hey, can we meet Thursday?"',
                      hintStyle: TextStyle(color: textMuted, fontSize: 13),
                      filled: true,
                      fillColor: lilac.withValues(alpha: 0.07),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    style: TextStyle(color: textPrim, fontSize: 14),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: lilac,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                      ),
                      icon: _isTestLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('See How Twin Would Reply',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      onPressed: _isTestLoading ? null : _testTwin,
                    ),
                  ),
                  if (_testReplies.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    ...List.generate(_testReplies.length, (i) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: lilac.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: lilac.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            Text('${i + 1}. ', style: TextStyle(color: lilac, fontWeight: FontWeight.bold, fontSize: 13)),
                            Expanded(
                              child: Text(
                                _testReplies[i],
                                style: TextStyle(color: textPrim, fontSize: 14),
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: _testReplies[i]));
                                _showSnack('Copied!', lilac);
                              },
                              child: Icon(Icons.copy_rounded, size: 16, color: textMuted),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── PRIVACY NOTE ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🔒', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Privacy: Your AI Twin only learns stylistic patterns (tone, length, emoji habits) — never stores raw message content. Training data never leaves your device in plain text.',
                    style: TextStyle(color: textSec, fontSize: 12.5, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatUntil(DateTime dt) {
    final diff = dt.difference(DateTime.now());
    if (diff.isNegative) return 'expired';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    return '${diff.inHours}h ${diff.inMinutes % 60}m';
  }
}

// ─── Helper widgets ───────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final Color color;
  const _SectionLabel(this.label, this.color);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          label,
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5),
        ),
      );
}

class _Card extends StatelessWidget {
  final Widget child;
  final Color surface;
  final Color border;
  const _Card({required this.child, required this.surface, required this.border});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border),
        ),
        child: child,
      );
}

class _TimerChip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _TimerChip(this.label, this.color, this.onTap);

  @override
  Widget build(BuildContext context) => ActionChip(
        label: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
        backgroundColor: color.withValues(alpha: 0.1),
        side: BorderSide(color: color.withValues(alpha: 0.3)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        onPressed: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      );
}

class _BuildUntrained extends StatelessWidget {
  final Color lilac;
  final Color textMuted;
  final Color textSec;
  const _BuildUntrained({required this.lilac, required this.textMuted, required this.textSec});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text('🌱', style: const TextStyle(fontSize: 36)),
            const SizedBox(height: 10),
            Text(
              'Still learning your style…',
              style: TextStyle(color: textMuted, fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Send a few more messages in your chats and your AI Twin will start building your persona profile automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(color: textSec, fontSize: 13, height: 1.4),
            ),
          ],
        ),
      );
}

class _BuildPersonaStats extends StatelessWidget {
  final TwinPersona persona;
  final Color lilac;
  final Color textPrim;
  final Color textMuted;
  final Color textSec;
  final Color surface;
  const _BuildPersonaStats({
    required this.persona,
    required this.lilac,
    required this.textPrim,
    required this.textMuted,
    required this.textSec,
    required this.surface,
  });

  @override
  Widget build(BuildContext context) {
    final lastStr = persona.lastTrained != null
        ? _timeAgo(persona.lastTrained!)
        : 'Never';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('🤖', style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Trained on ${persona.trainedOnCount} messages',
                    style: TextStyle(color: textPrim, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  Text(
                    'Last updated $lastStr',
                    style: TextStyle(color: textMuted, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Stat('🎭 Tone', persona.toneLabel, lilac),
          _Stat('📝 Vocabulary', '${_capitalize(persona.vocabularyLevel)} · ~${persona.avgResponseLengthWords} words avg', lilac),
          _Stat('😄 Emojis', persona.emojiLabel, lilac),
          _Stat('👋 Greeting', '"${persona.typicalGreeting}"', lilac),
          if (persona.typicalSignOff.isNotEmpty)
            _Stat('🤝 Sign-off', '"${persona.typicalSignOff}"', lilac),
          if (persona.samplePhrases.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Characteristic phrases:',
              style: TextStyle(color: textMuted, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: persona.samplePhrases
                  .map((p) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: lilac.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('"$p"',
                            style: TextStyle(color: lilac, fontSize: 11.5, fontStyle: FontStyle.italic)),
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              _MiniBar('Humor', persona.humorIndex, Colors.orange, textMuted),
              const SizedBox(width: 10),
              _MiniBar('Empathy', persona.empathyIndex, Colors.pink, textMuted),
            ],
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _capitalize(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Stat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    final textMuted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5);
    final textPrim = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: TextStyle(color: textMuted, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value, style: TextStyle(color: textPrim, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _MiniBar extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final Color textMuted;
  const _MiniBar(this.label, this.value, this.color, this.textMuted);

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$label ${(value * 100).round()}%',
                style: TextStyle(color: textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value.clamp(0.0, 1.0),
                backgroundColor: color.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation(color),
                minHeight: 6,
              ),
            ),
          ],
        ),
      );
}
