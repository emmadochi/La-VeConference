import re

path = 'lib/screens/chat_conversation_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Update Media Bubbles Rendering
old_bubbles = """                                          // Image Bubble (Zoomable on Tap)
                                          else if (type == 'image' && (mediaUrl != null || localPath != null))
                                            GestureDetector(
                                              onTap: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) => ImageViewerScreen(
                                                      imageUrl: mediaUrl,
                                                      localPath: localPath,
                                                      title: senderName,
                                                      subtitle: timeString,
                                                    ),
                                                  ),
                                                );
                                              },
                                              child: Padding(
                                                padding: const EdgeInsets.only(bottom: 6),
                                                child: ClipRRect(
                                                  borderRadius: BorderRadius.circular(12),
                                                  child: (localPath != null && File(localPath).existsSync())
                                                      ? Image.file(File(localPath), fit: BoxFit.cover)
                                                      : (mediaUrl != null && mediaUrl.startsWith('data:')
                                                          ? Image.memory(
                                                              base64Decode(mediaUrl.substring(mediaUrl.indexOf(',') + 1)),
                                                              fit: BoxFit.cover,
                                                            )
                                                          : Image.network(
                                                              mediaUrl ?? '',
                                                              fit: BoxFit.cover,
                                                              loadingBuilder: (context, child, progress) {
                                                                if (progress == null) return child;
                                                                return Container(
                                                                  height: 180,
                                                                  color: Colors.black26,
                                                                  child: Center(
                                                                    child: CircularProgressIndicator(color: mint),
                                                                  ),
                                                                );
                                                              },
                                                              errorBuilder: (context, error, stackTrace) => Container(
                                                                height: 140,
                                                                color: Colors.black26,
                                                                child: const Center(
                                                                  child: Icon(Icons.broken_image_rounded, color: Colors.white54, size: 36),
                                                                ),
                                                              ),
                                                            )),
                                                ),
                                              ),
                                            )
                                          // Interactive Video Message Bubble
                                          else if (type == 'video')
                                            VideoMessageBubble(
                                              mediaUrl: mediaUrl,
                                              localPath: localPath,
                                              fileName: fileName,
                                              fileSize: fileSize,
                                              durationSeconds: duration,
                                              isMe: isMe,
                                              senderName: senderName,
                                              timeString: timeString,
                                            )
                                          // Interactive Voice Note Bubble
                                          else if (type == 'audio')
                                            VoiceNoteBubble(
                                              mediaUrl: mediaUrl,
                                              localPath: localPath,
                                              fileName: fileName,
                                              durationSeconds: duration,
                                              isMe: isMe,
                                              messageId: messageId,
                                            )
                                          // Document / File Message Bubble
                                          else if (type == 'file')
                                            FileMessageBubble(
                                              mediaUrl: mediaUrl,
                                              localPath: localPath,
                                              fileName: fileName ?? 'Document',
                                              fileSize: fileSize,
                                              isMe: isMe,
                                            )"""

