# amap_native_plugin example

Demonstrates a map-center circle geofence editing flow.

The top half of the screen displays the native AMap view. Drag the map to move
the geofence center, then release to redraw the circle at the screen center. The
bottom half contains a slider for changing the geofence radius from 10m to
1500m.

Run with your AMap API keys:

```sh
flutter run \
  --dart-define=AMAP_ANDROID_API_KEY=your-android-key \
  --dart-define=AMAP_IOS_API_KEY=your-ios-key
```
