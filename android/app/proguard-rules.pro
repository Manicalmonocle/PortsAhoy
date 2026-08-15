# Flutter's engine entry points are reached reflectively.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Flutter ships hooks for Play Store deferred components. This game does not
# use them and does not depend on the Play Core library, so R8 sees dangling
# references. Silencing them is the documented fix, not a workaround.
-dontwarn com.google.android.play.core.**
