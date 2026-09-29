//
//  KeychainCredentialStore.swift
//  GoldenArchive
//
//  Data layer — the optional catalog API key lives in the Keychain, never
//  in the archive file or in backups.
//

import Foundation
import Security

final class KeychainCredentialStore: CredentialStore {
    private let service = "app.GoldenArchive.catalog"
    private let account = "numista-api-key"

    func numistaAPIKey() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty
        else { return nil }
        return key
    }

    func setNumistaAPIKey(_ key: String?) {
        SecItemDelete(baseQuery as CFDictionary)
        guard let key = key?.trimmed, !key.isEmpty, let data = key.data(using: .utf8) else { return }
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
