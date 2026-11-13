# Внешний сервер управления и журналов

Реализованы исходящее соединение OpenOS → внешний TCP-сервер, взаимный RPC,
доверенный heartbeat, зашифрованный spool → подтверждённое сохранение на сервере,
расшифровка и Discord outbox. На ПК проверен настоящий обмен Lua приложения
с Python-сервером по localhost TCP с ECDSA/AES. Minecraft, реальная Internet/Data
Card, внешний сервер и настоящий Discord webhook ещё не проверялись и не настроены.

## Канал и доверие

`cnc/channel.lua` открывает исходящий `internet.connect(host,port)` через указанный
component address интернет-карты. Используются finishConnect/read/write без
ожидания данных внутри callback; частичная запись, пустое чтение, EOF и таймаут
подключения обрабатываются отдельно. Нужны разрешённые TCP и адрес/порт в
конфигурации самого OpenComputers. Входящее интернет-соединение в OpenOS не нужно.
После разрыва канал закрывает socket и переподключается с backoff 1…30 s;
backoff сбрасывается после аутентифицированного heartbeat.

TCP переносит существующие RPC frames: u32 big-endian длина (1…98304), затем
ровно столько байтов `rpc/protocol.lua`. Logical RPC port — 27016, service `rpc`.
При включении CnC приложение требует этот же logical port для LAN RPC. Внешний
TCP port можно менять отдельно. Новый raw command/анонимный heartbeat API не вводится.
Карты LAN и интернет-карта обслуживаются одним RPC instance. Discovery/bus через
интернет не пересылаются. Разрешён только configured peer; его адрес — статическое
имя внешней RPC identity, например `cnc-server`, привязанное сертификатом.
Адрес узла в игре — настоящий component address интернет-карты.

Обе стороны pin точные байты сертификата другой стороны и проверяют CA, usage,
адрес, подпись, grants, nonce/challenge/recipient. Замена сертификата требует
обновления конфигурации/pin. Node certificate на ПК указывается явно, чужой
сертификат того же CA не подходит. CnC certificate обычно имеет subject Owner,
usage client+server и права нужных моделей; команды затем проходят owner/admin
ACL целевой модели. Ship certificate имеет subject Ship и grants только серверных
методов `_cnc.heartbeat`/`_logs.put`. Частные ключи CnC и расшифровки логов на
корабль не копируются. Сертификаты статические, отзыв — serial в `revoked` и restart.

Подпись не шифрует RPC payload. Экран, ввод и результаты управляющих запросов
остаются видимыми на канале; содержимое log upload уже зашифровано отдельным
публичным ключом. Отражение/повтор старых frames не создаёт новый вызов без
свежего подписанного invoke. Сбой результата после действия может оставлять
исход неизвестным; команды не повторяются с новым ID автоматически.

## Heartbeat и оборонительная политика

Agent асинхронно вызывает `_cnc.heartbeat` раз в 10 s через RPC begin/poll/take.
Только успешный ответ `{alive=true}` на текущий challenge-bound вызов обновляет
`cnc.lastHeartbeat`. Канал отличает TCP `connected` от подтверждённого `trusted`.
Одноразовый частный объект-подтверждение внутри процесса передаётся в defense;
`verifyHeartbeat` принимает его ровно один раз. Ни `{alive=true}`, ни сетевое
событие, ни discovery не являются таким доказательством. На сервере соединение
регистрируется для команд только после свежего heartbeat invoke, а не после
записанного ранее hello или одного успешного TCP connect.

App связывает этот verifier с уже имеющимся OR-правилом Scorched Earth.
Возраст heartbeat считается по uptime клиента, часы ПК и Minecraft не сверяются.
Начальная льгота после старта — существующий `defense.heartbeatTimeout`; без
связи с сервером возраст продолжает расти. Для проверки используется armed=false
и контрольные лампы. Остальные службы не зависят от CnC.

## Ключи и конфигурация

PKI/DER и создание CA описаны в [rpc.md](rpc.md). Дополнительно создать отдельные
identity ключи `cnc`, `ship` и ключ получателя `logs` через `tools/pki.py keygen`.
Пример grants для ship:

```json
{"_cnc":["heartbeat","whitelist","alert"],"_logs":["put"]}
```

The `_cnc.whitelist` method returns the node-scoped whitelist configured in the
server database. Set it with `python3 -m server.control --database DB
whitelist-set --node INTERNET-CARD-ADDRESS --entries-file whitelist.json` where
the file is a JSON array of exact target IDs/names. The satellite copies it to
its encrypted local cache when a local encryption adapter is configured. The
`_cnc.alert` method durably records mine alerts in SQLite; it does not execute
operator commands or acknowledge that an attack succeeded.

Operators can inspect the latest heartbeat and recorded alerts with
`python3 -m server.control --database DB satellite-status --node NODE` and
`python3 -m server.control --database DB satellite-alerts --node NODE`.

Выпустить ship certificate с subject `Ship`, usage `client` и `server`, адресом
интернет-карты и этими grants. Если этот же ключ обслуживает LAN, добавить его
modem/tunnel addresses. Выпустить CnC certificate с subject из `owners`, адресом
`cnc-server`, usage `client` и `server` и выбранными правами моделей. Пример команды
выдачи (файлы/адреса заменить на свои):

```sh
python3 tools/pki.py issue --ca-private .runtime/pki/root/private.der --public-key .runtime/pki/ship/public.der --subject Ship --address INTERNET-CARD-ADDRESS --usage client --usage server --grants .runtime/pki/ship-grants.json --out .runtime/pki/ship/node.cert
```

