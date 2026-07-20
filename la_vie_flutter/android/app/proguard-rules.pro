# WebRTC / LiveKit
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**
-keep class livekit.** { *; }
-dontwarn livekit.**

# Firebase
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Cloud Firestore
-keep class com.google.firebase.firestore.** { *; }
-dontwarn com.google.firebase.firestore.**

# General rule to prevent R8 from obfuscating native methods
-keepclasseswithmembernames class * {
    native <methods>;
}
