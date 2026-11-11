# Super Celik для Android

Kotlin + Jetpack Compose, дизайн Material You (динамические цвета с Android 12, на Android 8–11 палитра из цветов флага).
Читает личные данные и фото сербской ID-карты, карты иностранца и вида на жительство:

- **по NFC** (если в карте есть бесконтактный чип);
- **через USB-ридер CCID** (например Gemalto CT40) по OTG-кабелю: приложение само говорит с ридером через USB host API.

Протокол карты портирован из `Sources/SerbiaID/EidCard.swift`. Языки: RU / EN / SR (по языку системы).

## Статус
Первая версия. Чтение данных написано, но **ни на телефоне, ни с настоящим ридером не проверялось**: CI проверяет только сборку.
Пока нет: проверки подписи МУП, печати/PDF, PIN, подписи файла (всё это есть в версии для Mac).

## Сборка
Android Studio (Koala или новее) → открыть папку `android` → Run. Или в командной строке (нужны JDK 17, Android SDK и Gradle 8.9):

    gradle -p android assembleDebug

APK: `android/app/build/outputs/apk/debug/`. Сборка также делается в GitHub Actions (артефакт `SuperCelik-android-debug`).
