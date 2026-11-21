import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/vault_service.dart';

class ChatVaultHeader extends StatefulWidget {
  final String chatId;
  final String chatTitle;
  final String currentUserId;
  final List<Map<String, dynamic>> recentMessages;

  const ChatVaultHeader({
    super.key,
    required this.chatId,
    required this.chatTitle,
    required this.currentUserId,
    required this.recentMessages,
  });

  @override
  State<ChatVaultHeader> createState() => _ChatVaultHeaderState();
}

class _ChatVaultHeaderState extends State<ChatVaultHeader> {
  bool _isExpanded = false;
  int _selectedTab = 0; // 0: Commitments, 1: Quick Info, 2: Expenses
  bool _isSyncingAI = false;

  Future<void> _syncWithAI() async {
    if (_isSyncingAI || widget.recentMessages.isEmpty) return;

    setState(() => _isSyncingAI = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            SizedBox(width: 12),
            Text("Extracting promises, codes & debts with Gemini AI..."),
          ],
        ),
        duration: Duration(seconds: 4),
      ),
    );

    final success = await VaultService.syncVaultWithAI(
      chatId: widget.chatId,
      messages: widget.recentMessages,
      chatTitle: widget.chatTitle,
    );

    if (mounted) {
      setState(() => _isSyncingAI = false);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Vault updated from conversation ✨")),
        );
      }
    }
  }

  void _showAddItemDialog() {
    final labelCtrl = TextEditingController();
    final valueCtrl = TextEditingController();
    String itemType = 'commitments';

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;
            return Padding(
              padding: EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 20 + bottomInset),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppTheme.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const Text(
                    "Add to Shared Vault",
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),

                  // Segmented Type Picker
                  Row(
                    children: [
                      _buildTypeOption(setSheetState, "Task", "commitments", itemType, (t) => itemType = t),
                      const SizedBox(width: 8),
                      _buildTypeOption(setSheetState, "Code / Info", "knowledge", itemType, (t) => itemType = t),
                      const SizedBox(width: 8),
                      _buildTypeOption(setSheetState, "Expense", "expenses", itemType, (t) => itemType = t),
                    ],
                  ),
                  const SizedBox(height: 14),

                  TextField(
                    controller: labelCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: itemType == 'commitments'
                          ? "What was promised? (e.g. Send report)"
                          : (itemType == 'knowledge' ? "Label (e.g. Gate Code, Wi-Fi)" : "Description (e.g. Lunch split)"),
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                      filled: true,
                      fillColor: AppTheme.background,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.border)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 10),

                  TextField(
                    controller: valueCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: itemType == 'commitments'
                          ? "Due Date / Time (e.g. Friday 5 PM)"
                          : (itemType == 'knowledge' ? "Code / Password / Address" : "Amount (e.g. \$25.00)"),
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                      filled: true,
                      fillColor: AppTheme.background,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.border)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 18),

                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      onPressed: () {
                        final label = labelCtrl.text.trim();
                        final val = valueCtrl.text.trim();
                        if (label.isEmpty) return;

                        Map<String, dynamic> data = {};
                        if (itemType == 'commitments') {
                          data = {
                            'task': label,
                            'dueDate': val.isNotEmpty ? val : 'Pending',
                            'author': 'You',
                            'assignee': 'You',
                            'status': 'pending',
                          };
                        } else if (itemType == 'knowledge') {
                          data = {
                            'label': label,
                            'value': val,
                            'category': 'reference',
                          };
                        } else {
                          data = {
                            'description': label,
                            'amount': val,
                            'payer': 'You',
                            'debtor': 'Other',
                            'settled': false,
                          };
                        }

                        VaultService.addItem(chatId: widget.chatId, itemType: itemType, itemData: data);
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                      child: const Text("Save to Vault", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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

  Widget _buildTypeOption(
    void Function(void Function()) setSheetState,
    String title,
    String typeKey,
    String currentType,
    Function(String) onSelect,
  ) {
    final isSelected = currentType == typeKey;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setSheetState(() => onSelect(typeKey));
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary.withValues(alpha: 0.2) : AppTheme.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppTheme.primary : AppTheme.border,
            ),
          ),
          child: Center(
            child: Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white60,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<VaultData>(
      stream: VaultService.streamVault(widget.chatId),
      builder: (context, snapshot) {
        final vault = snapshot.data ?? const VaultData();
        final commCount = vault.commitments.where((c) => c['status'] != 'completed').length;
        final knowCount = vault.knowledge.length;
        final expCount = vault.expenses.where((e) => e['settled'] != true).length;
        final totalActive = commCount + knowCount + expCount;

        // If vault is completely empty and not expanded, show a subtle prompt button
        if (totalActive == 0 && !_isExpanded) {
          return const SizedBox.shrink();
        }

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.surface.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border.withValues(alpha: 0.8)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Bar / Toggle Pill
                InkWell(
                  onTap: () => setState(() => _isExpanded = !_isExpanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.shield_outlined, color: AppTheme.primary, size: 15),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Vault: $commCount Promises • $knowCount Codes • $expCount Debts",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        // AI Sync button
                        InkWell(
                          onTap: _syncWithAI,
                          borderRadius: BorderRadius.circular(14),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            child: _isSyncingAI
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.mint),
                                  )
                                : const Icon(Icons.auto_awesome_rounded, color: AppTheme.mint, size: 16),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          color: Colors.white60,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),

                // Expanded Drawer
                if (_isExpanded) ...[
                  const Divider(height: 1, color: AppTheme.border),

                  // Section Tabs
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      children: [
                        _buildTabPill("Promises ($commCount)", 0),
                        const SizedBox(width: 6),
                        _buildTabPill("Codes ($knowCount)", 1),
                        const SizedBox(width: 6),
                        _buildTabPill("Debts ($expCount)", 2),
                      ],
                    ),
                  ),

                  // Tab Content
                  Container(
                    constraints: const BoxConstraints(maxHeight: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: SingleChildScrollView(
                      child: _selectedTab == 0
                          ? _buildCommitmentsList(vault.commitments)
                          : (_selectedTab == 1
                              ? _buildKnowledgeList(vault.knowledge)
                              : _buildExpensesList(vault.expenses)),
                    ),
                  ),

                  // Bottom Action Bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          onPressed: _showAddItemDialog,
                          icon: const Icon(Icons.add_rounded, size: 14, color: AppTheme.primary),
                          label: const Text("Add Item", style: TextStyle(color: AppTheme.primary, fontSize: 11)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _syncWithAI,
                          icon: const Icon(Icons.refresh_rounded, size: 13, color: Colors.white60),
                          label: const Text("AI Re-scan", style: TextStyle(color: Colors.white60, fontSize: 11)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTabPill(String title, int tabIndex) {
    final isSelected = _selectedTab == tabIndex;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = tabIndex),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary.withValues(alpha: 0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppTheme.primary.withValues(alpha: 0.6) : Colors.transparent,
            ),
          ),
          child: Center(
            child: Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white60,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCommitmentsList(List<Map<String, dynamic>> commitments) {
    if (commitments.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: Text(
            "No promises detected yet.\nAI scans conversation as you chat.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ),
      );
    }

    return Column(
      children: commitments.map((c) {
        final id = c['id'] ?? '';
        final task = c['task'] ?? '';
        final isDone = c['status'] == 'completed';
        final dueDate = c['dueDate'] ?? '';
        final author = c['author'] ?? '';

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.background.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              InkWell(
                onTap: () {
                  VaultService.toggleTaskStatus(
                    chatId: widget.chatId,
                    taskId: id,
                    isCompleted: !isDone,
                  );
                },
                child: Icon(
                  isDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  color: isDone ? Colors.greenAccent : Colors.white60,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task,
                      style: TextStyle(
                        color: isDone ? Colors.white38 : Colors.white,
                        fontSize: 12,
                        decoration: isDone ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (dueDate.isNotEmpty && dueDate != 'Pending')
                      Text(
                        "Due: $dueDate ($author)",
                        style: const TextStyle(color: Colors.amberAccent, fontSize: 10),
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => VaultService.deleteItem(chatId: widget.chatId, itemType: 'commitments', itemId: id),
                icon: const Icon(Icons.close_rounded, size: 14, color: Colors.white30),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildKnowledgeList(List<Map<String, dynamic>> knowledge) {
    if (knowledge.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: Text(
            "No Wi-Fi codes, addresses, or keys saved yet.",
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ),
      );
    }

    return Column(
      children: knowledge.map((k) {
        final id = k['id'] ?? '';
        final label = k['label'] ?? 'Code';
        final value = k['value'] ?? '';

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.background.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.key_rounded, color: AppTheme.primary, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
                    Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: value));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Copied $label to clipboard 📋"), duration: const Duration(seconds: 1)),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 15, color: AppTheme.mint),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: "Copy code",
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => VaultService.deleteItem(chatId: widget.chatId, itemType: 'knowledge', itemId: id),
                icon: const Icon(Icons.close_rounded, size: 14, color: Colors.white30),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildExpensesList(List<Map<String, dynamic>> expenses) {
    if (expenses.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: Text(
            "No shared expenses or debts recorded.",
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ),
      );
    }

    return Column(
      children: expenses.map((e) {
        final id = e['id'] ?? '';
        final desc = e['description'] ?? 'Expense';
        final amount = e['amount'] ?? '';
        final payer = e['payer'] ?? 'Payer';
        final debtor = e['debtor'] ?? 'Debtor';

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.background.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.payments_outlined, color: Colors.greenAccent, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(desc, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
                    Text("$payer paid • $debtor owes $amount", style: const TextStyle(color: Colors.greenAccent, fontSize: 10)),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => VaultService.deleteItem(chatId: widget.chatId, itemType: 'expenses', itemId: id),
                icon: const Icon(Icons.close_rounded, size: 14, color: Colors.white30),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
