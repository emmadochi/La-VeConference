"""
Media and Upload Configuration Module for La-Vie Conference & Messaging Platform.

Defines upload guards, file size limits, accepted MIME types, storage retention policies (TTL),
and per-user disk quotas.
"""

import os

# WhatsApp-style storage: chat media is a TEMPORARY RELAY on the server.
# Files are auto-purged after MEDIA_TTL_DAYS (default: 30 days).
# Devices are expected to save media locally upon receipt.
# Profile photos are permanent and are NOT subject to TTL purge.
MEDIA_TTL_DAYS = int(os.getenv("MEDIA_TTL_DAYS", "30"))

# LiveKit recording files are also temporary — purged after RECORDINGS_TTL_DAYS.
RECORDINGS_TTL_DAYS = int(os.getenv("RECORDINGS_TTL_DAYS", "7"))

# ── Upload guards ─────────────────────────────────────────────────────────────
# Maximum allowed file size for any upload (default 100 MB).
MAX_UPLOAD_MB = int(os.getenv("MAX_UPLOAD_MB", "100"))
MAX_UPLOAD_BYTES = MAX_UPLOAD_MB * 1024 * 1024

# MIME types accepted for chat media uploads.
ALLOWED_CHAT_MIME = {
    # Images
    "image/jpeg", "image/png", "image/gif", "image/webp", "image/heic", "image/heif", "image/svg+xml",
    # Video
    "video/mp4", "video/quicktime", "video/x-matroska", "video/webm", "video/3gpp", "video/3gp", "video/avi", "video/mpeg",
    # Audio
    "audio/mpeg", "audio/ogg", "audio/wav", "audio/aac", "audio/mp4", "audio/webm",
    "audio/x-m4a", "audio/m4a",
    # Documents & Office
    "application/pdf",
    "application/msword",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/vnd.ms-excel",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "application/vnd.ms-powerpoint",
    "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    "text/plain", "text/csv", "application/rtf", "application/json", "application/xml",
    # Archives & Packages
    "application/zip", "application/x-zip-compressed",
    "application/x-rar-compressed", "application/vnd.rar",
    "application/x-7z-compressed", "application/x-tar", "application/gzip",
    "application/vnd.android.package-archive",
    # Fallback binary stream (validated with filename extension)
    "application/octet-stream",
}

# Profile photos: only images allowed.
ALLOWED_PROFILE_MIME = {
    "image/jpeg", "image/png", "image/gif", "image/webp", "image/heic", "image/heif",
}
# ─────────────────────────────────────────────────────────────────────────────

# ── Per-user quota & disk guard ───────────────────────────────────────────────
# Max total bytes a single user can have in uploads/media/ (default 1000 MB / 1 GB).
USER_QUOTA_MB = int(os.getenv("USER_QUOTA_MB", "1000"))
USER_QUOTA_BYTES = USER_QUOTA_MB * 1024 * 1024

# Minimum free disk space required before accepting any upload (default 500 MB).
MIN_FREE_DISK_MB = int(os.getenv("MIN_FREE_DISK_MB", "500"))
MIN_FREE_DISK_BYTES = MIN_FREE_DISK_MB * 1024 * 1024
# ─────────────────────────────────────────────────────────────────────────────
