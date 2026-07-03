import AMapFoundationKit
import CoreLocation
import Flutter
import MAMapKit
import UIKit

public class AmapNativePlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "amap_native_plugin", binaryMessenger: registrar.messenger())
    let instance = AmapNativePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.register(
      AmapMapViewFactory(binaryMessenger: registrar.messenger()),
      withId: "amap_native_plugin/map_view"
    )
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "init":
      let args = call.arguments as? [String: Any]
      if let iosApiKey = args?["iosApiKey"] as? String, !iosApiKey.isEmpty {
        AMapServices.shared().apiKey = iosApiKey
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

final class AmapMapViewFactory: NSObject, FlutterPlatformViewFactory {
  private let binaryMessenger: FlutterBinaryMessenger

  init(binaryMessenger: FlutterBinaryMessenger) {
    self.binaryMessenger = binaryMessenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    return AmapPlatformMapView(
      frame: frame,
      viewIdentifier: viewId,
      binaryMessenger: binaryMessenger,
      arguments: args
    )
  }
}

final class AmapPlatformMapView: NSObject, FlutterPlatformView, MAMapViewDelegate {
  private let mapView: MAMapView
  private let channel: FlutterMethodChannel
  private var circleStyles: [ObjectIdentifier: CircleGeofenceStyle] = [:]
  private var circleOverlays: [MAMapCircle] = []

  init(
    frame: CGRect,
    viewIdentifier viewId: Int64,
    binaryMessenger: FlutterBinaryMessenger,
    arguments args: Any?
  ) {
    mapView = MAMapView(frame: frame)
    channel = FlutterMethodChannel(
      name: "amap_native_plugin/map_view_\(viewId)",
      binaryMessenger: binaryMessenger
    )
    super.init()
    mapView.delegate = self
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "updateCircleGeofences":
        let args = call.arguments as? [String: Any]
        self?.updateCircleGeofences(args?["circleGeofences"] as? [[String: Any]])
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    applyCreationParams(args as? [String: Any])
  }

  deinit {
    channel.setMethodCallHandler(nil)
  }

  func view() -> UIView {
    return mapView
  }

  private func applyCreationParams(_ params: [String: Any]?) {
    mapView.showsUserLocation = params?["showMyLocation"] as? Bool ?? false
    drawCircleGeofences(params?["circleGeofences"] as? [[String: Any]])

    guard
      let center = params?["initialCenter"] as? [String: Any],
      let latitude = center["latitude"] as? Double,
      let longitude = center["longitude"] as? Double
    else {
      return
    }

    mapView.centerCoordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    if let zoom = params?["initialZoom"] as? Double {
      mapView.zoomLevel = CGFloat(zoom)
    }
  }

  private func updateCircleGeofences(_ geofences: [[String: Any]]?) {
    if !circleOverlays.isEmpty {
      mapView.removeOverlays(circleOverlays)
      circleOverlays.removeAll()
    }
    circleStyles.removeAll()
    drawCircleGeofences(geofences)
  }

  private func drawCircleGeofences(_ geofences: [[String: Any]]?) {
    geofences?.forEach { geofence in
      guard
        let center = geofence["center"] as? [String: Any],
        let latitude = center["latitude"] as? Double,
        let longitude = center["longitude"] as? Double,
        let radius = geofence["radiusMeters"] as? Double
      else {
        return
      }

      let circle = MAMapCircle(
        center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
        radius: radius
      )
      circleStyles[ObjectIdentifier(circle)] = CircleGeofenceStyle(
        strokeColor: uiColor(from: geofence["strokeColor"], fallback: UIColor(red: 0.15, green: 0.39, blue: 0.92, alpha: 1)),
        fillColor: uiColor(from: geofence["fillColor"], fallback: UIColor(red: 0.15, green: 0.39, blue: 0.92, alpha: 0.2)),
        lineWidth: CGFloat((geofence["strokeWidth"] as? Double) ?? 2)
      )
      circleOverlays.append(circle)
      mapView.add(circle)
    }
  }

  func mapView(_ mapView: MAMapView!, rendererFor overlay: MAOverlay!) -> MAOverlayRenderer! {
    guard let circle = overlay as? MAMapCircle else {
      return nil
    }

    let renderer = MACircleRenderer(circle: circle)
    let style = circleStyles[ObjectIdentifier(circle)] ?? CircleGeofenceStyle(
      strokeColor: UIColor(red: 0.15, green: 0.39, blue: 0.92, alpha: 1),
      fillColor: UIColor(red: 0.15, green: 0.39, blue: 0.92, alpha: 0.2),
      lineWidth: 2
    )
    renderer?.strokeColor = style.strokeColor
    renderer?.fillColor = style.fillColor
    renderer?.lineWidth = style.lineWidth
    return renderer
  }

  func mapView(_ mapView: MAMapView!, regionWillChangeAnimated animated: Bool) {
    sendCameraEvent("cameraMove")
  }

  func mapView(_ mapView: MAMapView!, regionDidChangeAnimated animated: Bool) {
    sendCameraEvent("cameraIdle")
  }

  private func uiColor(from value: Any?, fallback: UIColor) -> UIColor {
    let argb: UInt32
    if let number = value as? NSNumber {
      argb = number.uint32Value
    } else if let intValue = value as? Int {
      argb = UInt32(bitPattern: Int32(intValue))
    } else {
      return fallback
    }

    return UIColor(
      red: CGFloat((argb >> 16) & 0xFF) / 255,
      green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255,
      alpha: CGFloat((argb >> 24) & 0xFF) / 255
    )
  }

  private func sendCameraEvent(_ method: String) {
    let center = mapView.centerCoordinate
    channel.invokeMethod(method, arguments: [
      "latitude": center.latitude,
      "longitude": center.longitude
    ])
  }
}

private struct CircleGeofenceStyle {
  let strokeColor: UIColor
  let fillColor: UIColor
  let lineWidth: CGFloat
}
