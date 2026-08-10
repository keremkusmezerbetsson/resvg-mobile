# Keep UniFFI / JNA entry points
-keep class com.resvg.mobile.** { *; }
-keep class com.sun.jna.** { *; }
-keepclassmembers class * extends com.sun.jna.** { public *; }
