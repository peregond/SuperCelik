using System.Globalization;

namespace SerbiaID;

public enum Lang { ru = 0, en = 1, sr = 2, srCyrl = 3, hu = 4, sq = 5, sk = 6, ro = 7, hr = 8, uk = 9, be = 10 }

/// Runtime-switchable strings: RU / EN / SR (Latin and Cyrillic) below, and HU / SQ / SK / RO / HR / UK / BE in LocExtra.cs
/// (a text a language does not have yet is shown in English).
public static class Loc
{
    public static Lang Current { get; set; } = Detect();

    public static Lang Detect() => CultureInfo.CurrentUICulture.TwoLetterISOLanguageName switch
    {
        "ru" => Lang.ru,
        "sr" => CultureInfo.CurrentUICulture.Name.IndexOf("Cyrl", StringComparison.OrdinalIgnoreCase) >= 0 ? Lang.srCyrl : Lang.sr,
        "bs" => Lang.sr,
        var code => FromCode(code) ?? Lang.en,
    };

    /// The extra languages by their two-letter code (null = not one of them).
    public static Lang? FromCode(string code) => code switch
    {
        "hu" => Lang.hu, "sq" => Lang.sq, "sk" => Lang.sk, "ro" => Lang.ro, "hr" => Lang.hr, "uk" => Lang.uk, "be" => Lang.be,
        _ => null,
    };

    /// The order of the language picker: Serbian (Latin, Cyrillic), English, Russian, then the others alphabetically by their English name.
    public static readonly Lang[] PickerOrder =
    {
        Lang.sr, Lang.srCyrl, Lang.en, Lang.ru,
        Lang.sq, Lang.be, Lang.hr, Lang.hu, Lang.ro, Lang.sk, Lang.uk,
    };

    /// The name of a language as its speakers write it (language picker).
    public static string NativeName(Lang l) => l switch
    {
        Lang.ru => "Русский", Lang.en => "English", Lang.sr => "Srpski (latinica)", Lang.srCyrl => "Српски (ћирилица)",
        Lang.hu => "Magyar", Lang.sq => "Shqip", Lang.sk => "Slovenčina", Lang.ro => "Română", Lang.hr => "Hrvatski",
        Lang.uk => "Українська", Lang.be => "Беларуская", _ => l.ToString(),
    };

    /// The name of the flag picture of a language (Flags\<name>.png in the Windows build; Serbian has one flag for both scripts).
    public static string FlagFile(Lang l) => l == Lang.srCyrl ? "sr" : l.ToString();

    /// The flag emoji of a language, for pickers that can draw it (Windows cannot: its emoji font has no flags, so the Windows picker leaves them out).
    public static string Flag(Lang l) => l switch
    {
        Lang.ru => "\U0001F1F7\U0001F1FA", Lang.en => "\U0001F1EC\U0001F1E7", Lang.sr or Lang.srCyrl => "\U0001F1F7\U0001F1F8",
        Lang.hu => "\U0001F1ED\U0001F1FA", Lang.sq => "\U0001F1E6\U0001F1F1", Lang.sk => "\U0001F1F8\U0001F1F0", Lang.ro => "\U0001F1F7\U0001F1F4",
        Lang.hr => "\U0001F1ED\U0001F1F7", Lang.uk => "\U0001F1FA\U0001F1E6", Lang.be => "\U0001F1E7\U0001F1FE", _ => "",
    };

    /// The language code the site pages (reader help, what's new) take.
    public static string SiteCode => Current switch
    {
        Lang.ru => "ru", Lang.en => "en", Lang.sr => "sr", Lang.srCyrl => "sc",
        var l => l.ToString(),
    };

    public static string T(string key)
    {
        if (!Table.TryGetValue(key, out var v)) return LocCards.Get(Current, key);   // vehicle card and diagnostics texts
        // Serbian Cyrillic = the Serbian (Latin) text run through SerbianScript
        if (Current == Lang.srCyrl) return SerbianScript.Cyrillic(v[(int)Lang.sr]);
        if ((int)Current > (int)Lang.srCyrl) return LocExtra.Get(Current, key) ?? v[(int)Lang.en];
        return v[(int)Current];
    }

