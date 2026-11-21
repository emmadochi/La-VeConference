package org.lifechangerstouch.lavie.messenger

import android.app.KeyguardManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.os.Vibrator
import android.os.VibratorManager
import android.os.VibrationEffect
import android.view.WindowManager
import java.io.File
import java.io.FileOutputStream
import android.net.Uri
import android.provider.OpenableColumns
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingCallData: Map<String, Any?>? = null
    private var pendingChatData: Map<String, Any?>? = null
    private var pendingContactData: Map<String, Any?>? = null
    private var pendingShareData: Map<String, Any?>? = null
    private var pendingReturnToCall: Boolean = false
    private var methodChannel: MethodChannel? = null
    private val ONGOING_CALL_ID = 88888

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        wakeAndUnlock()
        createNotificationChannels()
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        wakeAndUnlock()
        handleIntent(intent)
    }

    private fun wakeAndUnlock() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
            keyguardManager?.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val type = intent.getStringExtra("type")
        val intentAction = intent.action

        if (intentAction == "END_CALL" || type == "end_call") {
            hideOngoingCallNotification()
            methodChannel?.invokeMethod("onEndCallAction", null)
            return
        } else if (intentAction == "RETURN_TO_CALL" || type == "return_to_call") {
            if (methodChannel != null) {
                methodChannel?.invokeMethod("onReturnToCall", null)
            } else {
                pendingReturnToCall = true
            }
            return
        }

        if (type == "incoming_call" || intentAction == "INCOMING_CALL" || intentAction == "ANSWER_CALL") {
            val callId = intent.getStringExtra("call_id") ?: intent.getStringExtra("callId") ?: return
            val roomName = intent.getStringExtra("room_name") ?: intent.getStringExtra("roomName") ?: "call_$callId"
            val callerName = intent.getStringExtra("caller_name") ?: intent.getStringExtra("callerName") ?: "Contact"
            val callerAvatar = intent.getStringExtra("caller_avatar") ?: intent.getStringExtra("callerAvatar")
            val isVideo = intent.getStringExtra("is_video") ?: intent.getStringExtra("isVideo") ?: "false"
            val isGroup = intent.getStringExtra("is_group") ?: intent.getStringExtra("isGroup") ?: "false"
            val groupName = intent.getStringExtra("group_name") ?: intent.getStringExtra("groupName") ?: ""
            val action = intent.getStringExtra("action") ?: if (intentAction == "ANSWER_CALL") "answer" else "open"

            // Dismiss the notification immediately since MainActivity is now in foreground
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            notificationManager?.cancel(callId.hashCode())

            val map = mapOf(
                "type" to "incoming_call",
                "action" to action,
                "call_id" to callId,
                "callId" to callId,
                "room_name" to roomName,
                "roomName" to roomName,
                "caller_name" to callerName,
                "callerName" to callerName,
                "caller_avatar" to callerAvatar,
                "callerAvatar" to callerAvatar,
                "is_video" to isVideo,
                "isVideo" to isVideo,
                "is_group" to isGroup,
                "group_name" to groupName
            )

            if (methodChannel != null) {
                methodChannel?.invokeMethod("onIncomingCall", map)
            } else {
                pendingCallData = map
            }
        } else if (type == "chat" || type == "chat_message" || intentAction == "OPEN_CHAT") {
            val chatId = intent.getStringExtra("chat_id") ?: intent.getStringExtra("chatId") ?: ""
            val senderId = intent.getStringExtra("sender_id") ?: intent.getStringExtra("senderId") ?: ""
            val senderName = intent.getStringExtra("sender_name") ?: intent.getStringExtra("senderName") ?: "Contact"
            val senderAvatar = intent.getStringExtra("sender_avatar") ?: intent.getStringExtra("senderAvatar") ?: ""

            // Dismiss the chat notification
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            if (chatId.isNotEmpty()) {
                notificationManager?.cancel(chatId.hashCode())
            }

            val map = mapOf(
                "type" to "chat",
                "chat_id" to chatId,
                "chatId" to chatId,
                "sender_id" to senderId,
                "senderId" to senderId,
                "sender_name" to senderName,
                "senderName" to senderName,
                "sender_avatar" to senderAvatar,
                "senderAvatar" to senderAvatar
            )

            if (methodChannel != null) {
                methodChannel?.invokeMethod("onOpenChat", map)
            } else {
                pendingChatData = map
            }
        }

        // Handle Deep Linking (e.g. lichat://connect?uid=... or https://la-vie.lifechangerstouch.org/connect?uid=...)
        val dataUri = intent.data
        if (dataUri != null) {
            val scheme = dataUri.scheme
            val host = dataUri.host
            val path = dataUri.path
            if (scheme == "lichat" || (host == "la-vie.lifechangerstouch.org" && (path?.startsWith("/connect") == true || path?.startsWith("/lichat") == true))) {
                val peerUid = dataUri.getQueryParameter("uid") ?: ""
                val peerName = dataUri.getQueryParameter("name") ?: "Contact"
                val peerAvatar = dataUri.getQueryParameter("avatar") ?: ""
                if (peerUid.isNotEmpty()) {
                    val map = mapOf(
                        "type" to "pair_contact",
                        "peerUid" to peerUid,
                        "peerName" to peerName,
                        "peerAvatar" to peerAvatar
                    )
                    if (methodChannel != null) {
                        methodChannel?.invokeMethod("onPairContact", map)
                    } else {
                        pendingContactData = map
                    }
                }
            }
        }

        // Handle Incoming Share from Other Apps (ACTION_SEND & ACTION_SEND_MULTIPLE)
        if (intentAction == Intent.ACTION_SEND || intentAction == Intent.ACTION_SEND_MULTIPLE) {
            val mimeType = intent.type ?: "*/*"
            val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT) ?: intent.getStringExtra(Intent.EXTRA_TITLE)
            val filesList = mutableListOf<String>()

            if (intentAction == Intent.ACTION_SEND) {
                val streamUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                }
                if (streamUri != null) {
                    val cachedPath = copyUriToCache(streamUri)
                    if (cachedPath != null) {
                        filesList.add(cachedPath)
                    }
                }
            } else if (intentAction == Intent.ACTION_SEND_MULTIPLE) {
                val streamUris = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                }
                streamUris?.forEach { uri ->
                    val cachedPath = copyUriToCache(uri)
                    if (cachedPath != null) {
                        filesList.add(cachedPath)
                    }
                }
            }

            if (filesList.isNotEmpty() || !sharedText.isNullOrEmpty()) {
                val map = mapOf(
                    "type" to "incoming_share",
                    "mimeType" to mimeType,
                    "text" to (sharedText ?: ""),
                    "files" to filesList
                )
                if (methodChannel != null) {
                    methodChannel?.invokeMethod("onReceiveShare", map)
                } else {
                    pendingShareData = map
                }
            }
            return
        }
    }

    private fun copyUriToCache(uri: Uri): String? {
        return try {
            val contentResolver = applicationContext.contentResolver
            var fileName = "share_${System.currentTimeMillis()}"
            val cursor = contentResolver.query(uri, null, null, null, null)
            cursor?.use {
                if (it.moveToFirst()) {
                    val nameIndex = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (nameIndex >= 0) {
                        val name = it.getString(nameIndex)
                        if (!name.isNullOrEmpty()) {
                            fileName = name
                        }
                    }
                }
            }

            val cacheFolder = File(applicationContext.cacheDir, "incoming_shares")
            if (!cacheFolder.exists()) {
                cacheFolder.mkdirs()
            }

            val safeFileName = "${System.currentTimeMillis()}_${fileName.replace("[^a-zA-Z0-9._-]".toRegex(), "_")}"
            val destFile = File(cacheFolder, safeFileName)

            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(destFile).use { output ->
                    input.copyTo(output)
                }
            }

            destFile.absolutePath
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: android.content.res.Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        if (!isInPictureInPictureMode) {
            // User expanded or tapped PiP window to return to full app: restore ActiveCallScreen immediately!
            methodChannel?.invokeMethod("onReturnToCall", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "org.lifechangerstouch.lavie.messenger/call_overlay")
        methodChannel?.setMethodCallHandler { call, result ->
            try {
                if (call.method == "getInitialCall") {
                    result.success(pendingCallData)
                    pendingCallData = null
                } else if (call.method == "getInitialChat") {
                    result.success(pendingChatData)
                    pendingChatData = null
                } else if (call.method == "getInitialContact") {
                    result.success(pendingContactData)
                    pendingContactData = null
                } else if (call.method == "getInitialShare") {
                    result.success(pendingShareData)
                    pendingShareData = null
                } else if (call.method == "showOngoingCall") {
                    val callId = call.argument<String>("callId") ?: ""
                    val peerName = call.argument<String>("peerName") ?: "User"
                    val isVideo = call.argument<Boolean>("isVideo") ?: false
                    showOngoingCallNotification(callId, peerName, isVideo)
                    result.success(true)
                } else if (call.method == "hideOngoingCall") {
                    hideOngoingCallNotification()
                    ScreenShareService.stop(applicationContext)
                    result.success(true)
                } else if (call.method == "startScreenCaptureService") {
                    ScreenShareService.start(applicationContext)
                    result.success(true)
                } else if (call.method == "stopScreenCaptureService") {
                    ScreenShareService.stop(applicationContext)
                    result.success(true)
                } else if (call.method == "prepareVoipAudio") {
                    prepareVoipAudio()
                    result.success(true)
                } else if (call.method == "resetAudio") {
                    try {
                        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            audioManager?.clearCommunicationDevice()
                        }
                        @Suppress("DEPRECATION")
                        audioManager?.isSpeakerphoneOn = false
                        audioManager?.mode = AudioManager.MODE_NORMAL
                        @Suppress("DEPRECATION")
                        audioManager?.abandonAudioFocus(null)
                    } catch (_: Exception) {}
                    result.success(true)
                } else if (call.method == "setAudioOutput") {
                    val device = call.argument<String>("device") ?: "speaker"
                    setAudioDevice(device)
                    result.success(true)
                } else if (call.method == "startCallVibration") {
                    startCallVibration()
                    result.success(true)
                } else if (call.method == "stopCallVibration") {
                    stopCallVibration()
                    result.success(true)
                } else if (call.method == "vibrateFeedback") {
                    val ms = (call.argument<Number>("duration") ?: 40).toLong()
                    vibrateFeedback(ms)
                    result.success(true)
                } else if (call.method == "getAvailableAudioDevices") {
                    val devices = getAvailableAudioDevices()
                    result.success(devices)
                } else if (call.method == "enterPip") {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            val aspectRatio = android.util.Rational(9, 16)
                            val pipParams = android.app.PictureInPictureParams.Builder()
                                .setAspectRatio(aspectRatio)
                                .build()
                            val success = enterPictureInPictureMode(pipParams)
                            result.success(success)
                        } catch (e: Exception) {
                            try {
                                @Suppress("DEPRECATION")
                                val success = enterPictureInPictureMode()
                                result.success(success)
                            } catch (err: Exception) {
                                result.error("PIP_ERROR", err.message, null)
                            }
                        }
                    } else {
                        result.success(false)
                    }
                } else if (call.method == "isBatteryOptimizationIgnored") {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val pm = getSystemService(Context.POWER_SERVICE) as? android.os.PowerManager
                        val isIgnored = pm?.isIgnoringBatteryOptimizations(packageName) ?: false
                        result.success(isIgnored)
                    } else {
                        result.success(true)
                    }
                } else if (call.method == "requestIgnoreBatteryOptimization") {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        try {
                            val intent = Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            try {
                                val intent = Intent(android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                                startActivity(intent)
                                result.success(true)
                            } catch (err: Exception) {
                                result.success(false)
                            }
                        }
                    } else {
                        result.success(true)
                    }
                } else {
                    result.notImplemented()
                }
            } catch (e: Exception) {
                e.printStackTrace()
                result.error("ERROR", e.message, null)
            }
        }

        // If a call, chat or contact intent arrived before the Flutter engine was attached, deliver it immediately
        pendingCallData?.let {
            methodChannel?.invokeMethod("onIncomingCall", it)
            pendingCallData = null
        }
        pendingChatData?.let {
            methodChannel?.invokeMethod("onOpenChat", it)
            pendingChatData = null
        }
        pendingContactData?.let {
            methodChannel?.invokeMethod("onPairContact", it)
            pendingContactData = null
        }
        pendingShareData?.let {
            methodChannel?.invokeMethod("onReceiveShare", it)
            pendingShareData = null
        }
        if (pendingReturnToCall) {
            methodChannel?.invokeMethod("onReturnToCall", null)
            pendingReturnToCall = false
        }
    }

    private fun showOngoingCallNotification(callId: String, peerName: String, isVideo: Boolean) {
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return

            val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }

            val openIntent = Intent(this, MainActivity::class.java).apply {
                action = "RETURN_TO_CALL"
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("type", "return_to_call")
                putExtra("call_id", callId)
            }
            val openPendingIntent = PendingIntent.getActivity(this, 1001, openIntent, pendingFlags)

            val endIntent = Intent(this, MainActivity::class.java).apply {
                action = "END_CALL"
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("type", "end_call")
                putExtra("call_id", callId)
            }
            val endPendingIntent = PendingIntent.getActivity(this, 1002, endIntent, pendingFlags)

            val callTypeStr = if (isVideo) "Video" else "Voice"
            val notification = NotificationCompat.Builder(this, "ongoing_calls_channel")
                .setSmallIcon(R.drawable.ic_notification)
                .setColor(0xFF7C3AED.toInt())
                .setContentTitle("LiChat $callTypeStr Call Ongoing")
                .setContentText("Connected with $peerName")
                .setOngoing(true)
                .setAutoCancel(false)
                .setUsesChronometer(true)
                .setContentIntent(openPendingIntent)
                .addAction(android.R.drawable.ic_menu_close_clear_cancel, "End Call", endPendingIntent)
                .addAction(android.R.drawable.ic_menu_call, "Return to Call", openPendingIntent)
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .build()
                .also { it.flags = it.flags or android.app.Notification.FLAG_NO_CLEAR }

            notificationManager.notify(ONGOING_CALL_ID, notification)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun hideOngoingCallNotification() {
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
            notificationManager.cancel(ONGOING_CALL_ID)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun prepareVoipAudio() {
        try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
            
            // 1. Release any residual media playback focus from ringtones
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(null)

            // 2. Request exclusive VoIP audio focus and set MODE_IN_COMMUNICATION
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val playbackAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
                val focusRequest = android.media.AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
                    .setAudioAttributes(playbackAttributes)
                    .setAcceptsDelayedFocusGain(false)
                    .setWillPauseWhenDucked(false)
                    .build()
                audioManager.requestAudioFocus(focusRequest)
            } else {
                @Suppress("DEPRECATION")
                audioManager.requestAudioFocus(
                    null,
                    AudioManager.STREAM_VOICE_CALL,
                    AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE
                )
            }

            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION

            // 3. Ensure healthy call volume so audio isn't muted or whisper quiet
            try {
                val currentVol = audioManager.getStreamVolume(AudioManager.STREAM_VOICE_CALL)
                val maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL)
                if (currentVol < (maxVol * 0.75).toInt()) {
                    audioManager.setStreamVolume(AudioManager.STREAM_VOICE_CALL, (maxVol * 0.85).toInt(), 0)
                }
            } catch (_: Exception) {}
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun setAudioDevice(device: String) {
        try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
            try {
                audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
            } catch (_: Exception) {}

            // Ensure voice call volume is healthy so audio is not whisper quiet
            try {
                val currentVol = audioManager.getStreamVolume(AudioManager.STREAM_VOICE_CALL)
                val maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL)
                if (currentVol < (maxVol * 0.75).toInt()) {
                    audioManager.setStreamVolume(AudioManager.STREAM_VOICE_CALL, (maxVol * 0.85).toInt(), 0)
                }
            } catch (_: Exception) {}

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                try {
                    val availableDevices = audioManager.availableCommunicationDevices
                    when (device) {
                        "speaker" -> {
                            audioManager.clearCommunicationDevice()
                            val targetDevice = availableDevices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                            if (targetDevice != null) {
                                audioManager.setCommunicationDevice(targetDevice)
                            }
                            @Suppress("DEPRECATION")
                            audioManager.isSpeakerphoneOn = true
                        }
                        "earpiece" -> {
                            audioManager.clearCommunicationDevice()
                            val targetDevice = availableDevices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE }
                            if (targetDevice != null) {
                                audioManager.setCommunicationDevice(targetDevice)
                            }
                            @Suppress("DEPRECATION")
                            audioManager.isSpeakerphoneOn = false
                        }
                        "bluetooth" -> {
                            audioManager.clearCommunicationDevice()
                            val targetDevice = availableDevices.firstOrNull { 
                                it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO || 
                                it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                                it.type == AudioDeviceInfo.TYPE_BLE_HEADSET ||
                                it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                                it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES
                            }
                            if (targetDevice != null) {
                                audioManager.setCommunicationDevice(targetDevice)
                            }
                            @Suppress("DEPRECATION")
                            audioManager.isSpeakerphoneOn = false
                        }
                        else -> {
                            audioManager.clearCommunicationDevice()
                            @Suppress("DEPRECATION")
                            audioManager.isSpeakerphoneOn = true
                        }
                    }
                } catch (err: Exception) {
                    @Suppress("DEPRECATION")
                    audioManager.isSpeakerphoneOn = (device == "speaker")
                }
            } else {
                @Suppress("DEPRECATION")
                when (device) {
                    "speaker" -> {
                        try { audioManager.stopBluetoothSco() } catch (_: Exception) {}
                        audioManager.isBluetoothScoOn = false
                        audioManager.isSpeakerphoneOn = true
                    }
                    "earpiece" -> {
                        try { audioManager.stopBluetoothSco() } catch (_: Exception) {}
                        audioManager.isBluetoothScoOn = false
                        audioManager.isSpeakerphoneOn = false
                    }
                    "bluetooth" -> {
                        audioManager.isSpeakerphoneOn = false
                        try { audioManager.startBluetoothSco() } catch (_: Exception) {}
                        audioManager.isBluetoothScoOn = true
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun startCallVibration() {
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vibratorManager?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }

            if (vibrator == null || !vibrator.hasVibrator()) return

            val timings = longArrayOf(0, 1000, 1000, 1000, 1000)
            val amplitudes = intArrayOf(0, 255, 0, 255, 0)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val effect = VibrationEffect.createWaveform(timings, amplitudes, 1)
                val audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                vibrator.vibrate(effect, audioAttributes)
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(timings, 1)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun stopCallVibration() {
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vibratorManager?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }
            vibrator?.cancel()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun vibrateFeedback(milliseconds: Long = 40L) {
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vibratorManager?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }

            if (vibrator == null || !vibrator.hasVibrator()) return

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createOneShot(milliseconds, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(milliseconds)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun getAvailableAudioDevices(): List<Map<String, Any>> {
        val list = mutableListOf<Map<String, Any>>()
        try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return list

            // Speaker is always available
            list.add(mapOf("type" to "speaker", "name" to "Loudspeaker", "available" to true))

            var hasEarpiece = true
            var hasBluetooth = false
            var bluetoothName = "Bluetooth Headset"

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val devices = audioManager.availableCommunicationDevices
                hasEarpiece = devices.any { it.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE }
                val btDevice = devices.firstOrNull {
                    it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                    it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                    it.type == AudioDeviceInfo.TYPE_BLE_HEADSET ||
                    it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                    it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES
                }
                if (btDevice != null) {
                    hasBluetooth = true
                    if (btDevice.productName.isNotEmpty()) {
                        bluetoothName = btDevice.productName.toString()
                    }
                }
            } else {
                @Suppress("DEPRECATION")
                val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                hasEarpiece = devices.any { it.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE }
                val btDevice = devices.firstOrNull {
                    it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                    it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                    it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                    it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES
                }
                if (btDevice != null) {
                    hasBluetooth = true
                    if (btDevice.productName.isNotEmpty()) {
                        bluetoothName = btDevice.productName.toString()
                    }
                }
            }

            if (hasEarpiece) {
                list.add(mapOf("type" to "earpiece", "name" to "Phone Earpiece", "available" to true))
            }
            if (hasBluetooth) {
                list.add(mapOf("type" to "bluetooth", "name" to bluetoothName, "available" to true))
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return list
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // Clean up legacy channel if present
            try {
                notificationManager.deleteNotificationChannel("incoming_calls_channel")
            } catch (ignored: Exception) {}

            // 1. Incoming Calls Channel (Urgent, Heads-up, Ringtone, Vibration, bypass DND, Voice Signaling)
            val callChannel = NotificationChannel(
                "incoming_calls_channel_v2",
                "Incoming Calls",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Urgent notifications for incoming voice & video calls"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 1000, 500, 1000, 500, 1000)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                setBypassDnd(true)   // ring even when Do Not Disturb is active
                setShowBadge(true)
                val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                val audioAttributes = AudioAttributes.Builder()
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION_SIGNALLING)
                    .build()
                setSound(soundUri, audioAttributes)
            }

            // 2. Messages Channel (High Importance, Custom Sound, Vibration)
            try {
                notificationManager.deleteNotificationChannel("messages_channel")
            } catch (ignored: Exception) {}

            val msgSoundUri = Uri.parse(android.content.ContentResolver.SCHEME_ANDROID_RESOURCE + "://" + packageName + "/" + R.raw.message_received)
            val msgAudioAttributes = AudioAttributes.Builder()
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
                lockscreenVisibility = android.app.Notification.VISIBILITY_PRIVATE
                setSound(msgSoundUri, msgAudioAttributes)
            }

            // 3. Ongoing Calls Channel (Persistent, Default Importance — must be visible in drawer)
            val ongoingCallChannel = NotificationChannel(
                "ongoing_calls_channel",
                "Ongoing Calls",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Shows ongoing call indicator and quick controls in the notification drawer"
                setShowBadge(false)
                setSound(null, null) // No sound for ongoing — it's a status indicator
                enableVibration(false)
            }

            notificationManager.createNotificationChannel(callChannel)
            notificationManager.createNotificationChannel(messageChannel)
            notificationManager.createNotificationChannel(ongoingCallChannel)
        }
    }
}