На корабле настроить `rpc` и `cnc` из `config.example.lua`. `cnc.actor` — subject
собственного client certificate Ship, не ник внешнего оператора. Настроить
`crypto.publicKeyFile` на public DER ключ logs и включить Data Card encryption.
Для журнала `nodeId` по умолчанию machine address; он может отличаться от адреса
интернет-карты, namespace хранения на сервере всё равно определяется проверенным
RPC sender. `network.enabled` необязателен для компьютера только с интернет-картой.

На ПК скопировать проект, установить `requirements-tools.txt` в своё Python
окружение (Python 3.11+). Скопировать [server/config.example.json](../server/config.example.json),
указать CA public key, CnC private/certificate, ship certificate pin,
logs private key и путь БД. `bind=127.0.0.1` подходит локальным проверкам; для
Minecraft на другом хосте выбрать слушающий адрес, достижимый с сервера игры.
Настоящие ключи, hostname, bind и webhook этим проектом не установлены.

```sh
python3 -m server.main --config /path/to/server.json
```

PC server запускается отдельно от обновляемых Lua generations. Секреты и SQLite
должны находиться вне исходников. SQLite-файл создаётся с mode 0600; рядом с ним
работают штатные SQLite WAL/SHM. Хранение журналов использует WAL и synchronous=FULL;
реальная надёжность диска/ФС остаётся свойством выбранного сервера.

## Отправка и хранение журналов

Logger сначала шифрует запись, затем сохраняет `.sealed` на HDD. Agent начинает
`_logs.put{id,data}` и возвращает pending без ожидания сети. Следующие ticks
проверяют тот же вызов. Logger сохраняет приоритет pending filename: появление
`node-10.sealed` не вытесняет ожидающий ACK `node-2.sealed`. Timer обрабатывает
до 8 новых записей и 4 подтверждённых файлов за tick; лимиты задаются через
`logging.maxRecordsPerTick`/`maxUploadsPerTick`. Явный flush/stop пытается обработать
всю очередь. Ошибка шифрования/диска/сети оставляет очередь/файл для повтора.

Сервер проверяет ECDH P-256 → HKDF-SHA256 → AES128CBC + HMACSHA256, затем структуру
записи. Шифрованный blob, расшифрованная запись и intent уведомления сохраняются
одной SQLite-транзакцией. Только после commit возвращается `{receipt=id,
digest=SHA256(sealed)}` в подписанном RPC result. Agent проверяет оба поля,
затем logger удаляет локальный файл. Такое же содержимое с прежним node/id даёт
тот же ACK; другое содержимое — конфликт, без перезаписи. У разных узлов namespaces
независимы. Потеря ACK после commit допускает повтор нового RPC с прежним log ID.
Без криптопровайдера остаётся прежняя ограниченная RAM-очередь, plaintext на HDD
не пишется и не отправляется вместо encrypted spool.

Серверный plaintext находится только на внешнем сервере в SQLite вместе с
sealed оригиналом, subject sender, received wall time и digest. Uptime самой
записи сохраняется. Ротация/удаление старых серверных записей оператором пока
не автоматизированы; исходное ТЗ не задаёт срок хранения.

## Discord

В `discordWebhook` указать HTTPS URL Discord или HTTPS endpoint Pipedream.
Без URL сетевых уведомлений нет; intents остаются в outbox. По умолчанию туда
попадают warning/error/critical. Фоновый worker отправляет bounded JSON content
с node/log ID и `allowed_mentions.parse=[]`. Для Discord используется `wait=true`,
успех 2xx отмечает запись отправленной. Redirect отключён; 429 учитывает
retry_after, остальные ошибки повторяются с задержкой до 300 s. Outbox и attempts
переживают перезапуск. Получение ACK журнала не ждёт Discord.

После принятия webhook и сбоя до записи sent уведомление может прийти повторно;
node/log ID позволяет распознать его. Через Pipedream 2xx подтверждает приём
endpoint, дальнейшую доставку выполняет настроенная автоматизация. Реальных
сообщений в Discord при разработке не отправлялось; HTTP sender проверен со стабом.

## Команды внешнего оператора

Локальная утилита пишет команды в ту же БД; отдельного HTTP command API нет.
Доступ к БД — доступ к командам configured CnC identity. Пример получения состояния:

```sh
python3 -m server.control --database /path/to/state.sqlite3 enqueue --node INTERNET-CARD-ADDRESS --model hardware --action snapshot
python3 -m server.control --database /path/to/state.sqlite3 get COMMAND-ID
```

Для аргументов есть `--args` JSON object и `--args-file` для файла. Состояния:
queued (ожидает узел), running (зарезервировано перед передачей), done (ответ),
failed (получена ошибка/локальный запрет), unknown (таймаут/разрыв/restart при
running). Ошибка обработчика тоже может следовать после частичного действия;
никакое состояние не вызывает автоматический запуск новой команды.
Running после перезапуска переводится в unknown. Если действие нужно повторить,
оператор сначала проверяет фактическое состояние и явно создаёт новую команду.

## Проверки

`python3 -m unittest discover -s tools/tests -p '*_test.py'` проверяет реальные
ECDSA/AES, Lua sealed fixture, SQLite rollback/durability/duplicate receipts,
outbox retry, RPC replay/restart/revocation, localhost TCP partial header и потерю
результата. При наличии liblua5.2 запускается настоящее Lua приложение с настоящим
Python сервером; аппаратные API заменены bridge, crypto выполняется Python
cryptography. CI устанавливает эту библиотеку, чтобы тест не пропускался.
`run_tests.lua cnc logging rpc` выполняет отдельные переносимые Lua проверки.
Оставшиеся игровые проверки — пункты 25–28 в [ingame_checks.md](ingame_checks.md).
