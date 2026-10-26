import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AudioChunkPlugin") {
      AudioChunkPlugin.register(with: registrar)
    }
  }
}

final class AudioChunkPlugin: NSObject, FlutterPlugin {
  private let queue = DispatchQueue(label: "cabina.audio-chunks", qos: .utility)
  // Accessed only on the platform/main thread; flags themselves are thread-safe.
  private var jobs: [String: AudioChunkCancellation] = [:]

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "cabina/audio_chunks", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(AudioChunkPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any], let id = args["id"] as? String else {
      result(FlutterError(code: "invalid_arguments", message: "Missing job ID", details: nil)); return
    }
    if call.method == "cancel" { jobs[id]?.cancel(); result(nil); return }
    guard call.method == "extract" else { result(FlutterMethodNotImplemented); return }
    guard let source = args["sourcePath"] as? String,
          let destination = args["outputPath"] as? String,
          let start = args["startUs"] as? NSNumber else {
      result(FlutterError(code: "invalid_arguments", message: "Missing audio paths", details: nil)); return
    }
    let cancellation = AudioChunkCancellation()
    jobs[id] = cancellation
    queue.async {
      let response: Any
      do {
        response = try AudioChunkExtractor.extract(source: source, destination: destination,
          startUs: start.int64Value, cancellation: cancellation)
      } catch {
        response = FlutterError(code: "audio_preparation_failed",
          message: "Audio preparation failed or was cancelled", details: nil)
      }
      DispatchQueue.main.async { self.jobs.removeValue(forKey: id); result(response) }
    }
  }

  func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    for job in jobs.values { job.cancel() }
  }
}
