import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    // the order is the order of the language pickers, as on the site: Serbian (Latin, Cyrillic), a divider, then the others alphabetically by their English name
    case sr, srCyrl, sq, be, hr, en, hu, ro, ru, sk, uk
    /// The languages whose texts live in LocalizationExtra.swift (everything missing there falls back to English).
    var isExtra: Bool { switch self { case .hu, .sq, .sk, .ro, .hr, .uk, .be: return true; default: return false } }
    var id: String { rawValue }
    /// The two Serbian scripts, above the divider of the pickers.
    static var pickerTop: [AppLanguage] { Array(allCases.prefix(2)) }
    /// All the other languages, below the divider.
    static var pickerRest: [AppLanguage] { Array(allCases.dropFirst(2)) }
    var flag: String {
        switch self {
        case .ru: return "🇷🇺"
        case .en: return "🇬🇧"
        case .sr, .srCyrl: return "🇷🇸"
        case .hu: return "🇭🇺"
        case .sq: return "🇦🇱"
        case .sk: return "🇸🇰"
        case .ro: return "🇷🇴"
        case .hr: return "🇭🇷"
        case .uk: return "🇺🇦"
        case .be: return "🇧🇾"
        }
    }
}

/// The demo cards of the Settings switches (one at a time): the ID card, the health insurance card, the vehicle registration card.
enum DemoKind: String, CaseIterable, Identifiable {
    case card, health, vehicle
    var id: String { rawValue }
    var labelKey: String { switch self { case .card: return "demoCard"; case .health: return "demoHealth"; case .vehicle: return "demoVehicle" } }
}

extension Loc {
    /// The label of a language in the pickers: its flag and its name in the language of the interface (for the two Serbian scripts just
    /// "Latin" and "Cyrillic": the Serbian flag says which language that is).
    func pickerLabel(_ l: AppLanguage) -> String {
        let names = x("langNames").components(separatedBy: "|")
        let i = AppLanguage.allCases.firstIndex(of: l) ?? 0
        return "\(l.flag)  \(i < names.count ? names[i] : l.rawValue)"
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
        let tag = Locale.preferredLanguages.first ?? "en"
        let code = tag.prefix(2).lowercased()
        switch code {
        case "ru": return .ru
        case "sr": return tag.contains("Cyrl") ? .srCyrl : .sr      // plain "sr" -> Latin, as most people in Serbia use it
        case "bs": return .sr
        case "hu": return .hu
        case "sq": return .sq
        case "sk": return .sk
        case "ro": return .ro
        case "hr": return .hr
        case "uk": return .uk
        case "be": return .be
        default: return .en
        }
    }

    /// The language code the site pages (reader help, what's new) take.
    var siteLang: String {
        switch language { case .srCyrl: return "sc"; default: return language.rawValue }
    }
    var changelogURL: URL {
        #if os(iOS)
        let app = "ios"
        #else
        let app = "macos"
        #endif
        return URL(string: "https://celik.peregon.cc/changelog/?lang=\(siteLang)&app=\(app)")!
    }
    static let feedbackURL = URL(string: "https://github.com/peregond/SuperCelik/issues/new")!

    func t(_ key: L) -> String {
        // Serbian Cyrillic is the Serbian (Latin) text run through SerbianScript, once per key
        if language == .srCyrl {
            if let c = Self.cyrillicCache[key] { return c }
            let c = SerbianScript.cyrillic(Self.table[key]?[.sr] ?? Self.table[key]?[.en] ?? "\(key)")
            Self.cyrillicCache[key] = c
            return c
        }
        if language.isExtra, let x = LocExtra.table(language)["\(key)"] { return x }
        return Self.table[key]?[language] ?? Self.table[key]?[.en] ?? "\(key)"
    }

