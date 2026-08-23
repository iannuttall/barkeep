import Foundation

@MainActor
enum MenuBarSpacingService {
    private static let spacingKey = "NSStatusItemSpacing" as CFString
    private static let paddingKey = "NSStatusItemSelectionPadding" as CFString
    private static let savedSpacingKey = "Barkeep.OriginalStatusItemSpacing"
    private static let savedPaddingKey = "Barkeep.OriginalStatusItemSelectionPadding"
    private static let changedKey = "Barkeep.ChangedStatusItemSpacing"

    static func apply(settings: BarkeepSettings) {
        if settings.reduceItemSpacing {
            saveOriginalValuesOnce()
            set(settings.itemSpacing, for: spacingKey)
            set(settings.itemPadding, for: paddingKey)
        } else if UserDefaults.standard.bool(forKey: changedKey) {
            restore(savedKey: savedSpacingKey, systemKey: spacingKey)
            restore(savedKey: savedPaddingKey, systemKey: paddingKey)
            UserDefaults.standard.removeObject(forKey: changedKey)
        }
        CFPreferencesSynchronize(
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
    }

    private static func saveOriginalValuesOnce() {
        guard !UserDefaults.standard.bool(forKey: changedKey) else { return }
        saveOriginal(systemKey: spacingKey, savedKey: savedSpacingKey)
        saveOriginal(systemKey: paddingKey, savedKey: savedPaddingKey)
        UserDefaults.standard.set(true, forKey: changedKey)
    }

    private static func saveOriginal(systemKey: CFString, savedKey: String) {
        if let value = CFPreferencesCopyValue(
            systemKey,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        ) as? NSNumber {
            UserDefaults.standard.set(value.intValue, forKey: savedKey)
        } else {
            UserDefaults.standard.set(NSNull(), forKey: savedKey)
        }
    }

    private static func restore(savedKey: String, systemKey: CFString) {
        let saved = UserDefaults.standard.object(forKey: savedKey)
        if let number = saved as? NSNumber {
            set(number.intValue, for: systemKey)
        } else {
            set(nil, for: systemKey)
        }
        UserDefaults.standard.removeObject(forKey: savedKey)
    }

    private static func set(_ value: Int?, for key: CFString) {
        CFPreferencesSetValue(
            key,
            value.map(NSNumber.init(value:)),
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
    }
}
