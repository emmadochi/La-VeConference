package org.lifechangerstouch.lavie.messenger

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

class CallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return

        val callId = intent.getStringExtra("call_id") ?: intent.getStringExtra("callId")

        // 1. Cancel the ringing notification immediately
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        if (callId != null) {
            notificationManager?.cancel(callId.hashCode())
        }

        // 2. Dispatch decline update to server
        if (callId != null && callId.isNotEmpty()) {
            thread {
                try {
                    val url = URL("https://la-vie.lifechangerstouch.org/api/call/decline")
                    val conn = url.openConnection() as HttpURLConnection
                    conn.requestMethod = "POST"
                    conn.setRequestProperty("Content-Type", "application/json")
                    conn.connectTimeout = 5000
                    conn.readTimeout = 5000
                    conn.doOutput = true
                    val json = """{"call_id":"$callId"}"""
                    conn.outputStream.use { it.write(json.toByteArray()) }
                    conn.responseCode
                    conn.disconnect()
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        }
    }
}
