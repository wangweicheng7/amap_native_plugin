import AMapFoundationKit
import AMapSearchKit
import CoreLocation
import Flutter
import MAMapKit
import UIKit

public class AmapNativePlugin: NSObject, FlutterPlugin {
  private var inputTipsSearches: [UUID: InputTipsSearch] = [:]

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
      AMapSearchAPI.updatePrivacyShow(.didShow, privacyInfo: .didContain)
      AMapSearchAPI.updatePrivacyAgree(.didAgree)
      result(nil)
    case "searchPlaces":
      let args = call.arguments as? [String: Any]
      searchPlaces(
        keyword: args?["keyword"] as? String ?? "",
        latitude: args?["latitude"] as? Double,
        longitude: args?["longitude"] as? Double,
        result: result
      )
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func searchPlaces(
    keyword: String,
    latitude: Double?,
    longitude: Double?,
    result: @escaping FlutterResult
  ) {
    let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count >= 2 else {
      result([])
      return
    }

    let id = UUID()
    let search = InputTipsSearch(
      keyword: trimmed,
      latitude: latitude,
      longitude: longitude
    ) { [weak self] response in
      result(response)
      self?.inputTipsSearches.removeValue(forKey: id)
    }
    inputTipsSearches[id] = search
    search.start()
  }
}

private final class InputTipsSearch: NSObject, AMapSearchDelegate {
  private let search: AMapSearchAPI?
  private let keyword: String
  private let latitude: Double?
  private let longitude: Double?
  private let completion: (Any) -> Void
  private var isCompleted = false

  init(
    keyword: String,
    latitude: Double?,
    longitude: Double?,
    completion: @escaping (Any) -> Void
  ) {
    self.keyword = keyword
    self.latitude = latitude
    self.longitude = longitude
    self.completion = completion
    search = AMapSearchAPI()
    super.init()
    search?.delegate = self
  }

  func start() {
    guard let search else {
      finish(FlutterError(
        code: "AMAP_SEARCH_UNAVAILABLE",
        message: "地点搜索服务初始化失败",
        details: nil
      ))
      return
    }
    let request = AMapInputTipsSearchRequest()
    request.keywords = keyword
    request.cityLimit = false
    if let latitude, let longitude {
      request.location = "\(longitude),\(latitude)"
    }
    search.aMapInputTipsSearch(request)
  }

  func onInputTipsSearchDone(
    _ request: AMapInputTipsSearchRequest!,
    response: AMapInputTipsSearchResponse!
  ) {
    let places = (response?.tips ?? []).compactMap { tip -> [String: Any]? in
      guard let location = tip.location else { return nil }
      return [
        "name": tip.name ?? "",
        "latitude": location.latitude,
        "longitude": location.longitude,
        "district": tip.district ?? "",
        "address": tip.address ?? "",
      ]
    }
    finish(places)
  }

  func aMapSearchRequest(_ request: Any!, didFailWithError error: Error!) {
    finish(FlutterError(
      code: "AMAP_SEARCH_FAILED",
      message: error.localizedDescription,
      details: nil
    ))
  }

  private func finish(_ response: Any) {
    guard !isCompleted else { return }
    isCompleted = true
    completion(response)
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
  private var circleOverlays: [MACircle] = []
  private var borderOverlays: [MAPolyline] = []
  private var borderStyles: [ObjectIdentifier: CircleGeofenceStyle] = [:]
  private var pinAnnotations: [MAPointAnnotation] = []
  private var pinStyles: [ObjectIdentifier: CustomPinStyle] = [:]
  private var routePolylines: [MAPolyline] = []
  private var routePolylineStyles: [ObjectIdentifier: PolylineStyle] = [:]

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
      case "updatePins":
        let args = call.arguments as? [String: Any]
        self?.updatePins(args?["pins"] as? [[String: Any]])
        result(nil)
      case "updatePolylines":
        let args = call.arguments as? [String: Any]
        self?.updatePolylines(args?["polylines"] as? [[String: Any]])
        result(nil)
      case "updateMovingPins":
        let args = call.arguments as? [String: Any]
        self?.updateMovingPins(args?["updates"] as? [[String: Any]])
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
      case "fitAllOverlays":
        let args = call.arguments as? [String: Any]
        self?.fitAllOverlays(padding: CGFloat((args?["padding"] as? Double) ?? 48))
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    applyCreationParams(args as? [String: Any])
  }