    private static readonly Dictionary<string, string[]> Table = new()
    {
        // ru, en, sr
        ["appTitle"] = new[] { "Super Čelik", "Super Čelik", "Super Čelik" },
        ["tabPersonal"] = new[] { "Карта", "Card", "Kartica" },
        ["tabToken"] = new[] { "Токен и сертификаты", "Token & certificates", "Token i sertifikati" },
        ["tabAbout"] = new[] { "О программе", "About", "O programu" },
        ["reader"] = new[] { "Считыватель", "Reader", "Čitač" },
        ["noReader"] = new[] { "Считыватель не найден", "No reader found", "Čitač nije pronađen" },
        ["refresh"] = new[] { "Обновить", "Refresh", "Osveži" },
        ["readCard"] = new[] { "Прочитать карту", "Read card", "Pročitaj karticu" },
        ["cardPresent"] = new[] { "Карта вставлена", "Card inserted", "Kartica je umetnuta" },
        ["noCard"] = new[] { "Карты нет", "No card", "Nema kartice" },
        ["surname"] = new[] { "Фамилия", "Surname", "Prezime" },
        ["givenName"] = new[] { "Имя", "Given name", "Ime" },
        ["parentName"] = new[] { "Имя родителя", "Parent's name", "Ime roditelja" },
        ["dob"] = new[] { "Дата рождения", "Date of birth", "Datum rođenja" },
        ["placeOfBirth"] = new[] { "Место рождения", "Place of birth", "Mesto rođenja" },
        ["sex"] = new[] { "Пол", "Sex", "Pol" },
        ["jmbg"] = new[] { "ЕМБГ", "Personal ID (JMBG)", "JMBG" },
        ["docNumber"] = new[] { "Номер документа", "Document number", "Broj dokumenta" },
        ["docSerial"] = new[] { "Серийный номер документа", "Document serial number", "Serijski broj dokumenta" },
        ["issuedBy"] = new[] { "Кем выдан", "Issued by", "Izdaje" },
        ["issueDate"] = new[] { "Дата выдачи", "Issue date", "Datum izdavanja" },
        ["expiryDate"] = new[] { "Действителен до", "Valid until", "Važi do" },
        ["address"] = new[] { "Адрес", "Address", "Adresa" },
        ["nationality"] = new[] { "Гражданство", "Nationality", "Državljanstvo" },
        ["certificates"] = new[] { "Сертификаты", "Certificates", "Sertifikati" },
        ["pinStepOld"] = new[] { "Шаг 1 из 3. Введите ДЕЙСТВУЮЩИЙ PIN (тот, что сейчас на карте).", "Step 1 of 3. Enter your CURRENT PIN (the one on the card now).", "Korak 1 od 3. Unesite TRENUTNI PIN (onaj koji je sada na kartici)." },
        ["pinStepPuk"] = new[] { "Шаг 1 из 3. Введите PUK (код разблокировки).", "Step 1 of 3. Enter your PUK (unblock code).", "Korak 1 od 3. Unesite PUK (kod za odblokiranje)." },
        ["pinStepNew"] = new[] { "Шаг 2 из 3. Придумайте и введите НОВЫЙ PIN (4–8 цифр).", "Step 2 of 3. Choose and enter a NEW PIN (4–8 digits).", "Korak 2 od 3. Smislite i unesite NOVI PIN (4–8 cifara)." },
        ["pinStepConfirm"] = new[] { "Шаг 3 из 3. Введите НОВЫЙ PIN ещё раз для подтверждения.", "Step 3 of 3. Enter the NEW PIN again to confirm.", "Korak 3 od 3. Unesite NOVI PIN još jednom radi potvrde." },
        ["cancel"] = new[] { "Отмена", "Cancel", "Otkaži" },
        ["changePin"] = new[] { "Сменить PIN", "Change PIN", "Promeni PIN" },
        ["unblockPin"] = new[] { "Разблокировать по PUK", "Unblock with PUK", "Odblokiraj PUK-om" },
        ["signFile"] = new[] { "Подписать файл", "Sign file", "Potpiši fajl" },
        ["pinOld"] = new[] { "Текущий PIN (4–8 цифр)", "Current PIN (4–8 digits)", "Trenutni PIN (4–8 cifara)" },
        ["pinNew"] = new[] { "Новый PIN (4–8 цифр)", "New PIN (4–8 digits)", "Novi PIN (4–8 cifara)" },
        ["pinNew2"] = new[] { "Повторите новый PIN", "Repeat new PIN", "Ponovite novi PIN" },
        ["pinEnter"] = new[] { "PIN (4–8 цифр)", "PIN (4–8 digits)", "PIN (4–8 cifara)" },
        ["pukEnter"] = new[] { "PUK (4–8 цифр)", "PUK (4–8 digits)", "PUK (4–8 cifara)" },
        ["pinWarn"] = new[] { "Неверный PIN тратит попытку; после исчерпания токен блокируется.", "A wrong PIN uses up one try; the token locks when none are left.", "Pogrešan PIN troši pokušaj; token se zaključava kad ih nestane." },
        ["pukWarn"] = new[] { "Неверный PUK тоже тратит попытку. Функция не проверена на реальной карте.", "A wrong PUK also uses up a try. Not verified on a real card.", "Pogrešan PUK takođe troši pokušaj. Nije proveren na pravoj kartici." },
        ["pinMismatch"] = new[] { "Новые PIN не совпадают", "New PINs do not match", "Novi PIN-ovi se ne poklapaju" },
        ["pinChanged"] = new[] { "PIN изменён", "PIN changed", "PIN je promenjen" },
        ["pinUnblocked"] = new[] { "PIN разблокирован и заменён новым", "PIN unblocked and replaced", "PIN je odblokiran i zamenjen" },
        ["pinWrong"] = new[] { "Неверный PIN/PUK. Осталось попыток: {0}", "Wrong PIN/PUK. Tries left: {0}", "Pogrešan PIN/PUK. Preostalo pokušaja: {0}" },
        ["pinBlockedMsg"] = new[] { "PIN заблокирован. Используйте «Разблокировать по PUK».", "PIN is blocked. Use “Unblock with PUK”.", "PIN je blokiran. Koristite „Odblokiraj PUK-om“." },
        ["pinInvalid"] = new[] { "PIN/PUK должен состоять из 4–8 цифр", "PIN/PUK must be 4–8 digits", "PIN/PUK mora imati 4–8 cifara" },
        ["signed"] = new[] { "Подпись сохранена: {0}", "Signature saved: {0}", "Potpis je sačuvan: {0}" },
        ["signNeedCert"] = new[] { "На токене не найден сертификат", "No certificate found on the token", "Na tokenu nije pronađen sertifikat" },
        ["readToken"] = new[] { "Прочитать токен", "Read token", "Pročitaj token" },
        ["verifySignature"] = new[] { "Проверить подпись", "Verify signature", "Proveri potpis" },
        ["printCard"] = new[] { "Печать", "Print", "Štampa" },
        ["brandSub"] = new[] { "Электронная ID-карта Сербии", "Serbian electronic ID card", "Elektronska lična karta Srbije" },
        ["statusReading"] = new[] { "Читаю карту…", "Reading the card…", "Čitam karticu…" },
        ["emptyNoReaderT"] = new[] { "Подключите считыватель", "Connect a card reader", "Povežite čitač" },
        ["emptyNoReaderH"] = new[] { "Подключите считыватель по USB: приложение увидит его само. Если он уже подключён, проверьте драйвер.", "Plug the reader in via USB: the app will notice it by itself. If it is already connected, check the driver.", "Povežite čitač preko USB-a: aplikacija će ga sama prepoznati. Ako je već povezan, proverite drajver." },
        ["emptyNoCardT"] = new[] { "Вставьте карту", "Insert the card", "Umetnite karticu" },
        ["emptyNoCardH"] = new[] { "Вставьте карту в считыватель до конца.", "Push the card all the way into the reader.", "Umetnite karticu u čitač do kraja." },
        ["emptyReadyT"] = new[] { "Можно читать", "Ready to read", "Spremno za čitanje" },
        ["emptyReadyH"] = new[] { "Данные останутся на этом компьютере.", "The data stays on this computer.", "Podaci ostaju na ovom računaru." },
        ["hintToken"] = new[] { "Нажмите «Прочитать токен», чтобы увидеть сертификаты.", "Press “Read token” to see the certificates.", "Pritisnite „Pročitaj token“ da vidite sertifikate." },
        ["hintRead"] = new[] { "Вставьте карту в считыватель и нажмите «Прочитать карту».", "Insert the card into the reader and press “Read card”.", "Umetnite karticu u čitač i pritisnite „Pročitaj karticu“." },
        ["docID"] = new[] { "Электронная ID-карта", "Electronic ID card", "Elektronska lična karta" },
        ["docIF"] = new[] { "ID-карта иностранца", "ID card for foreigners", "Lična karta za strance" },
        ["docRP"] = new[] { "Вид на жительство", "Residence permit", "Boravišna dozvola" },
        ["tabSettings"] = new[] { "Настройки", "Settings", "Podešavanja" },
        ["setAppearance"] = new[] { "Оформление", "Appearance", "Izgled" },
        ["setTheme"] = new[] { "Тема", "Theme", "Tema" },
        ["themeSystem"] = new[] { "Как в системе", "System", "Sistemska" },
        ["themeLight"] = new[] { "Светлая", "Light", "Svetla" },
        ["themeDark"] = new[] { "Тёмная", "Dark", "Tamna" },
        ["setPrivacy"] = new[] { "Конфиденциальность", "Privacy", "Privatnost" },
        ["setMask"] = new[] { "Скрывать ЕМБГ, адрес и номер документа", "Hide personal number, address and document number", "Sakrij JMBG, adresu i broj dokumenta" },
        ["setAutoHide"] = new[] { "Скрывать данные при бездействии, минут (0 — никогда)", "Hide data when idle, minutes (0 = never)", "Sakrij podatke pri neaktivnosti, minuta (0 = nikad)" },
        ["setBrowser"] = new[] { "Вход в браузере", "Browser login", "Prijava u pregledaču" },
        ["driverAsk"] = new[] { "Чтобы входить на eid.gov.rs и другие сайты через Chrome, Edge или Firefox по сертификату с карты, Windows нужен драйвер карты. Super Čelik может установить свой (один раз, нужны права администратора). Установить?", "To sign in to eid.gov.rs and other sites with the card certificate in Chrome, Edge or Firefox, Windows needs a card driver. Super Čelik can install its own (once, administrator rights needed). Install it?", "Za prijavu na eid.gov.rs i druge sajtove sertifikatom sa kartice u Chrome-u, Edge-u ili Firefox-u, Windows-u treba drajver kartice. Super Čelik može da instalira svoj (jednom, potrebna su administratorska prava). Instalirati?" },
        ["driverDone"] = new[] { "Драйвер установлен. Выньте карту и вставьте снова, затем перезапустите браузер.", "The driver is installed. Take the card out and put it in again, then restart the browser.", "Drajver je instaliran. Izvadite karticu i umetnite je ponovo, pa ponovo pokrenite pregledač." },
        ["driverFail"] = new[] { "Не удалось установить драйвер (отказано в правах или файл занят браузером).", "Could not install the driver (permission denied, or the file is in use by a browser).", "Instalacija drajvera nije uspela (odbijena prava ili pregledač koristi fajl)." },
        ["driverNoCard"] = new[] { "Вставьте карту: драйвер регистрируется для её типа.", "Insert the card: the driver is registered for its type.", "Umetnite karticu: drajver se registruje za njen tip." },
        ["driverOn"] = new[] { "Драйвер карты установлен: вход по сертификату работает в Chrome, Edge и Firefox.", "The card driver is installed: certificate sign-in works in Chrome, Edge and Firefox.", "Drajver kartice je instaliran: prijava sertifikatom radi u Chrome-u, Edge-u i Firefox-u." },
        ["driverOff"] = new[] { "Драйвер карты не установлен: для входа в браузере по сертификату он нужен.", "The card driver is not installed: it is needed for certificate sign-in in the browser.", "Drajver kartice nije instaliran: potreban je za prijavu sertifikatom u pregledaču." },
        ["driverMissing"] = new[] { "В этой сборке нет драйвера карты (используйте установщик).", "This build has no card driver (use the installer).", "Ova verzija nema drajver kartice (koristite instalater)." },
        ["driverInstall"] = new[] { "Установить драйвер", "Install the driver", "Instaliraj drajver" },
        ["driverRemove"] = new[] { "Удалить драйвер", "Remove the driver", "Ukloni drajver" },
        ["browserHint"] = new[] { "Если браузер не предлагает карту при входе: закройте его полностью и откройте страницу заново или выньте карту из ридера и вставьте снова.", "If the browser does not offer the card when you sign in: quit it completely and open the page again, or take the card out of the reader and put it back in.", "Ako pregledač ne nudi karticu pri prijavi: potpuno ga zatvorite i ponovo otvorite stranicu, ili izvadite karticu iz čitača i ponovo je umetnite." },
        ["firefoxOn"] = new[] { "Firefox настроен на сертификаты Windows (как Chrome и Edge).", "Firefox is set to use the Windows certificates (like Chrome and Edge).", "Firefox je podešen da koristi Windows sertifikate (kao Chrome i Edge)." },
        ["firefoxOff"] = new[] { "В Firefox выключено использование сертификатов Windows, поэтому сертификат карты в нём не появится.", "Firefox is set not to use the Windows certificates, so the card certificate will not show up in it.", "Firefox je podešen da ne koristi Windows sertifikate, pa se sertifikat kartice u njemu neće pojaviti." },
        ["firefoxOld"] = new[] { "Firefox {0} слишком старый: сертификаты Windows он использовать не умеет (нужна версия 75 или новее). Обновите Firefox или войдите через Chrome или Edge.", "Firefox {0} is too old to use the Windows certificates (version 75 or newer is needed). Update Firefox or sign in with Chrome or Edge.", "Firefox {0} je prestar da bi koristio Windows sertifikate (potrebna je verzija 75 ili novija). Ažurirajte Firefox ili se prijavite preko Chrome-a ili Edge-a." },
        ["firefoxFix"] = new[] { "Включить в Firefox", "Turn on in Firefox", "Uključi u Firefox-u" },
        ["firefoxAsk"] = new[] { "В Firefox выключено использование сертификатов Windows, поэтому вход на eid.gov.rs по карте в нём не сработает. Включить? Super Čelik добавит одну строку в файл user.js профиля Firefox. После этого Firefox нужно полностью закрыть и открыть снова.", "Firefox is set not to use the Windows certificates, so signing in to eid.gov.rs with the card will not work in it. Turn it on? Super Čelik adds one line to the user.js file of the Firefox profile. Afterwards quit Firefox completely and open it again.", "Firefox je podešen da ne koristi Windows sertifikate, pa prijava karticom na eid.gov.rs u njemu neće raditi. Uključiti? Super Čelik dodaje jedan red u fajl user.js profila Firefox-a. Posle toga potpuno zatvorite Firefox i ponovo ga pokrenite." },
        ["firefoxDone"] = new[] { "Готово: Firefox теперь использует сертификаты Windows. Закройте Firefox полностью и откройте снова.", "Done: Firefox now uses the Windows certificates. Quit Firefox completely and open it again.", "Gotovo: Firefox sada koristi Windows sertifikate. Potpuno zatvorite Firefox i ponovo ga pokrenite." },
        ["firefoxFail"] = new[] { "Не удалось изменить настройки Firefox.", "Could not change the Firefox settings.", "Nije uspela izmena podešavanja Firefox-a." },
        ["setBehavior"] = new[] { "Поведение", "Behavior", "Ponašanje" },
        ["setAutoRead"] = new[] { "Читать карту автоматически при вставке", "Read the card automatically when inserted", "Automatski pročitaj karticu pri umetanju" },
        ["setPrintJmbg"] = new[] { "Печатать ЕМБГ в распечатке и PDF", "Include personal number in printouts and PDF", "Štampaj JMBG u štampi i PDF-u" },
        ["setAutoUpdate"] = new[] { "Проверять обновления при запуске", "Check for updates on startup", "Proveri ažuriranja pri pokretanju" },
        ["copy"] = new[] { "Копировать", "Copy", "Kopiraj" },
        ["reveal"] = new[] { "Показать", "Show", "Prikaži" },
        ["hideValue"] = new[] { "Скрыть", "Hide", "Sakrij" },
        ["more"] = new[] { "Ещё", "More", "Više" },
        ["copyAll"] = new[] { "Копировать все данные", "Copy all data", "Kopiraj sve podatke" },
        ["savePhoto"] = new[] { "Сохранить фото", "Save photo", "Sačuvaj fotografiju" },
        ["exportJson"] = new[] { "Экспорт в JSON", "Export as JSON", "Izvezi kao JSON" },
        ["expiresIn"] = new[] { "Действителен ещё {0} дн.", "Valid for {0} more days", "Važi još {0} dana" },
        ["expiredOn"] = new[] { "Срок действия истёк", "Expired", "Istekao je" },
        ["certIssuer"] = new[] { "Выдан", "Issued by", "Izdavalac" },
        ["certValid"] = new[] { "Действителен с {0} по {1}", "Valid {0} – {1}", "Važi od {0} do {1}" },
        ["exportCert"] = new[] { "Экспорт .cer", "Export .cer", "Izvezi .cer" },
        ["preview"] = new[] { "Предпросмотр", "Preview", "Pregled" },
        ["close"] = new[] { "Закрыть", "Close", "Zatvori" },
        ["copied"] = new[] { "Скопировано", "Copied", "Kopirano" },
        ["autoHidden"] = new[] { "Данные скрыты из-за бездействия. Прочитайте карту снова.", "Data hidden due to inactivity. Read the card again.", "Podaci su sakriveni zbog neaktivnosti. Ponovo pročitajte karticu." },
        ["betaNote"] = new[] { "Версия для Linux пока тестовая. Программа ещё проверяется на реальных картах и ридерах, возможны ошибки.", "The Linux version is still in testing: it has not been tried on many real cards and readers yet, so bugs are possible.", "Linux verzija je još u testiranju. Aplikacija se još proverava na pravim karticama i čitačima, moguće su greške." },
        ["betaReport"] = new[] { "Сообщить об ошибке или оставить отзыв", "Report a bug or leave feedback", "Prijavi grešku ili ostavi povratnu informaciju" },
        ["errNoServiceT"] = new[] { "Служба смарт-карт не запущена", "The smart card service is not running", "Servis za pametne kartice nije pokrenut" },
        ["errNoServiceH"] = new[] { "Установите и запустите pcscd (например: sudo apt install pcscd, затем sudo systemctl enable --now pcscd.socket) и нажмите «Обновить».", "Install and start pcscd (for example: sudo apt install pcscd, then sudo systemctl enable --now pcscd.socket) and press Refresh.", "Instalirajte i pokrenite pcscd (na primer: sudo apt install pcscd, pa sudo systemctl enable --now pcscd.socket) i pritisnite Osveži." },
        ["errNoReaderT"] = new[] { "Считыватель не найден", "No card reader found", "Čitač nije pronađen" },
        ["errNoReaderH"] = new[] { "Подключите считыватель по USB и нажмите «Обновить». Если он уже подключён, проверьте драйвер.", "Plug in the reader via USB and press Refresh. If it is already connected, check the driver.", "Povežite čitač preko USB-a i pritisnite „Osveži“. Ako je već povezan, proverite drajver." },
        ["errNoCardT"] = new[] { "Карты нет в считывателе", "No card in the reader", "Nema kartice u čitaču" },
        ["errNoCardH"] = new[] { "Вставьте карту чипом вниз до конца.", "Insert the card fully, chip side down.", "Umetnite karticu do kraja, čipom nadole." },
        ["errUnsupportedT"] = new[] { "Карта не поддерживается", "Card not supported", "Kartica nije podržana" },
        ["errUnsupportedH"] = new[] { "Поддерживаются электронная ID-карта, карта иностранца и вид на жительство. Старые карты (до 18.08.2014) не поддерживаются.", "Supported: electronic ID card, ID for foreigners and residence permit. Old cards (before 18.08.2014) are not supported.", "Podržane su elektronska lična karta, lična karta za strance i boravišna dozvola. Stare kartice (pre 18.08.2014) nisu podržane." },
        ["errGenericT"] = new[] { "Не удалось выполнить операцию", "The operation failed", "Operacija nije uspela" },
        ["errGenericH"] = new[] { "Переставьте карту и попробуйте ещё раз.", "Re-insert the card and try again.", "Ponovo umetnite karticu i pokušajte opet." },
        ["techDetails"] = new[] { "Подробности", "Details", "Detalji" },
        ["savePdf"] = new[] { "Сохранить PDF", "Save PDF", "Sačuvaj PDF" },
        ["pdfSaved"] = new[] { "PDF сохранён", "PDF saved", "PDF je sačuvan" },
        ["version"] = new[] { "Версия", "Version", "Verzija" },
        ["checkUpdates"] = new[] { "Проверить обновления", "Check for updates", "Proveri ažuriranja" },
        ["readerHelp"] = new[] { "Нет считывателя?", "No reader yet?", "Nemate čitač?" },
        ["whatsNew"] = new[] { "Что нового?", "What’s new?", "Šta je novo?" },
        ["updateAvailable"] = new[] { "Доступна новая версия {0}", "New version {0} is available", "Dostupna je nova verzija {0}" },
        ["updateNow"] = new[] { "Обновить", "Update", "Ažuriraj" },
        ["updateDownloading"] = new[] { "Загрузка обновления…", "Downloading update…", "Preuzimanje ažuriranja…" },
        ["upToDate"] = new[] { "У вас последняя версия", "You have the latest version", "Imate najnoviju verziju" },
        ["updateUnavailable"] = new[] { "Не удалось получить сведения об обновлениях (нет сети или репозиторий закрыт)", "Could not get update information (offline or the repository is private)", "Nije moguće dobiti podatke o ažuriranju (nema mreže ili je repozitorijum privatan)" },
        ["updDownloading"] = new[] { "Скачиваю обновление…", "Downloading the update…", "Preuzimam ažuriranje…" },
        ["updInstalling"] = new[] { "Устанавливаю (может потребоваться пароль администратора)…", "Installing (the administrator password may be needed)…", "Instaliram (može biti potrebna administratorska lozinka)…" },
        ["openReleasePage"] = new[] { "Открыть страницу релиза", "Open the release page", "Otvori stranicu izdanja" },
        ["loginEuprava"] = new[] { "Войти на eUprava", "Sign in to eUprava", "Prijava na eUpravu" },
        ["loginEupravaNote"] = new[] { "«Войти на eUprava» открывает страницу входа в браузере по умолчанию. Если браузер не предлагает карту: закройте его полностью и откройте страницу заново или выньте карту из ридера и вставьте снова. Не помогло — «Настроить вход в браузере» покажет, где сбой.", "“Sign in to eUprava” opens the sign-in page in your default browser. If the browser does not offer the card: quit it completely and open the page again, or take the card out of the reader and put it back in. If that does not help, “Set up browser sign-in” shows what is wrong.", "„Prijava na eUpravu“ otvara stranicu za prijavu u podrazumevanom pregledaču. Ako pregledač ne nudi karticu: potpuno ga zatvorite i ponovo otvorite stranicu, ili izvadite karticu iz čitača i ponovo je umetnite. Ako ne pomogne, „Podesi prijavu u pregledaču“ pokazuje šta nije u redu." },
        ["loginEupravaNoteManual"] = new[] { "«Войти на eUprava» открывает страницу входа в браузере по умолчанию. Чтобы браузер предложил сертификат карты, в нём должен быть подключён модуль PKCS#11 (OpenSC или srb-id-pkcs11). Если браузер не предлагает карту: закройте его полностью и откройте страницу заново или выньте карту из ридера и вставьте снова.", "“Sign in to eUprava” opens the sign-in page in your default browser. For the browser to offer the card certificate, a PKCS#11 module (OpenSC or srb-id-pkcs11) must be set up in it. If the browser does not offer the card: quit it completely and open the page again, or take the card out of the reader and put it back in.", "„Prijava na eUpravu“ otvara stranicu za prijavu u podrazumevanom pregledaču. Da bi pregledač ponudio sertifikat sa kartice, u njemu mora biti podešen PKCS#11 modul (OpenSC ili srb-id-pkcs11). Ako pregledač ne nudi karticu: potpuno ga zatvorite i ponovo otvorite stranicu, ili izvadite karticu iz čitača i ponovo je umetnite." },
        ["setupBrowser"] = new[] { "Настроить вход в браузере", "Set up browser sign-in", "Podesi prijavu u pregledaču" },
        ["setupAsk"] = new[] { "Подключить карту к браузерам (Firefox, Chrome, Edge, Chromium), чтобы можно было входить на государственные порталы? Программа добавит в них свой модуль карты (srb-id-pkcs11, входит в программу). Потом браузер нужно полностью закрыть и открыть снова.", "Connect the card to your browsers (Firefox, Chrome, Edge, Chromium) so that you can sign in to government portals? The app adds its card module (srb-id-pkcs11, included in the app) to them. Afterwards quit the browser completely and open it again.", "Povezati karticu sa pregledačima (Firefox, Chrome, Edge, Chromium) da biste mogli da se prijavljujete na državne portale? Aplikacija u njih dodaje svoj modul za karticu (srb-id-pkcs11, sastavni deo aplikacije). Posle toga potpuno zatvorite pregledač i ponovo ga otvorite." },
        ["setupConnect"] = new[] { "Подключить", "Connect", "Poveži" },
        ["setupLater"] = new[] { "Не сейчас", "Not now", "Ne sada" },
        ["setupDone"] = new[] { "Готово. Подключено: {0}. Полностью закройте браузер и откройте его снова.", "Done. Connected: {0}. Quit the browser completely and open it again.", "Gotovo. Povezano: {0}. Potpuno zatvorite pregledač i ponovo ga otvorite." },
        ["setupNone"] = new[] { "Не найден профиль Firefox, Chrome / Edge или Chromium. Если браузер установлен, запустите его один раз и нажмите кнопку снова, либо подключите модуль вручную: {0}", "No Firefox profile or Chrome / Edge / Chromium found. If a browser is installed, start it once and press the button again, or add the module by hand: {0}", "Nije pronađen profil Firefox-a, Chrome-a / Edge-a ili Chromium-a. Ako je pregledač instaliran, pokrenite ga jednom i ponovo pritisnite dugme, ili dodajte modul ručno: {0}" },
        ["setupSandboxed"] = new[] { "Браузеры в изолированной среде ({0}) не подключены: песочница не пускает к ним модуль карты из этого приложения (Ubuntu описывает ручную настройку для Snap-браузеров, но называет её экспериментальной). Поставьте браузер обычным пакетом (Firefox: репозиторий Mozilla для APT или .tar.gz с mozilla.org; Chrome и Edge: .deb с их сайтов) либо используйте другой браузер.", "Sandboxed browsers ({0}) are not connected: their sandbox keeps out the card module of this app (Ubuntu describes manual steps for Snap browsers, but calls them experimental). Install the browser as a regular package (Firefox: Mozilla’s APT repository or the .tar.gz from mozilla.org; Chrome and Edge: the .deb from their websites), or use another browser.", "Pregledači u izolovanom okruženju ({0}) nisu povezani: izolovano okruženje ne propušta modul kartice ove aplikacije (Ubuntu opisuje ručna podešavanja za Snap pregledače, ali ih naziva eksperimentalnim). Instalirajte pregledač kao običan paket (Firefox: Mozilla APT repozitorijum ili .tar.gz sa mozilla.org; Chrome i Edge: .deb sa njihovih sajtova) ili koristite drugi pregledač." },
        ["setupNoTool"] = new[] { "Нужна утилита modutil: sudo apt install libnss3-tools", "The modutil tool is needed: sudo apt install libnss3-tools", "Potreban je alat modutil: sudo apt install libnss3-tools" },
        ["setupNoService"] = new[] { "Служба смарт-карт (pcscd) не запущена, поэтому модуль пока нельзя подключить. Выполните: sudo systemctl enable --now pcscd.socket и нажмите кнопку снова.", "The smart card service (pcscd) is not running, so the module cannot be connected yet. Run: sudo systemctl enable --now pcscd.socket, then press the button again.", "Usluga za pametne kartice (pcscd) nije pokrenuta, pa se modul još ne može povezati. Pokrenite: sudo systemctl enable --now pcscd.socket, pa ponovo pritisnite dugme." },
        ["setupOldLibc"] = new[] { "Системная библиотека C (glibc) слишком старая для модуля карты: ему нужен glibc 2.28 или новее (Ubuntu 20.04, Debian 10, RHEL 8 и новее). Подключите к браузеру OpenSC.", "The C library (glibc) of this system is too old for the card module: it needs glibc 2.28 or newer (Ubuntu 20.04, Debian 10, RHEL 8 or newer). Add OpenSC to the browser.", "Sistemska C biblioteka (glibc) je prestara za modul kartice: potreban je glibc 2.28 ili noviji (Ubuntu 20.04, Debian 10, RHEL 8 ili noviji). Povežite OpenSC sa pregledačem." },
        ["setupNoPcscLib"] = new[] { "Не найдена библиотека смарт-карт libpcsclite: sudo apt install libpcsclite1 (в других системах пакет pcsc-lite), затем нажмите кнопку снова.", "The smart card library libpcsclite is missing: sudo apt install libpcsclite1 (the pcsc-lite package elsewhere), then press the button again.", "Nedostaje biblioteka za pametne kartice libpcsclite: sudo apt install libpcsclite1 (na drugim sistemima paket pcsc-lite), pa ponovo pritisnite dugme." },
        ["setupFailed"] = new[] { "Не удалось подключить модуль: {0}", "Could not connect the module: {0}", "Nije uspelo povezivanje modula: {0}" },
        ["checkBrowser"] = new[] { "Проверить вход в браузере", "Check browser sign-in", "Proveri prijavu u pregledaču" },
        ["chkTitle"] = new[] { "Проверка входа в браузере", "Browser sign-in check", "Provera prijave u pregledaču" },
        ["chkCardOk"] = new[] { "Карта в ридере", "The card is in the reader", "Kartica je u čitaču" },
        ["chkNoCard"] = new[] { "В ридере нет карты", "There is no card in the reader", "U čitaču nema kartice" },
        ["chkNoReader"] = new[] { "Ридер не найден", "No reader found", "Čitač nije pronađen" },
        ["chkConnected"] = new[] { "Модуль карты подключён: {0}", "Card module connected: {0}", "Modul kartice je povezan: {0}" },
        ["chkNotConnected"] = new[] { "Модуль карты не подключён: {0}", "Card module not connected: {0}", "Modul kartice nije povezan: {0}" },
        ["chkNotLoaded"] = new[] { "Модуль не запускается", "The module does not start", "Modul se ne pokreće" },
        ["chkSeesCard"] = new[] { "Модуль видит карту", "The module sees the card", "Modul vidi karticu" },
        ["chkNoSeeCard"] = new[] { "Модуль не видит карту", "The module does not see the card", "Modul ne vidi karticu" },
        ["chkNoSeeReader"] = new[] { "Модуль не видит ридер", "The module does not see a reader", "Modul ne vidi čitač" },
        ["chkSandboxed"] = new[] { "Подключить нельзя (песочница): {0}", "Cannot be connected (sandbox): {0}", "Ne može da se poveže (izolovano okruženje): {0}" },
        ["stepConnect"] = new[] { "Нажмите «Настроить вход в браузере».", "Press “Set up browser sign-in”.", "Pritisnite „Podesi prijavu u pregledaču“." },
        ["stepNoService"] = new[] { "Служба смарт-карт (pcscd) не запущена. Запустите её и проверьте ещё раз.", "The smart card service (pcscd) is not running. Start it and check again.", "Usluga za pametne kartice (pcscd) nije pokrenuta. Pokrenite je i ponovo proverite." },
        ["stepStuck"] = new[] { "Служба смарт-карт (pcscd) не отвечает. Перезапустите её.", "The smart card service (pcscd) does not answer. Restart it.", "Usluga za pametne kartice (pcscd) ne odgovara. Ponovo je pokrenite." },
        ["stepNoLib"] = new[] { "Не найдена библиотека libpcsclite: установите пакет libpcsclite1 (в других системах pcsc-lite).", "The libpcsclite library is missing: install the libpcsclite1 package (pcsc-lite elsewhere).", "Nedostaje biblioteka libpcsclite: instalirajte paket libpcsclite1 (na drugim sistemima pcsc-lite)." },
        ["stepNoLoad"] = new[] { "Модуль не запускается. Проверьте, что pcscd и libpcsclite1 установлены и служба pcscd запущена.", "The module does not start. Check that pcscd and libpcsclite1 are installed and the pcscd service is running.", "Modul se ne pokreće. Proverite da su pcscd i libpcsclite1 instalirani i da je usluga pcscd pokrenuta." },
        ["stepNoReader"] = new[] { "Подключите ридер.", "Connect the reader.", "Povežite čitač." },
        ["stepNoCard"] = new[] { "Вставьте карту в ридер.", "Insert the card into the reader.", "Umetnite karticu u čitač." },
        ["stepReinsert"] = new[] { "Выньте карту из ридера и вставьте снова. Не помогло — перезапустите службу pcscd.", "Take the card out of the reader and put it back in. If that does not help, restart the pcscd service.", "Izvadite karticu iz čitača i ponovo je umetnite. Ako ne pomogne, ponovo pokrenite uslugu pcscd." },
        ["stepOk"] = new[] { "Всё в порядке. Если браузер всё равно не предлагает карту, закройте его полностью и откройте страницу заново.", "All good. If the browser still does not offer the card, quit it completely and open the page again.", "Sve je u redu. Ako pregledač ipak ne nudi karticu, potpuno ga zatvorite i ponovo otvorite stranicu." },
        ["chkDriverOn"] = new[] { "Драйвер карты установлен", "The card driver is installed", "Drajver kartice je instaliran" },
        ["chkDriverOff"] = new[] { "Драйвер карты не установлен", "The card driver is not installed", "Drajver kartice nije instaliran" },
        ["chkDriverOther"] = new[] { "Карту обслуживает другой драйвер (МУП / NetSeT)", "Another driver (MUP / NetSeT) handles the card", "Karticu opslužuje drugi drajver (MUP / NetSeT)" },
        ["chkDriverNone"] = new[] { "В этой сборке нет драйвера карты (используйте установщик)", "This build has no card driver (use the installer)", "Ova verzija nema drajver kartice (koristite instalater)" },
        ["chkFirefoxOn"] = new[] { "Firefox использует сертификаты Windows", "Firefox uses the Windows certificates", "Firefox koristi Windows sertifikate" },
        ["chkFirefoxOff"] = new[] { "В Firefox выключены сертификаты Windows", "Firefox has the Windows certificates turned off", "U Firefox-u su Windows sertifikati isključeni" },
        ["chkFirefoxOld"] = new[] { "Firefox {0} слишком старый (нужна версия 75 или новее)", "Firefox {0} is too old (version 75 or newer is needed)", "Firefox {0} je prestar (potrebna je verzija 75 ili novija)" },
        ["stepFirefoxOld"] = new[] { "Обновите Firefox или войдите через Chrome или Edge.", "Update Firefox or sign in with Chrome or Edge.", "Ažurirajte Firefox ili se prijavite preko Chrome-a ili Edge-a." },
        ["stepDriverNone"] = new[] { "Установите программу установщиком: в нём есть драйвер карты.", "Install the program with the installer: it carries the card driver.", "Instalirajte program instalerom: u njemu je drajver kartice." },
        ["setupWinDone"] = new[] { "Всё уже настроено. Если браузер не предлагает карту, закройте его полностью и откройте страницу заново.", "Everything is already set up. If the browser does not offer the card, quit it completely and open the page again.", "Sve je već podešeno. Ako pregledač ne nudi karticu, zatvorite ga potpuno i otvorite stranicu ponovo." },
        ["copyLogs"] = new[] { "Скопировать логи и ошибки", "Copy logs and errors", "Kopiraj logove i greške" },
        ["copyLogsHint"] = new[] { "Копирует технические сведения об ошибках (без ваших данных с карты), чтобы вставить их в сообщение об ошибке.", "Copies the technical details of the errors (without your card data) so you can paste them into a bug report.", "Kopira tehničke podatke o greškama (bez vaših podataka sa kartice) da ih nalepite u prijavu greške." },
        ["copyLogsDone"] = new[] { "Логи скопированы. Вставьте их в сообщение об ошибке.", "Logs copied. Paste them into your bug report.", "Logovi su kopirani. Nalepite ih u prijavu greške." },
        ["demoData"] = new[] { "Показать демо-данные", "Show demo data", "Prikaži demo podatke" },
        ["demoHint"] = new[] { "Вымышленные данные без карты, чтобы посмотреть, как выглядит программа. Пока включено, настоящий ридер не опрашивается.", "Fictional data without a card, to see what the app looks like. While it is on, the real reader is not polled.", "Izmišljeni podaci bez kartice, da vidite kako aplikacija izgleda. Dok je uključeno, pravi čitač se ne proverava." },
        ["updateFailed"] = new[] { "Не удалось обновить", "Update failed", "Ažuriranje nije uspelo" },
        ["sigOk"] = new[] { "Подпись верна, данные не изменены", "Signature valid, data unmodified", "Potpis je ispravan, podaci nisu menjani" },
        ["sigChain"] = new[] { "Не удалось построить цепочку доверия (это не значит, что данные неверны)", "Trust chain could not be established (does not mean the data is invalid)", "Nije uspostavljen lanac poverenja (ne znači da podaci nisu ispravni)" },
        ["sigBad"] = new[] { "Подпись неверна или данные изменены", "Signature invalid or data modified", "Potpis nije ispravan ili su podaci izmenjeni" },
        ["chainOk"] = new[] { "Цепочка доверия до МУП подтверждена", "Chain to MUP CA verified", "Lanac poverenja do MUP-a potvrđen" },
        ["pinNote"] = new[] { "Чтение токена не использует PIN. Подпись создаёт отдельный файл .p7s (CMS, отсоединённая), проверяемый любой программой с поддержкой CMS.", "Reading the token does not use the PIN. Signing creates a detached CMS .p7s file verifiable by any CMS-capable tool.", "Čitanje tokena ne koristi PIN. Potpis pravi odvojeni CMS .p7s fajl koji može da proveri svaki alat sa CMS podrškom." },
        ["error"] = new[] { "Ошибка", "Error", "Greška" },
        ["language"] = new[] { "Язык", "Language", "Jezik" },
        ["aboutText"] = new[] { "Единое приложение для чтения электронной ID-карты и управления токеном. Независимая реализация, не связанная с МУП РС и NetSeT/Veridos.", "A single app for reading the electronic ID card and managing the token. Independent implementation, not affiliated with MUP RS or NetSeT/Veridos.", "Jedinstvena aplikacija za čitanje elektronske lične karte i upravljanje tokenom. Nezavisna implementacija, nije povezana sa MUP RS i NetSeT/Veridos." },
    };
}
