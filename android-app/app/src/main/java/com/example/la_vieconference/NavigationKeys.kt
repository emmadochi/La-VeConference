package com.example.la_vieconference

import androidx.navigation3.runtime.NavKey
import kotlinx.serialization.Serializable

@Serializable data class ConferenceWebView(val url: String) : NavKey
