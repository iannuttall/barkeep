import Combine
import Foundation
import Sparkle

@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    @Published private(set) var pendingVersion: String?

    private var controller: SPUStandardUpdaterController?
    private let observer = UpdateWindowObserver()

    var onWillShowWindow: (@MainActor () -> Void)?

    var isConfigured: Bool {
        controller != nil
    }

    var canCheckForUpdates: Bool {
        controller?.updater.canCheckForUpdates ?? false
    }

    private init() {
        guard Self.configurationValue("SUFeedURL") != nil,
              Self.configurationValue("SUPublicEDKey") != nil else {
            return
        }

        observer.willShowWindow = { [weak self] in
            self?.onWillShowWindow?()
        }
        observer.foundScheduledUpdate = { [weak self] version in
            self?.pendingVersion = version
        }
        observer.didFinish = { [weak self] in
            self?.pendingVersion = nil
        }

        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: observer
        )
    }

    func checkForUpdates() {
        controller?.updater.checkForUpdates()
    }

    private static func configurationValue(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty,
              !value.hasPrefix("REPLACE_") else {
            return nil
        }
        return value
    }
}

private final class UpdateWindowObserver: NSObject, SPUStandardUserDriverDelegate, @unchecked Sendable {
    var willShowWindow: (@MainActor () -> Void)?
    var foundScheduledUpdate: (@MainActor (String) -> Void)?
    var didFinish: (@MainActor () -> Void)?

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard handleShowingUpdate else {
            MainActor.assumeIsolated {
                foundScheduledUpdate?(update.displayVersionString)
            }
            return
        }
        notifyBeforeWindow()
    }

    func standardUserDriverWillShowModalAlert() {
        notifyBeforeWindow()
    }

    func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { didFinish?() }
    }

    private func notifyBeforeWindow() {
        MainActor.assumeIsolated { willShowWindow?() }
    }
}
