# Release builds shrink and minify, and `flutter analyze`/`flutter test`
# never touch Gradle — so a broken release config sits invisible until
# someone actually builds one. Run `flutter build apk --release` after any
# change to the Android side.

# flutter_local_notifications is reached reflectively when Android reopens
# the app from a tapped notification, and the scheduled-notification
# receiver is resolved by name at boot.
-keep class com.dexterous.** { *; }

# flutter_tts and record both reach their Android implementations through
# the plugin registrant.
-keep class com.tundralabs.fluttertts.** { *; }
-keep class com.llfbandit.record.** { *; }

# audioplayers, likewise, for the playback of a recorded attempt.
-keep class xyz.luan.audioplayers.** { *; }
