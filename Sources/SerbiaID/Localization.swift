import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case ru, en, sr
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ru: return "Русский"
        case .en: return "English"
        case .sr: return "Srpski"
        }
    }
}

/// Runtime-switchable localization (no app restart needed).
final class Loc: ObservableObject {
    @AppStorage("language") private var stored: String = Loc.systemDefault().rawValue
    @Published var language: AppLanguage = .en {
        didSet { stored = language.rawValue }
    }

    init() {
        language = AppLanguage(rawValue: stored) ?? .en
    }

    static func systemDefault() -> AppLanguage {
        let code = Locale.preferredLanguages.first?.prefix(2).lowercased() ?? "en"
        switch code {
        case "ru": return .ru
        case "sr", "hr", "bs": return .sr
        default: return .en
        }
    }

    func t(_ key: L) -> String {
        Self.table[key]?[language] ?? Self.table[key]?[.en] ?? "\(key)"
    }

    enum L: Hashable {
        case appTitle, tabPersonal, tabToken, tabAbout
        case reader, noReader, refresh, readCard, cardPresent, noCard, atr
        case surname, givenName, parentName, dob, placeOfBirth, sex, jmbg
        case docNumber, issuedBy, issueDate, expiryDate, address, portrait
        case certificates, changePin, currentPin, newPin, confirmPin, pinMismatch
        case pinChanged, pinFailed, verifySignature, export
        case notImplemented, error, ok, cancel, language, aboutText
        case nationality, docSerial, pinUnsupported, sigOk, sigChain, sigBad
        case readToken, chainOk, pinNote, printCard
        case certMoiCA, certAuth, certSign, certSigFixed, certSigVariable
    }

