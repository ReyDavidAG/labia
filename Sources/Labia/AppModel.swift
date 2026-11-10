import AppKit
import AVFoundation
import LabiaCore
import Observation
import ServiceManagement
import SwiftUI

enum Pill: Equatable {
	case listening
	case locked
	case transcribing
	case done(words: Int, pasted: Bool)
	/// No se pudo escribir: el dictado completo quedó en el portapapeles.
	case unpasted(LiveDictation.Miss)
	case short
	case cancelled
	case silent
	case permission
	case noModel
	case failed(String)
	case updated(String)

	/// Se muestra aunque la cápsula esté apagada en Ajustes.
	var isNotice: Bool {
		if case .updated = self { return true }
		return false
	}

	var isWarning: Bool {
		switch self {
		case .short, .cancelled, .silent, .permission, .noModel, .failed, .unpasted: true
		default: false
		}
	}
}

enum ModelStatus: Equatable {
	case missing
	case downloading(Double)
	case unloaded
	case loading
	case ready
	case failed(String)
}

enum SettingsTab: Hashable {
	case general, vocabulary, replacements, history, model
}

@MainActor @Observable
final class AppModel {
	static let historyURL = Transcriber.base.appending(path: "history.json")
	static let waveformBars = 24
	/// Se sigue grabando esto después de soltar: casi siempre se suelta mientras suena la última sílaba.
	static let tail: Duration = .milliseconds(300)

	var settings: Preferences {
		didSet {
			guard settings != oldValue else { return }
			settings.save()
			if settings.hotkey != oldValue.hotkey { hotkey.hotkey = settings.hotkey }
			if settings.vocabulary != oldValue.vocabulary { refreshPromptCost() }
			if settings.unloadAfterMinutes != oldValue.unloadAfterMinutes { scheduleUnload() }
			if settings.autoUpdate != oldValue.autoUpdate || settings.updateChannel != oldValue.updateChannel { updater.apply(settings) }
		}
	}

	var history: History
	var pill: Pill?
	var pillVisible = false
	var levels = [Float](repeating: 0, count: AppModel.waveformBars)
	var recordingStart: Date?
	var modelStatus: ModelStatus
	var micGranted = false
	var accessibilityGranted = false
	var launchAtLogin = SMAppService.mainApp.status == .enabled
	var promptTokens: Int?
	var settingsTab: SettingsTab = .general
	var paused = false {
		didSet { hotkey.isEnabled = !paused }
	}

	private var isSample = false
	private var machine = GestureMachine()
	private let recorder = Recorder()
	private let transcriber = Transcriber()
	private let hotkey = HotkeyTap()
	private let overlay = Overlay()
	let updater = Updater()
	private var lastDictation = Date.distantPast
	private var target: NSRunningApplication?
	private var live: LiveDictation?
	/// La entrega del dictado anterior: el siguiente espera a que termine de escribir antes de escribir él.
	private var delivery: Task<Void, Never>?
	private var tailTask: Task<Void, Never>?
	private var tickTimer: Timer?
	private var permissionTimer: Timer?
	private var hideTask: Task<Void, Never>?
	private var unloadTask: Task<Void, Never>?

	init(sample: Bool = false) {
		guard !sample else {
			var sampleSettings = Preferences()
			sampleSettings.vocabulary += ["useApiQuery", "staleTime"]
			settings = sampleSettings
			history = History()
			modelStatus = .ready
			micGranted = true
			accessibilityGranted = true
			promptTokens = 26
			isSample = true
			return
		}
		settings = Preferences.load()
		history = History.load(from: AppModel.historyURL)
		modelStatus = Transcriber.isDownloaded ? .unloaded : .missing
		hotkey.hotkey = settings.hotkey
		hotkey.onEvent = { [weak self] event in
			MainActor.assumeIsolated { self?.handle(event) ?? false }
		}
		NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { _ in
			MainActor.assumeIsolated { LiveDictation.userInput += 1 }
		}
		recorder.onLevel = { [weak self] level in
			Task { @MainActor in self?.push(level) }
		}
		refreshPermissions()
		if modelStatus == .unloaded { preload() }
		if needsSetup { startPermissionPolling() }
		updater.isBusy = { [weak self] in
			guard let self else { return false }
			return machine.isRecording || tailTask != nil || live != nil || pill == .transcribing
		}
		updater.lastActivity = { [weak self] in self?.lastDictation ?? .distantPast }
		updater.start(settings: settings)
		if let version = Updater.takeNotice() {
			Task {
				try? await Task.sleep(for: .seconds(1))
				show(.updated(version))
				hide(after: 4)
			}
		}
	}

