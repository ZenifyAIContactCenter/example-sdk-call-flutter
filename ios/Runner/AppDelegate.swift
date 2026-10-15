import AVFoundation
import CallKit
import Flutter
import UIKit
import flutter_callkit_incoming
import zenify_call

/// Tích hợp zenify_call — đây chính là mẫu app tiêu thụ cần chép (README):
///  · ZenifyCallKit.shared.start() sớm nhất có thể (PushKit giao push ngay khi đăng ký)
///  · Conform CallkitIncomingAppDelegate và chuyển tiếp sang ZenifyCallKit —
///    flutter_callkit_incoming tìm delegate qua UIApplication.shared.delegate
///  · Silent APNs CALL_CANCEL → handleRemoteNotification
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, CallkitIncomingAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    ZenifyCallKit.shared.start()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    // CALL_CANCEL im lặng → SDK; push khác (chat…) → firebase_messaging qua super
    if ZenifyCallKit.shared.handleRemoteNotification(userInfo) {
      completionHandler(.newData)
      return
    }
    super.application(application, didReceiveRemoteNotification: userInfo, fetchCompletionHandler: completionHandler)
  }

  // MARK: CallkitIncomingAppDelegate → zenify_call
  func onAccept(_ call: Call, _ action: CXAnswerCallAction) { ZenifyCallKit.shared.onAccept(call, action) }
  func onDecline(_ call: Call, _ action: CXEndCallAction) { ZenifyCallKit.shared.onDecline(call, action) }
  func onEnd(_ call: Call, _ action: CXEndCallAction) { ZenifyCallKit.shared.onEnd(call, action) }
  func onTimeOut(_ call: Call) { ZenifyCallKit.shared.onTimeOut(call) }
  func didActivateAudioSession(_ audioSession: AVAudioSession) { ZenifyCallKit.shared.didActivateAudioSession(audioSession) }
  func didDeactivateAudioSession(_ audioSession: AVAudioSession) { ZenifyCallKit.shared.didDeactivateAudioSession(audioSession) }
  func providerDidReset() { ZenifyCallKit.shared.providerDidReset() }
}