    // swiftlint:disable line_length
    static let table: [L: [AppLanguage: String]] = [
        .printCard: [.ru: "Печать / PDF", .en: "Print / PDF", .sr: "Štampa / PDF"],
        .readToken: [.ru: "Прочитать токен", .en: "Read token", .sr: "Pročitaj token"],
        .chainOk: [.ru: "Цепочка доверия до МУП подтверждена", .en: "Chain to MUP CA verified", .sr: "Lanac poverenja do MUP-a potvrđen"],
        .pinNote: [.ru: "Чтение токена не использует PIN. Подпись документов токеном пока не поддерживается.", .en: "Reading the token does not use the PIN. Signing with the token is not supported yet.", .sr: "Čitanje tokena ne koristi PIN. Potpisivanje tokenom još nije podržano."],
        .sigOk: [.ru: "Подпись верна, данные не изменены", .en: "Signature valid, data unmodified", .sr: "Potpis je ispravan, podaci nisu menjani"],
        .sigChain: [.ru: "Не удалось построить цепочку доверия (это не значит, что данные неверны)", .en: "Trust chain could not be established (does not mean the data is invalid)", .sr: "Nije uspostavljen lanac poverenja (ne znači da podaci nisu ispravni)"],
        .sigBad: [.ru: "Подпись неверна или данные изменены", .en: "Signature invalid or data modified", .sr: "Potpis nije ispravan ili su podaci izmenjeni"],
        .nationality: [.ru: "Гражданство", .en: "Nationality", .sr: "Državljanstvo"],
        .docSerial: [.ru: "Серийный номер документа", .en: "Document serial number", .sr: "Serijski broj dokumenta"],
        .pinUnsupported: [.ru: "Смена PIN доступна только для старой карты (до 18.08.2014)", .en: "PIN change is available only for the old card (issued before 18.08.2014)", .sr: "Promena PIN-a je moguća samo za staru karticu (pre 18.08.2014)"],
        .certMoiCA: [.ru: "Промежуточный сертификат МВД", .en: "MoI intermediate CA", .sr: "Posrednički sertifikat MUP-a"],
        .certAuth: [.ru: "Сертификат аутентификации", .en: "Authentication certificate", .sr: "Sertifikat za autentikaciju"],
        .certSign: [.ru: "Сертификат подписи", .en: "Signing certificate", .sr: "Sertifikat za potpisivanje"],
        .certSigFixed: [.ru: "Подписант неизменяемых данных", .en: "Fixed-data signer", .sr: "Potpisnik nepromenljivih podataka"],
        .certSigVariable: [.ru: "Подписант изменяемых данных", .en: "Variable-data signer", .sr: "Potpisnik promenljivih podataka"],
        .appTitle: [.ru: "Электронная ID-карта Сербии", .en: "Serbian eID Card", .sr: "Elektronska lična karta"],
        .tabPersonal: [.ru: "Личные данные", .en: "Personal data", .sr: "Lični podaci"],
        .tabToken: [.ru: "Токен и сертификаты", .en: "Token & certificates", .sr: "Token i sertifikati"],
        .tabAbout: [.ru: "О программе", .en: "About", .sr: "O programu"],
        .reader: [.ru: "Считыватель", .en: "Reader", .sr: "Čitač"],
        .noReader: [.ru: "Считыватель не найден", .en: "No reader found", .sr: "Čitač nije pronađen"],
        .refresh: [.ru: "Обновить", .en: "Refresh", .sr: "Osveži"],
        .readCard: [.ru: "Прочитать карту", .en: "Read card", .sr: "Pročitaj karticu"],
        .cardPresent: [.ru: "Карта вставлена", .en: "Card inserted", .sr: "Kartica je umetnuta"],
        .noCard: [.ru: "Карты нет", .en: "No card", .sr: "Nema kartice"],
        .atr: [.ru: "ATR", .en: "ATR", .sr: "ATR"],
        .surname: [.ru: "Фамилия", .en: "Surname", .sr: "Prezime"],
        .givenName: [.ru: "Имя", .en: "Given name", .sr: "Ime"],
        .parentName: [.ru: "Имя родителя", .en: "Parent's name", .sr: "Ime roditelja"],
        .dob: [.ru: "Дата рождения", .en: "Date of birth", .sr: "Datum rođenja"],
        .placeOfBirth: [.ru: "Место рождения", .en: "Place of birth", .sr: "Mesto rođenja"],
        .sex: [.ru: "Пол", .en: "Sex", .sr: "Pol"],
        .jmbg: [.ru: "ЕМБГ", .en: "Personal ID (JMBG)", .sr: "JMBG"],
        .docNumber: [.ru: "Номер документа", .en: "Document number", .sr: "Broj dokumenta"],
        .issuedBy: [.ru: "Кем выдан", .en: "Issued by", .sr: "Izdaje"],
        .issueDate: [.ru: "Дата выдачи", .en: "Issue date", .sr: "Datum izdavanja"],
        .expiryDate: [.ru: "Действителен до", .en: "Valid until", .sr: "Važi do"],
        .address: [.ru: "Адрес", .en: "Address", .sr: "Adresa"],
        .portrait: [.ru: "Фото", .en: "Portrait", .sr: "Fotografija"],
        .certificates: [.ru: "Сертификаты", .en: "Certificates", .sr: "Sertifikati"],
        .changePin: [.ru: "Сменить PIN", .en: "Change PIN", .sr: "Promena PIN-a"],
        .currentPin: [.ru: "Текущий PIN", .en: "Current PIN", .sr: "Trenutni PIN"],
        .newPin: [.ru: "Новый PIN", .en: "New PIN", .sr: "Novi PIN"],
        .confirmPin: [.ru: "Повторите новый PIN", .en: "Confirm new PIN", .sr: "Potvrdite novi PIN"],
        .pinMismatch: [.ru: "PIN-коды не совпадают", .en: "PINs do not match", .sr: "PIN-ovi se ne poklapaju"],
        .pinChanged: [.ru: "PIN изменён", .en: "PIN changed", .sr: "PIN je promenjen"],
        .pinFailed: [.ru: "Не удалось сменить PIN", .en: "PIN change failed", .sr: "Promena PIN-a nije uspela"],
        .verifySignature: [.ru: "Проверить подпись", .en: "Verify signature", .sr: "Proveri potpis"],
        .export: [.ru: "Экспорт", .en: "Export", .sr: "Izvoz"],
        .notImplemented: [.ru: "Эта функция ещё не реализована: нужен протокол карты", .en: "Not implemented yet: card protocol required", .sr: "Još nije implementirano: potreban je protokol kartice"],
        .error: [.ru: "Ошибка", .en: "Error", .sr: "Greška"],
        .ok: [.ru: "ОК", .en: "OK", .sr: "U redu"],
        .cancel: [.ru: "Отмена", .en: "Cancel", .sr: "Otkaži"],
        .language: [.ru: "Язык", .en: "Language", .sr: "Jezik"],
        .aboutText: [.ru: "Единое приложение для чтения электронной ID-карты и управления токеном. Независимая реализация для macOS.", .en: "A single app for reading the electronic ID card and managing the token. Independent macOS implementation.", .sr: "Jedinstvena aplikacija za čitanje elektronske lične karte i upravljanje tokenom. Nezavisna implementacija za macOS."]
    ]
}
