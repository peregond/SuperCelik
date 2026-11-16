# Super Čelik для iPhone и iPad

Приложение читает карту через проводной считыватель смарт-карт (USB-C или MFi) и использует тот же код, что и версия для Mac:
протокол карты (`Sources/SerbiaID/EidCard.swift`), проверку подписи МУП, разбор сертификата
токена и печатную форму МУП (`MupPrintLayout.swift`, PDF один в один как на Mac).

Приложение следит за считывателем: на экранах «Карта» и «Токен» видно, подключён ли считыватель и вставлена ли карта.

## Чтение по NFC отключено
Код чтения по NFC (`NFCCardReader.swift`) остался в проекте, но выключен флагом `PhoneModel.nfcEnabled = false`.
Разрешение NFC убрано из `Config/SuperCelik.entitlements` и `Config/Info.plist`; как вернуть, написано в комментарии
в entitlements. По открытым данным у сербских ID-карт чип только контактный, поэтому NFC для них не подходит.

## Не проверено на устройстве
Работа проводного считывателя на iPhone/iPad зависит от того, показывает ли iOS этот считыватель приложению
(`TKSmartCardSlotManager`). Нужен USB-C iPhone 15 и новее или iPad с CCID-считывателем, либо MFi-считыватель.
Если система считыватель не показывает, приложение остаётся в состоянии «не подключён».
Демо-данные (Настройки → «Показать демо-данные») работают без карты.

## Готовые сборки
CI на каждый PR и на каждый релиз собирает два файла (в Actions: артефакт `SuperCelik-iOS`, в релизе: рядом с dmg):
- `SuperCelik-<версия>-iOS-simulator.zip`: приложение для симулятора iPhone на Mac. Нужен только Xcode (в нём есть Simulator).
  Распакуйте, запустите Simulator, выберите любой iPhone и перетащите `SuperCelik.app` на окно симулятора.
- `SuperCelik-<версия>-iOS-unsigned.ipa`: сборка для iPhone **без подписи**; её нужно подписать своим аккаунтом
  (Sideloadly, AltStore, Apple Configurator или `Xcode → Devices`).

## Публикация в App Store
См. `docs/APPSTORE.md`: запись приложения с bundle id `app.supercelik`, секреты `APPLE_TEAM_ID`, `ASC_KEY_ID`,
`ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64` и workflow «App Store (iOS / iPadOS)».

## Сборка из Xcode
Откройте `ios/SuperCelik.xcodeproj` (папку репозитория нужно скачать целиком: проект берёт общий код из `Sources/SerbiaID`).
Цель SuperCelik → Signing & Capabilities → выберите свою команду (Team). Если bundle id `app.supercelik` занят, поменяйте его.
