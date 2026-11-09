import Foundation

/// One displayable field of the card.
struct Row: Identifiable {
    let id: String          // stable key (also used as JSON key)
    let label: Loc.L
    let value: String
    var sensitive: Bool { ["jmbg", "address", "docNumber", "docSerial"].contains(id) }
}

extension PersonalData {
    func rows(includeJmbg: Bool = true) -> [Row] {
        let f = fixed, d = document
        var r: [Row] = [Row(id: "surname", label: .surname, value: f.surname),
                        Row(id: "givenName", label: .givenName, value: f.givenName)]
        if (cardType == .id2008 || cardType == .id2014), !f.parentGivenName.isEmpty {
            r.append(Row(id: "parentName", label: .parentName, value: f.parentGivenName))
        }
        r.append(Row(id: "dob", label: .dob, value: f.dateOfBirth))
        r.append(Row(id: "sex", label: .sex, value: f.sex))
        r.append(Row(id: "placeOfBirth", label: .placeOfBirth,
                     value: [f.placeOfBirth, f.communityOfBirth, f.stateOfBirth].filter { !$0.isEmpty }.joined(separator: ", ")))
        if !f.nationalityFull.isEmpty { r.append(Row(id: "nationality", label: .nationality, value: f.nationalityFull)) }
        if includeJmbg { r.append(Row(id: "jmbg", label: .jmbg, value: f.personalNumber)) }
        r.append(Row(id: "address", label: .address, value: variable.formatted))
        r.append(Row(id: "docNumber", label: .docNumber, value: d.docRegNo))
        if !d.documentSerialNumber.isEmpty { r.append(Row(id: "docSerial", label: .docSerial, value: d.documentSerialNumber)) }
        r.append(Row(id: "issuedBy", label: .issuedBy, value: d.issuingAuthority))
        r.append(Row(id: "issueDate", label: .issueDate, value: d.issuingDate))
        r.append(Row(id: "expiryDate", label: .expiryDate, value: d.expiryDate))
        return r
    }

    var expiryDate: Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "dd.MM.yyyy"
        return f.date(from: document.expiryDate)
    }
}

func daysUntil(_ date: Date) -> Int {
    let cal = Calendar.current
    return cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: date)).day ?? 0
}
