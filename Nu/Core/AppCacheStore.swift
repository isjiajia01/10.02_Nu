import Foundation

struct AppCacheStore {
    private let store: KeyValueStoring

    static let shared = AppCacheStore(store: UserDefaults.standard)

    init(store: KeyValueStoring) {
        self.store = store
    }

    func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        store.set(data, forKey: key)
        store.set(Date().timeIntervalSince1970, forKey: key + "_ts")
    }

    func load<T: Decodable>(_ type: T.Type, key: String) -> (value: T, timestamp: Date)? {
        guard let data = store.data(forKey: key),
              let value = try? JSONDecoder().decode(T.self, from: data) else {
            return nil
        }
        let raw = store.double(forKey: key + "_ts")
        let ts = raw > 0 ? Date(timeIntervalSince1970: raw) : Date.distantPast
        return (value, ts)
    }

    static func save<T: Encodable>(_ value: T, key: String) {
        shared.save(value, key: key)
    }

    static func load<T: Decodable>(_ type: T.Type, key: String) -> (value: T, timestamp: Date)? {
        shared.load(type, key: key)
    }
}
