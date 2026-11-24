// Generated: translations of the interface texts (hu, sq, sk, ro, hr, uk, be); one "key|text" per line, keys are the Loc.L case names.
import Foundation

enum LocExtra {
    static func table(_ lang: AppLanguage) -> [String: String] {
        if let t = cache[lang] { return t }
        var t: [String: String] = [:]
        for line in (raw[lang] ?? "").split(separator: "\n") {
            if let bar = line.firstIndex(of: "|") { t[String(line[..<bar])] = String(line[line.index(after: bar)...]) }
        }
        cache[lang] = t
        return t
    }
    private static var cache: [AppLanguage: [String: String]] = [:]

    private static let raw: [AppLanguage: String] = [
        .hu: #"""
statusReading|Kártya olvasása…
emptyNoReaderT|Csatlakoztasson kártyaolvasót
emptyNoReaderH|Csatlakoztassa az olvasót USB-n: az alkalmazás magától észreveszi. Ha már csatlakoztatva van, ellenőrizze az illesztőprogramot.
emptyNoCardT|Helyezze be a kártyát
emptyNoCardH|Tolja be a kártyát teljesen az olvasóba.
emptyReadyT|Olvasásra kész
emptyReadyH|Az adatok ezen a számítógépen maradnak.
demoData|Demóadatok megjelenítése
demoHint|Kitalált adatok, hogy lássa, hogyan néz ki az alkalmazás kártya és olvasó nélkül.
tabCardShort|Kártya
tabTokenShort|Token
readCardAuto|Kártya olvasása
hintAuto|Csatlakoztasson olvasót és helyezze be a kártyát, vagy tartsa a kártyát az iPhone-hoz (NFC). Az alkalmazás automatikusan választ módszert.
viewPdf|PDF megtekintése
photo|Fénykép
scanUsb|Kártya olvasása USB-olvasóval
usbNoReaderT|A rendszer nem lát USB-olvasót
usbNoReaderH|Csatlakoztasson intelligenskártya-olvasót (iPhone 15 vagy újabb USB-C-n, vagy MFi-olvasó), és helyezze be a kártyát.
hintUsb|Csatlakoztasson USB-olvasót, helyezze be a kártyát, és koppintson a „Kártya olvasása USB-olvasóval” gombra. Ha a kártyán van NFC-chip, NFC-n is olvashatja.
scanCard|Kártya olvasása NFC-vel
nfcPrompt|Tartsa a kártyát az iPhone felső részéhez, és ne mozdítsa
nfcReading|Kártya olvasása… Tartsa tovább
nfcDone|Kész
sharePdf|PDF megosztása
hintNfc|Koppintson a „Kártya olvasása NFC-vel” gombra, és tartsa a kártyát az iPhone felső részéhez.
aboutTextIOS|A szerb elektronikus személyi igazolványt intelligenskártya-olvasón keresztül olvassa. Független megvalósítás, nem áll kapcsolatban a MUP RS-sel vagy a NetSeT/Veridosszal.
readerHelpTitle|Még nincs olvasója?
copyLogs|Naplók és hibák másolása
copyLogsHint|Lemásolja a hibák technikai részleteit (a kártyán lévő adatai nélkül), hogy beilleszthesse őket egy hibajelentésbe.
copyLogsDone|A naplók lemásolva. Illessze be őket a hibajelentésbe.
whatsNew|Mi újság?
betaReport|Hibajelentés vagy visszajelzés küldése
iosNoReaderH|Csatlakoztassa USB-C-n.
iosNoReaderQ|Csatlakoztasson intelligenskártya-olvasót az iPhone-hoz vagy iPadhez USB-C-n: az alkalmazás magától észreveszi.
iosNoCardH|Tolja be a kártyát teljesen.
iosReadyH|Koppintson a „Kártya olvasása” gombra. Az adatok ezen az eszközön maradnak.
nfcUnavailableT|Az NFC nem érhető el
nfcUnavailableH|Ez az eszköz nem tud NFC-n kártyát olvasni. iPhone 7 vagy újabb szükséges.
nfcNoCardT|Nem található kártya
nfcNoCardH|Tartsa a kártyát az iPhone felső részéhez, és ne mozdítsa. Ha az iPhone soha nem érzékeli, a kártyán valószínűleg nincs érintésmentes chip, és csak a Mac- vagy Windows-verzióban, USB-olvasóval olvasható.
nfcLostT|A kártyával megszakadt a kapcsolat
nfcLostH|Tartsa mozdulatlanul a kártyát az olvasás végéig, és próbálja újra.
menuCard|Kártya
tabSettings|Beállítások
setAppearance|Megjelenés
setTheme|Téma
themeSystem|Rendszer
themeLight|Világos
themeDark|Sötét
setPrivacy|Adatvédelem
setMask|Személyi szám, cím és okmányszám elrejtése
setAutoHide|Adatok elrejtése tétlenség esetén, percben (0 = soha)
setBehavior|Működés
setAutoRead|Kártya automatikus olvasása behelyezéskor
setPrintJmbg|Személyi szám szerepeltetése a nyomtatványon és a PDF-ben
setAutoUpdate|Frissítések keresése indításkor
copy|Másolás
reveal|Megjelenítés
hideValue|Elrejtés
more|Továbbiak
copyAll|Összes adat másolása
savePhoto|Fénykép mentése
exportJson|Exportálás JSON-ként
expiresIn|Még %d napig érvényes
expiredOn|Lejárt
certIssuer|Kiállító
certValid|Érvényes: %@ – %@
exportCert|.cer exportálása
preview|Előnézet
close|Bezárás
copied|Másolva
autoHidden|Az adatok tétlenség miatt el lettek rejtve. Olvassa be újra a kártyát.
errNoReaderT|Nem található kártyaolvasó
errNoReaderH|Csatlakoztassa az olvasót USB-n, és nyomja meg a Frissítés gombot. Ha már csatlakoztatva van, ellenőrizze az illesztőprogramot.
errNoCardT|Nincs kártya az olvasóban
errNoCardH|Helyezze be a kártyát teljesen, chippel lefelé.
errUnsupportedT|A kártya nem támogatott
errUnsupportedH|Támogatott: elektronikus személyi igazolvány, külföldiek személyi igazolványa és tartózkodási engedély. A régi kártyák (2014. 08. 18. előttiek) nem támogatottak.
errGenericT|A művelet nem sikerült
errGenericH|Helyezze be újra a kártyát, és próbálja meg ismét.
techDetails|Részletek
printCard|Nyomtatás
savePdf|PDF mentése
pdfSaved|PDF mentve
version|Verzió
checkUpdates|Frissítések keresése
updateAvailable|Új verzió érhető el: %@
updateNow|Frissítés
updateDownloading|Frissítés letöltése…
upToDate|A legújabb verziót használja
updateUnavailable|A frissítési információkat nem sikerült lekérni (nincs kapcsolat, vagy a tároló privát)
updateFailed|A frissítés nem sikerült
brandSub|Szerb elektronikus személyi igazolvány
hintRead|Helyezze be a kártyát az olvasóba, és nyomja meg a „Kártya olvasása” gombot.
hintToken|A tanúsítványok megtekintéséhez nyomja meg a „Token olvasása” gombot.
docID|Elektronikus személyi igazolvány
docIF|Külföldiek személyi igazolványa
docRP|Tartózkodási engedély
readToken|Token olvasása
chainOk|A MUP CA-ig tartó lánc ellenőrizve
pinNote|A token olvasása nem használ PIN-kódot. Az aláírás különálló CMS .p7s fájlt hoz létre, amelyet bármely CMS-képes eszköz ellenőrizni tud.
sigOk|Az aláírás érvényes, az adatok nem módosultak
sigChain|A bizalmi lánc nem építhető fel (ez nem jelenti, hogy az adatok érvénytelenek)
sigBad|Az aláírás érvénytelen, vagy az adatok módosultak
nationality|Állampolgárság
docSerial|Okmány sorozatszáma
pinUnsupported|A PIN módosítása csak a régi kártyához érhető el (2014. 08. 18. előtt kiállítva)
certMoiCA|MUP közbenső CA
certAuth|Bejelentkezési tanúsítvány
certSign|Aláírási tanúsítvány
certSigFixed|Állandó adatok aláírója
certSigVariable|Változó adatok aláírója
appTitle|Super Čelik
tabPersonal|Kártyaadatok
tabToken|Token és tanúsítványok
tabAbout|Névjegy
reader|Olvasó
noReader|Nem található olvasó
refresh|Frissítés
readCard|Kártya olvasása
cardPresent|Kártya behelyezve
noCard|Nincs kártya
atr|ATR
surname|Vezetéknév
givenName|Utónév
parentName|Szülő neve
dob|Születési idő
placeOfBirth|Születési hely
sex|Nem
jmbg|Személyi azonosító (JMBG)
docNumber|Okmányszám
issuedBy|Kiállító
issueDate|Kiállítás dátuma
expiryDate|Érvényes eddig
address|Cím
portrait|Arckép
certificates|Tanúsítványok
loginEuprava|Bejelentkezés az eUprávába
loginEupravaNote|Megnyílik az eUpráva oldala. Válassza a minősített tanúsítványos bejelentkezést: a rendszer megadja a kártya tanúsítványát, és maga kéri a PIN-kódot. Behelyezett kártyás olvasó szükséges.
loginNoDriver|A rendszer még nem rendelte a kártyát a böngészőhöz, ezért az oldal nem biztos, hogy látja a tanúsítványt. Vegye ki a kártyát, helyezze be újra, és várjon néhány másodpercet. Mégis megnyitja a bejelentkezési oldalt?
changePin|PIN módosítása
currentPin|Jelenlegi PIN
newPin|Új PIN
confirmPin|Új PIN megerősítése
pinMismatch|A PIN-kódok nem egyeznek
driverStuck|Böngészős bejelentkezés: a rendszer még nem rendelte a kártyát a böngészőhöz. Vegye ki a kártyát, helyezze be újra, várjon pár másodpercet, majd zárja be teljesen, és nyissa meg újra a böngészőt.
loginCheckTitle|Böngészős bejelentkezés
loginCheckOk|Minden rendben: a rendszer látja a kártyát. Ha a böngésző még mindig nem kínálja fel, zárja be teljesen (⌘Q), és nyissa meg újra az oldalt.
loginCheckMissing|A rendszer még nem rendelte hozzá a kártyát. Vegye ki az olvasóból, és helyezze vissza, várjon pár másodpercet, és ellenőrizze újra.
loginCheckNoCard|Helyezze be a kártyát az olvasóba.
loginCheckBtn|Ellenőrzés
loginHint|A böngésző nem kínálja fel a kártyát? Zárja be teljesen (⌘Q), és nyissa meg újra az oldalt, vagy vegye ki a kártyát az olvasóból, és helyezze vissza.
loginCheckRun|Bejelentkezés ellenőrzése a böngészőben
chkExtOk|Kártya-illesztőprogram regisztrálva
chkExtNo|A kártya-illesztőprogram nincs regisztrálva vagy ki van kapcsolva
chkAttachedOk|A kártya az illesztőprogramhoz rendelve
chkAttachedNo|A kártya még nincs az illesztőprogramhoz rendelve
chkFfOk|A Firefox a macOS-tanúsítványokat használja
chkFfOff|A Firefox nem használja a macOS-tanúsítványokat
stepRepair|Nyomja meg a „Javítás” gombot, majd vegye ki a kártyát az olvasóból, és helyezze vissza.
repairBtn|Javítás
stepFirefox|Nyomja meg a „Bekapcsolás” gombot, majd zárja be teljesen a Firefoxot (⌘Q), és nyissa meg újra az oldalt.
firefoxOff|A Firefox nem használja a kulcskarika tanúsítványait, ezért a kártya tanúsítványa nem jelenik meg benne. Bekapcsolja?
firefoxFix|Bekapcsolás
firefoxLater|Most nem
firefoxDone|Kész. Zárja be teljesen a Firefoxot (⌘Q), és nyissa meg újra az oldalt.
firefoxFail|A Firefox beállításait nem sikerült módosítani.
pinStepOld|1. lépés a 3-ból. Adja meg a JELENLEGI PIN-kódot (azt, amelyik most a kártyán van).
pinStepPuk|1. lépés a 3-ból. Adja meg a PUK-kódot (feloldó kód).
pinStepNew|2. lépés a 3-ból. Válasszon és adjon meg egy ÚJ PIN-kódot (4–8 számjegy).
pinStepConfirm|3. lépés a 3-ból. Adja meg ismét az ÚJ PIN-kódot a megerősítéshez.
unblockPin|Feloldás PUK-kal
pukLabel|PUK (4–8 számjegy)
signFile|Fájl aláírása
signedSaved|Aláírás mentve
fileTooLarge|A fájl túl nagy a telefonon történő aláíráshoz (legfeljebb 100 MB)
fileUnreadable|A fájlt nem sikerült beolvasni
pinWarn|A hibás PIN/PUK egy próbálkozást használ el; ha elfogynak, a token zárolódik. A PUK-os feloldás valódi kártyán nincs ellenőrizve.
pinWrongMsg|Hibás PIN/PUK. Hátralévő próbálkozások: 
pinBlockedMsg|A PIN zárolva van. Használja a „Feloldás PUK-kal” lehetőséget.
pinInvalid|A PIN/PUK 4–8 számjegyből álljon
pinUnblocked|A PIN feloldva és lecserélve
signNeedCert|Nem található tanúsítvány a tokenen
pinChanged|A PIN módosítva
pinFailed|A PIN módosítása nem sikerült
verifySignature|Aláírás ellenőrzése
export|Exportálás
notImplemented|Még nincs megvalósítva: kártyaprotokoll szükséges
error|Hiba
ok|OK
cancel|Mégse
language|Nyelv
aboutText|Egyetlen alkalmazás az elektronikus személyi igazolvány olvasásához és a token kezeléséhez. Független macOS-megvalósítás.
"""#,
        .sq: #"""
statusReading|Po lexohet karta…
emptyNoReaderT|Lidhni një lexues kartash
emptyNoReaderH|Lidheni lexuesin me USB: aplikacioni do ta vërejë vetë. Nëse është lidhur tashmë, kontrolloni drejtuesin.
emptyNoCardT|Futni kartën
emptyNoCardH|Shtyjeni kartën plotësisht në lexues.
emptyReadyT|Gati për lexim
emptyReadyH|Të dhënat mbeten në këtë kompjuter.
demoData|Shfaq të dhëna demo
demoHint|Të dhëna fiktive, për të parë si duket aplikacioni pa kartë dhe pa lexues.
tabCardShort|Karta
tabTokenShort|Token
readCardAuto|Lexo kartën
hintAuto|Lidhni një lexues dhe futni kartën, ose mbajeni kartën pranë iPhone (NFC). Aplikacioni zgjedh vetë metodën.
viewPdf|Shiko PDF
photo|Fotografia
scanUsb|Lexo kartën me lexues USB
usbNoReaderT|Sistemi nuk sheh asnjë lexues USB
usbNoReaderH|Lidhni një lexues kartash inteligjente (iPhone 15 ose më i ri me USB-C, ose lexues MFi) dhe futni kartën.
hintUsb|Lidhni një lexues USB, futni kartën dhe prekni „Lexo kartën me lexues USB”. Nëse karta ka çip NFC, mund ta lexoni edhe me NFC.
scanCard|Lexo kartën me NFC
nfcPrompt|Mbajeni kartën pranë pjesës së sipërme të iPhone dhe mos e lëvizni
nfcReading|Po lexohet karta… Vazhdoni ta mbani
nfcDone|U krye
sharePdf|Ndaj PDF
hintNfc|Prekni „Lexo kartën me NFC” dhe mbajeni kartën pranë pjesës së sipërme të iPhone.
aboutTextIOS|Lexon letërnjoftimin elektronik serb përmes një lexuesi kartash inteligjente. Zbatim i pavarur, pa lidhje me MUP RS ose NetSeT/Veridos.
readerHelpTitle|Nuk keni lexues?
copyLogs|Kopjo regjistrat dhe gabimet
copyLogsHint|Kopjon detajet teknike të gabimeve (pa të dhënat e kartës suaj) që t’i ngjitni në një raport gabimi.
copyLogsDone|Regjistrat u kopjuan. Ngjitini në raportin e gabimit.
whatsNew|Çfarë ka të re?
betaReport|Raporto një gabim ose lër një koment
iosNoReaderH|Lidheni me USB-C.
iosNoReaderQ|Lidhni një lexues kartash inteligjente me iPhone ose iPad përmes USB-C: aplikacioni do ta vërejë vetë.
iosNoCardH|Shtyjeni kartën deri në fund.
iosReadyH|Prekni „Lexo kartën”. Të dhënat mbeten në këtë pajisje.
nfcUnavailableT|NFC nuk është i disponueshëm
nfcUnavailableH|Kjo pajisje nuk mund të lexojë karta me NFC. Nevojitet iPhone 7 ose më i ri.
nfcNoCardT|Nuk u gjet asnjë kartë
nfcNoCardH|Mbajeni kartën pranë pjesës së sipërme të iPhone dhe mos e lëvizni. Nëse iPhone nuk e zbulon kurrë, karta ka shumë mundësi të mos ketë çip pa kontakt dhe mund të lexohet vetëm me lexues USB në versionin për Mac ose Windows.
nfcLostT|Lidhja me kartën u humb
nfcLostH|Mbajeni kartën pa e lëvizur deri sa të mbarojë leximi dhe provoni përsëri.
menuCard|Karta
tabSettings|Cilësimet
setAppearance|Pamja
setTheme|Tema
themeSystem|Sistemi
themeLight|E çelët
themeDark|E errët
setPrivacy|Privatësia
setMask|Fshih numrin personal, adresën dhe numrin e dokumentit
setAutoHide|Fshih të dhënat kur nuk përdoret, në minuta (0 = kurrë)
setBehavior|Sjellja
setAutoRead|Lexo kartën automatikisht kur futet
setPrintJmbg|Përfshi numrin personal në printim dhe PDF
setAutoUpdate|Kontrollo për përditësime gjatë nisjes
copy|Kopjo
reveal|Shfaq
hideValue|Fshih
more|Më shumë
copyAll|Kopjo të gjitha të dhënat
savePhoto|Ruaj fotografinë
exportJson|Eksporto si JSON
expiresIn|Vlen edhe për %d ditë
expiredOn|Ka skaduar
certIssuer|Lëshuar nga
certValid|Vlen %@ – %@
exportCert|Eksporto .cer
preview|Pamja paraprake
close|Mbyll
copied|U kopjua
autoHidden|Të dhënat u fshehën për shkak të joaktivitetit. Lexojeni kartën përsëri.
errNoReaderT|Nuk u gjet asnjë lexues kartash
errNoReaderH|Lidheni lexuesin me USB dhe shtypni Rifresko. Nëse është lidhur tashmë, kontrolloni drejtuesin.
errNoCardT|Nuk ka kartë në lexues
errNoCardH|Futeni kartën plotësisht, me çipin nga poshtë.
errUnsupportedT|Karta nuk mbështetet
errUnsupportedH|Mbështeten: letërnjoftimi elektronik, letërnjoftimi për të huajt dhe leja e qëndrimit. Kartat e vjetra (para 18.08.2014) nuk mbështeten.
errGenericT|Veprimi dështoi
errGenericH|Futeni kartën përsëri dhe provoni sërish.
techDetails|Detaje
printCard|Printo
savePdf|Ruaj PDF
pdfSaved|PDF u ruajt
version|Versioni
checkUpdates|Kontrollo për përditësime
updateAvailable|Është i disponueshëm versioni i ri %@
updateNow|Përditëso
updateDownloading|Po shkarkohet përditësimi…
upToDate|Keni versionin më të ri
updateUnavailable|Informacioni i përditësimit nuk u mor dot (pa internet ose depoja është private)
updateFailed|Përditësimi dështoi
brandSub|Letërnjoftimi elektronik serb
hintRead|Futeni kartën në lexues dhe shtypni „Lexo kartën”.
hintToken|Shtypni „Lexo tokenin” për të parë certifikatat.
docID|Letërnjoftim elektronik
docIF|Letërnjoftim për të huajt
docRP|Leje qëndrimi
readToken|Lexo tokenin
chainOk|Zinxhiri deri te MUP CA u verifikua
pinNote|Leximi i tokenit nuk përdor PIN. Nënshkrimi krijon një skedar të veçantë CMS .p7s që mund ta verifikojë çdo mjet që mbështet CMS.
sigOk|Nënshkrimi është i vlefshëm, të dhënat nuk janë ndryshuar
sigChain|Zinxhiri i besimit nuk u ndërtua dot (nuk do të thotë se të dhënat janë të pavlefshme)
sigBad|Nënshkrimi është i pavlefshëm ose të dhënat janë ndryshuar
nationality|Shtetësia
docSerial|Numri serik i dokumentit
pinUnsupported|Ndryshimi i PIN-it është i mundur vetëm për kartën e vjetër (të lëshuar para 18.08.2014)
certMoiCA|CA e ndërmjetme e MUP
certAuth|Certifikata e hyrjes
certSign|Certifikata e nënshkrimit
certSigFixed|Nënshkruesi i të dhënave të pandryshueshme
certSigVariable|Nënshkruesi i të dhënave të ndryshueshme
appTitle|Super Čelik
tabPersonal|Të dhënat e kartës
tabToken|Token dhe certifikata
tabAbout|Rreth programit
reader|Lexuesi
noReader|Nuk u gjet asnjë lexues
refresh|Rifresko
readCard|Lexo kartën
cardPresent|Karta është futur
noCard|Nuk ka kartë
atr|ATR
surname|Mbiemri
givenName|Emri
parentName|Emri i prindit
dob|Data e lindjes
placeOfBirth|Vendi i lindjes
sex|Gjinia
jmbg|Numri personal (JMBG)
docNumber|Numri i dokumentit
issuedBy|Lëshuar nga
issueDate|Data e lëshimit
expiryDate|Vlen deri më
address|Adresa
portrait|Portreti
certificates|Certifikatat
loginEuprava|Hyr në eUprava
loginEupravaNote|Hapet faqja e eUprava. Zgjidhni hyrjen me certifikatë të kualifikuar: sistemi jep certifikatën e kartës dhe e kërkon vetë PIN-in. Nevojitet një lexues me kartën e futur.
loginNoDriver|Sistemi nuk e ka lidhur ende kartën me shfletuesin, ndaj faqja mund të mos e shohë certifikatën. Nxirreni kartën, futeni përsëri dhe prisni disa sekonda. Ta hapim faqen e hyrjes sidoqoftë?
changePin|Ndrysho PIN-in
currentPin|PIN-i aktual
newPin|PIN-i i ri
confirmPin|Konfirmo PIN-in e ri
pinMismatch|PIN-et nuk përputhen
driverStuck|Hyrja në shfletues: sistemi nuk e ka lidhur ende kartën me shfletuesin. Nxirreni kartën dhe futeni përsëri, prisni disa sekonda, pastaj mbylleni plotësisht shfletuesin dhe hapeni përsëri.
loginCheckTitle|Hyrja në shfletues
loginCheckOk|Gjithçka në rregull: sistemi e sheh kartën. Nëse shfletuesi prapë nuk e ofron, mbylleni plotësisht (⌘Q) dhe hapni faqen përsëri.
loginCheckMissing|Sistemi nuk e ka lidhur ende kartën. Nxirreni nga lexuesi dhe futeni përsëri, prisni disa sekonda dhe kontrolloni sërish.
loginCheckNoCard|Futni kartën në lexues.
loginCheckBtn|Kontrollo
loginHint|Shfletuesi nuk e ofron kartën? Mbylleni plotësisht (⌘Q) dhe hapni faqen përsëri, ose nxirrni kartën nga lexuesi dhe futeni sërish.
loginCheckRun|Kontrollo hyrjen në shfletues
chkExtOk|Drejtuesi i kartës është regjistruar
chkExtNo|Drejtuesi i kartës nuk është regjistruar ose është çaktivizuar
chkAttachedOk|Karta është lidhur me drejtuesin
chkAttachedNo|Karta nuk është lidhur ende me drejtuesin
chkFfOk|Firefox përdor certifikatat e macOS
chkFfOff|Firefox nuk përdor certifikatat e macOS
stepRepair|Shtypni „Riparo”, pastaj nxirreni kartën nga lexuesi dhe futeni përsëri.
repairBtn|Riparo
stepFirefox|Shtypni „Aktivizo”, pastaj mbylleni plotësisht Firefox (⌘Q) dhe hapni faqen përsëri.
firefoxOff|Firefox është caktuar të mos përdorë certifikatat nga zinxhiri i çelësave, ndaj certifikata e kartës nuk do të shfaqet në të. Ta aktivizojë?
firefoxFix|Aktivizo
firefoxLater|Jo tani
firefoxDone|U krye. Mbylleni plotësisht Firefox (⌘Q) dhe hapni faqen përsëri.
firefoxFail|Cilësimet e Firefox nuk u ndryshuan dot.
pinStepOld|Hapi 1 nga 3. Shkruani PIN-in AKTUAL (atë që është tani në kartë).
pinStepPuk|Hapi 1 nga 3. Shkruani PUK-un (kodin e zhbllokimit).
pinStepNew|Hapi 2 nga 3. Zgjidhni dhe shkruani një PIN të RI (4–8 shifra).
pinStepConfirm|Hapi 3 nga 3. Shkruani përsëri PIN-in e RI për ta konfirmuar.
unblockPin|Zhblloko me PUK
pukLabel|PUK (4–8 shifra)
signFile|Nënshkruaj skedarin
signedSaved|Nënshkrimi u ruajt
fileTooLarge|Skedari është shumë i madh për t’u nënshkruar në telefon (deri në 100 MB)
fileUnreadable|Skedari nuk u lexua dot
pinWarn|Një PIN/PUK i gabuar harxhon një provë; tokeni bllokohet kur nuk mbetet asnjë. Zhbllokimi me PUK nuk është verifikuar në kartë të vërtetë.
pinWrongMsg|PIN/PUK i gabuar. Prova të mbetura: 
pinBlockedMsg|PIN-i është i bllokuar. Përdorni „Zhblloko me PUK”.
pinInvalid|PIN/PUK duhet të ketë 4–8 shifra
pinUnblocked|PIN-i u zhbllokua dhe u zëvendësua
signNeedCert|Nuk u gjet asnjë certifikatë në token
pinChanged|PIN-i u ndryshua
pinFailed|Ndryshimi i PIN-it dështoi
verifySignature|Verifiko nënshkrimin
export|Eksporto
notImplemented|Ende i paimplementuar: nevojitet protokolli i kartës
error|Gabim
ok|OK
cancel|Anulo
language|Gjuha
aboutText|Një aplikacion i vetëm për leximin e letërnjoftimit elektronik dhe menaxhimin e tokenit. Zbatim i pavarur për macOS.
"""#,
        .sk: #"""
statusReading|Číta sa karta…
emptyNoReaderT|Pripojte čítačku kariet
emptyNoReaderH|Pripojte čítačku cez USB: aplikácia si ju všimne sama. Ak je už pripojená, skontrolujte ovládač.
emptyNoCardT|Vložte kartu
emptyNoCardH|Zasuňte kartu úplne do čítačky.
emptyReadyT|Pripravené na čítanie
emptyReadyH|Údaje zostávajú v tomto počítači.
demoData|Zobraziť ukážkové údaje
demoHint|Vymyslené údaje, aby ste videli, ako aplikácia vyzerá bez karty a čítačky.
tabCardShort|Karta
tabTokenShort|Token
readCardAuto|Prečítať kartu
hintAuto|Pripojte čítačku a vložte kartu, alebo pridržte kartu pri iPhone (NFC). Aplikácia vyberie spôsob automaticky.
viewPdf|Zobraziť PDF
photo|Fotografia
scanUsb|Prečítať kartu cez USB čítačku
usbNoReaderT|Systém nevidí žiadnu USB čítačku
usbNoReaderH|Pripojte čítačku čipových kariet (iPhone 15 alebo novší cez USB-C, alebo čítačka MFi) a vložte kartu.
hintUsb|Pripojte USB čítačku, vložte kartu a ťuknite na „Prečítať kartu cez USB čítačku“. Ak má karta čip NFC, môžete ju čítať aj cez NFC.
scanCard|Prečítať kartu cez NFC
nfcPrompt|Pridržte kartu pri hornej časti iPhonu a nehýbte ňou
nfcReading|Číta sa karta… Držte ju ďalej
nfcDone|Hotovo
sharePdf|Zdieľať PDF
hintNfc|Ťuknite na „Prečítať kartu cez NFC“ a pridržte kartu pri hornej časti iPhonu.
aboutTextIOS|Číta srbský elektronický občiansky preukaz cez čítačku čipových kariet. Nezávislá implementácia, nie je spojená s MUP RS ani NetSeT/Veridos.
readerHelpTitle|Nemáte čítačku?
copyLogs|Kopírovať protokoly a chyby
copyLogsHint|Skopíruje technické podrobnosti o chybách (bez údajov z vašej karty), aby ste ich mohli vložiť do hlásenia chyby.
copyLogsDone|Protokoly skopírované. Vložte ich do hlásenia chyby.
whatsNew|Čo je nové?
betaReport|Nahlásiť chybu alebo zanechať spätnú väzbu
iosNoReaderH|Pripojte ju cez USB-C.
iosNoReaderQ|Pripojte čítačku čipových kariet k iPhonu alebo iPadu cez USB-C: aplikácia si ju všimne sama.
iosNoCardH|Zasuňte kartu úplne.
iosReadyH|Ťuknite na „Prečítať kartu“. Údaje zostávajú v tomto zariadení.
nfcUnavailableT|NFC nie je k dispozícii
nfcUnavailableH|Toto zariadenie nevie čítať karty cez NFC. Je potrebný iPhone 7 alebo novší.
nfcNoCardT|Karta sa nenašla
nfcNoCardH|Pridržte kartu pri hornej časti iPhonu a nehýbte ňou. Ak ju iPhone nikdy nezistí, karta pravdepodobne nemá bezkontaktný čip a dá sa čítať len USB čítačkou vo verzii pre Mac alebo Windows.
nfcLostT|Spojenie s kartou sa prerušilo
nfcLostH|Držte kartu bez pohybu, kým sa čítanie neskončí, a skúste to znova.
menuCard|Karta
tabSettings|Nastavenia
setAppearance|Vzhľad
setTheme|Motív
themeSystem|Systémový
themeLight|Svetlý
themeDark|Tmavý
setPrivacy|Súkromie
setMask|Skryť osobné číslo, adresu a číslo dokladu
setAutoHide|Skryť údaje pri nečinnosti, v minútach (0 = nikdy)
setBehavior|Správanie
setAutoRead|Prečítať kartu automaticky po vložení
setPrintJmbg|Zahrnúť osobné číslo do tlače a PDF
setAutoUpdate|Pri spustení hľadať aktualizácie
copy|Kopírovať
reveal|Zobraziť
hideValue|Skryť
more|Viac
copyAll|Kopírovať všetky údaje
savePhoto|Uložiť fotografiu
exportJson|Exportovať ako JSON
expiresIn|Platné ešte %d dní
expiredOn|Platnosť vypršala
certIssuer|Vydal
certValid|Platné %@ – %@
exportCert|Exportovať .cer
preview|Náhľad
close|Zavrieť
copied|Skopírované
autoHidden|Údaje boli skryté pre nečinnosť. Prečítajte kartu znova.
errNoReaderT|Čítačka kariet sa nenašla
errNoReaderH|Pripojte čítačku cez USB a stlačte Obnoviť. Ak je už pripojená, skontrolujte ovládač.
errNoCardT|V čítačke nie je karta
errNoCardH|Vložte kartu úplne, čipom nadol.
errUnsupportedT|Karta nie je podporovaná
errUnsupportedH|Podporované: elektronický občiansky preukaz, preukaz pre cudzincov a povolenie na pobyt. Staré karty (spred 18. 8. 2014) nie sú podporované.
errGenericT|Operácia zlyhala
errGenericH|Vložte kartu znova a skúste to ešte raz.
techDetails|Podrobnosti
printCard|Tlačiť
savePdf|Uložiť PDF
pdfSaved|PDF uložené
version|Verzia
checkUpdates|Hľadať aktualizácie
updateAvailable|Je dostupná nová verzia %@
updateNow|Aktualizovať
updateDownloading|Sťahuje sa aktualizácia…
upToDate|Máte najnovšiu verziu
updateUnavailable|Informácie o aktualizácii sa nepodarilo získať (offline alebo je repozitár súkromný)
updateFailed|Aktualizácia zlyhala
brandSub|Srbský elektronický občiansky preukaz
hintRead|Vložte kartu do čítačky a stlačte „Prečítať kartu“.
hintToken|Stlačením „Prečítať token“ zobrazíte certifikáty.
docID|Elektronický občiansky preukaz
docIF|Preukaz totožnosti pre cudzincov
docRP|Povolenie na pobyt
readToken|Prečítať token
chainOk|Reťaz po MUP CA overená
pinNote|Čítanie tokenu nepoužíva PIN. Podpisovanie vytvorí samostatný súbor CMS .p7s, ktorý overí ľubovoľný nástroj podporujúci CMS.
sigOk|Podpis je platný, údaje nie sú zmenené
sigChain|Reťaz dôvery sa nepodarilo zostaviť (neznamená to, že údaje sú neplatné)
sigBad|Podpis je neplatný alebo boli údaje zmenené
nationality|Štátna príslušnosť
docSerial|Sériové číslo dokladu
pinUnsupported|Zmena PIN je dostupná len pre starú kartu (vydanú pred 18. 8. 2014)
certMoiCA|Sprostredkujúca CA MUP
certAuth|Certifikát na prihlásenie
certSign|Certifikát na podpisovanie
certSigFixed|Podpisovateľ stálych údajov
certSigVariable|Podpisovateľ premenných údajov
appTitle|Super Čelik
tabPersonal|Údaje z karty
tabToken|Token a certifikáty
tabAbout|O aplikácii
reader|Čítačka
noReader|Čítačka sa nenašla
refresh|Obnoviť
readCard|Prečítať kartu
cardPresent|Karta je vložená
noCard|Žiadna karta
atr|ATR
surname|Priezvisko
givenName|Meno
parentName|Meno rodiča
dob|Dátum narodenia
placeOfBirth|Miesto narodenia
sex|Pohlavie
jmbg|Osobné identifikačné číslo (JMBG)
docNumber|Číslo dokladu
issuedBy|Vydal
issueDate|Dátum vydania
expiryDate|Platné do
address|Adresa
portrait|Portrét
certificates|Certifikáty
loginEuprava|Prihlásiť sa do eUprava
loginEupravaNote|Otvorí sa stránka eUprava. Vyberte prihlásenie kvalifikovaným certifikátom: systém dodá certifikát karty a PIN si vypýta sám. Je potrebná čítačka s vloženou kartou.
loginNoDriver|Systém ešte nepripojil kartu k prehliadaču, preto stránka certifikát nemusí vidieť. Kartu vyberte, vložte znova a počkajte niekoľko sekúnd. Napriek tomu otvoriť prihlasovaciu stránku?
changePin|Zmeniť PIN
currentPin|Aktuálny PIN
newPin|Nový PIN
confirmPin|Potvrďte nový PIN
pinMismatch|PIN kódy sa nezhodujú
driverStuck|Prihlásenie v prehliadači: systém ešte nepripojil kartu k prehliadaču. Kartu vyberte a vložte znova, počkajte pár sekúnd, potom prehliadač úplne zatvorte a otvorte znova.
loginCheckTitle|Prihlásenie v prehliadači
loginCheckOk|Všetko je v poriadku: systém kartu vidí. Ak ju prehliadač stále neponúka, úplne ho zatvorte (⌘Q) a stránku otvorte znova.
loginCheckMissing|Systém ešte kartu nepripojil. Vyberte ju z čítačky a vložte späť, počkajte pár sekúnd a skontrolujte znova.
loginCheckNoCard|Vložte kartu do čítačky.
loginCheckBtn|Skontrolovať
loginHint|Prehliadač kartu neponúka? Úplne ho zatvorte (⌘Q) a stránku otvorte znova, alebo kartu vyberte z čítačky a vložte späť.
loginCheckRun|Skontrolovať prihlásenie v prehliadači
chkExtOk|Ovládač karty je zaregistrovaný
chkExtNo|Ovládač karty nie je zaregistrovaný alebo je vypnutý
chkAttachedOk|Karta je pripojená k ovládaču
chkAttachedNo|Karta ešte nie je pripojená k ovládaču
chkFfOk|Firefox používa certifikáty macOS
chkFfOff|Firefox nepoužíva certifikáty macOS
stepRepair|Stlačte „Opraviť“, potom kartu vyberte z čítačky a vložte späť.
repairBtn|Opraviť
stepFirefox|Stlačte „Zapnúť“, potom Firefox úplne zatvorte (⌘Q) a stránku otvorte znova.
firefoxOff|Firefox je nastavený tak, aby nepoužíval certifikáty zo zväzku kľúčov, preto sa v ňom certifikát karty nezobrazí. Zapnúť?
firefoxFix|Zapnúť
firefoxLater|Teraz nie
firefoxDone|Hotovo. Firefox úplne zatvorte (⌘Q) a stránku otvorte znova.
firefoxFail|Nastavenia Firefoxu sa nepodarilo zmeniť.
pinStepOld|Krok 1 z 3. Zadajte AKTUÁLNY PIN (ten, ktorý je teraz na karte).
pinStepPuk|Krok 1 z 3. Zadajte PUK (odblokovací kód).
pinStepNew|Krok 2 z 3. Vymyslite a zadajte NOVÝ PIN (4–8 číslic).
pinStepConfirm|Krok 3 z 3. Zadajte NOVÝ PIN ešte raz na potvrdenie.
unblockPin|Odblokovať pomocou PUK
pukLabel|PUK (4–8 číslic)
signFile|Podpísať súbor
signedSaved|Podpis bol uložený
fileTooLarge|Súbor je príliš veľký na podpísanie v telefóne (do 100 MB)
fileUnreadable|Súbor sa nepodarilo prečítať
pinWarn|Nesprávny PIN/PUK minie jeden pokus; token sa zablokuje, keď žiadny nezostane. Odblokovanie pomocou PUK nie je overené na skutočnej karte.
pinWrongMsg|Nesprávny PIN/PUK. Zostávajúce pokusy: 
pinBlockedMsg|PIN je zablokovaný. Použite „Odblokovať pomocou PUK“.
pinInvalid|PIN/PUK musí mať 4–8 číslic
pinUnblocked|PIN bol odblokovaný a nahradený
signNeedCert|Na tokene sa nenašiel certifikát
pinChanged|PIN bol zmenený
pinFailed|Zmena PIN zlyhala
verifySignature|Overiť podpis
export|Exportovať
notImplemented|Zatiaľ neimplementované: je potrebný protokol karty
error|Chyba
ok|OK
cancel|Zrušiť
language|Jazyk
aboutText|Jedna aplikácia na čítanie elektronického občianskeho preukazu a správu tokenu. Nezávislá implementácia pre macOS.
"""#,
        .ro: #"""
statusReading|Se citește cardul…
emptyNoReaderT|Conectați un cititor de carduri
emptyNoReaderH|Conectați cititorul prin USB: aplicația îl va observa singură. Dacă este deja conectat, verificați driverul.
emptyNoCardT|Introduceți cardul
emptyNoCardH|Împingeți cardul complet în cititor.
emptyReadyT|Gata de citire
emptyReadyH|Datele rămân pe acest calculator.
demoData|Arată date demo
demoHint|Date fictive, ca să vedeți cum arată aplicația fără card și fără cititor.
tabCardShort|Card
tabTokenShort|Token
readCardAuto|Citește cardul
hintAuto|Conectați un cititor și introduceți cardul, sau țineți cardul lângă iPhone (NFC). Aplicația alege metoda automat.
viewPdf|Vezi PDF
photo|Fotografie
scanUsb|Citește cardul prin cititor USB
usbNoReaderT|Sistemul nu vede niciun cititor USB
usbNoReaderH|Conectați un cititor de carduri inteligente (iPhone 15 sau mai nou prin USB-C, sau un cititor MFi) și introduceți cardul.
hintUsb|Conectați un cititor USB, introduceți cardul și atingeți „Citește cardul prin cititor USB”. Dacă cardul are cip NFC, îl puteți citi și prin NFC.
scanCard|Citește cardul prin NFC
nfcPrompt|Țineți cardul lângă partea de sus a iPhone-ului și nu-l mișcați
nfcReading|Se citește cardul… Continuați să-l țineți
nfcDone|Gata
sharePdf|Partajează PDF
hintNfc|Atingeți „Citește cardul prin NFC” și țineți cardul lângă partea de sus a iPhone-ului.
aboutTextIOS|Citește cartea electronică de identitate sârbă printr-un cititor de carduri inteligente. Implementare independentă, fără legătură cu MUP RS sau NetSeT/Veridos.
readerHelpTitle|Nu aveți cititor?
copyLogs|Copiază jurnalele și erorile
copyLogsHint|Copiază detaliile tehnice ale erorilor (fără datele de pe cardul dvs.) ca să le puteți lipi într-un raport de eroare.
copyLogsDone|Jurnalele au fost copiate. Lipiți-le în raportul de eroare.
whatsNew|Ce este nou?
betaReport|Raportează o eroare sau lasă un comentariu
iosNoReaderH|Conectați-l prin USB-C.
iosNoReaderQ|Conectați un cititor de carduri inteligente la iPhone sau iPad prin USB-C: aplicația îl va observa singură.
iosNoCardH|Împingeți cardul până la capăt.
iosReadyH|Atingeți „Citește cardul”. Datele rămân pe acest dispozitiv.
nfcUnavailableT|NFC nu este disponibil
nfcUnavailableH|Acest dispozitiv nu poate citi carduri prin NFC. Este necesar un iPhone 7 sau mai nou.
nfcNoCardT|Nu s-a găsit niciun card
nfcNoCardH|Țineți cardul lângă partea de sus a iPhone-ului și nu-l mișcați. Dacă iPhone-ul nu îl detectează niciodată, cardul probabil nu are cip contactless și poate fi citit doar cu un cititor USB în versiunea pentru Mac sau Windows.
nfcLostT|Conexiunea cu cardul s-a pierdut
nfcLostH|Țineți cardul nemișcat până se termină citirea și încercați din nou.
menuCard|Card
tabSettings|Setări
setAppearance|Aspect
setTheme|Temă
themeSystem|Sistem
themeLight|Luminoasă
themeDark|Întunecată
setPrivacy|Confidențialitate
setMask|Ascunde numărul personal, adresa și numărul documentului
setAutoHide|Ascunde datele la inactivitate, în minute (0 = niciodată)
setBehavior|Comportament
setAutoRead|Citește cardul automat la introducere
setPrintJmbg|Include numărul personal în tipărire și PDF
setAutoUpdate|Caută actualizări la pornire
copy|Copiază
reveal|Arată
hideValue|Ascunde
more|Mai multe
copyAll|Copiază toate datele
savePhoto|Salvează fotografia
exportJson|Exportă ca JSON
expiresIn|Valabil încă %d zile
expiredOn|Expirat
certIssuer|Emis de
certValid|Valabil %@ – %@
exportCert|Exportă .cer
preview|Previzualizare
close|Închide
copied|Copiat
autoHidden|Datele au fost ascunse din cauza inactivității. Citiți din nou cardul.
errNoReaderT|Nu s-a găsit niciun cititor de carduri
errNoReaderH|Conectați cititorul prin USB și apăsați Reîmprospătează. Dacă este deja conectat, verificați driverul.
errNoCardT|Nu este niciun card în cititor
errNoCardH|Introduceți cardul complet, cu cipul în jos.
errUnsupportedT|Card neacceptat
errUnsupportedH|Acceptate: cartea electronică de identitate, cartea de identitate pentru străini și permisul de ședere. Cardurile vechi (înainte de 18.08.2014) nu sunt acceptate.
errGenericT|Operațiunea a eșuat
errGenericH|Introduceți cardul din nou și încercați încă o dată.
techDetails|Detalii
printCard|Tipărește
savePdf|Salvează PDF
pdfSaved|PDF salvat
version|Versiune
checkUpdates|Caută actualizări
updateAvailable|Este disponibilă versiunea nouă %@
updateNow|Actualizează
updateDownloading|Se descarcă actualizarea…
upToDate|Aveți cea mai recentă versiune
updateUnavailable|Nu s-au putut obține informațiile despre actualizare (fără conexiune sau depozitul este privat)
updateFailed|Actualizarea a eșuat
brandSub|Cartea electronică de identitate sârbă
hintRead|Introduceți cardul în cititor și apăsați „Citește cardul”.
hintToken|Apăsați „Citește tokenul” pentru a vedea certificatele.
docID|Carte electronică de identitate
docIF|Carte de identitate pentru străini
docRP|Permis de ședere
readToken|Citește tokenul
chainOk|Lanțul până la MUP CA verificat
pinNote|Citirea tokenului nu folosește PIN-ul. Semnarea creează un fișier CMS separat .p7s, verificabil de orice instrument cu suport CMS.
sigOk|Semnătura este validă, datele nu au fost modificate
sigChain|Lanțul de încredere nu a putut fi stabilit (nu înseamnă că datele sunt invalide)
sigBad|Semnătura este invalidă sau datele au fost modificate
nationality|Cetățenia
docSerial|Seria documentului
pinUnsupported|Schimbarea PIN-ului este disponibilă doar pentru cardul vechi (emis înainte de 18.08.2014)
certMoiCA|CA intermediar MUP
certAuth|Certificat de autentificare
certSign|Certificat de semnare
certSigFixed|Semnatar al datelor fixe
certSigVariable|Semnatar al datelor variabile
appTitle|Super Čelik
tabPersonal|Datele cardului
tabToken|Token și certificate
tabAbout|Despre
reader|Cititor
noReader|Nu s-a găsit niciun cititor
refresh|Reîmprospătează
readCard|Citește cardul
cardPresent|Card introdus
noCard|Fără card
atr|ATR
surname|Nume de familie
givenName|Prenume
parentName|Numele părintelui
dob|Data nașterii
placeOfBirth|Locul nașterii
sex|Sex
jmbg|Cod numeric personal (JMBG)
docNumber|Numărul documentului
issuedBy|Emis de
issueDate|Data emiterii
expiryDate|Valabil până la
address|Adresa
portrait|Portret
certificates|Certificate
loginEuprava|Autentificare la eUprava
loginEupravaNote|Se deschide pagina eUprava. Alegeți autentificarea cu certificat calificat: sistemul oferă certificatul cardului și cere singur PIN-ul. Este necesar un cititor cu cardul introdus.
loginNoDriver|Sistemul nu a atașat încă cardul la browser, deci este posibil ca site-ul să nu vadă certificatul. Scoateți cardul, introduceți-l din nou și așteptați câteva secunde. Deschideți totuși pagina de autentificare?
changePin|Schimbă PIN-ul
currentPin|PIN actual
newPin|PIN nou
confirmPin|Confirmați PIN-ul nou
pinMismatch|PIN-urile nu coincid
driverStuck|Autentificare în browser: sistemul nu a atașat încă cardul la browser. Scoateți cardul și introduceți-l din nou, așteptați câteva secunde, apoi închideți browserul complet și deschideți-l din nou.
loginCheckTitle|Autentificare în browser
loginCheckOk|Totul este în regulă: sistemul vede cardul. Dacă browserul tot nu îl oferă, închideți-l complet (⌘Q) și deschideți pagina din nou.
loginCheckMissing|Sistemul nu a atașat încă cardul. Scoateți-l din cititor și puneți-l la loc, așteptați câteva secunde și verificați din nou.
loginCheckNoCard|Introduceți cardul în cititor.
loginCheckBtn|Verifică
loginHint|Browserul nu oferă cardul? Închideți-l complet (⌘Q) și deschideți pagina din nou, sau scoateți cardul din cititor și puneți-l la loc.
loginCheckRun|Verifică autentificarea în browser
chkExtOk|Driverul cardului este înregistrat
chkExtNo|Driverul cardului nu este înregistrat sau este dezactivat
chkAttachedOk|Cardul este atașat la driver
chkAttachedNo|Cardul nu este încă atașat la driver
chkFfOk|Firefox folosește certificatele macOS
chkFfOff|Firefox nu folosește certificatele macOS
stepRepair|Apăsați „Repară”, apoi scoateți cardul din cititor și puneți-l la loc.
repairBtn|Repară
stepFirefox|Apăsați „Activează”, apoi închideți Firefox complet (⌘Q) și deschideți pagina din nou.
firefoxOff|Firefox este setat să nu folosească certificatele din breloc, deci certificatul cardului nu va apărea în el. Îl activați?
firefoxFix|Activează
firefoxLater|Nu acum
firefoxDone|Gata. Închideți Firefox complet (⌘Q) și deschideți pagina din nou.
firefoxFail|Setările Firefox nu au putut fi modificate.
pinStepOld|Pasul 1 din 3. Introduceți PIN-ul ACTUAL (cel care este acum pe card).
pinStepPuk|Pasul 1 din 3. Introduceți PUK-ul (codul de deblocare).
pinStepNew|Pasul 2 din 3. Alegeți și introduceți un PIN NOU (4–8 cifre).
pinStepConfirm|Pasul 3 din 3. Introduceți din nou PIN-ul NOU pentru confirmare.
unblockPin|Deblochează cu PUK
pukLabel|PUK (4–8 cifre)
signFile|Semnează fișierul
signedSaved|Semnătura a fost salvată
fileTooLarge|Fișierul este prea mare pentru a fi semnat pe telefon (până la 100 MB)
fileUnreadable|Fișierul nu a putut fi citit
pinWarn|Un PIN/PUK greșit consumă o încercare; tokenul se blochează când nu mai rămâne niciuna. Deblocarea cu PUK nu este verificată pe un card real.
pinWrongMsg|PIN/PUK greșit. Încercări rămase: 
pinBlockedMsg|PIN-ul este blocat. Folosiți „Deblochează cu PUK”.
pinInvalid|PIN-ul/PUK-ul trebuie să aibă 4–8 cifre
pinUnblocked|PIN-ul a fost deblocat și înlocuit
signNeedCert|Nu s-a găsit niciun certificat pe token
pinChanged|PIN-ul a fost schimbat
pinFailed|Schimbarea PIN-ului a eșuat
verifySignature|Verifică semnătura
export|Exportă
notImplemented|Încă neimplementat: este necesar protocolul cardului
error|Eroare
ok|OK
cancel|Anulează
language|Limba
aboutText|O singură aplicație pentru citirea cărții electronice de identitate și gestionarea tokenului. Implementare independentă pentru macOS.
"""#,
        .hr: #"""
statusReading|Čitanje kartice…
emptyNoReaderT|Spojite čitač kartica
emptyNoReaderH|Spojite čitač preko USB-a: aplikacija će ga sama prepoznati. Ako je već spojen, provjerite upravljački program.
emptyNoCardT|Umetnite karticu
emptyNoCardH|Gurnite karticu do kraja u čitač.
emptyReadyT|Spremno za čitanje
emptyReadyH|Podaci ostaju na ovom računalu.
demoData|Prikaži demo podatke
demoHint|Izmišljeni podaci, da vidite kako aplikacija izgleda bez kartice i čitača.
tabCardShort|Kartica
tabTokenShort|Token
readCardAuto|Pročitaj karticu
hintAuto|Spojite čitač i umetnite karticu ili prislonite karticu na iPhone (NFC). Aplikacija sama bira način.
viewPdf|Prikaži PDF
photo|Fotografija
scanUsb|Pročitaj karticu preko USB čitača
usbNoReaderT|Sustav ne vidi nijedan USB čitač
usbNoReaderH|Spojite čitač pametnih kartica (iPhone 15 ili noviji preko USB-C, ili MFi čitač) i umetnite karticu.
hintUsb|Spojite USB čitač, umetnite karticu i dodirnite „Pročitaj karticu preko USB čitača”. Ako kartica ima NFC čip, možete je pročitati i preko NFC-a.
scanCard|Pročitaj karticu preko NFC-a
nfcPrompt|Prislonite karticu na gornji dio iPhonea i držite je mirno
nfcReading|Čitanje kartice… Nastavite držati
nfcDone|Gotovo
sharePdf|Podijeli PDF
hintNfc|Dodirnite „Pročitaj karticu preko NFC-a” i prislonite karticu na gornji dio iPhonea.
aboutTextIOS|Čita srpsku elektroničku osobnu iskaznicu preko čitača pametnih kartica. Neovisna izvedba, nije povezana s MUP RS ni NetSeT/Veridos.
readerHelpTitle|Nemate čitač?
copyLogs|Kopiraj zapise i pogreške
copyLogsHint|Kopira tehničke pojedinosti o pogreškama (bez podataka s vaše kartice) da ih možete zalijepiti u prijavu pogreške.
copyLogsDone|Zapisi su kopirani. Zalijepite ih u prijavu pogreške.
whatsNew|Što je novo?
betaReport|Prijavi pogrešku ili ostavi povratnu informaciju
iosNoReaderH|Spojite ga preko USB-C.
iosNoReaderQ|Spojite čitač pametnih kartica na iPhone ili iPad preko USB-C: aplikacija će ga sama prepoznati.
iosNoCardH|Gurnite karticu do kraja.
iosReadyH|Dodirnite „Pročitaj karticu”. Podaci ostaju na ovom uređaju.
nfcUnavailableT|NFC nije dostupan
nfcUnavailableH|Ovaj uređaj ne može čitati kartice preko NFC-a. Potreban je iPhone 7 ili noviji.
nfcNoCardT|Kartica nije pronađena
nfcNoCardH|Prislonite karticu na gornji dio iPhonea i držite je mirno. Ako iPhone nikad ne otkrije karticu, najvjerojatnije nema beskontaktni čip i može se čitati samo USB čitačem u verziji za Mac ili Windows.
nfcLostT|Veza s karticom je prekinuta
nfcLostH|Držite karticu mirno dok čitanje ne završi i pokušajte ponovno.
menuCard|Kartica
tabSettings|Postavke
setAppearance|Izgled
setTheme|Tema
themeSystem|Sustav
themeLight|Svijetla
themeDark|Tamna
setPrivacy|Privatnost
setMask|Sakrij osobni broj, adresu i broj dokumenta
setAutoHide|Sakrij podatke pri mirovanju, minute (0 = nikad)
setBehavior|Ponašanje
setAutoRead|Automatski pročitaj karticu pri umetanju
setPrintJmbg|Uključi osobni broj u ispis i PDF
setAutoUpdate|Provjeri ažuriranja pri pokretanju
copy|Kopiraj
reveal|Prikaži
hideValue|Sakrij
more|Više
copyAll|Kopiraj sve podatke
savePhoto|Spremi fotografiju
exportJson|Izvezi kao JSON
expiresIn|Vrijedi još %d dana
expiredOn|Isteklo
certIssuer|Izdao
certValid|Vrijedi %@ – %@
exportCert|Izvezi .cer
preview|Pregled
close|Zatvori
copied|Kopirano
autoHidden|Podaci su skriveni zbog neaktivnosti. Ponovno pročitajte karticu.
errNoReaderT|Čitač kartica nije pronađen
errNoReaderH|Spojite čitač preko USB-a i pritisnite Osvježi. Ako je već spojen, provjerite upravljački program.
errNoCardT|Nema kartice u čitaču
errNoCardH|Umetnite karticu do kraja, čipom prema dolje.
errUnsupportedT|Kartica nije podržana
errUnsupportedH|Podržano: elektronička osobna iskaznica, osobna iskaznica za strance i dozvola boravka. Stare kartice (prije 18. 8. 2014.) nisu podržane.
errGenericT|Operacija nije uspjela
errGenericH|Ponovno umetnite karticu i pokušajte opet.
techDetails|Pojedinosti
printCard|Ispiši
savePdf|Spremi PDF
pdfSaved|PDF je spremljen
version|Verzija
checkUpdates|Provjeri ažuriranja
updateAvailable|Dostupna je nova verzija %@
updateNow|Ažuriraj
updateDownloading|Preuzimanje ažuriranja…
upToDate|Imate najnoviju verziju
updateUnavailable|Podatke o ažuriranju nije bilo moguće dohvatiti (izvan mreže ili je repozitorij privatan)
updateFailed|Ažuriranje nije uspjelo
brandSub|Srpska elektronička osobna iskaznica
hintRead|Umetnite karticu u čitač i pritisnite „Pročitaj karticu”.
hintToken|Pritisnite „Pročitaj token” za prikaz certifikata.
docID|Elektronička osobna iskaznica
docIF|Osobna iskaznica za strance
docRP|Dozvola boravka
readToken|Pročitaj token
chainOk|Lanac do MUP CA provjeren
pinNote|Čitanje tokena ne koristi PIN. Potpisivanjem nastaje odvojena CMS datoteka .p7s koju može provjeriti bilo koji alat koji podržava CMS.
sigOk|Potpis je valjan, podaci nisu mijenjani
sigChain|Lanac povjerenja nije moguće uspostaviti (ne znači da su podaci nevaljani)
sigBad|Potpis je nevaljan ili su podaci mijenjani
nationality|Državljanstvo
docSerial|Serijski broj dokumenta
pinUnsupported|Promjena PIN-a dostupna je samo za staru karticu (izdanu prije 18. 8. 2014.)
certMoiCA|Posredni CA MUP-a
certAuth|Certifikat za prijavu
certSign|Certifikat za potpisivanje
certSigFixed|Potpisnik nepromjenjivih podataka
certSigVariable|Potpisnik promjenjivih podataka
appTitle|Super Čelik
tabPersonal|Podaci s kartice
tabToken|Token i certifikati
tabAbout|O programu
reader|Čitač
noReader|Čitač nije pronađen
refresh|Osvježi
readCard|Pročitaj karticu
cardPresent|Kartica je umetnuta
noCard|Nema kartice
atr|ATR
surname|Prezime
givenName|Ime
parentName|Ime roditelja
dob|Datum rođenja
placeOfBirth|Mjesto rođenja
sex|Spol
jmbg|Osobni identifikacijski broj (JMBG)
docNumber|Broj dokumenta
issuedBy|Izdao
issueDate|Datum izdavanja
expiryDate|Vrijedi do
address|Adresa
portrait|Portret
certificates|Certifikati
loginEuprava|Prijava na eUpravu
loginEupravaNote|Otvara se stranica eUprave. Odaberite prijavu kvalificiranim certifikatom: sustav daje certifikat kartice i sam traži PIN. Potreban je čitač s umetnutom karticom.
loginNoDriver|Sustav još nije povezao karticu s preglednikom pa stranica možda ne vidi certifikat. Izvadite karticu, ponovno je umetnite i pričekajte nekoliko sekundi. Svejedno otvoriti stranicu za prijavu?
changePin|Promijeni PIN
currentPin|Trenutni PIN
newPin|Novi PIN
confirmPin|Potvrdite novi PIN
pinMismatch|PIN-ovi se ne podudaraju
driverStuck|Prijava u pregledniku: sustav još nije povezao karticu s preglednikom. Izvadite karticu i ponovno je umetnite, pričekajte par sekundi, zatim potpuno zatvorite i ponovno otvorite preglednik.
loginCheckTitle|Prijava u pregledniku
loginCheckOk|Sve je u redu: sustav vidi karticu. Ako je preglednik i dalje ne nudi, potpuno ga zatvorite (⌘Q) i ponovno otvorite stranicu.
loginCheckMissing|Sustav još nije povezao karticu. Izvadite je iz čitača i ponovno umetnite, pričekajte par sekundi i provjerite opet.
loginCheckNoCard|Umetnite karticu u čitač.
loginCheckBtn|Provjeri
loginHint|Preglednik ne nudi karticu? Potpuno ga zatvorite (⌘Q) i ponovno otvorite stranicu, ili izvadite karticu iz čitača i ponovno je umetnite.
loginCheckRun|Provjeri prijavu u pregledniku
chkExtOk|Upravljački program kartice je registriran
chkExtNo|Upravljački program kartice nije registriran ili je isključen
chkAttachedOk|Kartica je povezana s upravljačkim programom
chkAttachedNo|Kartica još nije povezana s upravljačkim programom
chkFfOk|Firefox koristi macOS certifikate
chkFfOff|Firefox ne koristi macOS certifikate
stepRepair|Pritisnite „Popravi”, zatim izvadite karticu iz čitača i ponovno je umetnite.
repairBtn|Popravi
stepFirefox|Pritisnite „Uključi”, zatim potpuno zatvorite Firefox (⌘Q) i ponovno otvorite stranicu.
firefoxOff|Firefox je postavljen da ne koristi certifikate iz privjeska ključeva pa se certifikat kartice u njemu neće pojaviti. Uključiti?
firefoxFix|Uključi
firefoxLater|Ne sada
firefoxDone|Gotovo. Potpuno zatvorite Firefox (⌘Q) i ponovno otvorite stranicu.
firefoxFail|Postavke Firefoxa nije bilo moguće promijeniti.
pinStepOld|Korak 1 od 3. Unesite TRENUTNI PIN (onaj koji je sada na kartici).
pinStepPuk|Korak 1 od 3. Unesite PUK (kôd za otključavanje).
pinStepNew|Korak 2 od 3. Smislite i unesite NOVI PIN (4–8 znamenki).
pinStepConfirm|Korak 3 od 3. Ponovno unesite NOVI PIN radi potvrde.
unblockPin|Otključaj PUK-om
pukLabel|PUK (4–8 znamenki)
signFile|Potpiši datoteku
signedSaved|Potpis je spremljen
fileTooLarge|Datoteka je prevelika za potpisivanje na telefonu (do 100 MB)
fileUnreadable|Datoteku nije bilo moguće pročitati
pinWarn|Pogrešan PIN/PUK troši pokušaj; token se zaključava kad pokušaja više nema. Otključavanje PUK-om nije provjereno na stvarnoj kartici.
pinWrongMsg|Pogrešan PIN/PUK. Preostalo pokušaja: 
pinBlockedMsg|PIN je blokiran. Upotrijebite „Otključaj PUK-om”.
pinInvalid|PIN/PUK mora imati 4–8 znamenki
pinUnblocked|PIN je otključan i zamijenjen
signNeedCert|Na tokenu nije pronađen certifikat
pinChanged|PIN je promijenjen
pinFailed|Promjena PIN-a nije uspjela
verifySignature|Provjeri potpis
export|Izvezi
notImplemented|Još nije izvedeno: potreban je protokol kartice
error|Pogreška
ok|U redu
cancel|Odustani
language|Jezik
aboutText|Jedna aplikacija za čitanje elektroničke osobne iskaznice i upravljanje tokenom. Neovisna izvedba za macOS.
"""#,
        .uk: #"""
statusReading|Читання картки…
emptyNoReaderT|Підключіть зчитувач карток
emptyNoReaderH|Підключіть зчитувач через USB: програма помітить його сама. Якщо він уже підключений, перевірте драйвер.
emptyNoCardT|Вставте картку
emptyNoCardH|Вставте картку у зчитувач до кінця.
emptyReadyT|Готово до читання
emptyReadyH|Дані залишаються на цьому комп’ютері.
demoData|Показати демонстраційні дані
demoHint|Вигадані дані, щоб побачити, як виглядає програма без картки та зчитувача.
tabCardShort|Картка
tabTokenShort|Токен
readCardAuto|Прочитати картку
hintAuto|Підключіть зчитувач і вставте картку або піднесіть картку до iPhone (NFC). Програма сама вибирає спосіб.
viewPdf|Переглянути PDF
photo|Фото
scanUsb|Прочитати картку через USB-зчитувач
usbNoReaderT|Система не бачить жодного USB-зчитувача
usbNoReaderH|Підключіть зчитувач смарт-карток (iPhone 15 або новіший через USB-C чи зчитувач MFi) і вставте картку.
hintUsb|Підключіть USB-зчитувач, вставте картку й торкніться «Прочитати картку через USB-зчитувач». Якщо в картки є чип NFC, її можна читати й через NFC.
scanCard|Прочитати картку через NFC
nfcPrompt|Піднесіть картку до верхньої частини iPhone й тримайте нерухомо
nfcReading|Читання картки… Продовжуйте тримати
nfcDone|Готово
sharePdf|Поділитися PDF
hintNfc|Торкніться «Прочитати картку через NFC» і піднесіть картку до верхньої частини iPhone.
aboutTextIOS|Читає сербську електронну ID-картку через зчитувач смарт-карток. Незалежна реалізація, не пов’язана з MUP RS чи NetSeT/Veridos.
readerHelpTitle|Немає зчитувача?
copyLogs|Копіювати журнали та помилки
copyLogsHint|Копіює технічні подробиці помилок (без даних з вашої картки), щоб вставити їх у звіт про помилку.
copyLogsDone|Журнали скопійовано. Вставте їх у звіт про помилку.
whatsNew|Що нового?
betaReport|Повідомити про помилку або залишити відгук
iosNoReaderH|Підключіть через USB-C.
iosNoReaderQ|Підключіть зчитувач смарт-карток до iPhone або iPad через USB-C: програма помітить його сама.
iosNoCardH|Вставте картку до кінця.
iosReadyH|Торкніться «Прочитати картку». Дані залишаються на цьому пристрої.
nfcUnavailableT|NFC недоступний
nfcUnavailableH|Цей пристрій не може читати картки через NFC. Потрібен iPhone 7 або новіший.
nfcNoCardT|Картку не знайдено
nfcNoCardH|Піднесіть картку до верхньої частини iPhone й тримайте нерухомо. Якщо iPhone ніколи її не виявляє, імовірно, у картки немає безконтактного чипа, і її можна читати лише USB-зчитувачем у версії для Mac або Windows.
nfcLostT|Зв’язок із карткою втрачено
nfcLostH|Тримайте картку нерухомо, доки читання не завершиться, і спробуйте знову.
menuCard|Картка
tabSettings|Налаштування
setAppearance|Вигляд
setTheme|Тема
themeSystem|Системна
themeLight|Світла
themeDark|Темна
setPrivacy|Приватність
setMask|Приховувати особистий номер, адресу та номер документа
setAutoHide|Приховувати дані при бездіяльності, хвилин (0 = ніколи)
setBehavior|Поведінка
setAutoRead|Автоматично читати картку після вставлення
setPrintJmbg|Включати особистий номер у друк і PDF
setAutoUpdate|Перевіряти оновлення під час запуску
copy|Копіювати
reveal|Показати
hideValue|Сховати
more|Більше
copyAll|Копіювати всі дані
savePhoto|Зберегти фото
exportJson|Експортувати як JSON
expiresIn|Дійсна ще %d дн.
expiredOn|Термін дії минув
certIssuer|Ким виданий
certValid|Дійсна %@ – %@
exportCert|Експортувати .cer
preview|Попередній перегляд
close|Закрити
copied|Скопійовано
autoHidden|Дані приховано через бездіяльність. Прочитайте картку знову.
errNoReaderT|Зчитувач карток не знайдено
errNoReaderH|Підключіть зчитувач через USB і натисніть «Оновити». Якщо він уже підключений, перевірте драйвер.
errNoCardT|У зчитувачі немає картки
errNoCardH|Вставте картку до кінця, чипом донизу.
errUnsupportedT|Картка не підтримується
errUnsupportedH|Підтримуються: електронна ID-картка, посвідчення для іноземців і посвідка на проживання. Старі картки (до 18.08.2014) не підтримуються.
errGenericT|Операція не вдалася
errGenericH|Вставте картку знову й спробуйте ще раз.
techDetails|Подробиці
printCard|Друк
savePdf|Зберегти PDF
pdfSaved|PDF збережено
version|Версія
checkUpdates|Перевірити оновлення
updateAvailable|Доступна нова версія %@
updateNow|Оновити
updateDownloading|Завантаження оновлення…
upToDate|У вас остання версія
updateUnavailable|Не вдалося отримати відомості про оновлення (немає мережі або репозиторій приватний)
updateFailed|Не вдалося оновити
brandSub|Сербська електронна ID-картка
hintRead|Вставте картку у зчитувач і натисніть «Прочитати картку».
hintToken|Натисніть «Прочитати токен», щоб побачити сертифікати.
docID|Електронна ID-картка
docIF|Посвідчення особи для іноземців
docRP|Посвідка на проживання
readToken|Прочитати токен
chainOk|Ланцюг до MUP CA перевірено
pinNote|Читання токена не використовує PIN. Підписання створює окремий файл CMS .p7s, який може перевірити будь-який інструмент із підтримкою CMS.
sigOk|Підпис дійсний, дані не змінені
sigChain|Не вдалося побудувати ланцюг довіри (це не означає, що дані недійсні)
sigBad|Підпис недійсний або дані змінені
nationality|Громадянство
docSerial|Серійний номер документа
pinUnsupported|Зміна PIN доступна лише для старої картки (виданої до 18.08.2014)
certMoiCA|Проміжний CA MUP
certAuth|Сертифікат для входу
certSign|Сертифікат для підписання
certSigFixed|Підписувач незмінних даних
certSigVariable|Підписувач змінних даних
appTitle|Super Čelik
tabPersonal|Дані з картки
tabToken|Токен і сертифікати
tabAbout|Про програму
reader|Зчитувач
noReader|Зчитувач не знайдено
refresh|Оновити
readCard|Прочитати картку
cardPresent|Картку вставлено
noCard|Немає картки
atr|ATR
surname|Прізвище
givenName|Ім’я
parentName|Ім’я одного з батьків
dob|Дата народження
placeOfBirth|Місце народження
sex|Стать
jmbg|Особистий номер (JMBG)
docNumber|Номер документа
issuedBy|Ким виданий
issueDate|Дата видачі
expiryDate|Дійсний до
address|Адреса
portrait|Портрет
certificates|Сертифікати
loginEuprava|Увійти на eUprava
loginEupravaNote|Відкривається сторінка eUprava. Виберіть вхід за кваліфікованим сертифікатом: система подає сертифікат картки й сама запитує PIN. Потрібен зчитувач із вставленою карткою.
loginNoDriver|Система ще не прикріпила картку до браузера, тому сайт може не бачити сертифіката. Витягніть картку, вставте знову й зачекайте кілька секунд. Усе одно відкрити сторінку входу?
changePin|Змінити PIN
currentPin|Поточний PIN
newPin|Новий PIN
confirmPin|Підтвердіть новий PIN
pinMismatch|PIN-коди не збігаються
driverStuck|Вхід у браузері: система ще не прикріпила картку до браузера. Витягніть картку й вставте знову, зачекайте кілька секунд, потім повністю закрийте браузер і відкрийте знову.
loginCheckTitle|Вхід у браузері
loginCheckOk|Усе гаразд: система бачить картку. Якщо браузер усе ще не пропонує її, повністю закрийте його (⌘Q) і відкрийте сторінку знову.
loginCheckMissing|Система ще не прикріпила картку. Витягніть її зі зчитувача й вставте назад, зачекайте кілька секунд і перевірте знову.
loginCheckNoCard|Вставте картку у зчитувач.
loginCheckBtn|Перевірити
loginHint|Браузер не пропонує картку? Повністю закрийте його (⌘Q) і відкрийте сторінку знову, або витягніть картку зі зчитувача й вставте назад.
loginCheckRun|Перевірити вхід у браузері
chkExtOk|Драйвер картки зареєстровано
chkExtNo|Драйвер картки не зареєстровано або вимкнено
chkAttachedOk|Картку прикріплено до драйвера
chkAttachedNo|Картку ще не прикріплено до драйвера
chkFfOk|Firefox використовує сертифікати macOS
chkFfOff|Firefox не використовує сертифікати macOS
stepRepair|Натисніть «Виправити», потім витягніть картку зі зчитувача й вставте назад.
repairBtn|Виправити
stepFirefox|Натисніть «Увімкнути», потім повністю закрийте Firefox (⌘Q) і відкрийте сторінку знову.
firefoxOff|Firefox налаштований не використовувати сертифікати зі зв’язки ключів, тому сертифікат картки в ньому не з’явиться. Увімкнути?
firefoxFix|Увімкнути
firefoxLater|Не зараз
firefoxDone|Готово. Повністю закрийте Firefox (⌘Q) і відкрийте сторінку знову.
firefoxFail|Не вдалося змінити налаштування Firefox.
pinStepOld|Крок 1 із 3. Введіть ПОТОЧНИЙ PIN (той, що зараз на картці).
pinStepPuk|Крок 1 із 3. Введіть PUK (код розблокування).
pinStepNew|Крок 2 із 3. Придумайте й введіть НОВИЙ PIN (4–8 цифр).
pinStepConfirm|Крок 3 із 3. Введіть НОВИЙ PIN ще раз для підтвердження.
unblockPin|Розблокувати за PUK
pukLabel|PUK (4–8 цифр)
signFile|Підписати файл
signedSaved|Підпис збережено
fileTooLarge|Файл надто великий для підписання на телефоні (до 100 МБ)
fileUnreadable|Не вдалося прочитати файл
pinWarn|Неправильний PIN/PUK витрачає спробу; токен блокується, коли спроб не лишається. Розблокування за PUK не перевірено на справжній картці.
pinWrongMsg|Неправильний PIN/PUK. Залишилось спроб: 
pinBlockedMsg|PIN заблоковано. Скористайтеся «Розблокувати за PUK».
pinInvalid|PIN/PUK має містити 4–8 цифр
pinUnblocked|PIN розблоковано й замінено
signNeedCert|На токені не знайдено сертифіката
pinChanged|PIN змінено
pinFailed|Не вдалося змінити PIN
verifySignature|Перевірити підпис
export|Експорт
notImplemented|Ще не реалізовано: потрібен протокол картки
error|Помилка
ok|OK
cancel|Скасувати
language|Мова
aboutText|Єдина програма для читання електронної ID-картки та керування токеном. Незалежна реалізація для macOS.
"""#,
        .be: #"""
statusReading|Чытанне карты…
emptyNoReaderT|Падключыце счытвальнік карт
emptyNoReaderH|Падключыце счытвальнік праз USB: праграма заўважыць яго сама. Калі ён ужо падключаны, праверце драйвер.
emptyNoCardT|Устаўце карту
emptyNoCardH|Устаўце карту ў счытвальнік да канца.
emptyReadyT|Гатова да чытання
emptyReadyH|Даныя застаюцца на гэтым кампутары.
demoData|Паказаць дэманстрацыйныя даныя
demoHint|Выдуманыя даныя, каб убачыць, як выглядае праграма без карты і счытвальніка.
tabCardShort|Карта
tabTokenShort|Токен
readCardAuto|Счытаць карту
hintAuto|Падключыце счытвальнік і ўстаўце карту або прыкладзіце карту да iPhone (NFC). Праграма сама выбірае спосаб.
viewPdf|Праглядзець PDF
photo|Фота
scanUsb|Счытаць карту праз USB-счытвальнік
usbNoReaderT|Сістэма не бачыць ніводнага USB-счытвальніка
usbNoReaderH|Падключыце счытвальнік смарт-карт (iPhone 15 або навейшы праз USB-C ці счытвальнік MFi) і ўстаўце карту.
hintUsb|Падключыце USB-счытвальнік, устаўце карту і націсніце «Счытаць карту праз USB-счытвальнік». Калі ў карты ёсць чып NFC, яе можна чытаць і праз NFC.
scanCard|Счытаць карту праз NFC
nfcPrompt|Прыкладзіце карту да верхняй часткі iPhone і трымайце нерухома
nfcReading|Чытанне карты… Працягвайце трымаць
nfcDone|Гатова
sharePdf|Падзяліцца PDF
hintNfc|Націсніце «Счытаць карту праз NFC» і прыкладзіце карту да верхняй часткі iPhone.
aboutTextIOS|Чытае сербскую электронную ID-карту праз счытвальнік смарт-карт. Незалежная рэалізацыя, не звязаная з MUP RS або NetSeT/Veridos.
readerHelpTitle|Няма счытвальніка?
copyLogs|Капіяваць журналы і памылкі
copyLogsHint|Капіюе тэхнічныя падрабязнасці памылак (без даных з вашай карты), каб уставіць іх у справаздачу пра памылку.
copyLogsDone|Журналы скапіраваны. Устаўце іх у справаздачу пра памылку.
whatsNew|Што новага?
betaReport|Паведаміць пра памылку або пакінуць водгук
iosNoReaderH|Падключыце праз USB-C.
iosNoReaderQ|Падключыце счытвальнік смарт-карт да iPhone або iPad праз USB-C: праграма заўважыць яго сама.
iosNoCardH|Устаўце карту да канца.
iosReadyH|Націсніце «Счытаць карту». Даныя застаюцца на гэтай прыладзе.
nfcUnavailableT|NFC недаступны
nfcUnavailableH|Гэта прылада не можа чытаць карты праз NFC. Патрэбны iPhone 7 або навейшы.
nfcNoCardT|Карта не знойдзена
nfcNoCardH|Прыкладзіце карту да верхняй часткі iPhone і трымайце нерухома. Калі iPhone ніколі яе не выяўляе, імаверна, у карты няма бескантактавага чыпа, і яе можна чытаць толькі USB-счытвальнікам у версіі для Mac або Windows.
nfcLostT|Сувязь з картай страчана
nfcLostH|Трымайце карту нерухома, пакуль чытанне не завершыцца, і паспрабуйце зноў.
menuCard|Карта
tabSettings|Налады
setAppearance|Выгляд
setTheme|Тэма
themeSystem|Сістэмная
themeLight|Светлая
themeDark|Цёмная
setPrivacy|Прыватнасць
setMask|Хаваць асабісты нумар, адрас і нумар дакумента
setAutoHide|Хаваць даныя пры бяздзейнасці, хвілін (0 = ніколі)
setBehavior|Паводзіны
setAutoRead|Аўтаматычна чытаць карту пасля ўстаўлення
setPrintJmbg|Уключаць асабісты нумар у друк і PDF
setAutoUpdate|Правяраць абнаўленні пры запуску
copy|Капіяваць
reveal|Паказаць
hideValue|Схаваць
more|Больш
copyAll|Капіяваць усе даныя
savePhoto|Захаваць фота
exportJson|Экспартаваць як JSON
expiresIn|Дзейсная яшчэ %d дн.
expiredOn|Тэрмін дзеяння скончыўся
certIssuer|Кім выдадзены
certValid|Дзейсная %@ – %@
exportCert|Экспартаваць .cer
preview|Папярэдні прагляд
close|Закрыць
copied|Скапіравана
autoHidden|Даныя схаваны праз бяздзейнасць. Счытайце карту зноў.
errNoReaderT|Счытвальнік карт не знойдзены
errNoReaderH|Падключыце счытвальнік праз USB і націсніце «Абнавіць». Калі ён ужо падключаны, праверце драйвер.
errNoCardT|У счытвальніку няма карты
errNoCardH|Устаўце карту да канца, чыпам уніз.
errUnsupportedT|Карта не падтрымліваецца
errUnsupportedH|Падтрымліваюцца: электронная ID-карта, пасведчанне для іншаземцаў і від на жыхарства. Старыя карты (да 18.08.2014) не падтрымліваюцца.
errGenericT|Аперацыя не ўдалася
errGenericH|Устаўце карту зноў і паспрабуйце яшчэ раз.
techDetails|Падрабязнасці
printCard|Друк
savePdf|Захаваць PDF
pdfSaved|PDF захаваны
version|Версія
checkUpdates|Праверыць абнаўленні
updateAvailable|Даступная новая версія %@
updateNow|Абнавіць
updateDownloading|Спампоўка абнаўлення…
upToDate|У вас апошняя версія
updateUnavailable|Не атрымалася атрымаць звесткі пра абнаўленне (няма сеткі або рэпазітар прыватны)
updateFailed|Не атрымалася абнавіць
brandSub|Сербская электронная ID-карта
hintRead|Устаўце карту ў счытвальнік і націсніце «Счытаць карту».
hintToken|Націсніце «Счытаць токен», каб убачыць сертыфікаты.
docID|Электронная ID-карта
docIF|Пасведчанне асобы для іншаземцаў
docRP|Від на жыхарства
readToken|Счытаць токен
chainOk|Ланцужок да MUP CA правераны
pinNote|Чытанне токена не выкарыстоўвае PIN. Падпісанне стварае асобны файл CMS .p7s, які можа праверыць любы інструмент з падтрымкай CMS.
sigOk|Подпіс сапраўдны, даныя не змененыя
sigChain|Не атрымалася пабудаваць ланцужок даверу (гэта не значыць, што даныя несапраўдныя)
sigBad|Подпіс несапраўдны або даныя зменены
nationality|Грамадзянства
docSerial|Серыйны нумар дакумента
pinUnsupported|Змена PIN даступная толькі для старой карты (выдадзенай да 18.08.2014)
certMoiCA|Прамежкавы CA MUP
certAuth|Сертыфікат для ўваходу
certSign|Сертыфікат для падпісання
certSigFixed|Падпісант нязменных даных
certSigVariable|Падпісант зменных даных
appTitle|Super Čelik
tabPersonal|Даныя з карты
tabToken|Токен і сертыфікаты
tabAbout|Пра праграму
reader|Счытвальнік
noReader|Счытвальнік не знойдзены
refresh|Абнавіць
readCard|Счытаць карту
cardPresent|Карту ўстаўлена
noCard|Няма карты
atr|ATR
surname|Прозвішча
givenName|Імя
parentName|Імя аднаго з бацькоў
dob|Дата нараджэння
placeOfBirth|Месца нараджэння
sex|Пол
jmbg|Асабісты нумар (JMBG)
docNumber|Нумар дакумента
issuedBy|Кім выдадзены
issueDate|Дата выдачы
expiryDate|Дзейсны да
address|Адрас
portrait|Партрэт
certificates|Сертыфікаты
loginEuprava|Увайсці ў eUprava
loginEupravaNote|Адкрываецца старонка eUprava. Выберыце ўваход па кваліфікаваным сертыфікаце: сістэма падае сертыфікат карты і сама запытвае PIN. Патрэбны счытвальнік з устаўленай картай.
loginNoDriver|Сістэма яшчэ не прымацавала карту да браўзера, таму сайт можа не бачыць сертыфіката. Выміце карту, устаўце зноў і пачакайце некалькі секунд. Усё роўна адкрыць старонку ўваходу?
changePin|Змяніць PIN
currentPin|Бягучы PIN
newPin|Новы PIN
confirmPin|Пацвердзіце новы PIN
pinMismatch|PIN-коды не супадаюць
driverStuck|Уваход у браўзеры: сістэма яшчэ не прымацавала карту да браўзера. Выміце карту і ўстаўце зноў, пачакайце некалькі секунд, потым цалкам зачыніце браўзер і адкрыйце зноў.
loginCheckTitle|Уваход у браўзеры
loginCheckOk|Усё добра: сістэма бачыць карту. Калі браўзер усё яшчэ не прапануе яе, цалкам зачыніце яго (⌘Q) і адкрыйце старонку зноў.
loginCheckMissing|Сістэма яшчэ не прымацавала карту. Выміце яе са счытвальніка і ўстаўце назад, пачакайце некалькі секунд і праверце зноў.
loginCheckNoCard|Устаўце карту ў счытвальнік.
loginCheckBtn|Праверыць
loginHint|Браўзер не прапануе карту? Цалкам зачыніце яго (⌘Q) і адкрыйце старонку зноў, або выміце карту са счытвальніка і ўстаўце назад.
loginCheckRun|Праверыць уваход у браўзеры
chkExtOk|Драйвер карты зарэгістраваны
chkExtNo|Драйвер карты не зарэгістраваны або адключаны
chkAttachedOk|Карта прымацавана да драйвера
chkAttachedNo|Карта яшчэ не прымацавана да драйвера
chkFfOk|Firefox выкарыстоўвае сертыфікаты macOS
chkFfOff|Firefox не выкарыстоўвае сертыфікаты macOS
stepRepair|Націсніце «Выправіць», потым выміце карту са счытвальніка і ўстаўце назад.
repairBtn|Выправіць
stepFirefox|Націсніце «Уключыць», потым цалкам зачыніце Firefox (⌘Q) і адкрыйце старонку зноў.
firefoxOff|Firefox наладжаны не выкарыстоўваць сертыфікаты з сувязі ключоў, таму сертыфікат карты ў ім не з’явіцца. Уключыць?
firefoxFix|Уключыць
firefoxLater|Не цяпер
firefoxDone|Гатова. Цалкам зачыніце Firefox (⌘Q) і адкрыйце старонку зноў.
firefoxFail|Не атрымалася змяніць налады Firefox.
pinStepOld|Крок 1 з 3. Увядзіце БЯГУЧЫ PIN (той, што цяпер на карце).
pinStepPuk|Крок 1 з 3. Увядзіце PUK (код разблакіроўкі).
pinStepNew|Крок 2 з 3. Прыдумайце і ўвядзіце НОВЫ PIN (4–8 лічбаў).
pinStepConfirm|Крок 3 з 3. Увядзіце НОВЫ PIN яшчэ раз для пацверджання.
unblockPin|Разблакіраваць праз PUK
pukLabel|PUK (4–8 лічбаў)
signFile|Падпісаць файл
signedSaved|Подпіс захаваны
fileTooLarge|Файл занадта вялікі для падпісання на тэлефоне (да 100 МБ)
fileUnreadable|Не атрымалася счытаць файл
pinWarn|Няправільны PIN/PUK расходуе спробу; токен блакіруецца, калі спроб не застаецца. Разблакіроўка праз PUK не правераная на сапраўднай карце.
pinWrongMsg|Няправільны PIN/PUK. Засталося спроб: 
pinBlockedMsg|PIN заблакіраваны. Скарыстайцеся «Разблакіраваць праз PUK».
pinInvalid|PIN/PUK павінен змяшчаць 4–8 лічбаў
pinUnblocked|PIN разблакіраваны і заменены
signNeedCert|На токене не знойдзена сертыфіката
pinChanged|PIN зменены
pinFailed|Не атрымалася змяніць PIN
verifySignature|Праверыць подпіс
export|Экспарт
notImplemented|Яшчэ не рэалізавана: патрэбны пратакол карты
error|Памылка
ok|OK
cancel|Скасаваць
language|Мова
aboutText|Адна праграма для чытання электроннай ID-карты і кіравання токенам. Незалежная рэалізацыя для macOS.
"""#,
    ]
}
