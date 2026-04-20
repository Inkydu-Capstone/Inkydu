//
//  InkyduApp.swift
//  Inkydu
//
//  Created by Riley Fisher on 4/19/26.
//

import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .portrait

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        Self.orientationLock
    }
}

enum AppOrientation {
    case portrait
    case landscape

    var mask: UIInterfaceOrientationMask {
        switch self {
        case .portrait:
            return .portrait
        case .landscape:
            return .landscapeLeft
        }
    }
}

enum OrientationLock {
    static func set(_ orientation: AppOrientation) {
        AppDelegate.orientationLock = orientation.mask

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return
        }

        let preferences = UIWindowScene.GeometryPreferences.iOS(
            interfaceOrientations: orientation.mask
        )

        windowScene.requestGeometryUpdate(preferences) { error in
            print("Orientation update failed: \(error.localizedDescription)")
        }

        UIViewController.attemptRotationToDeviceOrientation()
    }
}

@main
struct InkyduApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