  private func fitAllOverlays(padding: CGFloat) {
    var visibleRect = MAMapRectNull

    for circle in circleOverlays {
      visibleRect = MAMapRectUnion(visibleRect, circle.boundingMapRect)
    }
    for polyline in routePolylines {
      visibleRect = MAMapRectUnion(visibleRect, polyline.boundingMapRect)
    }
    for annotation in pinAnnotations {
      let point = MAMapPointForCoordinate(annotation.coordinate)
      let pointRect = MAMapRectMake(point.x, point.y, 1, 1)
      visibleRect = MAMapRectUnion(visibleRect, pointRect)
    }

    guard !MAMapRectIsNull(visibleRect) else {
      return
    }
    mapView.setVisibleMapRect(
      visibleRect,
      edgePadding: UIEdgeInsets(top: padding, left: padding, bottom: padding, right: padding),
      animated: true
    )
  }

  deinit {
    channel.setMethodCallHandler(nil)
  }

  func view() -> UIView {
    return mapView
  }

  private func applyCreationParams(_ params: [String: Any]?) {
    removeAllMapContent()
    mapView.showsUserLocation = params?["showMyLocation"] as? Bool ?? false
    drawCircleGeofences(params?["circleGeofences"] as? [[String: Any]])
    drawPins(params?["pins"] as? [[String: Any]])
    drawPolylines(params?["polylines"] as? [[String: Any]])

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
    removeAllCircleGeofenceOverlays()
    drawCircleGeofences(geofences)
  }

  private func updatePins(_ pins: [[String: Any]]?) {
    removePinAnnotations()
    drawPins(pins)
  }

  private func updatePolylines(_ polylines: [[String: Any]]?) {
    removeRoutePolylines()
    drawPolylines(polylines)
  }

