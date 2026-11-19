<p align="center"><a href="README.md">English</a> · <b>Русский</b> · <a href="README.sr.md">Srpski</a></p>

# Сборка для Mac App Store

Магазинная сборка делается из того же кода, что и приложение для прямой загрузки, и компилируется с `-Xswiftc -DAPPSTORE`:
- без самообновления (приложения Mac App Store не должны обновляться сами) и без сетевого кода, кроме страницы про считыватели внутри приложения (`com.apple.security.network.client`, только для celik.peregon.cc/reader);
- без вспомогательных процессов (`pluginkit`, `pkill`, `security`): в песочнице macOS сама находит и запускает
  встроенное расширение CryptoTokenKit;
- песочница + `com.apple.security.smartcard` (PC/SC), доступ к выбранным пользователем файлам, печать (`AppStore.entitlements`);
- расширение тоже работает в песочнице (`AppStoreToken.entitlements`).

Сборка (на Mac): `bash scripts/make-appstore-mac.sh <версия> <сборка>`.
`UNSIGNED=1` делает приложение с ad-hoc подписью для проверки состава (так делает CI). Для пакета магазина нужно из аккаунта разработчика:

| Что | Где взять |
|---|---|
| Team id (`TEAM_ID`) | developer.apple.com > Membership |
| Сертификат *3rd Party Mac Developer Application* (или *Apple Distribution*) | Certificates, Identifiers & Profiles |
| Сертификат *3rd Party Mac Developer Installer* | там же |
| App ID `app.supercelik` и `app.supercelik.token` (Mac) | Identifiers |
| Два профиля *Mac App Store*, по одному на App ID | Profiles |
| Ключ App Store Connect API (для загрузки) | App Store Connect > Users and Access > Integrations |

Workflow `App Store (macOS)` делает всё это из секретов репозитория; см. его заголовок.

**Не проверено:** без аккаунта разработчика здесь ничего нельзя было подписать или запустить в песочнице. Вероятные замечания первого раунда:
профиль песочницы для расширения CryptoTokenKit и видимость карты в связке ключей Safari/Chrome в сборке с песочницей.
