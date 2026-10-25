#!/usr/bin/env python3
"""Generate the root Package.swift for the AltTab app target.

The exclude list mirrors the Xcode target's Sources phase exactly: the unit tests and their
helpers, the Objective-C files (they live in the AltTabObjC target), and the *Specs.md docs.
"""
import os

excludes = ["_test-support"]
for h in ["vendors/AppCenterApplication.h", "vendors/AppCenterApplication.m",
          "vendors/ObjCExceptionCatcher.h", "vendors/ObjCExceptionCatcher.m"]:
    excludes.append(h)
for helper in ["TestInteractionModel.swift", "TestReducerRunner.swift",
               "TestScenarioGenerator.swift", "TestScenarioSimulator.swift"]:
    excludes.append("switcher/state/" + helper)
for root, dirs, files in os.walk("src"):
    for f in sorted(files):
        if f.endswith("Tests.swift") or f.endswith(".md"):
            excludes.append(os.path.relpath(os.path.join(root, f), "src"))
excludes = sorted(set(excludes))
print(len(excludes), "excludes")

body = "\n".join('            "%s",' % e for e in excludes)

TEMPLATE = r'''// swift-tools-version: 5.9
import Foundation
import PackageDescription

// A SwiftPM manifest for the app, so it can be built without Xcode.
//
// Why this exists: the Xcode project (alt-tab-macos.xcodeproj) is the upstream build system, and
// `xcodebuild` is the supported way to build AltTab. But xcodebuild, like ibtool and actool, only
// ships with a full Xcode installation — on a machine that has only the Command Line Tools, the
// project cannot be built at all. This manifest describes the same app target (the same Swift and
// Objective-C files, with the same exclusions) using the same vendored dependencies, so the app
// can still be compiled and installed.
//
// The bundle assembly, resource copying and code signing are not SwiftPM's job:
// scripts/build_local.sh does that, mirroring what the Xcode project's build phases do.

let packageDirectory = Context.packageDirectory

// Where the SDK keeps the private frameworks (SkyLight). The build script points this at the active
// SDK's PrivateFrameworks directory; the default is the Command Line Tools SDK.
let privateFrameworksPath = ProcessInfo.processInfo.environment["ALTTAB_PRIVATE_FRAMEWORKS"]
    ?? "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/PrivateFrameworks"

// The files under src/ that the app target does NOT compile: the unit tests and their helpers, the
// Objective-C files (they live in the AltTabObjC target), and the *Specs.md documents.
let excludedAppSources: [String] = [
__EXCLUDES__
]

let objCTarget: Target = .target(
    name: "AltTabObjC",
    dependencies: [
        .product(name: "AppCenterCrashes", package: "AppCenter"),
    ],
    path: "src/vendors",
    exclude: ["AppCenterCrashes.swift", "SparkleDelegate.swift"],
    publicHeadersPath: ".",
    cSettings: [
        .headerSearchPath("."),
    ],
    linkerSettings: [
        .linkedFramework("AppKit"),
    ]
)

let appTarget: Target = .executableTarget(
    name: "AltTab",
    dependencies: [
        "AltTabObjC",
        .product(name: "AppCenter", package: "AppCenter"),
        .product(name: "AppCenterCrashes", package: "AppCenter"),
        .product(name: "ShortcutRecorder", package: "ShortcutRecorder"),
        .product(name: "Sparkle", package: "Sparkle"),
    ],
    path: "src",
    exclude: excludedAppSources,
    swiftSettings: [
        // The Xcode project's bridging header, passed to swiftc the way Xcode passes it.
        .unsafeFlags(["-import-objc-header", packageDirectory + "/alt-tab-macos-Bridging-Header.h"]),
        .unsafeFlags(["-Xcc", "-I" + packageDirectory + "/src/vendors"]),
    ],
    linkerSettings: [
        // SkyLight is a private framework: only the SDK's .tbd stub can be linked against.
        .unsafeFlags(["-F" + privateFrameworksPath]),
        .linkedFramework("SkyLight"),
        // SDK 26 header bug: a stray ';' between API_AVAILABLE and @interface
        // SCScreenshotConfiguration detaches the annotation, so the class ref links strongly
        // and dyld aborts at launch on any macOS below 26.
        .unsafeFlags(["-weak_framework", "ScreenCaptureKit"]),
    ]
)

let package = Package(
    name: "AltTab",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "AltTab", targets: ["AltTab"]),
    ],
    dependencies: [
        .package(path: "vendor/AppCenter"),
        .package(path: "vendor/ShortcutRecorder"),
        .package(path: "vendor/Sparkle"),
    ],
    targets: [objCTarget, appTarget],
    swiftLanguageVersions: [.v5]
)
'''

open("Package.swift", "w").write(TEMPLATE.replace("__EXCLUDES__", body))
print("wrote Package.swift")
