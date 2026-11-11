import Flutter
import UIKit

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
