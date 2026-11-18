# Super Čelik для Linux (бета)

Версия для Linux в **бета-статусе**: в окне приложения это помечено, во вкладке «О программе» есть ссылка на [GitHub Issues](https://github.com/peregond/SuperCelik/issues/new) для сообщений об ошибках и отзывов.

Avalonia (.NET 8). Протокол карты, проверка подписи (CMS + цепочка до сертификатов МУП), подпись файла и тексты общие с Windows-версией:
файлы `windows/SerbiaID.Windows/{Card,CardErrors,Crypto,Models,Loc,SerbianScript,SelfTest}.cs` подключены ссылками. Своё здесь только:
доступ к PC/SC через `libpcsclite` (`Native.cs`), интерфейс и макет печатного листа (`PrintSheet.cs`, PDF через SkiaSharp).

## Что нужно в системе
- `pcscd` и `libpcsclite1` (в .deb прописаны как зависимости); для не-Debian: `pcsc-lite` / `pcsclite`.
- USB-ридер смарт-карт. Если приложение пишет «Служба смарт-карт не запущена»: `sudo systemctl enable --now pcscd.socket`.
- Для открытия PDF / страницы релиза: `xdg-utils` (необязательно).

## Чего нет по сравнению с Windows
- Вход в браузере по сертификату с карты: на Linux это делается PKCS#11-модулем (OpenSC или [srb-id-pkcs11](https://github.com/ubavic/srb-id-pkcs11)) в настройках браузера, приложение этого не настраивает.
- Автообновление: приложение только сообщает о новой версии и открывает страницу релиза.
- Печать: «Печать» сохраняет PDF во временный файл и открывает его в просмотрщике (там окно печати), «Сохранить PDF» кладёт файл куда выберете.

## Запуск и проверка
    dotnet run --project linux/SerbiaID.Linux -- --demo [вкладка 0-3] [--dark] [--state noreader|nocard|busy|error]
    dotnet run --project linux/SerbiaID.Linux -- --demo --shot out.png      # окно как PNG (вымышленные данные)
    dotnet run --project linux/SerbiaID.Linux -- --demo --pdf out.pdf       # печатный лист как PDF
    SuperCelik --selftest                                                  # отчёт по реальной карте без личных данных (selftest.txt рядом с программой)

Настройки: `~/.config/SuperCelik/settings.json`. Язык интерфейса берётся из `LANG` (ru / sr / en), меняется на вкладке «Настройки».

**Статус:** на реальной карте под Linux не проверялось (разработка велась на Mac: интерфейс, PDF и сборка проверены, чтение карты через `libpcsclite` и CMS-подпись на Linux — нет). Первым делом запустите `--selftest`.
