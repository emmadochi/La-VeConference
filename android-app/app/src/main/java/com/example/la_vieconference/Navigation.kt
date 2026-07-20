package com.example.la_vieconference

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.navigation3.runtime.entryProvider
import androidx.navigation3.runtime.rememberNavBackStack
import androidx.navigation3.ui.NavDisplay
import com.example.la_vieconference.ui.webview.ConferenceWebViewScreen

@Composable
fun MainNavigation() {
  val backStack = rememberNavBackStack(ConferenceWebView("https://la-vie.lifechangerstouch.org"))

  NavDisplay(
    backStack = backStack,
    onBack = { backStack.removeLastOrNull() },
    entryProvider =
      entryProvider {
        entry<ConferenceWebView> { key ->
          ConferenceWebViewScreen(
            url = key.url,
            onBack = { backStack.removeLastOrNull() },
            modifier = Modifier.fillMaxSize()
          )
        }
      },
  )
}
