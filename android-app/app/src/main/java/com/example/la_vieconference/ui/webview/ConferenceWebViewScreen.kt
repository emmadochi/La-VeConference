package com.example.la_vieconference.ui.webview

import android.Manifest
import android.annotation.SuppressLint
import android.webkit.JavascriptInterface
import android.webkit.PermissionRequest
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun ConferenceWebViewScreen(
    url: String,
    onBack: () -> Unit,
    onCallEnded: (() -> Unit)? = null, // PHASE C: callback for JS bridge call-end signal
    modifier: Modifier = Modifier
) {
    // Request camera and microphone permissions at runtime
    val permissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestMultiplePermissions()
    ) { _ -> }

    LaunchedEffect(Unit) {
        permissionLauncher.launch(
            arrayOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO)
        )
    }

    var webViewInstance by remember { mutableStateOf<WebView?>(null) }

    // Intercept hardware back button to navigate inside WebView history
    BackHandler(enabled = true) {
        if (webViewInstance?.canGoBack() == true) {
            webViewInstance?.goBack()
        } else {
            onBack()
        }
    }

    AndroidView(
        factory = { context ->
            WebView(context).apply {
                webViewInstance = this

                // PHASE C: Enable hardware acceleration for GPU-accelerated rendering.
                // This is critical for WebRTC video compositing performance.
                setLayerType(WebView.LAYER_TYPE_HARDWARE, null)

                // Configure WebView settings for full WebRTC and local storage capabilities
                settings.apply {
                    javaScriptEnabled = true
                    domStorageEnabled = true
                    databaseEnabled = true
                    allowFileAccess = true
                    mediaPlaybackRequiresUserGesture = false
                    setSupportMultipleWindows(false) // PHASE C: reduce overhead
                }

                // PHASE C: JavaScript bridge so the web app can signal native Android
                // when the user has left the call, enabling proper Compose navigation.
                class NativeBridge {
                    @JavascriptInterface
                    fun onCallEnded() {
                        // Post to main thread since JS bridge runs on a background thread
                        post { onCallEnded?.invoke() }
                    }
                }
                addJavascriptInterface(NativeBridge(), "AndroidBridge")

                webViewClient = object : WebViewClient() {
                    override fun shouldOverrideUrlLoading(view: WebView?, url: String?): Boolean {
                        return false
                    }

                    override fun onPageFinished(view: WebView?, url: String?) {
                        super.onPageFinished(view, url)
                        // Mark the app as native so the web client can adapt its UI
                        view?.evaluateJavascript("document.body.classList.add('is-native-app');", null)
                    }
                }

                webChromeClient = object : WebChromeClient() {
                    override fun onPermissionRequest(request: PermissionRequest) {
                        // Grant camera and microphone permissions requested by the web app
                        request.grant(request.resources)
                    }
                }

                loadUrl(url)
            }
        },
        update = { webView ->
            webViewInstance = webView
        },
        modifier = modifier.fillMaxSize()
    )
}
