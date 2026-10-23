// swift-tools-version:5.10
//
// FinderPlusKit — every piece of FinderPlus that is not the app shell or the Finder extension shell.
//
//   FinderPlusCore            Module contract, manifests, settings schema, menu rules, snapshot, shared paths.
//                             Linked by the Finder Sync extension, so it must stay small and free of UI.
//   FinderPlusEngine          Execution engine, task store, dependency checks, script packages, AppKit services.
//   FinderPlusUI              SwiftUI building blocks shared by the host and modules (schema-driven forms).
//   FPxxx (Sources/Modules)   One target per feature module. Modules depend only on Core/UI, never on each other.
//   FinderPlusBuiltinModules  The compile-time list of native modules shipped with the app.

import PackageDescription

/// Declares a feature module target living in `Sources/Modules/<name>`.
func module(
    _ name: String,
    dependencies: [Target.Dependency] = [],
    resources: [Resource]? = nil
) -> Target {
    .target(
        name: "FP\(name)",
        dependencies: ["FinderPlusCore", "FinderPlusUI"] + dependencies,
        path: "Sources/Modules/\(name)",
        exclude: [],
        resources: resources
    )
}

let builtinModules = [
    "FileCreator",
    "PathTools",
    "QuickOpen",
    "ImageCompressor",
    "MarkdownPDF",
    "MarkItDown",
    "FolderIcon",
    "Sidebar",
    "Appearance",
]

let package = Package(
    name: "FinderPlusKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FinderPlusCore", targets: ["FinderPlusCore"]),
        .library(name: "FinderPlusEngine", targets: ["FinderPlusEngine"]),
        .library(name: "FinderPlusUI", targets: ["FinderPlusUI"]),
        .library(name: "FinderPlusBuiltinModules", targets: ["FinderPlusBuiltinModules"]),
    ],
    dependencies: [
        // 0.6.x keeps swift-tools-version 5.7 so the package still builds with Xcode 15.3 / 16.
        .package(url: "https://github.com/swiftlang/swift-markdown.git", .upToNextMinor(from: "0.6.0")),
    ],
    targets: [
        .target(name: "FinderPlusCore"),
        .target(name: "FinderPlusEngine", dependencies: ["FinderPlusCore"]),
        .target(name: "FinderPlusUI", dependencies: ["FinderPlusCore"]),

        module("FileCreator"),
        module("PathTools"),
        module("QuickOpen"),
        module("ImageCompressor"),
        module(
            "MarkdownPDF",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")],
            resources: [.copy("Resources/web")]
        ),
        module("MarkItDown"),
        module("FolderIcon"),
        module("Sidebar"),
        module("Appearance"),

        .target(
            name: "FinderPlusBuiltinModules",
            dependencies: builtinModules.map { Target.Dependency(stringLiteral: "FP\($0)") }
        ),

        .testTarget(name: "FinderPlusCoreTests", dependencies: ["FinderPlusCore", "FinderPlusEngine"]),
        .testTarget(
            name: "FinderPlusModuleTests",
            dependencies: ["FinderPlusCore", "FinderPlusEngine", "FinderPlusBuiltinModules"]
                + builtinModules.map { Target.Dependency(stringLiteral: "FP\($0)") }
        ),
    ]
)
