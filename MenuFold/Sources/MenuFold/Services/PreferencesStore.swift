import Foundation

final class PreferencesStore {
    private let defaults: UserDefaults
    private let key = "MenuFold.preferences.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppPreferences {
        guard let data = defaults.data(forKey: key),
              let preferences = try? decoder.decode(AppPreferences.self, from: data)
        else {
            return AppPreferences()
        }
        return preferences
    }

    func save(_ preferences: AppPreferences) {
        guard let data = try? encoder.encode(preferences) else { return }
        defaults.set(data, forKey: key)
    }
}
