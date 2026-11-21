package org.lifechangerstouch.lavie.messenger

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.graphics.BitmapFactory
import android.net.Uri
import android.content.ContentResolver
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class CallNotificationService : FirebaseMessagingService() {

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        val data = remoteMessage.data
        val type = data["type"]

        if (type == "incoming_call") {
            handleIncomingCall(data)
        } else if (type == "chat_message") {
            handleChatMessage(data, remoteMessage.notification)
        }

        super.onMessageReceived(remoteMessage)
    }

    private fun handleIncomingCall(data: Map<String, String>) {
        val callId = data["call_id"] ?: data["callId"] ?: return
        val callerName = data["caller_name"] ?: data["callerName"] ?: "Contact"
        val callerAvatar = data["caller_avatar"] ?: data["callerAvatar"] ?: ""
        val isVideo = (data["is_video"] ?: data["isVideo"]) == "true"
        val roomName = data["room_name"] ?: data["roomName"] ?: "call_$callId"
        val isGroup = data["is_group"] == "true" || data["isGroup"] == "true"
        val groupName = data["group_name"] ?: data["groupName"] ?: ""
        val callTypeStr = if (isVideo) "Video" else "Voice"

        // 0. Immediate background ACK: Notify server/caller in ~300ms that recipient phone is awake & physically ringing!
        kotlin.concurrent.thread {
            try {
                val url = java.net.URL("https://la-vie.lifechangerstouch.org/api/call/ringing")
                val conn = url.openConnection() as java.net.HttpURLConnection
                conn.requestMethod = "POST"
                conn.setRequestProperty("Content-Type", "application/json")
                conn.connectTimeout = 4000
                conn.readTimeout = 4000
                conn.doOutput = true
                val json = """{"call_id":"$callId"}"""
                conn.outputStream.use { it.write(json.toByteArray()) }
                conn.responseCode
                conn.disconnect()
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        // 1. Wake up the screen even if locked
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
            @Suppress("DEPRECATION")
            val wakeLock = powerManager?.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                PowerManager.ACQUIRE_CAUSES_WAKEUP or
                PowerManager.ON_AFTER_RELEASE,
                "LiChat:IncomingCallWakeLock"
            )
            wakeLock?.acquire(35000)
        } catch (e: Exception) {
            e.printStackTrace()
        }

        val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        // 2. Open / Tap Notification Intent (Brings up incoming call UI)
        val openCallIntent = Intent(this, MainActivity::class.java).apply {
            action = "INCOMING_CALL"
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("type", "incoming_call")
            putExtra("action", "open")
            putExtra("call_id", callId)
            putExtra("callId", callId)
            putExtra("room_name", roomName)
            putExtra("roomName", roomName)
            putExtra("caller_name", callerName)
            putExtra("callerName", callerName)
            putExtra("caller_avatar", callerAvatar)
            putExtra("callerAvatar", callerAvatar)
            putExtra("is_video", isVideo.toString())
            putExtra("isVideo", isVideo.toString())
            putExtra("is_group", isGroup.toString())
            putExtra("group_name", groupName)
        }

        val openPendingIntent = PendingIntent.getActivity(
            this,
            callId.hashCode(),
            openCallIntent,
            pendingFlags
        )

        // 3. Answer Action Intent
        val answerIntent = Intent(this, MainActivity::class.java).apply {
            action = "ANSWER_CALL"
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("type", "incoming_call")
            putExtra("action", "answer")
            putExtra("call_id", callId)
            putExtra("callId", callId)
            putExtra("room_name", roomName)
            putExtra("roomName", roomName)
            putExtra("caller_name", callerName)
            putExtra("callerName", callerName)
            putExtra("caller_avatar", callerAvatar)
            putExtra("callerAvatar", callerAvatar)
            putExtra("is_video", isVideo.toString())
            putExtra("isVideo", isVideo.toString())
            putExtra("is_group", isGroup.toString())
            putExtra("group_name", groupName)
        }

        val answerPendingIntent = PendingIntent.getActivity(
            this,
            (callId + "_answer").hashCode(),
            answerIntent,
            pendingFlags
        )

        // 4. Decline Action Intent
        val declineIntent = Intent(this, CallActionReceiver::class.java).apply {
            action = "DECLINE_CALL"
            putExtra("call_id", callId)
            putExtra("callId", callId)
        }

        val declinePendingIntent = PendingIntent.getBroadcast(
            this,
            (callId + "_decline").hashCode(),
            declineIntent,
            pendingFlags
        )

        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        ensureCallChannelExists(notificationManager)

        val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        val titleText = if (isGroup && groupName.isNotEmpty()) "LiChat Group $callTypeStr Call 📞" else "LiChat Incoming $callTypeStr Call 📞"
        val contentText = if (isGroup && groupName.isNotEmpty()) "$callerName is inviting you to a group call ($groupName)" else "$callerName is calling you..."

        val notificationBuilder = NotificationCompat.Builder(this, "incoming_calls_channel_v2")
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(0xFF7C3AED.toInt())
            .setContentTitle(titleText)
            .setContentText(contentText)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .setOngoing(true)
            .setSound(soundUri)
            .setVibrate(longArrayOf(0, 1000, 500, 1000, 500, 1000))
            .setFullScreenIntent(openPendingIntent, true)
            .setContentIntent(openPendingIntent)
            .addAction(android.R.drawable.ic_menu_call, "Answer", answerPendingIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Decline", declinePendingIntent)

        val notification = notificationBuilder.build()
        // FLAG_INSISTENT loops the ringtone audio and vibration continuously until user interacts!
        notification.flags = notification.flags or
                Notification.FLAG_INSISTENT or
                Notification.FLAG_ONGOING_EVENT

        // notificationManager.notify call
        notificationManager.notify(callId.hashCode(), notification)

        // 5. Auto-cancel after 35 s — matches the caller-side timeout so the
        //    FLAG_INSISTENT ringtone loop stops even if the user never taps.
        Handler(Looper.getMainLooper()).postDelayed({
            notificationManager.cancel(callId.hashCode())
        }, 35_000L)

        // 6. Try to bring MainActivity directly to front if permitted
        try {
            startActivity(openCallIntent)
        } catch (e: Exception) {
            // Android 10+ background restriction will cleanly rely on fullScreenIntent
        }
    }

    private fun handleChatMessage(data: Map<String, String>, notification: RemoteMessage.Notification?) {
        val chatId = data["chat_id"] ?: data["chatId"] ?: ""
        val messageId = data["message_id"] ?: data["messageId"] ?: ""
        val senderId = data["sender_id"] ?: data["senderId"] ?: ""
        val receiverId = data["receiver_id"] ?: data["receiverId"] ?: ""
        val senderName = data["sender_name"] ?: data["senderName"] ?: notification?.title ?: "New Message"
        val senderAvatar = data["sender_avatar"] ?: data["senderAvatar"] ?: ""
        val text = data["text"] ?: notification?.body ?: "You have a new message"

        // Immediate background delivery receipt ACK (WhatsApp-style double tick)
        if (chatId.isNotEmpty()) {
            kotlin.concurrent.thread {
                try {
                    val url = java.net.URL("https://la-vie.lifechangerstouch.org/api/chat/delivered")
                    val conn = url.openConnection() as java.net.HttpURLConnection
                    conn.requestMethod = "POST"
                    conn.setRequestProperty("Content-Type", "application/json")
                    conn.connectTimeout = 4000
                    conn.readTimeout = 4000
                    conn.doOutput = true
                    val json = org.json.JSONObject().apply {
                        put("chat_id", chatId)
                        put("receiver_id", receiverId)
                        put("message_id", messageId)
                    }.toString()
                    conn.outputStream.use { it.write(json.toByteArray()) }
                    conn.responseCode
                    conn.disconnect()
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        }

        val clickIntent = Intent(this, MainActivity::class.java).apply {
            action = "OPEN_CHAT"
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("type", "chat_message")
            putExtra("chat_id", chatId)
            putExtra("chatId", chatId)
            putExtra("message_id", messageId)
            putExtra("messageId", messageId)
            putExtra("sender_id", senderId)
            putExtra("senderId", senderId)
            putExtra("receiver_id", receiverId)
            putExtra("receiverId", receiverId)
            putExtra("sender_name", senderName)
            putExtra("senderName", senderName)
            putExtra("sender_avatar", senderAvatar)
            putExtra("senderAvatar", senderAvatar)
        }

        val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            chatId.hashCode(),
            clickIntent,
            pendingFlags
        )

        // RemoteInput for direct inline reply from notification bar
        val remoteInput = androidx.core.app.RemoteInput.Builder(ChatActionReceiver.KEY_TEXT_REPLY)
            .setLabel("Reply to $senderName...")
            .build()

        val replyIntent = Intent(this, ChatActionReceiver::class.java).apply {
            action = ChatActionReceiver.ACTION_DIRECT_REPLY
            putExtra("chat_id", chatId)
            putExtra("chatId", chatId)
            putExtra("message_id", messageId)
            putExtra("messageId", messageId)
            putExtra("sender_id", senderId)
            putExtra("senderId", senderId)
            putExtra("receiver_id", receiverId)
            putExtra("receiverId", receiverId)
            putExtra("sender_name", senderName)
            putExtra("senderName", senderName)
        }

        val replyPendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val replyPendingIntent = PendingIntent.getBroadcast(
            this,
            (chatId + "_reply").hashCode(),
            replyIntent,
            replyPendingFlags
        )

        val replyAction = NotificationCompat.Action.Builder(
            android.R.drawable.ic_menu_send,
            "Reply",
            replyPendingIntent
        ).addRemoteInput(remoteInput).build()

        val largeIconBitmap = try {
            BitmapFactory.decodeResource(resources, R.mipmap.ic_launcher)
        } catch (_: Exception) {
            null
        }

        val notificationBuilder = NotificationCompat.Builder(this, "messages_channel_v2")
            .setSmallIcon(R.drawable.ic_notification)
            .apply {
                if (largeIconBitmap != null) {
                    setLargeIcon(largeIconBitmap)
                }
            }
            .setColor(0xFF7C3AED.toInt())
            .setContentTitle(senderName)
            .setContentText(text)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .addAction(replyAction)

        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        ensureMessageChannelExists(notificationManager)
        notificationManager.notify(chatId.hashCode(), notificationBuilder.build())
    }

    private fun ensureCallChannelExists(notificationManager: NotificationManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val existing = notificationManager.getNotificationChannel("incoming_calls_channel_v2")
            if (existing == null) {
                val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                val audioAttributes = AudioAttributes.Builder()
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION_SIGNALLING) // Overrides media volume and rings at telecom volume
                    .build()

                val callChannel = NotificationChannel(
                    "incoming_calls_channel_v2",
                    "Incoming Calls",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "High-priority incoming voice & video calls"
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 1000, 500, 1000, 500, 1000)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                    setSound(soundUri, audioAttributes)
                    setShowBadge(true)
                    setBypassDnd(true)   // ring even when Do Not Disturb is active
                }
                notificationManager.createNotificationChannel(callChannel)
            }
        }
    }

    private fun ensureMessageChannelExists(notificationManager: NotificationManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val existing = notificationManager.getNotificationChannel("messages_channel_v2")
            if (existing == null) {
                val soundUri = Uri.parse(ContentResolver.SCHEME_ANDROID_RESOURCE + "://" + packageName + "/" + R.raw.message_received)
                val audioAttributes = AudioAttributes.Builder()
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_COMMUNICATION_INSTANT)
                    .build()

                val messageChannel = NotificationChannel(
                    "messages_channel_v2",
                    "Messages",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Notifications for new chat messages"
                    enableVibration(true)
                    lockscreenVisibility = Notification.VISIBILITY_PRIVATE
                    setSound(soundUri, audioAttributes)
                }
                notificationManager.createNotificationChannel(messageChannel)
            }
        }
    }
}

