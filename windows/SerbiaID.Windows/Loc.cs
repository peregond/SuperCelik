using System.Globalization;

namespace SerbiaID;

public enum Lang { ru = 0, en = 1, sr = 2 }

/// Runtime-switchable RU / EN / SR strings (same texts as the macOS app).
public static class Loc
{
    public static Lang Current { get; set; } = Detect();

    public static Lang Detect() => CultureInfo.CurrentUICulture.TwoLetterISOLanguageName switch
    {
        "ru" => Lang.ru,
        "sr" or "hr" or "bs" => Lang.sr,
        _ => Lang.en,
    };

    public static string T(string key) =>
        Table.TryGetValue(key, out var v) ? v[(int)Current] : key;

    private static readonly Dictionary<string, string[]> Table = new()
    {
        // ru, en, sr
        ["appTitle"] = new[] { "Super Celik", "Super Celik", "Super Celik" },
        ["tabPersonal"] = new[] { "Личные данные", "Personal data", "Lični podaci" },
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
        ["readToken"] = new[] { "Прочитать токен", "Read token", "Pročitaj token" },
        ["verifySignature"] = new[] { "Проверить подпись", "Verify signature", "Proveri potpis" },
        ["printCard"] = new[] { "Печать / PDF", "Print / PDF", "Štampa / PDF" },
        ["sigOk"] = new[] { "Подпись верна, данные не изменены", "Signature valid, data unmodified", "Potpis je ispravan, podaci nisu menjani" },
        ["sigChain"] = new[] { "Не удалось построить цепочку доверия (это не значит, что данные неверны)", "Trust chain could not be established (does not mean the data is invalid)", "Nije uspostavljen lanac poverenja (ne znači da podaci nisu ispravni)" },
        ["sigBad"] = new[] { "Подпись неверна или данные изменены", "Signature invalid or data modified", "Potpis nije ispravan ili su podaci izmenjeni" },
        ["chainOk"] = new[] { "Цепочка доверия до МУП подтверждена", "Chain to MUP CA verified", "Lanac poverenja do MUP-a potvrđen" },
        ["pinNote"] = new[] { "Чтение токена не использует PIN. Подпись документов токеном пока не поддерживается.", "Reading the token does not use the PIN. Signing with the token is not supported yet.", "Čitanje tokena ne koristi PIN. Potpisivanje tokenom još nije podržano." },
        ["error"] = new[] { "Ошибка", "Error", "Greška" },
        ["language"] = new[] { "Язык", "Language", "Jezik" },
        ["aboutText"] = new[] { "Единое приложение для чтения электронной ID-карты и управления токеном. Независимая реализация, не связанная с МУП РС и NetSeT/Veridos.", "A single app for reading the electronic ID card and managing the token. Independent implementation, not affiliated with MUP RS or NetSeT/Veridos.", "Jedinstvena aplikacija za čitanje elektronske lične karte i upravljanje tokenom. Nezavisna implementacija, nije povezana sa MUP RS i NetSeT/Veridos." },
    };
}
