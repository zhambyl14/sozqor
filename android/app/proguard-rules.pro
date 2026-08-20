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

# Flutter's engine carries a Play Core deferred-components manager that this
# app never uses, so the Play Core library is not on the classpath — and R8
# refuses to finish a release build over the dangling references. The app
# ships as a single APK with no deferred components, so warning about them is
# noise; without this, `flutter build apk --release` fails outright at
# :app:minifyReleaseWithR8.
-dontwarn com.google.android.play.core.**
-keep class io.flutter.embedding.engine.deferredcomponents.** { *; }
