import Foundation

@MainActor
enum MenuBarSpacingService {
    private static let spacingKey = "NSStatusItemSpacing" as CFString
    private static let paddingKey = "NSStatusItemSelectionPadding" as CFString
    private static let savedSpacingKey = "Barkeep.OriginalStatusItemSpacing"
    private static let savedPaddingKey = "Barkeep.OriginalStatusItemSelectionPadding"
    private static let hadSpacingKey = "Barkeep.HadOriginalStatusItemSpacing"
    private static let hadPaddingKey = "Barkeep.HadOriginalStatusItemSelectionPadding"
    private static let changedKey = "Barkeep.ChangedStatusItemSpacing"

    static func apply(settings: BarkeepSettings) {
        if settings.reduceItemSpacing {
            saveOriginalValuesOnce()
            set(settings.itemSpacing, for: spacingKey)
            set(settings.itemPadding, for: paddingKey)
        } else if UserDefaults.standard.bool(forKey: changedKey) {
            restore(savedKey: savedSpacingKey, hadValueKey: hadSpacingKey, systemKey: spacingKey)
            restore(savedKey: savedPaddingKey, hadValueKey: hadPaddingKey, systemKey: paddingKey)
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
        saveOriginal(systemKey: spacingKey, savedKey: savedSpacingKey, hadValueKey: hadSpacingKey)
        saveOriginal(systemKey: paddingKey, savedKey: savedPaddingKey, hadValueKey: hadPaddingKey)
        UserDefaults.standard.set(true, forKey: changedKey)
    }

    private static func saveOriginal(systemKey: CFString, savedKey: String, hadValueKey: String) {
        if let value = CFPreferencesCopyValue(
            systemKey,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        ) as? NSNumber {
            UserDefaults.standard.set(value.intValue, forKey: savedKey)
            UserDefaults.standard.set(true, forKey: hadValueKey)
        } else {
            UserDefaults.standard.removeObject(forKey: savedKey)
            UserDefaults.standard.set(false, forKey: hadValueKey)
        }
    }

    private static func restore(savedKey: String, hadValueKey: String, systemKey: CFString) {
        if UserDefaults.standard.bool(forKey: hadValueKey) {
            set(UserDefaults.standard.integer(forKey: savedKey), for: systemKey)
        } else {
            set(nil, for: systemKey)
        }
        UserDefaults.standard.removeObject(forKey: savedKey)
        UserDefaults.standard.removeObject(forKey: hadValueKey)
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
