import Foundation

enum DirectPurchaseConfig {
    static let displayPrice = "$4.99"
    static let purchaseURL = URL(string: "https://tappy-plum.vercel.app/#buy")!
    static let gumroadProductID = "rejkbe"
}

@MainActor
final class DirectLicenseStore: ObservableObject {
    private enum DefaultsKey {
        static let licenseKey = "Tappy.directLicenseKey"
        static let unlocked = "Tappy.directLicenseUnlocked"
    }

    private static let verifyURL = URL(string: "https://api.gumroad.com/v2/licenses/verify")!

    @Published private(set) var hasUnlockedPremium: Bool
    @Published private(set) var isActivating = false
    @Published private(set) var isValidating = false
    @Published private(set) var lastMessage: String?

    var onUnlockStateChange: ((Bool) -> Void)?

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        hasUnlockedPremium = userDefaults.bool(forKey: DefaultsKey.unlocked)
            && userDefaults.string(forKey: DefaultsKey.licenseKey) != nil
    }

    var isBusy: Bool {
        isActivating || isValidating
    }

    var hasSavedLicense: Bool {
        storedLicenseKey != nil
    }

    func activate(licenseKey rawLicenseKey: String) async {
        let licenseKey = rawLicenseKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !licenseKey.isEmpty else {
            lastMessage = "Paste your Gumroad license key first."
            return
        }

        guard !isBusy else {
            lastMessage = "A license check is already running."
            return
        }

        guard !Self.productID.isEmpty else {
            lastMessage = "Gumroad checkout is not connected yet. Add the Gumroad product ID before activating licenses."
            return
        }

        isActivating = true
        defer { isActivating = false }

        do {
            let response = try await verify(licenseKey: licenseKey, shouldIncrementUses: true)

            guard response.grantsAccess else {
                lastMessage = response.userFacingError ?? "That license key could not be activated."
                return
            }

            userDefaults.set(licenseKey, forKey: DefaultsKey.licenseKey)
            applyUnlocked(true)
            lastMessage = "Gumroad license activated. Premium ASMR packs unlocked."
        } catch {
            lastMessage = "License activation failed: \(error.localizedDescription)"
        }
    }

    func validateSavedLicense() async {
        guard let licenseKey = storedLicenseKey else {
            lastMessage = nil
            applyUnlocked(false)
            return
        }

        guard !isBusy else { return }
        guard !Self.productID.isEmpty else { return }

        isValidating = true
        defer { isValidating = false }

        do {
            let response = try await verify(licenseKey: licenseKey, shouldIncrementUses: false)

            if response.grantsAccess {
                applyUnlocked(true)
                lastMessage = nil
            } else {
                clearSavedLicense()
                lastMessage = response.userFacingError ?? "That license is no longer valid."
            }
        } catch {
            if hasUnlockedPremium {
                lastMessage = "License could not be checked, so your activated ASMR packs remain available offline."
            } else {
                lastMessage = "License check failed: \(error.localizedDescription)"
            }
        }
    }

    func clearSavedLicense() {
        userDefaults.removeObject(forKey: DefaultsKey.licenseKey)
        applyUnlocked(false)
    }

    private var storedLicenseKey: String? {
        userDefaults.string(forKey: DefaultsKey.licenseKey)
    }

    private static var productID: String {
        DirectPurchaseConfig.gumroadProductID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func verify(licenseKey: String, shouldIncrementUses: Bool) async throws -> LicenseAPIResponse {
        var request = URLRequest(url: Self.verifyURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Self.formURLEncoded([
            "product_id": Self.productID,
            "license_key": licenseKey,
            "increment_uses_count": shouldIncrementUses ? "true" : "false",
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        let decoder = JSONDecoder()

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            if let decoded = try? decoder.decode(LicenseAPIResponse.self, from: data),
               let message = decoded.userFacingError {
                throw LicenseError.api(message)
            }

            throw LicenseError.api("Gumroad returned an unexpected response.")
        }

        return try decoder.decode(LicenseAPIResponse.self, from: data)
    }

    private func applyUnlocked(_ unlocked: Bool) {
        let changed = hasUnlockedPremium != unlocked
        hasUnlockedPremium = unlocked
        userDefaults.set(unlocked, forKey: DefaultsKey.unlocked)

        if changed {
            onUnlockStateChange?(unlocked)
        }
    }

    private static func formURLEncoded(_ parameters: [String: String]) -> Data? {
        parameters
            .map { "\(percentEncode($0.key))=\(percentEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)
    }

    private static func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

private struct LicenseAPIResponse: Decodable {
    let success: Bool
    let uses: Int?
    let message: String?
    let error: String?
    let purchase: LicensePurchase?

    var grantsAccess: Bool {
        guard success else { return false }
        guard purchase?.refunded != true else { return false }
        guard purchase?.chargebacked != true else { return false }
        guard purchase?.disputed != true else { return false }
        return true
    }

    var userFacingError: String? {
        if let message, !message.isEmpty {
            return message
        }

        if let error, !error.isEmpty {
            return error
        }

        if purchase?.refunded == true {
            return "That Gumroad purchase was refunded."
        }

        if purchase?.chargebacked == true || purchase?.disputed == true {
            return "That Gumroad purchase is disputed."
        }

        return nil
    }
}

private struct LicensePurchase: Decodable {
    let email: String?
    let refunded: Bool?
    let disputed: Bool?
    let chargebacked: Bool?
    let test: Bool?

    private enum CodingKeys: String, CodingKey {
        case email
        case refunded
        case disputed
        case chargebacked
        case test
    }
}

private enum LicenseError: LocalizedError {
    case api(String)

    var errorDescription: String? {
        switch self {
        case .api(let message):
            return message
        }
    }
}
