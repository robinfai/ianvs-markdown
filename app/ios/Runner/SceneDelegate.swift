import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    // Cold launch URLs arrive here, before the Dart listener is ready.
    PreviewIntegration.shared.receive(connectionOptions.urlContexts.map(\.url))
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    if !PreviewIntegration.shared.receive(URLContexts.map(\.url)) {
      super.scene(scene, openURLContexts: URLContexts)
    }
  }
}
