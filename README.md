# amap_native_plugin

A Flutter plugin for embedding native AMap map views on Android and iOS.

The plugin provides map display and native drawing overlays. It does not
implement geofence enter or exit business events.

## Features

- Display native AMap map views in Flutter.
- Configure initial map center and zoom.
- Draw one or more circle geofences by center point and radius, with a dashed border.
- Update circle geofence radius and center at runtime.
- Place native map pins by coordinate and react to map tap events.
- Draw and update native polylines with custom colors and widths.
- Listen for map camera movement and idle events.
- Overlay custom Flutter center pins for map-center selection flows.
- Optionally show the user's location after the host app handles permissions.

## Installation

Add the package to `pubspec.yaml`:

```yaml
dependencies:
  amap_native_plugin: ^0.1.0
```

## Initialization

Call `AmapNative.init` before creating map widgets.

```dart
await AmapNative.init(
  androidApiKey: 'your-android-key',
  iosApiKey: 'your-ios-key',
);
```

Android also requires the AMap privacy compliance state before SDK use. The
plugin defaults `androidPrivacyShown` and `androidPrivacyAgreed` to `true`; pass
explicit values if your consent flow needs tighter control.

## Basic Usage

```dart
const AmapMapView(
  height: 300,
  initialCenter: AmapLatLng(31.2304, 121.4737),
  initialZoom: 12,
);
```

## Circle Geofence

```dart
AmapMapView(
  height: 300,
  initialCenter: const AmapLatLng(31.2304, 121.4737),
  initialZoom: 13,
  circleGeofences: const [
    AmapCircleGeofence(
      center: AmapLatLng(31.2304, 121.4737),
      radiusMeters: 500,
      strokeColor: Color(0xFF2563EB),
      fillColor: Color(0x332563EB),
      strokeWidth: 4,
    ),
  ],
);
```

## Map-Center Geofence Selection

Use `centerPin`, `movingCenterPin`, and `onCameraIdle` to let users drag the map
and choose the geofence center from the screen center.

```dart
AmapMapView(
  initialCenter: center,
  initialZoom: 14,
  centerPin: const Icon(Icons.location_pin, color: Colors.blue, size: 44),
  movingCenterPin: const Icon(Icons.location_pin, color: Colors.orange, size: 44),
  onCameraIdle: (center) {
    // Update your geofence center with the final map center.
  },
  circleGeofences: [
    AmapCircleGeofence(center: center, radiusMeters: radiusMeters),
  ],
);
```

## Map Pin Placement

Use `pins` to show native map markers, and `onMapTap` to place or replace a pin
from user interaction.

```dart
AmapMapView(
  initialCenter: center,
  initialZoom: 14,
  pins: const [
    AmapMapPin(
      position: AmapLatLng(31.2304, 121.4737),
      title: 'Placed pin',
    ),
  ],
  onMapTap: (position) {
    // Update your pin state with the tapped coordinate.
  },
);
```

## Polyline Drawing

Use `polylines` to draw routes from coordinates. Updating the list updates the
native overlays without recreating the map view.

```dart
AmapMapView(
  initialCenter: const AmapLatLng(31.2304, 121.4737),
  initialZoom: 14,
  polylines: const [
    AmapMapPolyline(
      points: [
        AmapLatLng(31.2304, 121.4737),
        AmapLatLng(31.2320, 121.4760),
        AmapLatLng(31.2340, 121.4780),
      ],
      color: Color(0xFFFF5B00),
      width: 6,
    ),
  ],
);
```

## Platform Notes

### Android

The plugin depends on the AMap Android map SDK:

```kotlin
implementation("com.amap.api:3dmap:latest.integration")
```

If you do not pass the Android API key through `AmapNative.init`, configure
`com.amap.api.v2.apikey` in the host app's `AndroidManifest.xml` according to
the AMap documentation.

If you set `showMyLocation: true`, the host app must request runtime location
permissions before showing the map.

### iOS

The plugin depends on the AMap iOS map SDK through CocoaPods:

```ruby
s.dependency 'AMap3DMap'
```

If you set `showMyLocation: true`, configure the required location usage
description keys in the host app's `Info.plist` and request location permission
at runtime.

## Example

```sh
cd example
flutter run \
  --dart-define=AMAP_ANDROID_API_KEY=your-android-key \
  --dart-define=AMAP_IOS_API_KEY=your-ios-key
```
