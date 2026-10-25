// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShortcutRecorder",
    defaultLocalization: "en",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "ShortcutRecorder", type: .static, targets: ["ShortcutRecorder"]),
    ],
    targets: [
        .target(
            name: "ShortcutRecorder",
            path: "Sources/ShortcutRecorder",
            // Images.xcassets and the .lproj dirs are excluded instead of being declared as SPM
            // resources: compiling the asset catalog needs actool, which only ships with Xcode, so
            // a Command Line Tools-only build would fail. The app bundle assembler
            // (scripts/build_local.sh) builds ShortcutRecorder_ShortcutRecorder.bundle by hand —
            // the flat PNGs that `-[NSBundle imageForResource:]` looks up, plus the
            // <lang>.lproj/ShortcutRecorder.strings tables SRLoc() reads.
            exclude: [
                "Images.xcassets",
                "de.lproj", "en.lproj", "es.lproj", "fr.lproj", "it.lproj", "ja.lproj",
                "ko.lproj", "nl.lproj", "pl.lproj", "pt-BR.lproj", "ru.lproj", "sv.lproj",
                "th.lproj", "zh-Hans.lproj", "zh-Hant.lproj",
            ],
            publicHeadersPath: "include",
            cSettings: [
                // Lets .m files use `#import "SRCommon.h"` as well as `<ShortcutRecorder/SRCommon.h>`.
                .headerSearchPath("include/ShortcutRecorder"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
            ]
        ),
    ]
)
