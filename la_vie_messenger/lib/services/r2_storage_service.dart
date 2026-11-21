import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:minio/minio.dart';
import 'package:path/path.dart' as p;

/// Cloudflare R2 object storage client for LiChat.
///
/// Provides zero-egress-fee file uploads and downloads to the `lichat-vault`
/// bucket. Uses the S3-compatible MinIO Dart SDK, so switching to AWS S3 or
/// any other S3-compatible provider is a single config change.
///
/// Configuration is read at runtime from compile-time constants injected via
/// `--dart-define` or a secrets manager. For local dev the values below are
/// read from environment variables via String.fromEnvironment.
class R2StorageService {
  // ── Cloudflare R2 Configuration ─────────────────────────────────────────
  static const String _accountId = String.fromEnvironment(
    'R2_ACCOUNT_ID',
    defaultValue: '2a0c8de07b3da2a968e54be4055611bd',
  );
  static const String _accessKeyId = String.fromEnvironment(
    'R2_ACCESS_KEY_ID',
    defaultValue: 'afecd3797a69a55623d8f302fd7cc617',
  );
  static const String _secretAccessKey = String.fromEnvironment(
    'R2_SECRET_ACCESS_KEY',
    defaultValue:
        '9fc3650c281cfe29ef6264ca06a16d044d0594c8d8f3bf3cde1afe145c0d8d28',
  );
  static const String _bucket = String.fromEnvironment(
    'R2_BUCKET_NAME',
    defaultValue: 'lichat-vault',
  );

  static Minio? _client;

  static Minio get _minio {
    if (_client != null) return _client!;
    _client = Minio(
      endPoint: '$_accountId.r2.cloudflarestorage.com',
      accessKey: _accessKeyId,
      secretKey: _secretAccessKey,
      useSSL: true,
      // R2 does not use path-style but Minio SDK uses virtual-host by default.
    );
    return _client!;
  }

  // ── Upload API ────────────────────────────────────────────────────────────

  /// Uploads a chat media file (image, audio, video, document) to R2.
  ///
  /// Returns the public or pre-signed URL of the uploaded object.
  /// [onProgress] fires with (bytesSent, totalBytes) on every chunk.
  static Future<String> uploadMedia({
    required File file,
    required String chatId,
    required String fileName,
    String? contentType,
    void Function(int sent, int total)? onProgress,
  }) async {
    final ext = p.extension(fileName).toLowerCase();
    final mime = contentType ?? _mimeFromExt(ext);
    final objectKey = 'media/$chatId/${DateTime.now().millisecondsSinceEpoch}_$fileName';

    final fileSize = await file.length();
    int bytesSent = 0;

    final stream = file.openRead().map((chunk) {
      bytesSent += chunk.length;
      onProgress?.call(bytesSent, fileSize);
      return Uint8List.fromList(chunk);
    });

    await _minio.putObject(
      _bucket,
      objectKey,
      stream,
      size: fileSize,
      metadata: {'content-type': mime},
    );

    debugPrint('[R2] Uploaded $objectKey ($fileSize bytes)');
    return _publicUrl(objectKey);
  }

  /// Uploads a profile photo to R2 under `profiles/{uid}.jpg`.
  static Future<String> uploadProfilePhoto({
    required File file,
    required String uid,
  }) async {
    const mime = 'image/jpeg';
    final objectKey = 'profiles/$uid.jpg';
    final fileSize = await file.length();

    await _minio.putObject(
      _bucket,
      objectKey,
      file.openRead().map((b) => Uint8List.fromList(b)),
      size: fileSize,
      metadata: {'content-type': mime},
    );

    debugPrint('[R2] Uploaded profile photo for $uid');
    return _publicUrl(objectKey);
  }

  /// Uploads a status (story) media file to R2 under `statuses/{uid}/`.
  /// Files under this prefix should have a 24-hour lifecycle rule applied
  /// in the Cloudflare R2 console.
  static Future<String> uploadStatus({
    required File file,
    required String uid,
    required String fileName,
    String? contentType,
  }) async {
    final mime = contentType ?? _mimeFromExt(p.extension(fileName).toLowerCase());
    final objectKey =
        'statuses/$uid/${DateTime.now().millisecondsSinceEpoch}_$fileName';
    final fileSize = await file.length();

    await _minio.putObject(
      _bucket,
      objectKey,
      file.openRead().map((b) => Uint8List.fromList(b)),
      size: fileSize,
      metadata: {'content-type': mime},
    );

    debugPrint('[R2] Uploaded status $objectKey');
    return _publicUrl(objectKey);
  }

  // ── Download API ──────────────────────────────────────────────────────────

  /// Downloads a file from R2 to a local [destinationPath].
  /// Returns the local file once complete.
  static Future<File> downloadFile({
    required String objectKey,
    required String destinationPath,
    void Function(int received, int total)? onProgress,
  }) async {
    final stream = await _minio.getObject(_bucket, objectKey);
    final file = File(destinationPath);
    final sink = file.openWrite();

    int received = 0;
    await for (final chunk in stream) {
      sink.add(chunk);
      received += chunk.length;
      onProgress?.call(received, received); // total not known upfront from stream
    }
    await sink.flush();
    await sink.close();

    debugPrint('[R2] Downloaded $objectKey to $destinationPath');
    return file;
  }

  // ── Delete API ────────────────────────────────────────────────────────────

  /// Deletes an object from R2 (e.g., expired status or deleted message media).
  static Future<void> deleteObject(String objectKey) async {
    try {
      await _minio.removeObject(_bucket, objectKey);
      debugPrint('[R2] Deleted $objectKey');
    } catch (e) {
      debugPrint('[R2] Delete error for $objectKey: $e');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Returns a publicly accessible URL for an R2 object.
  /// NOTE: Requires the bucket to have a public access domain configured in
  /// the Cloudflare R2 dashboard (Settings > Public Access > Custom Domain).
  /// Until then, pre-signed URLs via [presignedUrl] can be used.
  static String _publicUrl(String objectKey) {
    return 'https://$_accountId.r2.cloudflarestorage.com/$_bucket/$objectKey';
  }

  /// Generates a time-limited pre-signed URL (default 7 days) for private objects.
  static Future<String> presignedUrl(
    String objectKey, {
    Duration expiry = const Duration(days: 7),
  }) async {
    return await _minio.presignedGetObject(
      _bucket,
      objectKey,
      expires: expiry.inSeconds,
    );
  }

  static String _mimeFromExt(String ext) {
    switch (ext) {
      case '.mp4': return 'video/mp4';
      case '.mov': return 'video/quicktime';
      case '.webm': return 'video/webm';
      case '.mkv': return 'video/x-matroska';
      case '.3gp': return 'video/3gpp';
      case '.jpg':
      case '.jpeg': return 'image/jpeg';
      case '.png': return 'image/png';
      case '.webp': return 'image/webp';
      case '.gif': return 'image/gif';
      case '.mp3': return 'audio/mpeg';
      case '.m4a':
      case '.aac': return 'audio/x-m4a';
      case '.ogg': return 'audio/ogg';
      case '.wav': return 'audio/wav';
      case '.pdf': return 'application/pdf';
      default: return 'application/octet-stream';
    }
  }
}
