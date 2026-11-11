import AppKit
import LabiaCore
import Sparkle

/// Actualizaciones automáticas con Sparkle 2 (`updates/plan.md`).
///
/// Sparkle revisa el feed del canal, baja el `.zip`, comprueba su firma EdDSA y lo deja listo. Labia lo instala
/// sólo en reposo: sin dictado en curso y con al menos `idleBeforeInstall` desde el último. Al instalar,
/// Sparkle cierra Labia, reemplaza la app y la vuelve a abrir; la versión nueva avisa con la cápsula.
@MainActor
final class Updater: NSObject {
	nonisolated static let idleBeforeInstall: TimeInterval = 60
	/// Para probar con un feed local (`defaults write io.github.reydavidag.labia updateFeedURL http://…`).
	nonisolated static let feedOverrideKey = "updateFeedURL"
	/// La versión de la que venimos, para avisar después de reiniciar.
	nonisolated static let updatedFromKey = "updatedFrom"

	static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
	static var commit: String? { Bundle.main.object(forInfoDictionaryKey: "LabiaCommit") as? String }

	/// Sin llave pública (compilación local sin configurar) Sparkle no puede verificar nada: no se activa.
	static var isConfigured: Bool {
		let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
		return !key.isEmpty && !key.hasPrefix("__") && Bundle.main.bundleURL.pathExtension == "app"
	}

	/// Qué tan ocupada está Labia: lo consulta antes de instalar.
	var isBusy: () -> Bool = { false }
	var lastActivity: () -> Date = { .distantPast }
	var channel: UpdateChannel = .stable

	private var controller: SPUStandardUpdaterController?
	private var install: (() -> Void)?
	private var idleTimer: Timer?

	var isRunning: Bool { controller != nil }
	var canCheck: Bool { controller?.updater.canCheckForUpdates ?? false }
	var lastCheck: Date? { controller?.updater.lastUpdateCheckDate }

	func start(settings: Preferences) {
		channel = settings.updateChannel
		guard Self.isConfigured, controller == nil else { return }
		let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
		do {
			try controller.updater.start()
		} catch {
			NSLog("Labia: Sparkle no arrancó: \(error.localizedDescription)")
			return
		}
		self.controller = controller
		apply(settings)
	}

	/// Interruptor y canal de Ajustes. Cambiar de canal busca de inmediato, no en 6 h.
	func apply(_ settings: Preferences) {
		let changed = settings.updateChannel != channel
		channel = settings.updateChannel
		guard let updater = controller?.updater else { return }
		updater.automaticallyChecksForUpdates = settings.autoUpdate
		updater.automaticallyDownloadsUpdates = settings.autoUpdate
		if changed, settings.autoUpdate { updater.checkForUpdatesInBackground() }
	}

	/// «Buscar actualizaciones»: con la ventana de Sparkle, que dice si estás al día o qué trae la nueva.
	func checkNow() {
		controller?.checkForUpdates(nil)
		AppWindows.bringForward()
	}

	/// La versión nueva arranca y avisa una sola vez.
	static func takeNotice() -> String? {
		let defaults = UserDefaults.standard
		guard let from = defaults.string(forKey: updatedFromKey) else { return nil }
		defaults.removeObject(forKey: updatedFromKey)
		return from == version ? nil : version
	}

	private func installWhenIdle() {
		idleTimer?.invalidate()
		idleTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
			MainActor.assumeIsolated { self?.tryInstall() }
		}
		tryInstall()
	}

	private func tryInstall() {
		guard let install, !isBusy(), Date.now.timeIntervalSince(lastActivity()) >= Self.idleBeforeInstall else { return }
		idleTimer?.invalidate()
		idleTimer = nil
		self.install = nil
		UserDefaults.standard.set(Self.version, forKey: Self.updatedFromKey)
		install()
	}
}

extension Updater: SPUUpdaterDelegate {
	nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
		if let override = UserDefaults.standard.string(forKey: Updater.feedOverrideKey), !override.isEmpty { return override }
		return Preferences.load().updateChannel.feedURL
	}

	/// Sparkle ya bajó y verificó la versión nueva y la instalaría al salir; la instalamos antes, en reposo.
	nonisolated func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock: @escaping () -> Void) -> Bool {
		MainActor.assumeIsolated {
			install = immediateInstallationBlock
			installWhenIdle()
		}
		return true
	}

	nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
		NSLog("Labia: actualización cancelada: \(error.localizedDescription)")
	}
}

extension Updater: SPUStandardUserDriverDelegate {
	/// Labia vive en la barra de menú: si las descargas automáticas están apagadas, Sparkle muestra el aviso
	/// de versión nueva sin robar el foco.
	nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }
}
