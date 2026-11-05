import SwiftUI

struct LabiaApp: App {
	var body: some Scene {
		MenuBarExtra("Labia", systemImage: "waveform") { Button("Salir") { NSApp.terminate(nil) } }
	}
}
