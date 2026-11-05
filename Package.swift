// swift-tools-version: 6.0
import PackageDescription

let package = Package(
	name: "Labia",
	platforms: [.macOS(.v14)],
	dependencies: [
		.package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.1.1"),
	],
	targets: [
		.target(name: "LabiaCore", path: "Sources/LabiaCore"),
		.executableTarget(
			name: "Labia",
			dependencies: ["LabiaCore", .product(name: "WhisperKit", package: "argmax-oss-swift")],
			path: "Sources/Labia",
			swiftSettings: [.swiftLanguageMode(.v5)]
		),
		.testTarget(name: "LabiaCoreTests", dependencies: ["LabiaCore"], path: "Tests/LabiaCoreTests"),
	]
)
