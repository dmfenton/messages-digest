// Turn phone numbers and emails into contact names.
//
// Uses the Contacts framework, so the APP asks for its own Contacts permission (a separate,
// narrower grant than Full Disk Access). If it is denied, names are simply left out.

import Contacts
import Foundation

struct ContactNames {
    let status: String                 // "authorized", "denied", "restricted", "not_determined"
    private let byKey: [String: String]

    func name(for handle: String?) -> String? {
        guard let handle else { return nil }
        return byKey[Self.key(handle)]
    }

    // Phone numbers match on their last 10 digits ("+1 (706) 555-0100" == "7065550100");
    // emails match case-insensitively.
    static func key(_ handle: String) -> String {
        if handle.contains("@") { return handle.lowercased() }
        let digits = handle.filter(\.isNumber)
        return String(digits.suffix(10))
    }

    static func load() -> ContactNames {
        let store = CNContactStore()
        if CNContactStore.authorizationStatus(for: .contacts) == .notDetermined {
            let done = DispatchSemaphore(value: 0)
            store.requestAccess(for: .contacts) { _, _ in done.signal() }
            _ = done.wait(timeout: .now() + 120)  // limit: time for the owner to answer the prompt
        }

        let status = CNContactStore.authorizationStatus(for: .contacts)
        guard status == .authorized else {
            return ContactNames(status: describe(status), byKey: [:])
        }

        let keys = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ]
        var byKey: [String: String] = [:]
        try? store.enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { contact, _ in
            guard let name = CNContactFormatter.string(from: contact, style: .fullName), !name.isEmpty
            else { return }
            for phone in contact.phoneNumbers { byKey[key(phone.value.stringValue)] = name }
            for email in contact.emailAddresses { byKey[key(email.value as String)] = name }
        }
        return ContactNames(status: "authorized", byKey: byKey)
    }

    private static func describe(_ status: CNAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "not_determined"
        default: return "limited_or_unknown"
        }
    }
}
