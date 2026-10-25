// swift-tools-version: 5.9
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
            "_test-support",
            "coverage.md",
            "events/AxQueryRoutingSpecs.md",
            "events/AxQueryRoutingTests.swift",
            "events/CaptureDiscoveryTests.swift",
            "events/GestureTriggerKernelSpecs.md",
            "events/GestureTriggerKernelTests.swift",
            "events/KeyboardEventsSpecs.md",
            "events/KeyboardEventsTests.swift",
            "events/WindowCaptureEventsSpecs.md",
            "kit/AnchoredPopoverSpecs.md",
            "kit/AnchoredPopoverTests.swift",
            "kit/CustomRecorderControlSpecs.md",
            "kit/CustomRecorderControlTests.swift",
            "macos/PermissionCalloutResolverSpecs.md",
            "macos/PermissionCalloutResolverTests.swift",
            "macos/PermissionCheckRetrySpecs.md",
            "macos/PermissionCheckRetryTests.swift",
            "macos/api-wrappers/MissionControlOverlaySpecs.md",
            "macos/api-wrappers/MissionControlOverlayTests.swift",
            "macos/api-wrappers/OnActionExtensionSpecs.md",
            "macos/api-wrappers/OnActionExtensionTests.swift",
            "macos/api-wrappers/PersistedWindowFrameSpecs.md",
            "macos/api-wrappers/PersistedWindowFrameTests.swift",
            "macos/api-wrappers/ProcessLivenessSpecs.md",
            "macos/api-wrappers/ProcessLivenessTests.swift",
            "main-thread-ipc.md",
            "preferences/PreferencesMigrationsSpecs.md",
            "preferences/PreferencesMigrationsTests.swift",
            "preferences/PreferencesPersistenceProbeSpecs.md",
            "preferences/PreferencesPersistenceProbeTests.swift",
            "preferences/settings-window/EmailLineWrapSpecs.md",
            "preferences/settings-window/EmailLineWrapTests.swift",
            "preferences/settings-window/SettingsSearchHighlightSpecs.md",
            "preferences/settings-window/SettingsSearchHighlightTests.swift",
            "preferences/settings-window/SettingsSectionSearchContentSpecs.md",
            "preferences/settings-window/SettingsSectionSearchContentTests.swift",
            "preferences/settings-window/SidebarListSpecs.md",
            "preferences/settings-window/SidebarListTests.swift",
            "preferences/settings-window/tabs/controls/NativeHotkeyResolverSpecs.md",
            "preferences/settings-window/tabs/controls/NativeHotkeyResolverTests.swift",
            "preferences/settings-window/tabs/controls/OverrideClickResolverSpecs.md",
            "preferences/settings-window/tabs/controls/OverrideClickResolverTests.swift",
            "pro/license/LicenseManagerSpecs.md",
            "pro/license/LicenseManagerTests.swift",
            "pro/scheduling/ProTransitionSpecs.md",
            "pro/scheduling/ProTransitionTests.swift",
            "pro/ui/ProBadgeViewSegmentSpecs.md",
            "pro/ui/ProBadgeViewSegmentTests.swift",
            "secondary-windows/permission-window/PermissionFlowSpecs.md",
            "secondary-windows/permission-window/PermissionFlowTests.swift",
            "switcher/AppearanceSpecs.md",
            "switcher/AppearanceTests.swift",
            "switcher/KeyRepeatTimerSpecs.md",
            "switcher/KeyRepeatTimerTests.swift",
            "switcher/SearchSpecs.md",
            "switcher/SearchTests.swift",
            "switcher/main-window/DragAndDropResolverSpecs.md",
            "switcher/main-window/DragAndDropResolverTests.swift",
            "switcher/main-window/TileGridLayoutSpecs.md",
            "switcher/main-window/TileGridLayoutTests.swift",
            "switcher/main-window/TilePoolSpecs.md",
            "switcher/main-window/TilePoolTests.swift",
            "switcher/main-window/TilesPanelBackgroundViewSpecs.md",
            "switcher/search-discovery/SearchDiscoverySpecs.md",
            "switcher/search-discovery/SearchDiscoveryTests.swift",
            "switcher/state/BruteForceWindowMatchSpecs.md",
            "switcher/state/BruteForceWindowMatchTests.swift",
            "switcher/state/ExceptionMatcherSpecs.md",
            "switcher/state/ExceptionMatcherTests.swift",
            "switcher/state/FocusIntentPolicySpecs.md",
            "switcher/state/FocusIntentPolicyTests.swift",
            "switcher/state/PhantomWindowDetectorSpecs.md",
            "switcher/state/PhantomWindowDetectorTests.swift",
            "switcher/state/RealWorldScenariosSpecs.md",
            "switcher/state/RealWorldScenariosTests.swift",
            "switcher/state/SearchFieldEditingSpecs.md",
            "switcher/state/SearchFieldEditingTests.swift",
            "switcher/state/SearchModeResolverSpecs.md",
            "switcher/state/SearchModeResolverTests.swift",
            "switcher/state/SelectionResolverSpecs.md",
            "switcher/state/SelectionResolverTests.swift",
            "switcher/state/ShortcutModifierResolverSpecs.md",
            "switcher/state/ShortcutModifierResolverTests.swift",
            "switcher/state/TabGroupResolverSpecs.md",
            "switcher/state/TabGroupResolverTests.swift",
            "switcher/state/TabReadPolicySpecs.md",
            "switcher/state/TabReadPolicyTests.swift",
            "switcher/state/TestInteractionModel.swift",
            "switcher/state/TestReducerRunner.swift",
            "switcher/state/TestReducerRunnerSpecs.md",
            "switcher/state/TestReducerRunnerTests.swift",
            "switcher/state/TestScenarioGenerator.swift",
            "switcher/state/TestScenarioSimulator.swift",
            "switcher/state/TestScenarioSimulatorSpecs.md",
            "switcher/state/TestScenarioSimulatorTests.swift",
            "switcher/state/TrackedWindowStateFieldsTests.swift",
            "switcher/state/WindowAdmissionResolverSpecs.md",
            "switcher/state/WindowAdmissionResolverTests.swift",
            "switcher/state/WindowEventReducerFocusSpecs.md",
            "switcher/state/WindowEventReducerFocusTests.swift",
            "switcher/state/WindowEventReducerMinimizeSpecs.md",
            "switcher/state/WindowEventReducerMinimizeTests.swift",
            "switcher/state/WindowEventReducerPhantomSpecs.md",
            "switcher/state/WindowEventReducerPhantomTests.swift",
            "switcher/state/WindowEventReducerSpaceSpecs.md",
            "switcher/state/WindowEventReducerSpaceTests.swift",
            "switcher/state/WindowFilterResolverSpecs.md",
            "switcher/state/WindowFilterResolverTests.swift",
            "switcher/state/WindowLifecycleSpecs.md",
            "switcher/state/WindowOrderResolverSpecs.md",
            "switcher/state/WindowOrderResolverTests.swift",
            "switcher/state/WindowTitleSpecs.md",
            "switcher/state/WindowTitleTests.swift",
            "util/CoalescedWorkSpecs.md",
            "util/CoalescedWorkTests.swift",
            "util/SchedulingPolicySpecs.md",
            "util/SchedulingPolicyTests.swift",
            "util/StapledTicketSpecs.md",
            "util/StapledTicketTests.swift",
            "util/UsageStatsMessageSpecs.md",
            "util/UsageStatsMessageTests.swift",
            "vendors/AppCenterApplication.h",
            "vendors/AppCenterApplication.m",
            "vendors/ObjCExceptionCatcher.h",
            "vendors/ObjCExceptionCatcher.m",
            "window-tracking/AttentionDriverSpecs.md",
            "window-tracking/AttentionDriverTests.swift",
            "window-tracking/AttentionModelSpecs.md",
            "window-tracking/AttentionModelTests.swift",
            "window-tracking/AttentionOrderSpecs.md",
            "window-tracking/AttentionSettlePolicySpecs.md",
            "window-tracking/AttentionSettlePolicyTests.swift",
            "window-tracking/AxObserverHealthSpecs.md",
            "window-tracking/AxObserverHealthTests.swift",
            "window-tracking/AxTitleNotificationPolicySpecs.md",
            "window-tracking/AxTitleNotificationPolicyTests.swift",
            "window-tracking/TrackingTelemetrySpecs.md",
            "window-tracking/TrackingTelemetryTests.swift",
            "window-tracking/TrackingTypesSpecs.md",
            "window-tracking/TrackingTypesTests.swift",
            "windowserver/PublishedWindowsSpecs.md",
            "windowserver/PublishedWindowsTests.swift",
            "windowserver/README.md",
            "windowserver/WindowSurfaceInventorySpecs.md",
            "windowserver/WindowSurfaceInventoryTests.swift",
            "windowserver/WsEventRoutingSpecs.md",
            "windowserver/WsEventRoutingTests.swift",
            "windowserver/WsWindowStateSpecs.md",
            "windowserver/WsWindowStateTests.swift",
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
