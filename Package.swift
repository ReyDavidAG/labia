// swift-tools-version: 6.0
import PackageDescription

let package = Package(
	name: "Labia",
	platforms: [.macOS(.v14)],
	dependencies: [
		.package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.1.1"),
		.package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.10.1"),
	],
	targets: [
		.target(name: "LabiaCore", path: "Sources/LabiaCore"),
		.executableTarget(
			name: "Labia",
			dependencies: [
				"LabiaCore",
				.product(name: "WhisperKit", package: "argmax-oss-swift"),
				.product(name: "Sparkle", package: "Sparkle"),
			],
			path: "Sources/Labia",
			swiftSettings: [.swiftLanguageMode(.v5)],
			// Sparkle.framework va en Labia.app/Contents/Frameworks (scripts/bundle.sh).
			linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
		),
		.testTarget(name: "LabiaCoreTests", dependencies: ["LabiaCore"], path: "Tests/LabiaCoreTests"),
	]
)
