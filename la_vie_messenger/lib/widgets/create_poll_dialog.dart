import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class CreatePollDialog extends StatefulWidget {
  final Function(String question, List<String> options, bool allowMultiple) onPollCreated;

  const CreatePollDialog({
    super.key,
    required this.onPollCreated,
  });

  static Future<void> show(
    BuildContext context, {
    required Function(String question, List<String> options, bool allowMultiple) onPollCreated,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => CreatePollDialog(onPollCreated: onPollCreated),
    );
  }

  @override
  State<CreatePollDialog> createState() => _CreatePollDialogState();
}

class _CreatePollDialogState extends State<CreatePollDialog> {
  final TextEditingController _questionController = TextEditingController();
  final List<TextEditingController> _optionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool _allowMultiple = false;

  void _addOption() {
    if (_optionControllers.length < 10) {
      setState(() {
        _optionControllers.add(TextEditingController());
      });
    }
  }

  void _removeOption(int index) {
    if (_optionControllers.length > 2) {
      setState(() {
        _optionControllers[index].dispose();
        _optionControllers.removeAt(index);
      });
    }
  }

  void _submit() {
    final question = _questionController.text.trim();
    if (question.isEmpty) return;

    final options = _optionControllers
        .map((c) => c.text.trim())
        .where((text) => text.isNotEmpty)
        .toList();

    if (options.length < 2) return;

    widget.onPollCreated(question, options, _allowMultiple);
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _questionController.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textPrim = AppTheme.text(context);
    final textMuted = AppTheme.textMut(context);
    final surfaceElevated = AppTheme.surfaceElevatedColor(context);
    final border = AppTheme.borderColor(context);
    final mint = AppTheme.mintColor(context);

    final isValid = _questionController.text.trim().isNotEmpty &&
        _optionControllers.where((c) => c.text.trim().isNotEmpty).length >= 2;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 14,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.poll_rounded, color: mint, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'Create Poll',
                        style: TextStyle(
                          color: textPrim,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: isValid ? _submit : null,
                    child: Text(
                      'Create',
                      style: TextStyle(
                        color: isValid ? mint : textMuted,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Question Field
              Text(
                'QUESTION',
                style: TextStyle(
                  color: mint,
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: surfaceElevated,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: border),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: TextField(
                  controller: _questionController,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(color: textPrim, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Ask a question...',
                    hintStyle: TextStyle(color: textMuted, fontSize: 14),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Options
              Text(
                'OPTIONS',
                style: TextStyle(
                  color: mint,
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),

              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _optionControllers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  return Container(
                    decoration: BoxDecoration(
                      color: surfaceElevated,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: border),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Text(
                          '${index + 1}.',
                          style: TextStyle(color: textMuted, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _optionControllers[index],
                            onChanged: (_) => setState(() {}),
                            style: TextStyle(color: textPrim, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'Option ${index + 1}',
                              hintStyle: TextStyle(color: textMuted, fontSize: 13.5),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        if (_optionControllers.length > 2)
                          IconButton(
                            icon: Icon(Icons.close_rounded, color: textMuted, size: 18),
                            onPressed: () => _removeOption(index),
                          ),
                      ],
                    ),
                  );
                },
              ),

              if (_optionControllers.length < 10) ...[
                const SizedBox(height: 10),
                InkWell(
                  onTap: _addOption,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    child: Row(
                      children: [
                        Icon(Icons.add_circle_outline_rounded, color: mint, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Add option',
                          style: TextStyle(
                            color: mint,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 14),
              Divider(color: border, height: 1),
              const SizedBox(height: 10),

              // Multiple Answers Switch
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeColor: mint,
                title: Text(
                  'Allow multiple answers',
                  style: TextStyle(color: textPrim, fontSize: 14.5, fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  'Voters can select more than one option',
                  style: TextStyle(color: textMuted, fontSize: 12),
                ),
                value: _allowMultiple,
                onChanged: (val) => setState(() => _allowMultiple = val),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
