import Foundation
import AppKit

/// Keeps the keyboard's firmware-rendered clock correct without streaming images.
final class TimeSync: ObservableObject, @unchecked Sendable {
    static let shared = TimeSync()

    @Published var enabled: Bool {
        didSet {
            guard enabled != oldValue else { return }
            if persistsPreferences {
                UserDefaults.standard.set(enabled, forKey: "timeSyncEnabled")
            }
            enabled ? start() : stop()
        }
    }
    @Published private(set) var lastSync = "Not synced yet"
    @Published private(set) var lastSyncDate: Date?

    private let period: TimeInterval = 1800
    private let persistsPreferences: Bool
    private weak var device: AulaDevice?
    private var timer: Timer?
    private var requestSequence: UInt64 = 0
    private var automaticGeneration: UInt64 = 0
    private var activeRequest: UInt64?
    private var manualSyncPending = false
    private var defaultObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var isObserving = false

    init(persistPreferences: Bool = true, enabled override: Bool? = nil) {
        self.persistsPreferences = persistPreferences
        if let override {
            self.enabled = override
        } else if persistPreferences {
            self.enabled = UserDefaults.standard.object(forKey: "timeSyncEnabled") as? Bool ?? true
            self.lastSyncDate = UserDefaults.standard.object(forKey: "lastClockSyncDate") as? Date
        } else {
            self.enabled = false
        }
        if let date = lastSyncDate { lastSync = Self.display(date, prefix: "Last synced") }
    }

    deinit {
        timer?.invalidate()
        defaultObservers.forEach(NotificationCenter.default.removeObserver)
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    func attach(_ device: AulaDevice) {
        guard self.device !== device else { return }
        self.device = device
        installObservers()
        if enabled { start() }
    }

    private func installObservers() {
        guard !isObserving else { return }
        isObserving = true
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            .aulaDeviceConnected,
            NSNotification.Name.NSSystemClockDidChange,
            NSNotification.Name.NSSystemTimeZoneDidChange,
        ]
        defaultObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self, self.enabled else { return }
                self.syncAutomatically()
            }
        }
        workspaceObservers = [
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                guard let self, self.enabled else { return }
                self.syncAutomatically()
            }
        ]
    }

    private func start() {
        guard device != nil else { return }
        syncAutomatically()
        timer?.invalidate()
        let next = Timer(timeInterval: period, repeats: true) { [weak self] _ in self?.syncAutomatically() }
        RunLoop.main.add(next, forMode: .common)
        timer = next
        alog("clock: syncing keyboard RTC every \(Int(period / 60)) min and after wake/time changes")
    }

    private func stop() {
        timer?.invalidate(); timer = nil
        // The physical request cannot be cancelled halfway through its envelope.
        // Leave it in flight, but invalidate its automatic status update.
        automaticGeneration &+= 1
        lastSync = "Automatic sync is off"
        alog("clock: RTC sync off")
    }

    func syncNow() {
        requestSync(automatic: false)
    }

    private func syncAutomatically() {
        guard enabled else { return }
        requestSync(automatic: true)
    }

    private func requestSync(automatic: Bool) {
        guard let device else { return }
        guard activeRequest == nil else {
            if !automatic { manualSyncPending = true }
            return
        }
        let sentAt = Date()
        requestSequence &+= 1
        let request = requestSequence
        let generation = automaticGeneration
        activeRequest = request
        lastSync = "Syncing…"
        // Compensate for the observed one-second lag on the keyboard's display.
        // Keep sentAt unchanged so sync history records the actual request time.
        device.apply(.time(sentAt.addingTimeInterval(1))) { [weak self] result in
            guard let self, self.activeRequest == request else { return }
            self.activeRequest = nil
            if automatic && (!self.enabled || self.automaticGeneration != generation) {
                // An old automatic completion must not overwrite the user's Off
                // state, or clear a newer logical request after a rapid toggle.
                if self.manualSyncPending {
                    self.manualSyncPending = false
                    self.requestSync(automatic: false)
                } else if self.enabled {
                    self.syncAutomatically()
                }
                return
            }
            switch result {
            case .success:
                self.lastSyncDate = sentAt
                self.lastSync = Self.display(sentAt, prefix: "Last synced")
                if self.persistsPreferences {
                    UserDefaults.standard.set(sentAt, forKey: "lastClockSyncDate")
                }
            case .failure(.superseded):
                break
            case .failure(let error):
                self.lastSync = "Not synced · \(error.localizedDescription)"
            }
            if self.manualSyncPending {
                self.manualSyncPending = false
                self.requestSync(automatic: false)
            }
        }
    }

    private static func display(_ date: Date, prefix: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMMjms")
        return "\(prefix) \(formatter.string(from: date))"
    }
}
