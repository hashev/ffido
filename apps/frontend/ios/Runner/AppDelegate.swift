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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FfidoFiles") {
      FfidoFiles.register(with: registrar)
    }
  }
}


private final class FfidoFiles: NSObject, FlutterPlugin, UIDocumentPickerDelegate {
  private var pending: FlutterResult?
  private var directory: URL?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "org.ffido/files", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(FfidoFiles(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "saveUue" else { result(FlutterMethodNotImplemented); return }
    guard pending == nil else { result(FlutterError(code: "busy", message: "Сохранение уже открыто", details: nil)); return }
    guard let args = call.arguments as? [String: Any], let name = args["name"] as? String,
          let bytes = args["bytes"] as? FlutterStandardTypedData, bytes.data.count <= 16 * 1024 * 1024 else {
      result(FlutterError(code: "invalid", message: "Неверный файл", details: nil)); return
    }
    guard let root = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
      .flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController else {
      result(FlutterError(code: "save", message: "Окно недоступно", details: nil)); return
    }
    var presenter = root
    while let presented = presenter.presentedViewController { presenter = presented }
    do {
      let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
      directory = folder
      let base = (name.replacingOccurrences(of: "\\", with: "/") as NSString).lastPathComponent
      let safe = base.isEmpty || base == "." || base == ".." ? "attachment.bin" : base
      let file = folder.appendingPathComponent(safe)
      try bytes.data.write(to: file, options: .atomic)
      let picker = UIDocumentPickerViewController(url: file, in: .exportToService)
      picker.delegate = self
      pending = result
      presenter.present(picker, animated: true)
    } catch {
      clean()
      result(FlutterError(code: "save", message: "Не удалось подготовить файл", details: nil))
    }
  }
  private func clean() {
    if let folder = directory { try? FileManager.default.removeItem(at: folder) }
    directory = nil
  }
  private func finish(_ saved: Bool) {
    let result = pending; pending = nil; clean(); result?(saved)
  }
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(false) }
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { finish(!urls.isEmpty) }
}
