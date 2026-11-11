# The fixed AMap vendor bundle uses JNI and reflection to resolve classes and members by name.
# These consumer rules travel with the plugin so hosts retain the required native callbacks.
# Keep the vendor bundle's map, location and service internals even when only map APIs are exposed.

-keep class com.amap.api.maps.** { *; }
-keep class com.amap.api.trace.** { *; }
-keep class com.autonavi.** { *; }
-keep class com.amap.api.location.** { *; }
-keep class com.amap.api.fence.** { *; }
-keep class com.amap.location.** { *; }
-keep class com.loc.** { *; }
-keep class com.amap.api.services.** { *; }
-keep class com.amap.apis.** { *; }
-dontwarn com.amap.ams.gnss.GnssSoftLocator
-dontwarn net.jafama.FastMath
