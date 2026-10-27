//
//  AppStack.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What an app is built with, read from the files inside it.
public enum AppStack: String, Sendable, Codable, CaseIterable, Hashable {
    /// A web app in its own copy of Chromium and Node (Electron Framework).
    case electron
    /// A web app on the Chromium Embedded Framework.
    case cef
    /// A web app on NW.js (nwjs Framework).
    case nwjs
    /// Flutter (FlutterMacOS).
    case flutter
    /// React Native for macOS (React or Hermes framework).
    case reactNative = "react-native"
    /// Qt (QtCore).
    case qt
    /// A Java app carrying its own runtime.
    case java
    /// .NET / Mono / MAUI (MonoBundle).
    case dotnet
    /// A Unity game (UnityPlayer).
    case unity
    /// An iPad app rebuilt for the Mac (Mac Catalyst).
    case catalyst
    /// An iPhone or iPad app running unchanged on Apple silicon.
    case iosApp = "ios-app"
    /// None of the above: AppKit or SwiftUI, as far as the files say.
    case native
}
