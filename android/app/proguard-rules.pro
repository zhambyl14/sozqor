# Flutter / plugin classes are looked up reflectively at runtime.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase Cloud Messaging
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# flutter_local_notifications keeps its receivers by name
-keep class com.dexterous.** { *; }
-dontwarn com.dexterous.**

# Text-to-speech
-keep class android.speech.tts.** { *; }
