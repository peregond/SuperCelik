<p align="center"><img src="assets/icon-mac-1024.png" width="128" alt="Super Celik"></p>

# Super Celik

Единое приложение вместо Čelik + TrustEdge ID для сербской электронной ID-карты, карты иностранца и вида на жительство.
Языки: RU / EN / SR. Версии: **macOS** (SwiftUI) и **Windows** (WPF, .NET 8).
Независимая реализация, не связана с МУП РС и NetSeT/Veridos.

## Установка (готовые сборки — раздел Releases)
- **macOS 13+**: `SuperCelik-<версия>-macOS-apple-silicon.dmg` (M1 и новее) или `...-intel.dmg`. Откройте dmg и перетащите Super Celik в «Программы».
  Приложение подписано ad-hoc и не нотаризовано: при первом запуске — правый клик → «Открыть», либо
  `xattr -dr com.apple.quarantine /Applications/SuperCelik.app`.
- **Windows 10/11 x64**: `SuperCelik-<версия>-windows-x64-setup.exe`. Установщик не подписан сертификатом издателя: SmartScreen может показать предупреждение («Подробнее» → «Выполнить в любом случае»).

Сборка делается автоматически в GitHub Actions: каждый push в `main` → артефакты; тег `vX.Y.Z` → релиз.

## Сборка вручную
macOS (Xcode 15+ / Swift 5.9):

    swift run                         # с реальным ридером
    SERBIAID_DEMO=1 swift run         # демо-данные без карты
    bash scripts/make-app.sh 0.1.0 arm64   # или x86_64 / universal → dist/*.dmg

Windows (.NET 8 SDK):

    dotnet build windows/SerbiaID.Windows -c Release
    windows\SerbiaID.Windows\bin\Release\net8.0-windows\SuperCelik.exe --selftest   # проверка на реальной карте, отчёт selftest.txt без личных данных

## Статус
- Готово (обе платформы): интерфейс на трёх языках, поиск ридеров и ATR через PC/SC, чтение личных данных, адреса, документа и фото, проверка подписи (CMS + цепочка до сертификатов МУП из `Resources/CA`), чтение сертификата токена с проверкой цепочки, печать / PDF.
- **Проверено на реальной карте только в Windows-версии** (RP2024, `--selftest`): данные, фото, обе подписи и цепочка сертификатов токена прошли. macOS-версия использует тот же протокол, но на Mac код ещё не собирался и не запускался.
- Протокол получен наблюдением за `CelikApi.dll` и реальной картой; поля сверены с выводом DLL. Для ID-карты (SERID) и карты иностранца (SERIF) файлы, вероятно, те же, но не проверено; теги с пометкой UNVERIFIED в коде — предположения.
- PIN токена и подпись (`tokenSign`, `changeTokenPin`) реализованы в коде, но **в интерфейсе не подключены** и вживую не проверялись (неверный PIN тратит попытку). Заголовки APDU сверены с оригинальной `netsetpkcs11_x64.dll`, выбор ключа и отказ подписи без PIN (6982) проверены вживую.
- Вход в браузере по сертификату (eid.gov.rs) на **macOS**: в приложение встроен драйвер карты для macOS (CryptoTokenKit), см. ниже. Собран, но **на реальной карте ещё не проверен**. На Windows для входа в браузере пока нужен официальный драйвер MUP / NetSeT.
- Не готово: старая карта Apollo (протокол неизвестен).

## Вход на eid.gov.rs через Chrome / Safari (macOS)
Chrome и Safari на Mac берут клиентские сертификаты только из связки ключей macOS. Карта попадает туда
только через системный драйвер (CryptoTokenKit), а у MUP / NetSeT драйвера для macOS нет, поэтому
раньше сайт писал, что сертификат не найден, хотя Super Celik карту читал.

Теперь драйвер лежит внутри приложения (`SuperCelik.app/Contents/PlugIns/SuperCelikToken.appex`):
1. Установите Super Celik в «Программы» и запустите его один раз: приложение регистрирует драйвер
   и кладёт промежуточные сертификаты МУП в связку ключей «Вход» (только сертификаты, доверие не меняется).
2. Вставьте карту. Проверка в Терминале: `security list-smartcards` (должна появиться строка
   `com.peregond.supercelik.token:SuperCelik-…`) и `pluginkit -m -p com.apple.ctk-tokens`.
3. Полностью закройте Chrome (⌘Q) и откройте сайт снова. Chrome покажет выбор сертификата,
   а PIN попросит сама macOS в системном окне. Неверный PIN тратит попытку.

Если драйвер не появился в `pluginkit -m -p com.apple.ctk-tokens`: `pluginkit -a /Applications/SuperCelik.app/Contents/PlugIns/SuperCelikToken.appex`,
затем вытащить и вставить карту. Firefox можно настроить и без этого, через PKCS#11-модуль
[srb-id-pkcs11](https://github.com/ubavic/srb-id-pkcs11).

## Безопасность
Не коммитьте дампы карты и любые личные данные (см. `.gitignore`).
