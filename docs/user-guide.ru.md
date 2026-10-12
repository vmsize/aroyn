# Использование Aroyn

Откройте [aroyn.xyz](https://aroyn.xyz/) → **Open dashboard → Sign in with Discord**. Превью на главной использует иллюстративные данные. Доступ к вашим runtime-данным требует авторизации и привязанного работающего клиента.

## Hub 4.3.96

12 октября 2026 года публичный manifest независимо проверен: выбирается **4.3.96**. Обычная команда:

```luau
loadstring(game:HttpGet("https://aroyn.xyz/scripts/loader.luau"))()
```

Команда исполняет скачанный Luau в совместимой среде Greedy Growers; браузер Roblox-скрипты не запускает. Владелец сообщил успешную проверку точного immutable файла на Windows/Potassium и Android/Delta. Это не обещание совместимости со всеми executor/телефонами. См. [compatibility](compatibility.md) и [release identity](client-release.md).

В 4.3.96 — новый UI с восемью страницами. Покупка семян, сбор, compost, market и кормление включаются вручную. Автоматизация остаётся выключенной при старте и загрузке настроек/профиля.

## Подключение Dashboard

1. Войдите на сайте через Discord; при необходимости создайте/откройте Dashboard key в меню аккаунта.
2. В **4.3.96** откройте **Settings → Dashboard and preferences**, введите ключ и нажмите **Link**. Credential хранится отдельно от предпочтений.
3. **Auto-connect Dashboard** разрешает восстановление сохранённого подключения на следующих запусках. Ошибка необязательного подключения не блокирует сам Hub.
4. На сайте откройте **Dashboard → Runtime**. Inventory/activity/statistics появляются при наличии соответствующих данных клиента.
5. **Disconnect** останавливает подключение и intent повторного соединения; **Unlink** удаляет сохранённую привязку. Обычное закрытие клиента не означает явный unlink.

В старом **4.3.95** linking panel находится в **Session**. Опубликованные Hub docs ещё могут описывать старую структуру.

Ключ — credential: не публикуйте его в скриншотах, issues, логах и чате. Для диагностики проверяйте saved link, Auto-connect и конфигурацию сервисов, не пересылая ключ.

## Настройки и восстановление

Именованные профили и AutoSave работают при доступных файловых API; AutoSave можно выключить в Settings. Предыдущая успешно сохранённая копия доступна через **Restore previous saved profile**. Некорректный record не считается корректной конфигурацией; ошибки файловой системы могут ограничить сохранение текущей сессией. Полная защита от любого interrupted write не заявлена.

Загрузка настроек не включает automation. Сохраняйте backup-файлы при диагностике. При намеренном downgrade на 4.3.95 сначала закройте текущий клиент и проверьте toggles: legacy restore может вернуть automation ON, новые профили автоматически назад не мигрируют.

Повторный обычный loader скачивает выбранную manifest версию; уже запущенный клиент сам по себе не заменяется. Проверки размера/HTML внутри loader не заменяют независимый SHA256 check. См. [release verification](release-verification.md).

## Данные аккаунта

Меню аватара → **Account data**: export/delete. Удаление требует недавнего Discord sign-in и ввода `DELETE`; удаляется Aroyn account и отзываются его sessions/keys, а не Discord/Roblox аккаунты. Документированная retention: history 30 дней без обновлений, snapshot 7 дней. [Scope/limits](account-data.md).

Aroyn — новое имя Veyra Hub; совместимые технические имена сохранены. Статический preview не является полноценным telemetry service. [Local setup](setup.md); [status](https://aroyn.xyz/status/) проверяет HTTP availability, а не полный OAuth/gameplay flow.
