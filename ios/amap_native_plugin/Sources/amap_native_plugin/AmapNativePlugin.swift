import AMapFoundationKit
import Flutter
import Foundation
import MAMapKit

public class AmapNativePlugin: NSObject, FlutterPlugin {
  private let search = AmapSearchHandler()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "amap_native_plugin", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(AmapNativePlugin(), channel: channel)
    registrar.register(
      AmapMapViewFactory(binaryMessenger: registrar.messenger()),
      withId: "amap_native_plugin/map_view"
    )
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if ["searchPlaces", "reverseGeocode", "cancelSearch"].contains(call.method) {
      search.handle(call, result: result)
      return
    }
    guard call.method == "init" else {
      result(FlutterMethodNotImplemented)
      return
    }
    let args = call.arguments as? [String: Any]
    let privacyShown = args?["privacyShown"] as? Bool
      ?? args?["androidPrivacyShown"] as? Bool
      ?? false
    let privacyAgreed = args?["privacyAgreed"] as? Bool
      ?? args?["androidPrivacyAgreed"] as? Bool
      ?? false
    MAMapView.updatePrivacyShow(
      privacyShown ? .didShow : .notShow,
      privacyInfo: privacyShown ? .didContain : .notContain
    )
    MAMapView.updatePrivacyAgree(privacyAgreed ? .didAgree : .notAgree)
    if let iosApiKey = args?["iosApiKey"] as? String, !iosApiKey.isEmpty {
      AMapServices.shared().apiKey = iosApiKey
    }
    search.initialize(shown: privacyShown, agreed: privacyAgreed)
    result(nil)
  }
  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    search.dispose()
  }
}
