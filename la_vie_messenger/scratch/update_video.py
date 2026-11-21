path = 'lib/screens/chat_conversation_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

import re

# Find _pickAndSendVideo
start_marker = "  Future<void> _pickAndSendVideo(ImageSource source) async {"
end_marker = "      debugPrint(\"Failed to upload video: $e\");"

start_idx = content.find(start_marker)
end_idx = content.find(end_marker)

assert start_idx != -1, "start_marker not found"
assert end_idx != -1, "end_marker not found"

# Find closing brace of try/catch
sub = content[end_idx:]
catch_block_end = end_idx + sub.find("  }\n") + 4

old_method = content[start_idx:catch_block_end]

new_method = """  Future<void> _pickAndSendVideo(ImageSource source) async {
    final tempId = 'temp_vid_${DateTime.now().millisecondsSinceEpoch}';
    try {
      final picker = ImagePicker();
      final picked = await picker.pickVideo(
        source: source,
        maxDuration: const Duration(minutes: 10),
      );
      if (picked == null) return;

      final sourceFile = File(picked.path);
      final fileSize = await sourceFile.length();

      // Check 100 MB limit (server supports up to 100 MB after Nginx update)
      if (fileSize > 100 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Video exceeds 100 MB limit. Please select a shorter or compressed video.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      final fileName = 'vid_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final replyPayload = _replyingTo;
      if (_replyingTo != null) setState(() => _replyingTo = null);

      // 1. Save local copy first for immediate 0ms preview
      final localFile = await MediaStorageService.saveOutgoingFile(
        sourceFile: sourceFile,
        category: 'Videos',
        targetFileName: fileName,
      );

      // 2. Immediately insert 0ms optimistic message bubble into chat
      final optimisticMsg = <String, dynamic>{
        'id': tempId,
        'clientTempId': tempId,
        'senderId': _myUid,
        'senderName': _myName,
        'receiverId': widget.peerUid,
        'text': 'Video',
        'type': 'video',
        'mediaUrl': null,
        'fileName': fileName,
        'fileSize': fileSize,
        'localPath': localFile.path,
        'replyTo': replyPayload,
        'timestamp': Timestamp.now(),
        'status': 'uploading',
        'isUploading': true,
        'uploadProgress': 0.0,
        'isGroup': widget.isGroup,
        'isOptimistic': true,
        'readBy': {_myUid!: Timestamp.now()},
        'deliveredTo': {_myUid!: Timestamp.now()},
      };

      setState(() {
        _optimisticMessages.insert(0, optimisticMsg);
      });

      if (_scrollController.hasClients) {
        _scrollController.animateTo(0.0, duration: const Duration(milliseconds: 120), curve: Curves.easeOut);
      }

      // 3. Chunked streaming upload with live inline progress update
      final downloadUrl = await MediaStorageService.uploadEphemeralMedia(
        file: localFile,
        chatId: _chatId,
        fileName: fileName,
        contentType: 'video/mp4',
        onProgress: (sent, total) {
          if (total > 0 && mounted) {
            final pct = (sent / total).clamp(0.0, 1.0);
            final idx = _optimisticMessages.indexWhere((m) => m['clientTempId'] == tempId);
            if (idx != -1 && mounted) {
              setState(() {
                _optimisticMessages[idx]['uploadProgress'] = pct;
              });
            }
          }
        },
      );

      final idx = _optimisticMessages.indexWhere((m) => m['clientTempId'] == tempId);
      if (idx != -1 && mounted) {
        setState(() {
          _optimisticMessages[idx]['mediaUrl'] = downloadUrl;
          _optimisticMessages[idx]['isUploading'] = false;
          _optimisticMessages[idx]['status'] = 'sent';
        });
      }

      // 4. Send message to Firestore
      await ChatService.sendMessage(
        chatId: _chatId,
        senderId: _myUid!,
        senderName: _myName!,
        receiverId: widget.peerUid,
        text: 'Video',
        type: 'video',
        mediaUrl: downloadUrl,
        fileName: fileName,
        fileSize: fileSize,
        localPath: localFile.path,
        replyTo: replyPayload,
        isGroup: widget.isGroup,
        groupParticipants: _groupParticipants ?? widget.groupParticipants,
        clientTempId: tempId,
      );
    } catch (e) {
      debugPrint("Failed to upload video: $e");
      final idx = _optimisticMessages.indexWhere((m) => m['clientTempId'] == tempId);
      if (idx != -1 && mounted) {
        setState(() {
          _optimisticMessages[idx]['isUploading'] = false;
          _optimisticMessages[idx]['status'] = 'failed';
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload video: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }
"""

content = content[:start_idx] + new_method + content[catch_block_end:]
with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print("SUCCESS: _pickAndSendVideo updated cleanly!")