new_bubbles = """                                          // Image Bubble (Zoomable on Tap + Inline Progress Overlay)
                                          else if (type == 'image' && (mediaUrl != null || localPath != null))
                                            Builder(
                                              builder: (ctx) {
                                                final bool isUploading = data['isUploading'] == true || status == 'uploading';
                                                final double uploadProgress = (data['uploadProgress'] as num?)?.toDouble() ?? 0.0;
                                                final bool isFailed = status == 'failed';

                                                return GestureDetector(
                                                  onTap: isUploading ? null : () {
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (_) => ImageViewerScreen(
                                                          imageUrl: mediaUrl,
                                                          localPath: localPath,
                                                          title: senderName,
                                                          subtitle: timeString,
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                  child: Padding(
                                                    padding: const EdgeInsets.only(bottom: 6),
                                                    child: Stack(
                                                      alignment: Alignment.center,
                                                      children: [
                                                        ClipRRect(
                                                          borderRadius: BorderRadius.circular(12),
                                                          child: (localPath != null && File(localPath).existsSync())
                                                              ? Image.file(File(localPath), fit: BoxFit.cover)
                                                              : (mediaUrl != null && mediaUrl.startsWith('data:')
                                                                  ? Image.memory(
                                                                      base64Decode(mediaUrl.substring(mediaUrl.indexOf(',') + 1)),
                                                                      fit: BoxFit.cover,
                                                                    )
                                                                  : Image.network(
                                                                      mediaUrl ?? '',
                                                                      fit: BoxFit.cover,
                                                                      loadingBuilder: (context, child, progress) {
                                                                        if (progress == null) return child;
                                                                        return Container(
                                                                          height: 180,
                                                                          color: Colors.black26,
                                                                          child: Center(
                                                                            child: CircularProgressIndicator(color: mint),
                                                                          ),
                                                                        );
                                                                      },
                                                                      errorBuilder: (context, error, stackTrace) => Container(
                                                                        height: 140,
                                                                        color: Colors.black26,
                                                                        child: const Center(
                                                                          child: Icon(Icons.broken_image_rounded, color: Colors.white54, size: 36),
                                                                        ),
                                                                      ),
                                                                    )),
                                                        ),
                                                        if (isUploading)
                                                          Container(
                                                            padding: const EdgeInsets.all(12),
                                                            decoration: BoxDecoration(
                                                              color: Colors.black.withValues(alpha: 0.7),
                                                              shape: BoxShape.circle,
                                                              border: Border.all(color: Colors.white24, width: 2),
                                                            ),
                                                            child: Stack(
                                                              alignment: Alignment.center,
                                                              children: [
                                                                SizedBox(
                                                                  width: 44,
                                                                  height: 44,
                                                                  child: CircularProgressIndicator(
                                                                    value: uploadProgress > 0 ? uploadProgress : null,
                                                                    strokeWidth: 3.5,
                                                                    color: AppTheme.lilacLight,
                                                                  ),
                                                                ),
                                                                Text(
                                                                  '${(uploadProgress * 100).toInt()}%',
                                                                  style: const TextStyle(
                                                                    color: Colors.white,
                                                                    fontSize: 11,
                                                                    fontWeight: FontWeight.bold,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          )
                                                        else if (isFailed)
                                                          Container(
                                                            padding: const EdgeInsets.all(10),
                                                            decoration: BoxDecoration(
                                                              color: Colors.black.withValues(alpha: 0.75),
                                                              shape: BoxShape.circle,
                                                            ),
                                                            child: const Icon(Icons.refresh_rounded, color: Colors.amberAccent, size: 32),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                );
                                              },
                                            )
                                          // Interactive Video Message Bubble
                                          else if (type == 'video')
                                            VideoMessageBubble(
                                              mediaUrl: mediaUrl,
                                              localPath: localPath,
                                              fileName: fileName,
                                              fileSize: fileSize,
                                              durationSeconds: duration,
                                              isMe: isMe,
                                              senderName: senderName,
                                              timeString: timeString,
                                              isUploading: data['isUploading'] == true || status == 'uploading',
                                              uploadProgress: (data['uploadProgress'] as num?)?.toDouble() ?? 0.0,
                                              uploadFailed: status == 'failed',
                                            )
                                          // Interactive Voice Note Bubble
                                          else if (type == 'audio')
                                            VoiceNoteBubble(
                                              mediaUrl: mediaUrl,
                                              localPath: localPath,
                                              fileName: fileName,
                                              durationSeconds: duration,
                                              isMe: isMe,
                                              messageId: messageId,
                                            )
                                          // Document / File Message Bubble
                                          else if (type == 'file')
                                            FileMessageBubble(
                                              mediaUrl: mediaUrl,
                                              localPath: localPath,
                                              fileName: fileName ?? 'Document',
                                              fileSize: fileSize,
                                              isMe: isMe,
                                              isUploading: data['isUploading'] == true || status == 'uploading',
                                              uploadProgress: (data['uploadProgress'] as num?)?.toDouble() ?? 0.0,
                                              uploadFailed: status == 'failed',
                                            )"""

assert old_bubbles in content, "old_bubbles not found!"
content = content.replace(old_bubbles, new_bubbles)

# 2. Update _pickAndSendImage
old_pick_image = """  Future<void> _pickAndSendImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 65,
      );
      if (picked == null) return;

      final sourceFile = File(picked.path);
      final fileName = 'img_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final replyPayload = _replyingTo;
      if (_replyingTo != null) setState(() => _replyingTo = null);

      // 1. Save local copy first for immediate offline viewing
      final localFile = await MediaStorageService.saveOutgoingFile(
        sourceFile: sourceFile,
        category: 'Images',
        targetFileName: fileName,
      );

      // 2. Upload ephemeral copy to Firebase Storage
      final downloadUrl = await MediaStorageService.uploadEphemeralMedia(
        file: localFile,
        chatId: _chatId,
        fileName: fileName,
        contentType: 'image/jpeg',
      );

      // 3. Send message with localPath and remoteUrl
      ChatService.sendMessage(
        chatId: _chatId,
        senderId: _myUid!,
        senderName: _myName!,
        receiverId: widget.peerUid,
        text: 'Photo',
        type: 'image',
        mediaUrl: downloadUrl,
        fileName: fileName,
        fileSize: await localFile.length(),
        localPath: localFile.path,
        replyTo: replyPayload,
        isGroup: widget.isGroup,
        groupParticipants: _groupParticipants ?? widget.groupParticipants,
      );
    } catch (e) {
      debugPrint("Failed to upload image: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload image: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }"""

