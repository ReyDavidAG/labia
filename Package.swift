// swift-tools-version: 6.0
import PackageDescription

let package = Package(
	name: "Labia",
	platforms: [.macOS(.v14)],
	dependencies: [
		.package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.18.0"),
	],
	targets: [
		.target(name: "LabiaCore", path: "Sources/LabiaCore"),
		.executableTarget(
			name: "Labia",
			dependencies: ["LabiaCore", .product(name: "WhisperKit", package: "WhisperKit")],
			path: "Sources/Labia"
		),
		.testTarget(name: "LabiaCoreTests", dependencies: ["LabiaCore"], path: "Tests/LabiaCoreTests"),
	]
)
