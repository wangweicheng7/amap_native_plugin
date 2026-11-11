import CoreLocation
import Foundation
import Flutter
import MAMapKit
import UIKit

final class AmapPlatformMapView: NSObject, FlutterPlatformView, MAMapViewDelegate {
  private let mapView: MAMapView
  private lazy var overlays = AmapOverlayController(mapView)
  private lazy var snapshots = AmapSnapshotController(mapView)
  private var mapLoaded = false
  private let channel: FlutterMethodChannel
  private var disposed = false

  init(
    frame: CGRect,
    viewIdentifier viewId: Int64,
    binaryMessenger: FlutterBinaryMessenger,
    arguments args: Any?
  ) {
#if DEBUG
    let mapInitStartedAt = ProcessInfo.processInfo.systemUptime
#endif
    mapView = MAMapView(frame: frame)
#if DEBUG
    let mapInitDuration = (ProcessInfo.processInfo.systemUptime - mapInitStartedAt) * 1000
#endif
    channel = FlutterMethodChannel(
      name: "amap_native_plugin/map_view_\(viewId)",
      binaryMessenger: binaryMessenger
    )
    super.init()
#if DEBUG
    print(
      "[amap.performance] phase=map_view_constructor duration_ms=\(String(format: "%.1f", mapInitDuration)) main_thread=\(Thread.isMainThread)"
    )
#endif
    mapView.delegate = self
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "dispose" {
        self?.disposeMap()
        result(nil)
        return
      }
      guard self?.disposed == false else {
        result(FlutterError(code: "map_disposed", message: "Map view has already been disposed", details: nil))
        return
      }
      switch call.method {
      case "updateMyLocation":
        let args = call.arguments as? [String: Any]
        self?.mapView.showsUserLocation = args?["showMyLocation"] as? Bool ?? false
        result(nil)
      case "setVisible":
        let args = call.arguments as? [String: Any]
        let visible = args?["visible"] as? Bool ?? true
        self?.mapView.isHidden = !visible
        if !visible { self?.snapshots.cancelPending() }
        result(nil)
      case "updateCircleGeofences":
        let args = call.arguments as? [String: Any]
        self?.overlays.updateCircleGeofences(args?["circleGeofences"] as? [[String: Any]])
        result(nil)
      case "updatePins":
        let args = call.arguments as? [String: Any]
        self?.overlays.updatePins(args?["pins"] as? [[String: Any]])
        result(nil)
      case "updatePolylines":
        let args = call.arguments as? [String: Any]
        self?.overlays.updatePolylines(args?["polylines"] as? [[String: Any]])
        result(nil)
      case "updateMovingPins":
        let args = call.arguments as? [String: Any]
        self?.overlays.updateMovingPins(args?["updates"] as? [[String: Any]])
        result(nil)
      case "moveCamera":
        let args = call.arguments as? [String: Any]
        guard
          let center = args?["center"] as? [String: Any],
          let latitude = center["latitude"] as? Double,
          let longitude = center["longitude"] as? Double,
          let zoom = args?["zoom"] as? Double
        else {
          result(FlutterError(code: "invalid_arguments", message: "center and zoom are required", details: nil))
          return
        }
        self?.mapView.setCenter(
          CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
          animated: true
        )
        self?.mapView.setZoomLevel(CGFloat(zoom), animated: true)
        result(nil)
      case "zoomBy":
        let args = call.arguments as? [String: Any]
        guard let amount = args?["amount"] as? Double else {
          result(FlutterError(code: "invalid_arguments", message: "amount is required", details: nil))
          return
        }
        let targetZoom = (self?.mapView.zoomLevel ?? 15) + CGFloat(amount)
        self?.mapView.setZoomLevel(targetZoom, animated: true)
        result(nil)
      case "fitAllOverlays":
        let args = call.arguments as? [String: Any]
        self?.overlays.fitAllOverlays(padding: CGFloat((args?["padding"] as? Double) ?? 48))
        result(nil)
      case "takeSnapshot":
        guard let self else {
          result(FlutterError(code: "map_disposed", message: "Map view has already been disposed", details: nil))
          return
        }
        self.snapshots.capture(result: result, mapLoaded: self.mapLoaded)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
#if DEBUG
    let initialLayersStartedAt = ProcessInfo.processInfo.systemUptime
#endif
    applyCreationParams(args as? [String: Any])
#if DEBUG
    let initialLayersDuration = (ProcessInfo.processInfo.systemUptime - initialLayersStartedAt) * 1000
    print(
      "[amap.performance] phase=initial_layers duration_ms=\(String(format: "%.1f", initialLayersDuration)) main_thread=\(Thread.isMainThread)"
    )
#endif
  }

  deinit {
    disposeMap()
  }

  private func disposeMap() {
    guard !disposed else { return }
    disposed = true
    snapshots.dispose()
    channel.setMethodCallHandler(nil)
    mapView.delegate = nil
    mapView.showsUserLocation = false
    overlays.removeAllMapContent()
  }

  func view() -> UIView {
    return mapView
  }

  private func applyCreationParams(_ params: [String: Any]?) {
    overlays.removeAllMapContent()
    mapView.showsUserLocation = params?["showMyLocation"] as? Bool ?? false
    mapView.isHidden = !(params?["visible"] as? Bool ?? true)
    overlays.drawCircleGeofences(params?["circleGeofences"] as? [[String: Any]])
    overlays.drawPins(params?["pins"] as? [[String: Any]])
    overlays.drawPolylines(params?["polylines"] as? [[String: Any]])

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











  func mapView(_ mapView: MAMapView!, regionWillChangeAnimated animated: Bool) {
    sendCameraEvent("cameraMove")
  }

  func mapView(_ mapView: MAMapView!, regionDidChangeAnimated animated: Bool) {
    sendCameraEvent("cameraIdle")
  }

  func mapView(_ mapView: MAMapView!, didSingleTappedAt coordinate: CLLocationCoordinate2D) {
    channel.invokeMethod("mapTap", arguments: [
      "latitude": coordinate.latitude,
      "longitude": coordinate.longitude
    ])
  }

  func mapView(_ mapView: MAMapView!, rendererFor overlay: MAOverlay!) -> MAOverlayRenderer! {
    return overlays.renderer(for: overlay)
  }

  func mapView(_ mapView: MAMapView!, viewFor annotation: MAAnnotation!) -> MAAnnotationView! {
    return overlays.annotationView(for: annotation)
  }

  func mapViewDidFinishLoadingMap(_ mapView: MAMapView!) {
    mapLoaded = true
  }

  private func sendCameraEvent(_ method: String) {
    let center = mapView.centerCoordinate
    channel.invokeMethod(method, arguments: [
      "latitude": center.latitude,
      "longitude": center.longitude
    ])
  }
}
