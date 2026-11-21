import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

class VaultData {
  final List<Map<String, dynamic>> commitments;
  final List<Map<String, dynamic>> knowledge;
  final List<Map<String, dynamic>> expenses;

  const VaultData({
    this.commitments = const [],
    this.knowledge = const [],
    this.expenses = const [],
  });

  int get totalActiveCount {
    final activeComm = commitments.where((c) => c['status'] != 'completed').length;
    return activeComm + knowledge.length + expenses.length;
  }

  factory VaultData.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const VaultData();
    return VaultData(
      commitments: List<Map<String, dynamic>>.from(data['commitments'] ?? []),
      knowledge: List<Map<String, dynamic>>.from(data['knowledge'] ?? []),
      expenses: List<Map<String, dynamic>>.from(data['expenses'] ?? []),
    );
  }
}

class VaultService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _backendUrl = 'https://la-vie.lifechangerstouch.org';

  /// Real-time stream of the chat vault document
  static Stream<VaultData> streamVault(String chatId) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('vault')
        .doc('data')
        .snapshots()
        .map((snap) => VaultData.fromMap(snap.data()));
  }

  /// Triggers Gemini AI extraction of commitments, reference info, and expenses
  static Future<bool> syncVaultWithAI({
    required String chatId,
    required List<Map<String, dynamic>> messages,
    String chatTitle = 'Chat',
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_backendUrl/api/ai/vault/extract'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chatId': chatId,
          'messages': messages,
          'chat_title': chatTitle,
        }),
      ).timeout(const Duration(seconds: 25));

      return res.statusCode == 200;
    } catch (e) {
      debugPrint("Vault AI sync error: $e");
      return false;
    }
  }

  /// Toggles a commitment task status between completed and pending
  static Future<void> toggleTaskStatus({
    required String chatId,
    required String taskId,
    required bool isCompleted,
  }) async {
    final newStatus = isCompleted ? 'completed' : 'pending';

    // 1. Optimistic direct update to Firestore
    try {
      final docRef = _firestore.collection('chats').doc(chatId).collection('vault').doc('data');
      final snap = await docRef.get();
      if (snap.exists) {
        final list = List<Map<String, dynamic>>.from(snap.data()?['commitments'] ?? []);
        for (final item in list) {
          if (item['id'] == taskId) {
            item['status'] = newStatus;
            item['completedAt'] = isCompleted ? DateTime.now().toUtc().toIso8601String() : null;
            break;
          }
        }
        await docRef.set({'commitments': list, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint("Firestore direct task toggle error: $e");
    }

    // 2. Sync to backend API
    try {
      await http.post(
        Uri.parse('$_backendUrl/api/ai/vault/toggle-task'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chatId': chatId,
          'taskId': taskId,
          'status': newStatus,
        }),
      ).timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  /// Deletes an item from the vault (commitments, knowledge, or expenses)
  static Future<void> deleteItem({
    required String chatId,
    required String itemType, // 'commitments', 'knowledge', 'expenses'
    required String itemId,
  }) async {
    try {
      final docRef = _firestore.collection('chats').doc(chatId).collection('vault').doc('data');
      final snap = await docRef.get();
      if (snap.exists) {
        final list = List<Map<String, dynamic>>.from(snap.data()?[itemType] ?? []);
        list.removeWhere((item) => item['id'] == itemId);
        await docRef.set({itemType: list, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint("Firestore direct delete error: $e");
    }

    try {
      await http.post(
        Uri.parse('$_backendUrl/api/ai/vault/delete-item'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chatId': chatId,
          'itemType': itemType,
          'itemId': itemId,
        }),
      ).timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  /// Manually adds an item to the vault
  static Future<void> addItem({
    required String chatId,
    required String itemType,
    required Map<String, dynamic> itemData,
  }) async {
    try {
      await http.post(
        Uri.parse('$_backendUrl/api/ai/vault/add-item'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chatId': chatId,
          'itemType': itemType,
          'itemData': itemData,
        }),
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint("Add vault item error: $e");
    }
  }
}
