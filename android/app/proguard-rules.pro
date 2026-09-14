# AGP 8+ enables R8 minification by default for release builds even
# without an explicit `isMinifyEnabled = true`. That's what broke
# flutter_local_notifications on first launch after a release install:
# it uses Gson's TypeToken internally to persist scheduled notifications,
# and Gson's TypeToken throws at runtime if R8 strips the generic-type
# signature it needs (see the crash: "TypeToken must be created with a
# type argument ... make sure that generic signatures are preserved").
# These rules keep exactly what it needs.

# flutter_local_notifications' own models (scheduled notification data)
-keep class com.dexterous.** { *; }
-keep class * extends com.dexterous.flutterlocalnotifications.models.** { *; }
-dontwarn com.dexterous.**

# Gson (used internally by flutter_local_notifications for persistence) —
# generic signatures and annotations must survive shrinking for
# TypeToken-based (de)serialization to work.
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses
-keepattributes EnclosingMethod
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-dontwarn sun.misc.**