	var needsSetup: Bool { !micGranted || !accessibilityGranted || modelStatus == .missing || isDownloading }

	var isDownloading: Bool {
		if case .downloading = modelStatus { return true }
		return false
	}

	var isRecording: Bool { machine.isRecording }

	var lastText: String? { history.entries.first?.text }

	var menuSymbol: String {
		if paused { return "waveform.slash" }
		if needsSetup { return "waveform.badge.exclamationmark" }
		if isRecording { return "waveform.circle.fill" }
		return "waveform"
	}

	var statusLine: String {
		if paused { return "Labia está en pausa" }
		if needsSetup { return "Falta terminar la configuración" }
		switch modelStatus {
		case .loading: return "Cargando el modelo…"
		case .failed: return "El modelo no cargó"
		default: return "Lista · mantén \(settings.hotkey.label) para dictar"
		}
	}

	var promptCostLabel: String? {
		guard let promptTokens else { return nil }
		let ms = Int((Double(promptTokens) * 0.025 * 1000 / 10).rounded()) * 10
		return ms == 0 ? "sin costo extra" : "≈ +\(ms) ms por dictado"
	}

	// MARK: Gestos

	private func handle(_ event: GestureEvent) -> Bool {
		if case .otherKey = event { LiveDictation.userInput += 1 }
		let swallow = event == .escape && machine.swallowsEscape
		guard let action = machine.handle(event) else { return swallow }
		switch action {
		case .start: begin()
		case .lock: lock()
		case .stop: finish()
		case .cancel: abort(.cancelled)
		case .tooShort: abort(.short)
		case .chord: abort(nil)
		}
		return swallow
	}

	private func begin() {
		complete()
		guard modelStatus != .missing, !isDownloading else {
			machine.reset()
			flash(.noModel)
			return
		}
		guard micGranted else {
			machine.reset()
			flash(.failed("Falta permiso de micrófono"))
			return
		}
		do {
			try recorder.start()
		} catch {
			machine.reset()
			flash(.failed(error.localizedDescription))
			return
		}
		target = NSWorkspace.shared.frontmostApplication
		refreshPermissions()
		if settings.liveTyping, settings.autoPaste, accessibilityGranted {
			let dictation = LiveDictation(settings: settings, transcriber: transcriber, recorder: recorder)
			dictation.start(after: delivery)
			live = dictation
		}
		recordingStart = .now
		lastDictation = .now
		levels = Array(repeating: 0, count: Self.waveformBars)
		unloadTask?.cancel()
		show(.listening)
		play("Tink")
		startTicking()
		preload()
	}

	private func lock() {
		show(.locked)
		play("Pop")
	}

	private func finish() {
		stopTicking()
		lastDictation = .now
		recordingStart = nil
		tailTask = Task {
			try? await Task.sleep(for: Self.tail)
			guard !Task.isCancelled else { return }
			complete()
		}
	}

