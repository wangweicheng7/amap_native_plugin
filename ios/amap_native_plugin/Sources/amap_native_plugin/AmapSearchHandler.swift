import AMapSearchKit
import Flutter
import Foundation

final class AmapSearchHandler {
  private var initialized = false
  private var requests: [String: NativeSearchRequest] = [:]

  func initialize(shown: Bool, agreed: Bool) {
    dispose()
    AMapSearchAPI.updatePrivacyShow(
      shown ? .didShow : .notShow,
      privacyInfo: shown ? .didContain : .notContain
    )
    AMapSearchAPI.updatePrivacyAgree(agreed ? .didAgree : .notAgree)
    initialized = shown && agreed
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let id = args["requestId"] as? String ?? ""
    if call.method == "cancelSearch" {
      requests[id]?.finish(FlutterError(code: "cancelled", message: "Search cancelled.", details: nil))
      result(nil)
      return
    }
    guard initialized else {
      result(FlutterError(code: "not_initialized", message: "Initialize AMap with privacy consent before searching.", details: nil))
      return
    }
    guard !id.isEmpty, requests[id] == nil,
          let timeout = args["timeoutMs"] as? NSNumber,
          timeout.doubleValue.isFinite,
          (1...60000).contains(timeout.doubleValue) else {
      result(FlutterError(code: "invalid_argument", message: "Invalid requestId or timeout.", details: nil))
      return
    }

    let query: AMapSearchObject
    if call.method == "searchPlaces" {
      guard let keyword = args["keyword"] as? String,
            !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            keyword.utf16.count <= 80 else {
        result(FlutterError(code: "invalid_argument", message: "Invalid keyword.", details: nil))
        return
      }
      let request = AMapInputTipsSearchRequest()
      request.keywords = keyword
      request.city = args["city"] as? String
      request.cityLimit = args["cityLimit"] as? Bool ?? false
      if let location = args["location"] as? [String: Any] {
        guard let point = Self.point(location) else {
          result(FlutterError(code: "invalid_argument", message: "Invalid GCJ-02 coordinate.", details: nil))
          return
        }
        request.location = "\(point.longitude),\(point.latitude)"
      }
      query = request
    } else {
      guard let position = args["position"] as? [String: Any],
            let point = Self.point(position),
            let radius = args["radiusMeters"] as? NSNumber,
            radius.doubleValue.isFinite,
            (1...3000).contains(radius.doubleValue) else {
        result(FlutterError(code: "invalid_argument", message: "Invalid reverse geocoding arguments.", details: nil))
        return
      }
      let request = AMapReGeocodeSearchRequest()
      request.location = point
      request.radius = Int(ceil(radius.doubleValue))
      request.requireExtension = false
      query = request
    }

    let request = NativeSearchRequest(timeout: timeout.doubleValue / 1000) { [weak self] value in
      self?.requests.removeValue(forKey: id)
      result(value)
    }
    requests[id] = request
    request.start(query)
  }

  private static func point(_ value: [String: Any]) -> AMapGeoPoint? {
    guard let latitude = value["latitude"] as? NSNumber,
          let longitude = value["longitude"] as? NSNumber,
          latitude.doubleValue.isFinite, longitude.doubleValue.isFinite,
          abs(latitude.doubleValue) <= 90, abs(longitude.doubleValue) <= 180 else { return nil }
    return AMapGeoPoint.location(withLatitude: CGFloat(latitude.doubleValue), longitude: CGFloat(longitude.doubleValue))
  }

  func dispose() {
    initialized = false
    let pending = Array(requests.values)
    pending.forEach {
      $0.finish(FlutterError(code: "cancelled", message: "Search service detached or reinitialized.", details: nil))
    }
  }
}

private final class NativeSearchRequest: NSObject, AMapSearchDelegate {
  private let api = AMapSearchAPI()
  private let timeout: TimeInterval
  private var timer: DispatchWorkItem?
  private var completion: FlutterResult?

  init(timeout: TimeInterval, completion: @escaping FlutterResult) {
    self.timeout = timeout
    self.completion = completion
    super.init()
    api?.delegate = self
  }

  func start(_ query: AMapSearchObject) {
    guard let api else {
      finish(FlutterError(code: "sdk_error", message: "Unable to create AMap search service.", details: nil))
      return
    }
    let timer = DispatchWorkItem { [weak self] in
      self?.finish(FlutterError(code: "timeout", message: "AMap search timed out.", details: nil))
    }
    self.timer = timer
    DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timer)
    if let request = query as? AMapInputTipsSearchRequest {
      api.aMapInputTipsSearch(request)
    } else if let request = query as? AMapReGeocodeSearchRequest {
      api.aMapReGoecodeSearch(request)
    }
  }

  func onInputTipsSearchDone(_ request: AMapInputTipsSearchRequest!, response: AMapInputTipsSearchResponse!) {
    let values: [[String: Any]] = (response?.tips ?? []).map { tip in
      [
        "id": tip.uid ?? "",
        "name": tip.name ?? "",
        "address": tip.address ?? "",
        "district": tip.district ?? "",
        "adCode": tip.adcode ?? "",
        "latitude": tip.location.map { NSNumber(value: Double($0.latitude)) as Any } ?? NSNull(),
        "longitude": tip.location.map { NSNumber(value: Double($0.longitude)) as Any } ?? NSNull()
      ]
    }
    finish(values)
  }

  func onReGeocodeSearchDone(_ request: AMapReGeocodeSearchRequest!, response: AMapReGeocodeSearchResponse!) {
    guard let address = response?.regeocode else { finish(nil); return }
    let component = address.addressComponent
    let value = [
      "formattedAddress": address.formattedAddress ?? "",
      "province": component?.province ?? "",
      "city": component?.city ?? "",
      "district": component?.district ?? "",
      "adCode": component?.adcode ?? ""
    ]
    finish(value.values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ? value : nil)
  }

  func aMapSearchRequest(_ request: Any!, didFailWithError error: Error!) {
    let error = error as NSError? ?? NSError(domain: "AMapSearch", code: -1)
    let code: String
    switch error.code {
    case 1004, 1005, 1010: code = "rate_limited"
    case 1001...1014: code = "auth_error"
    case NSURLErrorTimedOut, 1102, 1103, 1802: code = "timeout"
    case NSURLErrorNotConnectedToInternet, NSURLErrorCannotConnectToHost, 1804, 1805, 1806: code = "network_error"
    case 1200, 1201, 1202, 1813: code = "invalid_argument"
    case NSURLErrorCancelled, 1807: code = "cancelled"
    default: code = "sdk_error"
    }
    finish(FlutterError(code: code, message: error.localizedDescription, details: ["vendorCode": error.code]))
  }

  func finish(_ value: Any?) {
    guard let completion else { return }
    self.completion = nil
    timer?.cancel()
    timer = nil
    api?.delegate = nil
    api?.cancelAllRequests()
    completion(value)
  }
}