  private func updateMovingPins(_ updates: [[String: Any]]?) {
    updates?.forEach { update in
      guard
        let index = update["index"] as? Int,
        pinAnnotations.indices.contains(index),
        let position = update["position"] as? [String: Any],
        let latitude = position["latitude"] as? Double,
        let longitude = position["longitude"] as? Double
      else {
        return
      }
      pinAnnotations[index].coordinate = CLLocationCoordinate2D(
        latitude: latitude,
        longitude: longitude
      )
    }
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

      let strokeColor = uiColor(from: geofence["strokeColor"], fallback: UIColor(red: 0.15, green: 0.39, blue: 0.92, alpha: 1))
      let fillColor = uiColor(from: geofence["fillColor"], fallback: UIColor(red: 0.15, green: 0.39, blue: 0.92, alpha: 0.2))
      let lineWidth = CGFloat((geofence["strokeWidth"] as? Double) ?? 2)

      guard let circle = MACircle(
        center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
        radius: radius
      ) else {
        return
      }
      circleStyles[ObjectIdentifier(circle)] = CircleGeofenceStyle(
        strokeColor: strokeColor,
        fillColor: fillColor,
        lineWidth: lineWidth
      )
      circleOverlays.append(circle)
      mapView.add(circle)

      drawDashedCircleBorder(
        center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
        radius: radius,
        strokeColor: strokeColor,
        lineWidth: lineWidth
      )
    }
  }

  private func drawPins(_ pins: [[String: Any]]?) {
    pins?.forEach { pin in
      guard
        let position = pin["position"] as? [String: Any],
        let latitude = position["latitude"] as? Double,
        let longitude = position["longitude"] as? Double
      else {
        return
      }

      let annotation = MAPointAnnotation()
      annotation.coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
      annotation.title = pin["title"] as? String
      annotation.subtitle = pin["snippet"] as? String
      let label = (pin["label"] as? String).flatMap { $0.isEmpty ? nil : $0 }
      let byteImage = (pin["imageBytes"] as? FlutterStandardTypedData)
        .flatMap { UIImage(data: $0.data) }
      let assetImage = byteImage ?? (pin["imageAsset"] as? String).flatMap(loadFlutterAssetImage)
      if label != nil || assetImage != nil {
        let imageWidth = CGFloat((pin["imageWidth"] as? Double) ?? 44)
        let imageHeight = CGFloat((pin["imageHeight"] as? Double) ?? 44)
        pinStyles[ObjectIdentifier(annotation)] = CustomPinStyle(
          label: label,
          image: assetImage,
          pinSize: assetImage == nil ? CGSize(width: 32, height: 42) : CGSize(width: imageWidth, height: imageHeight),
          pinColor: uiColor(from: pin["pinColor"], fallback: UIColor(red: 0.97, green: 0.45, blue: 0.09, alpha: 1)),
          textColor: uiColor(from: pin["labelTextColor"], fallback: .white),
          backgroundColor: uiColor(from: pin["labelBackgroundColor"], fallback: UIColor(red: 0.18, green: 0.22, blue: 0.28, alpha: 0.9))
        )
      }
      pinAnnotations.append(annotation)
      mapView.addAnnotation(annotation)
    }
  }

  private func loadFlutterAssetImage(_ assetName: String) -> UIImage? {
    let assetKey = FlutterDartProject.lookupKey(forAsset: assetName)
    guard let path = Bundle.main.path(forResource: assetKey, ofType: nil) else {
      return nil
    }
    return UIImage(contentsOfFile: path)
  }

  private func drawPolylines(_ polylines: [[String: Any]]?) {
    polylines?.forEach { item in
      guard let rawPoints = item["points"] as? [[String: Any]] else {
        return
      }

      let coordinates = rawPoints.compactMap { point -> CLLocationCoordinate2D? in
        guard
          let latitude = point["latitude"] as? Double,
          let longitude = point["longitude"] as? Double
        else {
          return nil
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
      }
      guard coordinates.count >= 2 else {
        return
      }

      var mutableCoordinates = coordinates
      let polyline = mutableCoordinates.withUnsafeMutableBufferPointer { buffer in
        MAPolyline(coordinates: buffer.baseAddress!, count: UInt(buffer.count))!
      }
      routePolylineStyles[ObjectIdentifier(polyline)] = PolylineStyle(
        color: uiColor(
          from: item["color"],
          fallback: UIColor(red: 1, green: 0.36, blue: 0, alpha: 1)
        ),
        width: CGFloat((item["width"] as? Double) ?? 6)
      )
      routePolylines.append(polyline)
      mapView.add(polyline)
    }
  }

  func mapView(_ mapView: MAMapView!, rendererFor overlay: MAOverlay!) -> MAOverlayRenderer! {
    guard let circle = overlay as? MACircle else {
      if let polyline = overlay as? MAPolyline {
        let renderer = MAPolylineRenderer(polyline: polyline)
        if let routeStyle = routePolylineStyles[ObjectIdentifier(polyline)] {
          renderer?.strokeColor = routeStyle.color
          renderer?.lineWidth = routeStyle.width
        } else {
          let style = borderStyles[ObjectIdentifier(polyline)] ?? CircleGeofenceStyle(
            strokeColor: UIColor(red: 0.15, green: 0.39, blue: 0.92, alpha: 1),
            fillColor: UIColor.clear,
            lineWidth: 2
          )
          renderer?.strokeColor = style.strokeColor
          renderer?.lineWidth = style.lineWidth
        }
        return renderer
      }
      return nil
    }

    let renderer = MACircleRenderer(circle: circle)
    let style = circleStyles[ObjectIdentifier(circle)] ?? CircleGeofenceStyle(
      strokeColor: UIColor(red: 0.15, green: 0.39, blue: 0.92, alpha: 1),
      fillColor: UIColor(red: 0.15, green: 0.39, blue: 0.92, alpha: 0.2),
      lineWidth: 2
    )
    renderer?.strokeColor = .clear
    renderer?.fillColor = style.fillColor
    renderer?.lineWidth = 0
    return renderer
  }

  func mapView(_ mapView: MAMapView!, viewFor annotation: MAAnnotation!) -> MAAnnotationView! {
    if annotation is MAUserLocation {
      return nil
    }

    if let style = pinStyles[ObjectIdentifier(annotation as AnyObject)] {
      let reuseIdentifier = "amap_native_plugin_labeled_pin"
      var view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseIdentifier)
      if view == nil {
        view = MAAnnotationView(annotation: annotation, reuseIdentifier: reuseIdentifier)
      } else {
        view?.annotation = annotation
      }
      let image = customPinImage(style)
      view?.image = image
      view?.centerOffset = CGPoint(
        x: image.size.width / 2 - style.pinSize.width / 2,
        y: -image.size.height / 2
      )
      view?.canShowCallout = true
      return view
    }

    let reuseIdentifier = "amap_native_plugin_pin"
    var view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseIdentifier) as? MAPinAnnotationView
    if view == nil {
      view = MAPinAnnotationView(annotation: annotation, reuseIdentifier: reuseIdentifier)
    } else {
      view?.annotation = annotation
    }

    view?.animatesDrop = true
    view?.canShowCallout = true
    return view
  }

  private func customPinImage(_ style: CustomPinStyle) -> UIImage {
    let pinWidth = style.pinSize.width
    let pinHeight = style.pinSize.height
    let gap: CGFloat = 6
    let labelHeight: CGFloat = 32
    let horizontalPadding: CGFloat = 10
    let font = UIFont.boldSystemFont(ofSize: 14)
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: style.textColor
    ]
    let textSize = style.label.map { ($0 as NSString).size(withAttributes: attributes) } ?? .zero
    let labelWidth = style.label == nil ? 0 : ceil(textSize.width + horizontalPadding * 2)
    let size = CGSize(
      width: pinWidth + (style.label == nil ? 0 : gap + labelWidth),
      height: max(pinHeight, labelHeight)
    )

    return UIGraphicsImageRenderer(size: size).image { _ in
      if let pinImage = style.image {
        pinImage.draw(in: CGRect(origin: .zero, size: style.pinSize))
      } else {
        style.pinColor.setFill()
        let triangle = UIBezierPath()
        triangle.move(to: CGPoint(x: 8, y: 21))
        triangle.addLine(to: CGPoint(x: pinWidth / 2, y: pinHeight))
        triangle.addLine(to: CGPoint(x: 24, y: 21))
        triangle.close()
        triangle.fill()
        UIBezierPath(ovalIn: CGRect(x: 4, y: 2, width: 24, height: 24)).fill()
        UIColor.white.setFill()
        UIBezierPath(ovalIn: CGRect(x: 12, y: 10, width: 8, height: 8)).fill()
      }

      if let label = style.label {
        let labelRect = CGRect(
          x: pinWidth + gap,
          y: (size.height - labelHeight) / 2,
          width: labelWidth,
          height: labelHeight
        )
        style.backgroundColor.setFill()
        UIBezierPath(roundedRect: labelRect, cornerRadius: 8).fill()
        let textRect = CGRect(
          x: labelRect.minX + horizontalPadding,
          y: labelRect.midY - textSize.height / 2,
          width: textSize.width,
          height: textSize.height
        )
        (label as NSString).draw(in: textRect, withAttributes: attributes)
      }
    }
  }

  private func removeAllCircleGeofenceOverlays() {
    if !circleOverlays.isEmpty {
      mapView.removeOverlays(circleOverlays)
      circleOverlays.removeAll()
    }
    if !borderOverlays.isEmpty {
      mapView.removeOverlays(borderOverlays)
      borderOverlays.removeAll()
    }
    circleStyles.removeAll()
    borderStyles.removeAll()
  }

  private func removePinAnnotations() {
    if !pinAnnotations.isEmpty {
      mapView.removeAnnotations(pinAnnotations)
      pinAnnotations.removeAll()
    }
    pinStyles.removeAll()
  }

  private func removeRoutePolylines() {
    if !routePolylines.isEmpty {
      mapView.removeOverlays(routePolylines)
      routePolylines.removeAll()
    }
    routePolylineStyles.removeAll()
  }

  private func removeAllMapContent() {
    removeAllCircleGeofenceOverlays()
    removePinAnnotations()
    removeRoutePolylines()
  }

  private func drawDashedCircleBorder(
    center: CLLocationCoordinate2D,
    radius: Double,
    strokeColor: UIColor,
    lineWidth: CGFloat
  ) {
    let dashCount = 36
    let pointsPerDash = 5

    for index in stride(from: 0, to: dashCount, by: 2) {
      let startFraction = Double(index) / Double(dashCount)
      let endFraction = Double(index + 1) / Double(dashCount)
      var coordinates: [CLLocationCoordinate2D] = []
      coordinates.reserveCapacity(pointsPerDash + 1)

      for step in 0...pointsPerDash {
        let fraction = startFraction + (endFraction - startFraction) * (Double(step) / Double(pointsPerDash))
        let bearing = 360.0 * fraction
        coordinates.append(destinationCoordinate(from: center, radiusMeters: radius, bearingDegrees: bearing))
      }

      var mutableCoordinates = coordinates
      let polyline = mutableCoordinates.withUnsafeMutableBufferPointer { buffer in
        MAPolyline(coordinates: buffer.baseAddress!, count: UInt(buffer.count))!
      }
      borderStyles[ObjectIdentifier(polyline)] = CircleGeofenceStyle(
        strokeColor: strokeColor,
        fillColor: .clear,
        lineWidth: lineWidth
      )
      borderOverlays.append(polyline)
      mapView.add(polyline)
    }
  }

  private func destinationCoordinate(
    from center: CLLocationCoordinate2D,
    radiusMeters: Double,
    bearingDegrees: Double
  ) -> CLLocationCoordinate2D {
    let earthRadiusMeters = 6_378_137.0
    let angularDistance = radiusMeters / earthRadiusMeters
    let bearing = bearingDegrees * .pi / 180.0
    let latitude1 = center.latitude * .pi / 180.0
    let longitude1 = center.longitude * .pi / 180.0

    let sinLatitude1 = sin(latitude1)
    let cosLatitude1 = cos(latitude1)
    let sinAngularDistance = sin(angularDistance)
    let cosAngularDistance = cos(angularDistance)

    let latitude2 = asin(
      sinLatitude1 * cosAngularDistance +
        cosLatitude1 * sinAngularDistance * cos(bearing)
    )
    let longitude2 = longitude1 + atan2(
      sin(bearing) * sinAngularDistance * cosLatitude1,
      cosAngularDistance - sinLatitude1 * sin(latitude2)
    )

    return CLLocationCoordinate2D(
      latitude: latitude2 * 180.0 / .pi,
      longitude: normalizeLongitude(longitude2 * 180.0 / .pi)
    )
  }

  private func normalizeLongitude(_ longitude: Double) -> Double {
    var normalized = longitude
    while normalized < -180.0 {
      normalized += 360.0
    }
    while normalized > 180.0 {
      normalized -= 360.0
    }
    return normalized
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

private struct PolylineStyle {
  let color: UIColor
  let width: CGFloat
}

private struct CustomPinStyle {
  let label: String?
  let image: UIImage?
  let pinSize: CGSize
  let pinColor: UIColor
  let textColor: UIColor
  let backgroundColor: UIColor
}
