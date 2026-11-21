package org.lifechangerstouch.lavie.messenger

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.RemoteInput
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

class ChatActionReceiver : BroadcastReceiver() {

    companion object {
        const val KEY_TEXT_REPLY = "key_text_reply"
        const val ACTION_DIRECT_REPLY = "org.lifechangerstouch.lavie.messenger.DIRECT_REPLY"
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return

        val results = RemoteInput.getResultsFromIntent(intent)
        val replyText = results?.getCharSequence(KEY_TEXT_REPLY)?.toString()?.trim()
        val chatId = intent.getStringExtra("chat_id") ?: intent.getStringExtra("chatId") ?: ""
        val senderId = intent.getStringExtra("sender_id") ?: intent.getStringExtra("senderId") ?: ""
        val receiverId = intent.getStringExtra("receiver_id") ?: intent.getStringExtra("receiverId") ?: ""
        val senderName = intent.getStringExtra("sender_name") ?: intent.getStringExtra("senderName") ?: "Contact"

        if (replyText.isNullOrEmpty() || chatId.isEmpty()) return

        // 1. Give immediate visual feedback by updating the notification
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        val repliedNotification = NotificationCompat.Builder(context, "messages_channel")
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(0xFF7C3AED.toInt())
            .setContentTitle(senderName)
            .setContentText("You: $replyText")
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setAutoCancel(true)
            .setTimeoutAfter(4000)
            .build()

        notificationManager?.notify(chatId.hashCode(), repliedNotification)

        // 2. Dispatch the reply payload to the backend server asynchronously
        thread {
            try {
                val url = URL("https://la-vie.lifechangerstouch.org/api/chat/reply")
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.setRequestProperty("Content-Type", "application/json")
                conn.connectTimeout = 8000
                conn.readTimeout = 8000
                conn.doOutput = true

                val payload = JSONObject().apply {
                    put("chat_id", chatId)
                    put("sender_id", receiverId) // The person replying is the receiver of the original message
                    put("sender_name", "Me")
                    put("receiver_id", senderId)
                    put("text", replyText)
                }

                conn.outputStream.use { os ->
                    os.write(payload.toString().toByteArray(Charsets.UTF_8))
                }

                val responseCode = conn.responseCode
                conn.disconnect()
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }
}
