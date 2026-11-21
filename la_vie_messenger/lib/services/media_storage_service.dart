import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'call_signaling_service.dart';
import 'r2_storage_service.dart';

/// Chunked multipart request: streams the file in 64 KB disk chunks,
/// reporting byte-level progress without ever loading the full file into RAM.
/// Eliminates Android OOM crashes on large video uploads (50 MB+).
class _ChunkedMultipartRequest extends http.MultipartRequest {
  final void Function(int bytesSent, int totalBytes)? onProgress;

  _ChunkedMultipartRequest(super.method, super.url, {this.onProgress});

  @override
  http.ByteStream finalize() {
    final byteStream = super.finalize();
    if (onProgress == null) return byteStream;
    final total = contentLength;
    int bytesSent = 0;
    final transformed = StreamTransformer<List<int>, List<int>>.fromHandlers(
      handleData: (data, sink) {
        sink.add(data);
        bytesSent += data.length;
        onProgress!(bytesSent, total > 0 ? total : bytesSent);
      },
    );
    return http.ByteStream(byteStream.transform(transformed));
  }
}

class MediaStorageService {
  static final FirebaseStorage _storage = FirebaseStorage.instance;
  static const String _backendUrl = 'https://la-vie.lifechangerstouch.org';

  static Future<Directory> getCategoryDirectory(String category) async {
    final appDir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory('${appDir.path}/LiChat/$category');
    if (!await mediaDir.exists()) await mediaDir.create(recursive: true);
    return mediaDir;
  }

  static Future<File?> findLocalFile({
    required String category,
    required String fileName,
    String? knownLocalPath,
  }) async {
    try {
      if (knownLocalPath != null && knownLocalPath.isNotEmpty) {
        final f = File(knownLocalPath);
        if (await f.exists()) return f;
      }
      final dir = await getCategoryDirectory(category);
      final file = File('${dir.path}/$fileName');
      if (await file.exists()) return file;
    } catch (e) {
      debugPrint("Error checking local file: $e");
    }
    return null;
  }

  static Future<File> saveOutgoingFile({
    required File sourceFile,
    required String category,
    required String targetFileName,
  }) async {
    final dir = await getCategoryDirectory(category);
    final targetPath = '${dir.path}/$targetFileName';
    if (sourceFile.path == targetPath) return sourceFile;
    return await sourceFile.copy(targetPath);
  }