	/// Cierra la grabación después de la cola. Si empieza otro dictado antes, la cola se corta ahí.
	private func complete() {
		guard let tailTask else { return }
		tailTask.cancel()
		self.tailTask = nil
		live?.stopListening()
		let samples = recorder.stop()
		let seconds = Double(samples.count) / Recorder.sampleRate
		guard seconds >= machine.minHold else { return discardLive(.short) }
		guard LiveSession.hasVoice(samples) else { return discardLive(.silent) }
		show(.transcribing)
		play("Pop")
		let settings = settings
		let target = target
		if let live {
			self.live = nil
			delivery = Task {
				do {
					let (text, miss) = try await live.finish(samples)
					modelStatus = .ready
					guard !text.isEmpty else { return flash(.silent) }
					history.add(HistoryEntry(text: text, seconds: seconds, app: target?.localizedName))
					try? history.save(to: Self.historyURL)
					if let miss {
						show(.unpasted(miss))
						hide(after: 3)
					} else {
						show(.done(words: text.split(whereSeparator: \.isWhitespace).count, pasted: true))
						hide(after: 0.9)
					}
				} catch {
					flash(.failed("No se pudo transcribir"))
				}
				scheduleUnload()
			}
			return
		}
		let previous = delivery
		delivery = Task {
			do {
				let raw = try await transcriber.transcribe(samples, prompt: settings.prompt, language: settings.language)
				modelStatus = .ready
				let text = TextCleaner.clean(raw, replacements: settings.replacements, vocabulary: settings.vocabulary)
				guard !text.isEmpty else { return flash(.silent) }
				await previous?.value
				await deliver(text, seconds: seconds, app: target?.localizedName, settings: settings)
			} catch {
				flash(.failed("No se pudo transcribir"))
			}
			scheduleUnload()
		}
	}

	private func abort(_ reason: Pill?) {
		stopTicking()
		live?.stopListening()
		_ = recorder.stop()
		recordingStart = nil
		discardLive(reason)
	}

	/// Termina sin texto: borra lo que el dictado en vivo ya había escrito.
	private func discardLive(_ reason: Pill?) {
		if let live {
			self.live = nil
			delivery = Task { await live.cancel() }
		}
		if let reason { flash(reason) } else { hide(after: 0) }
	}

	private func deliver(_ dictated: String, seconds: Double, app: String?, settings: Preferences) async {
		refreshPermissions()
		let canPaste = settings.autoPaste && accessibilityGranted
		let (text, send) = settings.sendOnKeyword && canPaste
			? SendKeyword.split(dictated, keywords: settings.sendKeywords)
			: (dictated, false)
		let output = settings.trailingSpace && !send && !text.hasSuffix("\n") ? text + " " : text
		if !text.isEmpty {
			history.add(HistoryEntry(text: text, seconds: seconds, app: app))
			try? history.save(to: Self.historyURL)
		}
		guard canPaste else {
			Paster.copy(output)
			show(.done(words: text.split(whereSeparator: \.isWhitespace).count, pasted: false))
			return hide(after: 0.9)
		}
		guard await Paster.paste(output, restore: settings.restoreClipboard, thenReturn: send) else {
			show(.unpasted(.unread))
			return hide(after: 3)
		}
		show(.done(words: text.split(whereSeparator: \.isWhitespace).count, pasted: true))
		hide(after: 0.9)
	}

