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
        case menuCard
        case pinStepOld, pinStepPuk, pinStepNew, pinStepConfirm, unblockPin, pukLabel, signFile, signedSaved, pinWarn, pinWrongMsg, pinBlockedMsg, pinInvalid, pinUnblocked, signNeedCert
        // iOS (NFC)
        case scanCard, nfcPrompt, nfcReading, nfcDone, sharePdf, hintNfc, aboutTextIOS
        case nfcUnavailableT, nfcUnavailableH, nfcNoCardT, nfcNoCardH, nfcLostT, nfcLostH
    }

    // swiftlint:disable line_length
    static let table: [L: [AppLanguage: String]] = [
        .scanCard: [.ru: "Прочитать карту по NFC", .en: "Read card via NFC", .sr: "Pročitaj karticu preko NFC-a"],
        .nfcPrompt: [.ru: "Приложите карту к верхней части iPhone и не двигайте её", .en: "Hold the card against the top of your iPhone and keep it still", .sr: "Prislonite karticu uz gornji deo iPhone-a i ne pomerajte je"],
        .nfcReading: [.ru: "Чтение карты… Не убирайте карту", .en: "Reading the card… Keep holding it", .sr: "Čitanje kartice… Ne pomerajte je"],
        .nfcDone: [.ru: "Готово", .en: "Done", .sr: "Gotovo"],
        .sharePdf: [.ru: "Поделиться PDF", .en: "Share PDF", .sr: "Podeli PDF"],
        .hintNfc: [.ru: "Нажмите «Прочитать карту по NFC» и приложите карту к верхней части iPhone.", .en: "Tap “Read card via NFC” and hold the card against the top of your iPhone.", .sr: "Dodirnite „Pročitaj karticu preko NFC-a“ i prislonite karticu uz gornji deo iPhone-a."],
        .aboutTextIOS: [.ru: "Чтение электронной ID-карты Сербии по NFC. Независимая реализация, не связана с МУП РС и NetSeT/Veridos.", .en: "Reads the Serbian electronic ID card over NFC. Independent implementation, not affiliated with MUP RS or NetSeT/Veridos.", .sr: "Čitanje elektronske lične karte Srbije preko NFC-a. Nezavisna implementacija, nije povezana sa MUP RS i NetSeT/Veridos."],
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
        .pinStepOld: [.ru: "Шаг 1 из 3. Введите ДЕЙСТВУЮЩИЙ PIN (тот, что сейчас на карте).", .en: "Step 1 of 3. Enter your CURRENT PIN (the one on the card now).", .sr: "Korak 1 od 3. Unesite TRENUTNI PIN (onaj koji je sada na kartici)."],
        .pinStepPuk: [.ru: "Шаг 1 из 3. Введите PUK (код разблокировки).", .en: "Step 1 of 3. Enter your PUK (unblock code).", .sr: "Korak 1 od 3. Unesite PUK (kod za odblokiranje)."],
        .pinStepNew: [.ru: "Шаг 2 из 3. Придумайте и введите НОВЫЙ PIN (4–8 цифр).", .en: "Step 2 of 3. Choose and enter a NEW PIN (4–8 digits).", .sr: "Korak 2 od 3. Smislite i unesite NOVI PIN (4–8 cifara)."],
        .pinStepConfirm: [.ru: "Шаг 3 из 3. Введите НОВЫЙ PIN ещё раз для подтверждения.", .en: "Step 3 of 3. Enter the NEW PIN again to confirm.", .sr: "Korak 3 od 3. Unesite NOVI PIN još jednom radi potvrde."],
        .unblockPin: [.ru: "Разблокировать по PUK", .en: "Unblock with PUK", .sr: "Odblokiraj PUK-om"],
        .pukLabel: [.ru: "PUK (4–8 цифр)", .en: "PUK (4–8 digits)", .sr: "PUK (4–8 cifara)"],
        .signFile: [.ru: "Подписать файл", .en: "Sign file", .sr: "Potpiši fajl"],
        .signedSaved: [.ru: "Подпись сохранена", .en: "Signature saved", .sr: "Potpis je sačuvan"],
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
