import Flutter
import UIKit

// Migrated to the UIScene lifecycle, by hand, to the exact shape
// flutter_tools writes — see
// packages/flutter_tools/lib/src/migrations/uiscene_migration.dart.
//
// It was doing this on the build machine, every build, to files that are not
// committed: "Upgrading project.pbxproj / Upgrading Podfile / Finished
// migration to UIScene lifecycle". A build that rewrites its own source is a
// build whose output nobody can reproduce, and it is one more thing between a
// symptom and its cause.
//
// The difference from the old shape: plugins are registered when the implicit
// engine is ready rather than in didFinishLaunching. Under UIScene the engine
// does not exist yet at that point.
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
  }
}