	private func startTicking() {
		tickTimer?.invalidate()
		tickTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
			MainActor.assumeIsolated { self?.tick() }
		}
	}

	private func stopTicking() {
		tickTimer?.invalidate()
		tickTimer = nil
	}

	private func tick() {
		if let action = machine.handle(.tick(ProcessInfo.processInfo.systemUptime)) {
			if action == .tooShort { abort(.short) }
			return
		}
		if let start = recordingStart, Date.now.timeIntervalSince(start) >= Double(settings.maxRecordingSeconds) {
			machine.reset()
			finish()
		}
	}

	private func push(_ level: Float) {
		guard recordingStart != nil else { return }
		let smoothed = max(level, (levels.last ?? 0) * 0.55)
		levels.removeFirst()
		levels.append(smoothed)
	}

	// MARK: Cápsula

	private func show(_ next: Pill) {
		hideTask?.cancel()
		pill = next
		guard settings.showPill || next.isWarning || next.isNotice else { return }
		overlay.show(self)
		if !pillVisible {
			withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) { pillVisible = true }
		}
	}

	private func flash(_ next: Pill) {
		show(next)
		hide(after: next == .noModel || next == .permission ? 1.8 : 0.8)
	}

	private func hide(after delay: Double) {
		hideTask?.cancel()
		hideTask = Task {
			try? await Task.sleep(for: .seconds(delay))
			guard !Task.isCancelled else { return }
			withAnimation(.easeOut(duration: 0.22)) { pillVisible = false }
			try? await Task.sleep(for: .milliseconds(260))
			guard !Task.isCancelled else { return }
			overlay.hide()
			pill = nil
		}
	}

	private func play(_ name: String) {
		guard settings.sounds, let sound = NSSound(named: name)?.copy() as? NSSound else { return }
		sound.volume = 0.25
		sound.play()
	}

	// MARK: Modelo

	func preload() {
		switch modelStatus {
		case .unloaded, .failed: break
		default: return
		}
		modelStatus = .loading
		Task {
			do {
				try await transcriber.load()
				modelStatus = .ready
				refreshPromptCost()
				scheduleUnload()
			} catch {
				modelStatus = .failed(error.localizedDescription)
			}
		}
	}

	func download() {
		guard modelStatus == .missing || modelStatus.isFailure else { return }
		modelStatus = .downloading(0)
		Task {
			do {
				try await transcriber.download { fraction in
					Task { @MainActor [weak self] in
						if case .downloading = self?.modelStatus { self?.modelStatus = .downloading(fraction) }
					}
				}
				modelStatus = Transcriber.isDownloaded ? .unloaded : .failed("La descarga quedó incompleta")
				preload()
			} catch {
				modelStatus = .failed(error.localizedDescription)
			}
		}
	}

	func unloadNow() {
		unloadTask?.cancel()
		Task {
			await transcriber.unload()
			if modelStatus == .ready { modelStatus = .unloaded }
		}
	}

	private func scheduleUnload() {
		unloadTask?.cancel()
		let minutes = settings.unloadAfterMinutes
		guard minutes > 0 else { return }
		unloadTask = Task {
			try? await Task.sleep(for: .seconds(Double(minutes) * 60))
			guard !Task.isCancelled, !machine.isRecording else { return }
			await transcriber.unload()
			if modelStatus == .ready { modelStatus = .unloaded }
		}
	}

	private func refreshPromptCost() {
		let prompt = settings.prompt
		Task { promptTokens = await transcriber.promptTokenCount(prompt) }
	}

	// MARK: Permisos y sistema

	func refreshPermissions() {
		guard !isSample else { return }
		micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
		accessibilityGranted = AXIsProcessTrusted()
		if accessibilityGranted, !hotkey.isRunning { hotkey.start() }
	}

	func requestMicrophone() {
		if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
			AVCaptureDevice.requestAccess(for: .audio) { _ in
				Task { @MainActor [weak self] in self?.refreshPermissions() }
			}
		} else {
			open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
		}
	}

	func requestAccessibility() {
		let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
		if !AXIsProcessTrustedWithOptions(options) {
			open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
		}
	}

	func startPermissionPolling() {
		permissionTimer?.invalidate()
		permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
			MainActor.assumeIsolated {
				guard let self else { return timer.invalidate() }
				self.refreshPermissions()
				if !self.needsSetup { timer.invalidate() }
			}
		}
	}

	func setLaunchAtLogin(_ on: Bool) {
		do {
			if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
		} catch {}
		launchAtLogin = SMAppService.mainApp.status == .enabled
	}

	func copyLast() {
		if let lastText { Paster.copy(lastText) }
	}

	func copy(_ entry: HistoryEntry) {
		Paster.copy(entry.text)
	}

	func clearHistory() {
		history.clear()
		try? history.save(to: Self.historyURL)
	}

	func revealModel() {
		NSWorkspace.shared.activateFileViewerSelecting([Transcriber.modelFolder])
	}

	private func open(_ url: String) {
		if let url = URL(string: url) { NSWorkspace.shared.open(url) }
	}
}

extension ModelStatus {
	var isFailure: Bool {
		if case .failed = self { return true }
		return false
	}
}
