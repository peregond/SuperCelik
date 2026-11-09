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
    static let shared = Loc()
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
        case readToken, chainOk, pinNote, printCard, savePdf, pdfSaved, version, checkUpdates
        case updateAvailable, updateNow, updateDownloading, upToDate, updateUnavailable, updateFailed
        case brandSub, hintRead, hintToken, docID, docIF, docRP
        case tabSettings, setAppearance, setTheme, themeSystem, themeLight, themeDark, setPrivacy, setMask, setAutoHide
        case setBehavior, setAutoRead, setPrintJmbg, setAutoUpdate, copy, reveal, hideValue, more, copyAll, savePhoto, exportJson
        case expiresIn, expiredOn, certIssuer, certValid, exportCert, preview, close, copied, autoHidden
        case errNoReaderT, errNoReaderH, errNoCardT, errNoCardH, errUnsupportedT, errUnsupportedH, errGenericT, errGenericH, techDetails
        case certMoiCA, certAuth, certSign, certSigFixed, certSigVariable
    }

    // swiftlint:disable line_length
    static let table: [L: [AppLanguage: String]] = [
        .tabSettings: [.ru: "Настройки", .en: "Settings", .sr: "Podešavanja"],
        .setAppearance: [.ru: "Оформление", .en: "Appearance", .sr: "Izgled"],
        .setTheme: [.ru: "Тема", .en: "Theme", .sr: "Tema"],
        .themeSystem: [.ru: "Как в системе", .en: "System", .sr: "Sistemska"],
        .themeLight: [.ru: "Светлая", .en: "Light", .sr: "Svetla"],
        .themeDark: [.ru: "Тёмная", .en: "Dark", .sr: "Tamna"],
        .setPrivacy: [.ru: "Конфиденциальность", .en: "Privacy", .sr: "Privatnost"],
        .setMask: [.ru: "Скрывать ЕМБГ, адрес и номер документа", .en: "Hide personal number, address and document number", .sr: "Sakrij JMBG, adresu i broj dokumenta"],
        .setAutoHide: [.ru: "Скрывать данные при бездействии, минут (0 — никогда)", .en: "Hide data when idle, minutes (0 = never)", .sr: "Sakrij podatke pri neaktivnosti, minuta (0 = nikad)"],
        .setBehavior: [.ru: "Поведение", .en: "Behavior", .sr: "Ponašanje"],
        .setAutoRead: [.ru: "Читать карту автоматически при вставке", .en: "Read the card automatically when inserted", .sr: "Automatski pročitaj karticu pri umetanju"],
        .setPrintJmbg: [.ru: "Печатать ЕМБГ в распечатке и PDF", .en: "Include personal number in printouts and PDF", .sr: "Štampaj JMBG u štampi i PDF-u"],
        .setAutoUpdate: [.ru: "Проверять обновления при запуске", .en: "Check for updates on startup", .sr: "Proveri ažuriranja pri pokretanju"],
        .copy: [.ru: "Копировать", .en: "Copy", .sr: "Kopiraj"],
        .reveal: [.ru: "Показать", .en: "Show", .sr: "Prikaži"],
        .hideValue: [.ru: "Скрыть", .en: "Hide", .sr: "Sakrij"],
        .more: [.ru: "Ещё", .en: "More", .sr: "Više"],
        .copyAll: [.ru: "Копировать все данные", .en: "Copy all data", .sr: "Kopiraj sve podatke"],
        .savePhoto: [.ru: "Сохранить фото", .en: "Save photo", .sr: "Sačuvaj fotografiju"],
        .exportJson: [.ru: "Экспорт в JSON", .en: "Export as JSON", .sr: "Izvezi kao JSON"],
        .expiresIn: [.ru: "Действителен ещё %d дн.", .en: "Valid for %d more days", .sr: "Važi još %d dana"],
        .expiredOn: [.ru: "Срок действия истёк", .en: "Expired", .sr: "Istekao je"],
        .certIssuer: [.ru: "Выдан", .en: "Issued by", .sr: "Izdavalac"],
        .certValid: [.ru: "Действителен с %@ по %@", .en: "Valid %@ – %@", .sr: "Važi od %@ do %@"],
        .exportCert: [.ru: "Экспорт .cer", .en: "Export .cer", .sr: "Izvezi .cer"],
        .preview: [.ru: "Предпросмотр", .en: "Preview", .sr: "Pregled"],
        .close: [.ru: "Закрыть", .en: "Close", .sr: "Zatvori"],
        .copied: [.ru: "Скопировано", .en: "Copied", .sr: "Kopirano"],
        .autoHidden: [.ru: "Данные скрыты из-за бездействия. Прочитайте карту снова.", .en: "Data hidden due to inactivity. Read the card again.", .sr: "Podaci su sakriveni zbog neaktivnosti. Ponovo pročitajte karticu."],
        .errNoReaderT: [.ru: "Считыватель не найден", .en: "No card reader found", .sr: "Čitač nije pronađen"],
        .errNoReaderH: [.ru: "Подключите считыватель по USB и нажмите «Обновить». Если он уже подключён, проверьте драйвер.", .en: "Plug in the reader via USB and press Refresh. If it is already connected, check the driver.", .sr: "Povežite čitač preko USB-a i pritisnite „Osveži“. Ako je već povezan, proverite drajver."],
        .errNoCardT: [.ru: "Карты нет в считывателе", .en: "No card in the reader", .sr: "Nema kartice u čitaču"],
        .errNoCardH: [.ru: "Вставьте карту чипом вниз до конца.", .en: "Insert the card fully, chip side down.", .sr: "Umetnite karticu do kraja, čipom nadole."],
        .errUnsupportedT: [.ru: "Карта не поддерживается", .en: "Card not supported", .sr: "Kartica nije podržana"],
        .errUnsupportedH: [.ru: "Поддерживаются электронная ID-карта, карта иностранца и вид на жительство. Старые карты (до 18.08.2014) не поддерживаются.", .en: "Supported: electronic ID card, ID for foreigners and residence permit. Old cards (before 18.08.2014) are not supported.", .sr: "Podržane su elektronska lična karta, lična karta za strance i boravišna dozvola. Stare kartice (pre 18.08.2014) nisu podržane."],
        .errGenericT: [.ru: "Не удалось выполнить операцию", .en: "The operation failed", .sr: "Operacija nije uspela"],
        .errGenericH: [.ru: "Переставьте карту и попробуйте ещё раз.", .en: "Re-insert the card and try again.", .sr: "Ponovo umetnite karticu i pokušajte opet."],
        .techDetails: [.ru: "Подробности", .en: "Details", .sr: "Detalji"],        .printCard: [.ru: "Печать", .en: "Print", .sr: "Štampa"],
        .savePdf: [.ru: "Сохранить PDF", .en: "Save PDF", .sr: "Sačuvaj PDF"],
        .pdfSaved: [.ru: "PDF сохранён", .en: "PDF saved", .sr: "PDF je sačuvan"],
        .version: [.ru: "Версия", .en: "Version", .sr: "Verzija"],
        .checkUpdates: [.ru: "Проверить обновления", .en: "Check for updates", .sr: "Proveri ažuriranja"],
        .updateAvailable: [.ru: "Доступна новая версия %@", .en: "New version %@ is available", .sr: "Dostupna je nova verzija %@"],
        .updateNow: [.ru: "Обновить", .en: "Update", .sr: "Ažuriraj"],
        .updateDownloading: [.ru: "Загрузка обновления…", .en: "Downloading update…", .sr: "Preuzimanje ažuriranja…"],
        .upToDate: [.ru: "У вас последняя версия", .en: "You have the latest version", .sr: "Imate najnoviju verziju"],
        .updateUnavailable: [.ru: "Не удалось получить сведения об обновлениях (нет сети или репозиторий закрыт)", .en: "Could not get update information (offline or the repository is private)", .sr: "Nije moguće dobiti podatke o ažuriranju (nema mreže ili je repozitorijum privatan)"],
        .updateFailed: [.ru: "Не удалось обновить", .en: "Update failed", .sr: "Ažuriranje nije uspelo"],
        .brandSub: [.ru: "Электронная ID-карта Сербии", .en: "Serbian electronic ID card", .sr: "Elektronska lična karta Srbije"],
        .hintRead: [.ru: "Вставьте карту в считыватель и нажмите «Прочитать карту».", .en: "Insert the card into the reader and press “Read card”.", .sr: "Umetnite karticu u čitač i pritisnite „Pročitaj karticu“."],
        .hintToken: [.ru: "Нажмите «Прочитать токен», чтобы увидеть сертификаты.", .en: "Press “Read token” to see the certificates.", .sr: "Pritisnite „Pročitaj token“ da vidite sertifikate."],
        .docID: [.ru: "Электронная ID-карта", .en: "Electronic ID card", .sr: "Elektronska lična karta"],
        .docIF: [.ru: "ID-карта иностранца", .en: "ID card for foreigners", .sr: "Lična karta za strance"],
        .docRP: [.ru: "Вид на жительство", .en: "Residence permit", .sr: "Boravišna dozvola"],
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
        .appTitle: [.ru: "Super Celik", .en: "Super Celik", .sr: "Super Celik"],
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