  static String _mimeFromFileName(String fileName, {String? hintContentType}) {
    if (hintContentType != null && hintContentType.isNotEmpty) return hintContentType;
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.mkv')) return 'video/x-matroska';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.3gp')) return 'video/3gpp';
    if (lower.endsWith('.avi')) return 'video/avi';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.m4a') || lower.endsWith('.aac')) return 'audio/x-m4a';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.ogg')) return 'audio/ogg';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    return 'application/octet-stream';
  }

  static MediaType? _toMediaType(String mimeStr) {
    try {
      final idx = mimeStr.indexOf('/');
      if (idx != -1) return MediaType(mimeStr.substring(0, idx), mimeStr.substring(idx + 1));
    } catch (_) {}
    return null;
  }

  static Future<String> uploadProfilePhoto({
    required File file,
    required String uid,
  }) async {
    // 0. Cloudflare R2 — primary path
    try {
      final r2Url = await R2StorageService.uploadProfilePhoto(file: file, uid: uid);
      debugPrint('[Upload] R2 profile photo success -> $r2Url');
      return r2Url;
    } catch (r2Error) {
      debugPrint('[Upload] R2 profile photo failed: $r2Error. Falling back...');
    }

    try {
      final uri = Uri.parse('$_backendUrl/api/profile/upload');
      final user = FirebaseAuth.instance.currentUser;
      final authToken = await user?.getIdToken();
      final request = http.MultipartRequest('POST', uri)
        ..fields['uid'] = uid
        ..files.add(await http.MultipartFile.fromPath(
          'file', file.path,
          filename: '$uid.jpg',
          contentType: MediaType('image', 'jpeg'),
        ));
      if (authToken != null && authToken.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $authToken';
      }
      final streamedResponse = await request.send().timeout(const Duration(seconds: 20));
      final response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['url'] != null) {
          final rawUrl = data['url'] as String;
          if (rawUrl.startsWith('/')) {
            return '$_backendUrl$rawUrl';
          }
          return rawUrl;
        }
      } else {
        debugPrint("Server profile upload status ${response.statusCode}: ${response.body}");
      }
    } catch (backendError) {
      debugPrint("Direct profile upload error: $backendError. Trying fallback...");
    }
    try {
      final ref = _storage.ref().child('profiles').child('$uid.jpg');
      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {'uploadedAt': DateTime.now().toIso8601String()},
      );
      final snapshot = await ref.putFile(file, metadata);
      return await snapshot.ref.getDownloadURL();
    } catch (storageError) {
      debugPrint("Firebase Storage profile upload error: $storageError. Using data URI fallback...");
    }
    try {
      final bytes = await file.readAsBytes();
      final base64String = base64Encode(bytes);
      return 'data:image/jpeg;base64,$base64String';
    } catch (e) {
      throw Exception("Could not process image: $e");
    }
  }

  /// Uploads media using a chunked stream — ZERO full-file RAM allocation.
  ///
  /// Priority: 1. Cloudflare R2 (zero-egress, fastest), 2. LiChat backend,
  /// 3. Firebase Storage fallback, 4. Base64 offline fallback (small files only).
  ///
  /// [onProgress] fires on every 64 KB chunk with (bytesSent, totalBytes).
  /// Use it to update a percentage progress bar in the chat UI.
  static Future<String> uploadEphemeralMedia({
    required File file,
    required String chatId,
    required String fileName,
    String? contentType,
    void Function(int bytesSent, int totalBytes)? onProgress,
  }) async {
    final mimeStr = _mimeFromFileName(fileName, hintContentType: contentType);
    final mediaType = _toMediaType(mimeStr);
    final fileSize = await file.length();
    String lastBackendError = '';
    String lastStorageError = '';


    // 0. Cloudflare R2 — primary path (zero egress fees, no server cost)
    try {
      final r2Url = await R2StorageService.uploadMedia(
        file: file,
        chatId: chatId,
        fileName: fileName,
        contentType: mimeStr,
        onProgress: onProgress,
      );
      debugPrint('[Upload] R2 success -> $r2Url');
      return r2Url;
    } catch (r2Error) {
      debugPrint('[Upload] R2 failed: $r2Error. Falling back to backend...');
    }
    try {
      final uri = Uri.parse('$_backendUrl/api/chat/upload');
      final user = FirebaseAuth.instance.currentUser;
      String? authToken;
      try {
        authToken = await user?.getIdToken(true);
      } catch (_) {
        authToken = await user?.getIdToken();
      }
      final request = _ChunkedMultipartRequest('POST', uri, onProgress: onProgress != null
          ? (sent, total) => onProgress(sent, total > 0 ? total : fileSize)
          : null)
        ..fields['chat_id'] = chatId
        ..fields['category'] = 'media'
        ..files.add(await http.MultipartFile.fromPath(
          'file', file.path,
          filename: fileName,
          contentType: mediaType,
        ));
      if (authToken != null && authToken.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $authToken';
      }
      final timeout = fileSize > 10 * 1024 * 1024
          ? const Duration(minutes: 10)
          : const Duration(minutes: 5);
      final streamedResponse = await request.send().timeout(timeout);
      final response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['url'] != null) {
          debugPrint("Upload success -> ${data['url']}");
          return data['url'] as String;
        }
      } else {
        lastBackendError = "HTTP ${response.statusCode}: ${response.body}";
        debugPrint("Server upload -> HTTP ${response.statusCode}: ${response.body}");
      }
    } catch (backendError) {
      lastBackendError = backendError.toString();
      debugPrint("Chunked server upload failed: $backendError. Trying Firebase...");
    }

    // 2. Firebase Storage fallback (streams internally, no full RAM load)
    try {
      final cleanName = fileName.replaceAll(RegExp(r'[^\w\.\-]'), '_');
      final storageRef = _storage
          .ref()
          .child('chat_media/$chatId/${DateTime.now().millisecondsSinceEpoch}_$cleanName');
      final metadata = SettableMetadata(
        contentType: mimeStr,
        customMetadata: {'uploadedAt': DateTime.now().toIso8601String(), 'ephemeral': 'true'},
      );
      final uploadTask = storageRef.putFile(file, metadata);
      if (onProgress != null) {
        uploadTask.snapshotEvents.listen((snapshot) {
          onProgress(snapshot.bytesTransferred.toInt(), snapshot.totalBytes.toInt());
        });
      }
      final snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (storageError) {
      lastStorageError = storageError.toString();
      debugPrint("Firebase Storage upload failed: $storageError");
    }

    // 3. Safe offline fallback: Base64 Data URI — ONLY for small files (< 800 KB).
    //    Videos must NOT use this path — base64 would OOM the device.
    if (fileSize <= 800 * 1024) {
      try {
        final bytes = await file.readAsBytes();
        final base64String = base64Encode(bytes);
        return 'data:$mimeStr;base64,$base64String';
      } catch (e) {
        debugPrint("Base64 fallback encoding failed: $e");
      }
    }

    final backendStr = lastBackendError.isNotEmpty ? "Backend: $lastBackendError. " : "";
    final storageStr = lastStorageError.isNotEmpty ? "Storage: $lastStorageError. " : "";
    final reasonStr = (backendStr.isNotEmpty || storageStr.isNotEmpty) ? " ($backendStr$storageStr)" : "";
    throw Exception(
      "Media upload failed: server and Firebase are unreachable.$reasonStr "
      "File size: ${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB. "
      "Please check your internet connection and try again.",
    );
  }

  /// Downloads remote media and saves to local device storage using chunked streaming.
  static Future<File?> downloadMediaToLocal({
    required String remoteUrl,
    required String category,
    required String targetFileName,
  }) async {
    try {
      final dir = await getCategoryDirectory(category);
      final file = File('${dir.path}/$targetFileName');
      if (remoteUrl.startsWith('data:')) {
        final commaIndex = remoteUrl.indexOf(',');
        if (commaIndex != -1) {
          final bytes = base64Decode(remoteUrl.substring(commaIndex + 1));
          await file.writeAsBytes(bytes);
          return file;
        }
      }
      final client = http.Client();
      try {
        final streamedResponse = await client.send(http.Request('GET', Uri.parse(remoteUrl)));
        if (streamedResponse.statusCode == 200) {
          final sink = file.openWrite();
          await streamedResponse.stream.pipe(sink);
          await sink.close();
          return file;
        } else {
          debugPrint("Download failed with status: ${streamedResponse.statusCode}");
        }
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint("Error downloading media: $e");
    }
    return null;
  }

  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String formatDuration(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  static ImageProvider? getAvatarProvider(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('data:')) {
      final comma = url.indexOf(',');
      if (comma != -1) {
        try {
          return MemoryImage(base64Decode(url.substring(comma + 1)));
        } catch (e) {
          debugPrint("Failed to decode base64 avatar: $e");
          return null;
        }
      }
    }
    return NetworkImage(url);
  }

  static Future<void> openOrShareFile(String filePath, String fileName) async {
    try {
      final xFile = XFile(filePath, name: fileName);
      await SharePlus.instance.share(ShareParams(files: [xFile], text: fileName));
    } catch (e) {
      debugPrint("Error opening/sharing file: $e");
    }
  }

  static Future<Directory> getPublicVideoDirectory() async {
    if (Platform.isAndroid) {
      try {
        final moviesDir = Directory('/storage/emulated/0/Movies/LiChat');
        if (!await moviesDir.exists()) await moviesDir.create(recursive: true);
        return moviesDir;
      } catch (e) {
        debugPrint("Could not access /storage/emulated/0/Movies/LiChat: $e");
        try {
          final downloadDir = Directory('/storage/emulated/0/Download/LiChat');
          if (!await downloadDir.exists()) await downloadDir.create(recursive: true);
          return downloadDir;
        } catch (_) {}
      }
    }
    return getCategoryDirectory('Recordings');
  }

  static Future<File?> saveCallRecordingToPhone({
    required String remoteUrl,
    required String fileName,
    String? callId,
  }) async {
    try {
      final fullUrl = remoteUrl.startsWith('http') ? remoteUrl : '$_backendUrl$remoteUrl';
      final targetDir = await getPublicVideoDirectory();
      final targetFile = File('${targetDir.path}/$fileName');
      final client = http.Client();
      try {
        final streamedResponse = await client.send(http.Request('GET', Uri.parse(fullUrl)));
        if (streamedResponse.statusCode == 200) {
          final sink = targetFile.openWrite();
          await streamedResponse.stream.pipe(sink);
          await sink.close();
        } else {
          final fallback = await downloadMediaToLocal(
            remoteUrl: fullUrl,
            category: 'Recordings',
            targetFileName: fileName,
          );
          if (fallback != null) {
            await CallSignalingService.purgeServerRecording(fileName: fileName, callId: callId);
            return fallback;
          }
          return null;
        }
      } finally {
        client.close();
      }
      try {
        final sandboxDir = await getCategoryDirectory('Recordings');
        final sandboxFile = File('${sandboxDir.path}/$fileName');
        if (sandboxFile.path != targetFile.path) await targetFile.copy(sandboxFile.path);
      } catch (_) {}
      await CallSignalingService.purgeServerRecording(fileName: fileName, callId: callId);
      debugPrint("Call recording saved to gallery folder: ${targetFile.path}");
      return targetFile;
    } catch (e) {
      debugPrint("Error saving call recording to phone: $e");
    }
    return null;
  }
}