    private static var cyrillicCache: [L: String] = [:]

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
        case menuCard
        case firefoxOff, firefoxFix, firefoxLater, firefoxDone, firefoxFail
        case loginHint, loginCheckRun, chkExtOk, chkExtNo, chkAttachedOk, chkAttachedNo, chkFfOk, chkFfOff, stepRepair, repairBtn, stepFirefox
        case driverStuck, pinStepOld, pinStepPuk, pinStepNew, pinStepConfirm, unblockPin, pukLabel, signFile, signedSaved, fileTooLarge, fileUnreadable, pinWarn, pinWrongMsg, pinBlockedMsg, pinInvalid, pinUnblocked, signNeedCert, loginEuprava, loginEupravaNote, loginNoDriver, loginCheckTitle, loginCheckOk, loginCheckMissing, loginCheckNoCard, loginCheckBtn
        // iOS (NFC)
        case statusReading, emptyNoReaderT, emptyNoReaderH, emptyNoCardT, emptyNoCardH, emptyReadyT, emptyReadyH, demoData, demoHint, tabCardShort, tabTokenShort, readCardAuto, hintAuto, viewPdf, photo, scanUsb, usbNoReaderT, usbNoReaderH, hintUsb, scanCard, nfcPrompt, nfcReading, nfcDone, sharePdf, hintNfc, aboutTextIOS
        case nfcUnavailableT, nfcUnavailableH, nfcNoCardT, nfcNoCardH, nfcLostT, nfcLostH
        case iosNoReaderH, iosNoCardH, iosReadyH, iosNoReaderQ, readerHelpTitle, whatsNew, betaReport, copyLogs, copyLogsHint, copyLogsDone
    }

    // swiftlint:disable line_length
    static let table: [L: [AppLanguage: String]] = [
        .statusReading: [.ru: "Читаю карту…", .en: "Reading the card…", .sr: "Čitam karticu…"],
        .emptyNoReaderT: [.ru: "Подключите считыватель", .en: "Connect a card reader", .sr: "Povežite čitač"],
        .emptyNoReaderH: [.ru: "Подключите считыватель по USB: приложение увидит его само. Если он уже подключён, проверьте драйвер.", .en: "Plug the reader in via USB: the app will notice it by itself. If it is already connected, check the driver.", .sr: "Povežite čitač preko USB-a: aplikacija će ga sama prepoznati. Ako je već povezan, proverite drajver."],
        .emptyNoCardT: [.ru: "Вставьте карту", .en: "Insert the card", .sr: "Umetnite karticu"],
        .emptyNoCardH: [.ru: "Вставьте карту в считыватель до конца.", .en: "Push the card all the way into the reader.", .sr: "Umetnite karticu u čitač do kraja."],
        .emptyReadyT: [.ru: "Можно читать", .en: "Ready to read", .sr: "Spremno za čitanje"],
        .emptyReadyH: [.ru: "Данные останутся на этом компьютере.", .en: "The data stays on this computer.", .sr: "Podaci ostaju na ovom računaru."],
        .demoData: [.ru: "Показать демо-данные", .en: "Show demo data", .sr: "Prikaži demo podatke"],
        .demoHint: [.ru: "Вымышленные данные, чтобы посмотреть, как выглядит приложение, без карты и ридера.", .en: "Fictional data, to see how the app looks without a card or reader.", .sr: "Izmišljeni podaci, da vidite kako aplikacija izgleda bez kartice i čitača."],
        .tabCardShort: [.ru: "Карта", .en: "Card", .sr: "Kartica"],
        .tabTokenShort: [.ru: "Токен", .en: "Token", .sr: "Token"],
        .readCardAuto: [.ru: "Прочитать карту", .en: "Read card", .sr: "Pročitaj karticu"],
        .hintAuto: [.ru: "Подключите ридер и вставьте карту, или приложите карту к iPhone (NFC). Приложение само выберет способ.", .en: "Connect a reader and insert the card, or hold the card to the iPhone (NFC). The app picks the method automatically.", .sr: "Povežite čitač i umetnite karticu, ili prislonite karticu uz iPhone (NFC). Aplikacija sama bira način."],
        .viewPdf: [.ru: "Открыть PDF", .en: "View PDF", .sr: "Otvori PDF"],
        .photo: [.ru: "Фото", .en: "Photo", .sr: "Fotografija"],
        .scanUsb: [.ru: "Прочитать через USB-ридер", .en: "Read card via USB reader", .sr: "Pročitaj karticu preko USB čitača"],
        .usbNoReaderT: [.ru: "USB-ридер не виден системе", .en: "No USB reader visible to the system", .sr: "USB čitač nije vidljiv sistemu"],
        .usbNoReaderH: [.ru: "Подключите считыватель смарт-карт (iPhone 15 и новее по USB-C, либо MFi-считыватель) и вставьте карту.", .en: "Connect a smart card reader (iPhone 15 or newer over USB-C, or an MFi reader) and insert the card.", .sr: "Povežite čitač kartica (iPhone 15 i noviji preko USB-C, ili MFi čitač) i umetnite karticu."],
        .hintUsb: [.ru: "Подключите USB-ридер, вставьте карту и нажмите «Прочитать через USB-ридер». Если в карте есть NFC-чип, можно читать и по NFC.", .en: "Connect a USB reader, insert the card and tap “Read card via USB reader”. If the card has an NFC chip you can read it over NFC too.", .sr: "Povežite USB čitač, umetnite karticu i dodirnite „Pročitaj karticu preko USB čitača“. Ako kartica ima NFC čip, možete je čitati i preko NFC-a."],
        .scanCard: [.ru: "Прочитать карту по NFC", .en: "Read card via NFC", .sr: "Pročitaj karticu preko NFC-a"],
        .nfcPrompt: [.ru: "Приложите карту к верхней части iPhone и не двигайте её", .en: "Hold the card against the top of your iPhone and keep it still", .sr: "Prislonite karticu uz gornji deo iPhone-a i ne pomerajte je"],
        .nfcReading: [.ru: "Чтение карты… Не убирайте карту", .en: "Reading the card… Keep holding it", .sr: "Čitanje kartice… Ne pomerajte je"],
        .nfcDone: [.ru: "Готово", .en: "Done", .sr: "Gotovo"],
        .sharePdf: [.ru: "Поделиться", .en: "Share PDF", .sr: "Podeli PDF"],
        .hintNfc: [.ru: "Нажмите «Прочитать карту по NFC» и приложите карту к верхней части iPhone.", .en: "Tap “Read card via NFC” and hold the card against the top of your iPhone.", .sr: "Dodirnite „Pročitaj karticu preko NFC-a“ i prislonite karticu uz gornji deo iPhone-a."],
        .aboutTextIOS: [.ru: "Чтение электронной ID-карты Сербии через считыватель смарт-карт. Независимая реализация, не связана с МУП РС и NetSeT/Veridos.", .en: "Reads the Serbian electronic ID card through a smart card reader. Independent implementation, not affiliated with MUP RS or NetSeT/Veridos.", .sr: "Čitanje elektronske lične karte Srbije preko čitača pametnih kartica. Nezavisna implementacija, nije povezana sa MUP RS i NetSeT/Veridos."],
        .readerHelpTitle: [.ru: "Нет считывателя?", .en: "No reader yet?", .sr: "Nemate čitač?"],
        .copyLogs: [.ru: "Скопировать логи и ошибки", .en: "Copy logs and errors", .sr: "Kopiraj logove i greške"],
        .copyLogsHint: [.ru: "Копирует технические сведения об ошибках (без ваших данных с карты), чтобы вставить их в сообщение об ошибке.", .en: "Copies the technical details of the errors (without your card data) so you can paste them into a bug report.", .sr: "Kopira tehničke podatke o greškama (bez vaših podataka sa kartice) da ih nalepite u prijavu greške."],
        .copyLogsDone: [.ru: "Логи скопированы. Вставьте их в сообщение об ошибке.", .en: "Logs copied. Paste them into your bug report.", .sr: "Logovi su kopirani. Nalepite ih u prijavu greške."],
        .whatsNew: [.ru: "Что нового?", .en: "What’s new?", .sr: "Šta je novo?"],
        .betaReport: [.ru: "Сообщить об ошибке или оставить отзыв", .en: "Report a bug or leave feedback", .sr: "Prijavi grešku ili ostavi povratnu informaciju"],
        .iosNoReaderH: [.ru: "Подключите его по USB-C.", .en: "Plug it in over USB-C.", .sr: "Povežite ga preko USB-C."],
        .iosNoReaderQ: [.ru: "Подключите считыватель смарт-карт к iPhone или iPad по USB-C: приложение увидит его само.", .en: "Plug a smart card reader into your iPhone or iPad over USB-C: the app will notice it by itself.", .sr: "Povežite čitač pametnih kartica na iPhone ili iPad preko USB-C: aplikacija će ga sama prepoznati."],
        .iosNoCardH: [.ru: "Вставьте карту до конца.", .en: "Push the card all the way in.", .sr: "Umetnite karticu do kraja."],
        .iosReadyH: [.ru: "Нажмите «Прочитать карту». Данные останутся на этом устройстве.", .en: "Tap “Read card”. The data stays on this device.", .sr: "Dodirnite „Pročitaj karticu“. Podaci ostaju na ovom uređaju."],
        .nfcUnavailableT: [.ru: "NFC недоступен", .en: "NFC is not available", .sr: "NFC nije dostupan"],
        .nfcUnavailableH: [.ru: "Это устройство не умеет читать карты по NFC. Нужен iPhone 7 или новее.", .en: "This device cannot read cards over NFC. An iPhone 7 or newer is required.", .sr: "Ovaj uređaj ne može da čita kartice preko NFC-a. Potreban je iPhone 7 ili noviji."],
        .nfcNoCardT: [.ru: "Карта не найдена", .en: "No card found", .sr: "Kartica nije pronađena"],
        .nfcNoCardH: [.ru: "Держите карту у верхней части iPhone и не двигайте её. Если iPhone не видит карту совсем, у неё, скорее всего, нет бесконтактного чипа: такую карту можно прочитать только USB-ридером в версии для Mac или Windows.", .en: "Hold the card against the top of the iPhone and keep it still. If the iPhone never detects it, the card most likely has no contactless chip and can only be read with a USB reader in the Mac or Windows version.", .sr: "Držite karticu uz gornji deo iPhone-a i ne pomerajte je. Ako je iPhone uopšte ne vidi, kartica verovatno nema beskontaktni čip i može se pročitati samo USB čitačem u verziji za Mac ili Windows."],
        .nfcLostT: [.ru: "Связь с картой прервалась", .en: "Connection to the card was lost", .sr: "Veza sa karticom je prekinuta"],
        .nfcLostH: [.ru: "Не двигайте карту до конца чтения и попробуйте ещё раз.", .en: "Keep the card still until reading finishes and try again.", .sr: "Ne pomerajte karticu dok se čitanje ne završi i pokušajte ponovo."],
        .menuCard: [.ru: "Карта", .en: "Card", .sr: "Kartica"],
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
        .pinNote: [.ru: "Чтение токена не использует PIN. Подпись создаёт отдельный файл .p7s (CMS, отсоединённая), проверяемый любой программой с поддержкой CMS.", .en: "Reading the token does not use the PIN. Signing creates a detached CMS .p7s file verifiable by any CMS-capable tool.", .sr: "Čitanje tokena ne koristi PIN. Potpis pravi odvojeni CMS .p7s fajl koji može da proveri svaki alat sa CMS podrškom."],
        .sigOk: [.ru: "Подпись верна, данные не изменены", .en: "Signature valid, data unmodified", .sr: "Potpis je ispravan, podaci nisu menjani"],
        .sigChain: [.ru: "Не удалось построить цепочку доверия (это не значит, что данные неверны)", .en: "Trust chain could not be established (does not mean the data is invalid)", .sr: "Nije uspostavljen lanac poverenja (ne znači da podaci nisu ispravni)"],
        .sigBad: [.ru: "Подпись неверна или данные изменены", .en: "Signature invalid or data modified", .sr: "Potpis nije ispravan ili su podaci izmenjeni"],
        .nationality: [.ru: "Гражданство", .en: "Nationality", .sr: "Državljanstvo"],
        .docSerial: [.ru: "Серийный номер документа", .en: "Document serial number", .sr: "Serijski broj dokumenta"],
        .pinUnsupported: [.ru: "Смена PIN доступна только для старой карты (до 18.08.2014)", .en: "PIN change is available only for the old card (issued before 18.08.2014)", .sr: "Promena PIN-a je moguća samo za staru karticu (pre 18.08.2014)"],
        .certMoiCA: [.ru: "Промежуточный сертификат МВД", .en: "MoI intermediate CA", .sr: "Posrednički sertifikat MUP-a"],
        .certAuth: [.ru: "Сертификат входа", .en: "Sign-in certificate", .sr: "Sertifikat za prijavu"],
        .certSign: [.ru: "Сертификат подписи", .en: "Signing certificate", .sr: "Sertifikat za potpis"],
        .certSigFixed: [.ru: "Подписант неизменяемых данных", .en: "Fixed-data signer", .sr: "Potpisnik nepromenljivih podataka"],
        .certSigVariable: [.ru: "Подписант изменяемых данных", .en: "Variable-data signer", .sr: "Potpisnik promenljivih podataka"],
        .appTitle: [.ru: "Super Čelik", .en: "Super Čelik", .sr: "Super Čelik"],
        .tabPersonal: [.ru: "Карта", .en: "Card", .sr: "Kartica"],
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
        .loginEuprava: [.ru: "Войти на eUprava", .en: "Sign in to eUprava", .sr: "Prijava na eUpravu"],
        .loginEupravaNote: [.ru: "Откроется страница eUprava. Выберите вход с квалифицированным сертификатом: сертификат карты подставит система, PIN она спросит сама. Нужен считыватель с вставленной картой.", .en: "The eUprava page opens. Choose sign-in with a qualified certificate: the system supplies the card certificate and asks for the PIN itself. A reader with the card inserted is required.", .sr: "Otvoriće se stranica eUprave. Izaberite prijavu kvalifikovanim sertifikatom: sistem nudi sertifikat sa kartice i sam traži PIN. Potreban je čitač sa umetnutom karticom."],
        .loginNoDriver: [.ru: "Система ещё не подключила карту к браузеру, поэтому сайт может не увидеть сертификат. Выньте карту, вставьте снова и подождите пару секунд. Открыть страницу входа всё равно?", .en: "The system has not attached the card to the browser yet, so the site may not see the certificate. Take the card out, insert it again and wait a few seconds. Open the sign-in page anyway?", .sr: "Sistem još nije povezao karticu sa pregledačem, pa sajt možda neće videti sertifikat. Izvadite karticu, umetnite je ponovo i sačekajte nekoliko sekundi. Ipak otvoriti stranicu za prijavu?"],
        .changePin: [.ru: "Сменить PIN", .en: "Change PIN", .sr: "Promena PIN-a"],
        .currentPin: [.ru: "Текущий PIN", .en: "Current PIN", .sr: "Trenutni PIN"],
        .newPin: [.ru: "Новый PIN", .en: "New PIN", .sr: "Novi PIN"],
        .confirmPin: [.ru: "Повторите новый PIN", .en: "Confirm new PIN", .sr: "Potvrdite novi PIN"],
        .pinMismatch: [.ru: "PIN-коды не совпадают", .en: "PINs do not match", .sr: "PIN-ovi se ne poklapaju"],
        .driverStuck: [.ru: "Вход в браузере: система ещё не подключила карту к браузеру. Выньте карту и вставьте её снова, подождите пару секунд, затем полностью закройте и откройте браузер.", .en: "Browser login: the system has not attached the card to the browser yet. Remove the card and insert it again, wait a couple of seconds, then fully quit and reopen the browser.", .sr: "Prijava u pregledaču: sistem još nije povezao karticu sa pregledačem. Izvadite karticu i ponovo je umetnite, sačekajte nekoliko sekundi, zatim potpuno zatvorite i ponovo otvorite pregledač."],
        .loginCheckTitle: [.ru: "Вход в браузере", .en: "Browser sign-in", .sr: "Prijava u pregledaču"],
        .loginCheckOk: [.ru: "Всё в порядке: система видит карту. Если браузер всё равно не предлагает её, закройте его полностью (⌘Q) и откройте сайт заново.", .en: "All good: the system sees the card. If the browser still does not offer it, quit it completely (⌘Q) and open the site again.", .sr: "Sve je u redu: sistem vidi karticu. Ako je pregledač ipak ne nudi, potpuno ga zatvorite (⌘Q) i ponovo otvorite sajt."],
        .loginCheckMissing: [.ru: "Система ещё не подключила карту. Выньте её из ридера и вставьте снова, подождите пару секунд и проверьте ещё раз.", .en: "The system has not attached the card yet. Take it out of the reader and put it back in, wait a couple of seconds and check again.", .sr: "Sistem još nije povezao karticu. Izvadite je iz čitača i ponovo je umetnite, sačekajte nekoliko sekundi i ponovo proverite."],
        .loginCheckNoCard: [.ru: "Вставьте карту в ридер.", .en: "Insert the card into the reader.", .sr: "Umetnite karticu u čitač."],
        .loginCheckBtn: [.ru: "Проверить", .en: "Check", .sr: "Proveri"],
        .loginHint: [.ru: "Браузер не предлагает карту? Закройте его полностью (⌘Q) и откройте страницу заново или выньте карту из ридера и вставьте снова.", .en: "The browser does not offer the card? Quit it completely (⌘Q) and open the page again, or take the card out of the reader and put it back in.", .sr: "Pregledač ne nudi karticu? Potpuno ga zatvorite (⌘Q) i ponovo otvorite stranicu, ili izvadite karticu iz čitača i ponovo je umetnite."],
        .loginCheckRun: [.ru: "Проверить вход в браузере", .en: "Check browser sign-in", .sr: "Proveri prijavu u pregledaču"],
        .chkExtOk: [.ru: "Драйвер карты зарегистрирован", .en: "Card driver registered", .sr: "Drajver kartice je registrovan"],
        .chkExtNo: [.ru: "Драйвер карты не зарегистрирован или выключен", .en: "Card driver not registered or switched off", .sr: "Drajver kartice nije registrovan ili je isključen"],
        .chkAttachedOk: [.ru: "Карта подключена к драйверу", .en: "Card attached to the driver", .sr: "Kartica je povezana sa drajverom"],
        .chkAttachedNo: [.ru: "Карта ещё не подключена к драйверу", .en: "Card not attached to the driver yet", .sr: "Kartica još nije povezana sa drajverom"],
        .chkFfOk: [.ru: "Firefox использует сертификаты macOS", .en: "Firefox uses the macOS certificates", .sr: "Firefox koristi sertifikate sistema macOS"],
        .chkFfOff: [.ru: "Firefox не использует сертификаты macOS", .en: "Firefox does not use the macOS certificates", .sr: "Firefox ne koristi sertifikate sistema macOS"],
        .stepRepair: [.ru: "Нажмите «Исправить», затем выньте карту из ридера и вставьте снова.", .en: "Press “Repair”, then take the card out of the reader and put it back in.", .sr: "Pritisnite „Popravi“, zatim izvadite karticu iz čitača i ponovo je umetnite."],
        .repairBtn: [.ru: "Исправить", .en: "Repair", .sr: "Popravi"],
        .stepFirefox: [.ru: "Нажмите «Включить», затем закройте Firefox полностью (⌘Q) и откройте сайт заново.", .en: "Press “Turn on”, then quit Firefox completely (⌘Q) and open the site again.", .sr: "Pritisnite „Uključi“, zatim potpuno zatvorite Firefox (⌘Q) i ponovo otvorite sajt."],
        .firefoxOff: [.ru: "В Firefox выключено использование сертификатов из связки ключей, поэтому сертификат карты в нём не появится. Включить?", .en: "Firefox is set not to use the certificates from the keychain, so the card certificate will not show up in it. Turn it on?", .sr: "Firefox je podešen da ne koristi sertifikate iz Keychain-a, pa se sertifikat kartice u njemu neće pojaviti. Uključiti?"],
        .firefoxFix: [.ru: "Включить", .en: "Turn on", .sr: "Uključi"],
        .firefoxLater: [.ru: "Не сейчас", .en: "Not now", .sr: "Ne sada"],
        .firefoxDone: [.ru: "Готово. Полностью закройте Firefox (⌘Q) и откройте сайт снова.", .en: "Done. Quit Firefox completely (⌘Q) and open the site again.", .sr: "Gotovo. Potpuno zatvorite Firefox (⌘Q) i ponovo otvorite sajt."],
        .firefoxFail: [.ru: "Не удалось изменить настройки Firefox.", .en: "Could not change the Firefox settings.", .sr: "Nije uspela izmena podešavanja Firefox-a."],
        .pinStepOld: [.ru: "Шаг 1 из 3. Введите ДЕЙСТВУЮЩИЙ PIN (тот, что сейчас на карте).", .en: "Step 1 of 3. Enter your CURRENT PIN (the one on the card now).", .sr: "Korak 1 od 3. Unesite TRENUTNI PIN (onaj koji je sada na kartici)."],
        .pinStepPuk: [.ru: "Шаг 1 из 3. Введите PUK (код разблокировки).", .en: "Step 1 of 3. Enter your PUK (unblock code).", .sr: "Korak 1 od 3. Unesite PUK (kod za odblokiranje)."],
        .pinStepNew: [.ru: "Шаг 2 из 3. Придумайте и введите НОВЫЙ PIN (4–8 цифр).", .en: "Step 2 of 3. Choose and enter a NEW PIN (4–8 digits).", .sr: "Korak 2 od 3. Smislite i unesite NOVI PIN (4–8 cifara)."],
        .pinStepConfirm: [.ru: "Шаг 3 из 3. Введите НОВЫЙ PIN ещё раз для подтверждения.", .en: "Step 3 of 3. Enter the NEW PIN again to confirm.", .sr: "Korak 3 od 3. Unesite NOVI PIN još jednom radi potvrde."],
        .unblockPin: [.ru: "Разблокировать по PUK", .en: "Unblock with PUK", .sr: "Odblokiraj PUK-om"],
        .pukLabel: [.ru: "PUK (4–8 цифр)", .en: "PUK (4–8 digits)", .sr: "PUK (4–8 cifara)"],
        .signFile: [.ru: "Подписать файл", .en: "Sign file", .sr: "Potpiši fajl"],
        .signedSaved: [.ru: "Подпись сохранена", .en: "Signature saved", .sr: "Potpis je sačuvan"],
        .fileTooLarge: [.ru: "Файл слишком большой для подписи на телефоне (до 100 МБ)", .en: "The file is too large to sign on the phone (up to 100 MB)", .sr: "Fajl je prevelik za potpisivanje na telefonu (do 100 MB)"],
        .fileUnreadable: [.ru: "Не удалось прочитать файл", .en: "The file could not be read", .sr: "Fajl nije moguće pročitati"],
        .pinWarn: [.ru: "Неверный PIN/PUK тратит попытку; после исчерпания токен блокируется. Разблокировка по PUK не проверена на реальной карте.", .en: "A wrong PIN/PUK uses up a try; the token locks when none are left. PUK unblock is not verified on a real card.", .sr: "Pogrešan PIN/PUK troši pokušaj; token se zaključava kad ih nestane. Odblokiranje PUK-om nije provereno na pravoj kartici."],
        .pinWrongMsg: [.ru: "Неверный PIN/PUK. Осталось попыток: ", .en: "Wrong PIN/PUK. Tries left: ", .sr: "Pogrešan PIN/PUK. Preostalo pokušaja: "],
        .pinBlockedMsg: [.ru: "PIN заблокирован. Используйте «Разблокировать по PUK».", .en: "PIN is blocked. Use “Unblock with PUK”.", .sr: "PIN je blokiran. Koristite „Odblokiraj PUK-om“."],
        .pinInvalid: [.ru: "PIN/PUK должен состоять из 4–8 цифр", .en: "PIN/PUK must be 4–8 digits", .sr: "PIN/PUK mora imati 4–8 cifara"],
        .pinUnblocked: [.ru: "PIN разблокирован и заменён новым", .en: "PIN unblocked and replaced", .sr: "PIN je odblokiran i zamenjen"],
        .signNeedCert: [.ru: "На токене не найден сертификат", .en: "No certificate found on the token", .sr: "Na tokenu nije pronađen sertifikat"],
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