new_pick_image = """  Future<void> _pickAndSendImage(ImageSource source) async {
    final tempId = 'temp_img_${DateTime.now().millisecondsSinceEpoch}';
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 65,
      );
      if (picked == null) return;

      final sourceFile = File(picked.path);
      final fileName = 'img_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final replyPayload = _replyingTo;
      if (_replyingTo != null) setState(() => _replyingTo = null);

      // 1. Save local copy first for immediate 0ms offline rendering
      final localFile = await MediaStorageService.saveOutgoingFile(
        sourceFile: sourceFile,
        category: 'Images',
        targetFileName: fileName,
      );
      final fileSize = await localFile.length();

      // 2. Immediately insert 0ms optimistic message bubble into chat
      final optimisticMsg = <String, dynamic>{
        'id': tempId,
        'clientTempId': tempId,
        'senderId': _myUid,
        'senderName': _myName,
        'receiverId': widget.peerUid,
        'text': 'Photo',
        'type': 'image',
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

      // 3. Upload with real-time percentage progress hook
      final downloadUrl = await MediaStorageService.uploadEphemeralMedia(
        file: localFile,
        chatId: _chatId,
        fileName: fileName,
        contentType: 'image/jpeg',
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
        text: 'Photo',
        type: 'image',
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
      debugPrint("Failed to upload image: $e");
      final idx = _optimisticMessages.indexWhere((m) => m['clientTempId'] == tempId);
      if (idx != -1 && mounted) {
        setState(() {
          _optimisticMessages[idx]['isUploading'] = false;
          _optimisticMessages[idx]['status'] = 'failed';
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload image: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }"""

assert old_pick_image in content, "old_pick_image not found!"
content = content.replace(old_pick_image, new_pick_image)

# 3. Update _pickAndSendFile
old_pick_file = """  Future<void> _pickAndSendFile() async {
    try {
      final result = await FilePicker.pickFiles();
      if (result == null || result.files.isEmpty) return;

      final pickedFile = result.files.single;
      if (pickedFile.path == null) return;

      final sourceFile = File(pickedFile.path!);
      final fileName = pickedFile.name;
      final fileSize = pickedFile.size;
      final replyPayload = _replyingTo;
      if (_replyingTo != null) setState(() => _replyingTo = null);

      // 1. Save locally to LiChat/Documents
      final localFile = await MediaStorageService.saveOutgoingFile(
        sourceFile: sourceFile,
        category: 'Documents',
        targetFileName: fileName,
      );

      // 2. Upload to Firebase Storage
      final remoteUrl = await MediaStorageService.uploadEphemeralMedia(
        file: localFile,
        chatId: _chatId,
        fileName: fileName,
        contentType: 'application/octet-stream',
      );

      // 3. Send message
      ChatService.sendMessage(
        chatId: _chatId,
        senderId: _myUid!,
        senderName: _myName!,
        receiverId: widget.peerUid,
        text: fileName,
        type: 'file',
        mediaUrl: remoteUrl,
        fileName: fileName,
        fileSize: fileSize,
        localPath: localFile.path,
        replyTo: replyPayload,
        isGroup: widget.isGroup,
        groupParticipants: _groupParticipants ?? widget.groupParticipants,
      );
    } catch (e) {
      debugPrint("Error picking and sending file: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send file: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }"""

new_pick_file = """  Future<void> _pickAndSendFile() async {
    final tempId = 'temp_file_${DateTime.now().millisecondsSinceEpoch}';
    try {
      final result = await FilePicker.pickFiles();
      if (result == null || result.files.isEmpty) return;

      final pickedFile = result.files.single;
      if (pickedFile.path == null) return;

      final sourceFile = File(pickedFile.path!);
      final fileName = pickedFile.name;
      final fileSize = pickedFile.size;
      final replyPayload = _replyingTo;
      if (_replyingTo != null) setState(() => _replyingTo = null);

      // 1. Save locally to LiChat/Documents
      final localFile = await MediaStorageService.saveOutgoingFile(
        sourceFile: sourceFile,
        category: 'Documents',
        targetFileName: fileName,
      );

      // 2. Immediately insert 0ms optimistic message bubble into chat
      final optimisticMsg = <String, dynamic>{
        'id': tempId,
        'clientTempId': tempId,
        'senderId': _myUid,
        'senderName': _myName,
        'receiverId': widget.peerUid,
        'text': fileName,
        'type': 'file',
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

      // 3. Upload with real-time percentage progress hook
      final remoteUrl = await MediaStorageService.uploadEphemeralMedia(
        file: localFile,
        chatId: _chatId,
        fileName: fileName,
        contentType: 'application/octet-stream',
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
          _optimisticMessages[idx]['mediaUrl'] = remoteUrl;
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
        text: fileName,
        type: 'file',
        mediaUrl: remoteUrl,
        fileName: fileName,
        fileSize: fileSize,
        localPath: localFile.path,
        replyTo: replyPayload,
        isGroup: widget.isGroup,
        groupParticipants: _groupParticipants ?? widget.groupParticipants,
        clientTempId: tempId,
      );
    } catch (e) {
      debugPrint("Error picking and sending file: $e");
      final idx = _optimisticMessages.indexWhere((m) => m['clientTempId'] == tempId);
      if (idx != -1 && mounted) {
        setState(() {
          _optimisticMessages[idx]['isUploading'] = false;
          _optimisticMessages[idx]['status'] = 'failed';
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send file: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }"""

assert old_pick_file in content, "old_pick_file not found!"
content = content.replace(old_pick_file, new_pick_file)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print("SUCCESS: chat_conversation_screen.dart updated cleanly!")
