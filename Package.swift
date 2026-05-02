// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PromptEvalApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PromptEvalApp", targets: ["PromptEvalApp"]),
    ],
    targets: [
        .executableTarget(name: "PromptEvalApp"),
    ]
)
