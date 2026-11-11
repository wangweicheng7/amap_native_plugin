import Flutter
import Foundation
import MAMapKit
import UIKit

final class AmapSnapshotController {
  private struct Request {
    let id: UUID
    let result: FlutterResult
    let timeout: DispatchWorkItem
    var encodingStarted = false
  }

  private let mapView: MAMapView
  private var pending: Request?
  private var disposed = false
  private var inactiveObserver: NSObjectProtocol?

  init(_ mapView: MAMapView) {
    self.mapView = mapView
    inactiveObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.willResignActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.cancelPending()
    }
  }

  deinit {
    if let observer = inactiveObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    pending?.timeout.cancel()
  }

  func capture(result: @escaping FlutterResult, mapLoaded: Bool) {
    guard !disposed else {
      result(FlutterError(code: "map_disposed", message: "Map view has already been disposed", details: nil))
      return
    }
    guard pending == nil else {
      result(FlutterError(code: "snapshot_in_progress", message: "A map snapshot is already in progress", details: nil))
      return
    }
    guard mapLoaded,
          UIApplication.shared.applicationState == .active,
          mapView.window != nil,
          !mapView.isHidden,
          mapView.alpha > 0,
          mapView.bounds.width > 0,
          mapView.bounds.height > 0 else {
      result(FlutterError(code: "map_not_ready", message: "Map must be loaded, active, visible and have nonzero dimensions", details: nil))
      return
    }
    let id = UUID()
    let timeout = DispatchWorkItem { [weak self] in
      self?.finish(id: id, response: nil)
    }
    pending = Request(id: id, result: result, timeout: timeout)
    DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)
    mapView.takeSnapshot(in: mapView.bounds, timeoutInterval: 5) { [weak self] image, _ in
      DispatchQueue.main.async { [weak self] in
        self?.acceptImage(image, id: id)
      }
    }
  }

  private func acceptImage(_ image: UIImage?, id: UUID) {
    guard pending?.id == id, pending?.encodingStarted == false else { return }
    pending?.encodingStarted = true
    guard let image else {
      finish(id: id, response: nil)
      return
    }
    // UIImage retains its immutable backing pixels for the background PNG encoder.
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let data = image.pngData()
      DispatchQueue.main.async { [weak self] in
        if let data {
          self?.finish(id: id, response: FlutterStandardTypedData(bytes: data))
        } else {
          self?.finish(id: id, response: FlutterError(
            code: "snapshot_failed", message: "The map snapshot could not be encoded as PNG", details: nil
          ))
        }
      }
    }
  }

  private func finish(id: UUID, response: Any?) {
    guard let request = pending, request.id == id else { return }
    request.timeout.cancel()
    pending = nil
    request.result(response)
  }

  func cancelPending() {
    guard let request = pending else { return }
    finish(id: request.id, response: FlutterError(
      code: "map_not_ready", message: "Map became inactive or hidden", details: nil
    ))
  }

  func dispose() {
    guard !disposed else { return }
    disposed = true
    if let request = pending {
      finish(id: request.id, response: FlutterError(
        code: "map_disposed", message: "Map view was disposed during the snapshot", details: nil
      ))
    }
    if let observer = inactiveObserver {
      NotificationCenter.default.removeObserver(observer)
      inactiveObserver = nil
    }
  }
}
