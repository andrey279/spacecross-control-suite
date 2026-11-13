# Проверенные источники

Проверено 2026-11-11; Computronics Radar источник добавлен 2026-11-13.
Ветки новых Minecraft-версий не используются как доказательство API 1.7.10.

- OpenComputers Component API: https://ocdoc.cil.li/api:component — `component.list`
  returns address/type pairs, `component.methods(address)` returns method names
  and direct-call flags, and `component.doc(address, method)` returns a method's
  documentation string when available. `bin/inspect_components.lua` uses these
  read-only inventory operations and never invokes hardware methods.

- OpenOS Event API: https://ocdoc.cil.li/api:event — listen/ignore/timer/cancel,
  event.push принимает аргументы computer.pushSignal, поэтому конверт шины передаётся примитивами.
- Process API: https://ocdoc.cil.li/api:process — process.info; POSIX PID API нет.
  При реализации mutex автопилота потребуется отдельный совместимый адаптер живых процессов.
- Modem: https://ocdoc.cil.li/component:modem — адрес карты и modem_message.
- GPU: https://ocdoc.cil.li/component:gpu — bind принимает адрес экрана, не GPU.
  VRAM-буферы появились в более поздних OC, поэтому remote terminal должен иметь software framebuffer.
- Internet: https://ocdoc.cil.li/api:internet — только исходящие соединения,
  HTTP iterator и response через metatable.
- OpenOS filesystem: https://github.com/MightyPirates/OpenComputers/blob/master-MC1.7.10/src/main/resources/assets/opencomputers/loot/openos/lib/core/full_filesystem.lua
  — rename между разными томами выполняет copy/remove; staging и active находятся на одном HDD.
- OpenSecurity 1.7.10, commit f2cf1d706a832199f51bb14f47584190706f7cc6:
  https://github.com/PC-Logix/OpenSecurity/tree/f2cf1d706a832199f51bb14f47584190706f7cc6
  Data Block (`os_datablock`) не имеет encrypt/decrypt/RSA/ECC.
  Entity Detector (`os_entdetector`) имеет `scanPlayers(range, offset)`;
  повторное сканирование без range уменьшает сохранённый range. В реализации
  аргумент явно передаётся при каждом вызове; возвращаемые координаты абсолютные.
- Computronics Radar documentation (1.7.10-compatible mod line):
  https://wiki.vexatos.com/wiki:computronics:radar — documents `getPlayers()` and
  describes a table of detected entity names/distances, with optional relative
  coordinates.
- Upstream source confirms the 1.7.10-compatible defaults: `TileRadar` registers
  the OpenComputers component as `radar`; `getPlayers` accepts an optional integer
  distance and returns a numerically indexed table; `RadarUtils` emits `name`,
  optional relative integer `x`/`y`/`z`, and numeric `distance`. The adapter uses
  these defaults and keeps explicit overrides for forks. This source describes
  upstream code, not the user's installed modpack.
- OpenComputers Data Card:
  https://github.com/MightyPirates/OpenComputers/blob/master-MC1.7.10/src/main/scala/li/cil/oc/server/component/DataCard.scala
  Tier3 generateKeyPair возвращает public/private; serialization X.509/PKCS8 DER;
  ECDH возвращает байты; AES требует ключ и IV по 16 байт, CBC/PKCS5Padding.
- https://github.com/Umaler/WDShipController — web fetch не удался, GitHub tree main вернул 404.
  Код исходного автопилота ещё не получен; исправление нельзя объявлять проверенным по нему.
- https://github.com/Umaler/OC_GlassesMagicEye/blob/main/meye.lua — web fetch не удался.
- https://pastebin.com/uhYCWUJZ — недоступен через web tool; эталон ещё не получен.

Неполученные источники не заменяются выдуманными методами компонентов.

OMT shield/turret API status: the project target is Minecraft 1.7.10. The current
official OMT wiki page explicitly documents 1.12.2, so its API is not treated as
proof for 1.7.10. The HAL adapter added in this iteration relies only on the
user-specified `toggle()`/`setMode()` contract; component types and optional
telemetry/status methods remain configuration-gated pending inspection in-game.

RFTools Shield Projector adapter: inspected archived `ShieldTEBase.java` source
showing component name `shield_projector`, active/composed callbacks,
`getRedstoneMode`/`setRedstoneMode`, and compose/decompose callbacks. The file is
available as a source mirror at
https://www.javatips.net/api/RFTools-master/src/main/java/mcjty/rftools/blocks/shield/ShieldTEBase.java;
an exact official 1.7.10 source commit was not pinned. Method mapping is therefore
covered by stubs and remains an in-game validation item. No shield health callback
was found in that component source; the driver does not report a health value.

WarpDrive MC1.7 исследован по commit `8c00788a1cd8005afd73128dbaba8a893d500471`:
https://github.com/LemADEC/WarpDrive/tree/8c00788a1cd8005afd73128dbaba8a893d500471
ShipController имеет имя `warpdriveShipController`, команды `MANUAL` и `OFFLINE`,
методы `movement(front,up,right)`, `enable`, `position`, `getOrientation`,
`getMaxJumpDistance` (возвращает success,value).
Деактивация для перемещения вложенных кораблей требует `OFFLINE`, а не только disable.
`shipCoreCooldownDone` в OpenComputers приходит с адресом отправителя: этот адрес
добавляется `server/machine/Machine.scala` при обработке `computer.signal`.
API Enan reactor: `warpdriveEnanReactorCore`, `energy`, `enable`, `state`.

Дополнение для этапа 3:
- OpenOS process source:
  https://github.com/MightyPirates/OpenComputers/blob/master-MC1.7.10/src/main/resources/assets/opencomputers/loot/openos/lib/process.lua
  `process.info(thread)` позволяет проверить принадлежность coroutine живому процессу.
  Изолированный адаптер назначает свои числовые IDs; это не POSIX PID.
- RF handler:
  https://github.com/MightyPirates/OpenComputers/blob/master-MC1.7.10/src/main/scala/li/cil/oc/integration/cofh/energy/DriverEnergyHandler.java
  `energy_handler.getEnergyStored(side=6)`, `getMaxEnergyStored(side=6)`.
- RF provider:
  https://github.com/MightyPirates/OpenComputers/blob/master-MC1.7.10/src/main/scala/li/cil/oc/integration/cofh/energy/DriverEnergyProvider.java
  тот же component name и контракт.
- CoFH energy info:
  https://github.com/MightyPirates/OpenComputers/blob/master-MC1.7.10/src/main/scala/li/cil/oc/integration/cofh/tileentity/DriverEnergyInfo.java
  `energy_info.getEnergy()`, `getMaxEnergy()`.
- CoFH redstone control:
  https://github.com/MightyPirates/OpenComputers/blob/master-MC1.7.10/src/main/scala/li/cil/oc/integration/cofh/tileentity/DriverRedstoneControl.java
  Предоставляет режимы redstone; `setControlDisable` не следует автоматически
  считать командой выключения генератора. Реализация использует явно настроенный
  проводной канал redstone, а не такое предположение.
- NuclearCraft 1.7.10, commit `ba4e3cc1d6b162a632391496c96de5d42fb5f812`:
  https://github.com/turbodiesel4598/NuclearCraft/blob/ba4e3cc1d6b162a632391496c96de5d42fb5f812/src/main/java/nc/tile/generator/TileFissionReactor.java
  Выработка требует `worldObj.isBlockIndirectlyGettingPowered(...)`.
  `TileGeneratorInventory` реализует IEnergyHandler/IEnergyProvider; нативный
  реакторный OC API новых версий не предполагается.
- Enan: `release(true)` возвращает boolean, `instability()` снимает startup hold,
  встроенный `runControlLoop` управляет установленными стабилизирующими лазерами.

Сетевой этап:
- Modem: https://ocdoc.cil.li/component:modem — broadcast(port,...), maxPacketSize,
  один строковый аргумент добавляет два байта overhead. modem_message содержит
  localAddress, remoteAddress, rawPort, distance, payload.
- Linked Card: https://ocdoc.cil.li/component:tunnel — send(...) без порта,
  аппаратная связь всегда открыта; идентичный формат modem_message.
- Проверено по исходнику 1.7.10:
  https://github.com/MightyPirates/OpenComputers/blob/master-MC1.7.10/src/main/scala/li/cil/oc/server/component/LinkedCard.scala
  Пакет создаётся с source=node.address и port=0. send может вернуть nil/error
  при недостатке энергии. getChannel не является component address.
- Network Card source:
  https://github.com/MightyPirates/OpenComputers/blob/master-MC1.7.10/src/main/scala/li/cil/oc/server/component/NetworkCard.scala
  Broadcast использует source=node.address. Open/close относятся к локальным портам.
- OpenOS UUID:
  https://github.com/MightyPirates/OpenComputers/blob/master-MC1.7.10/src/main/resources/assets/opencomputers/loot/openos/lib/uuid.lua
  uuid.next() генерирует обычный UUID через math.random. Используется только для
  имён сетевых сессий/дедупликации, не как криптографический nonce RPC.

Удалённый терминал, OpenOS branch master-MC1.7.10, tree
`667626d8e2fbd3b68ed6b80e9ed9921a6de265b6`:
- [term.lua](https://github.com/MightyPirates/OpenComputers/blob/master-MC1.7.10/src/main/resources/assets/opencomputers/loot/openos/lib/term.lua):
  `term.internal.open` переводит root window в process data; `term.bind(gpu,window)`
  и `as_window` используют отдельное окно процесса. Это внутренний API с риском
  различий между сборками; обязательна игровая проверка.
- [tty.lua](https://github.com/MightyPirates/OpenComputers/blob/master-MC1.7.10/src/main/resources/assets/opencomputers/loot/openos/lib/tty.lua):
  viewport/window GPU, software scroll через copy, явный window.keyboard предотвращает
  component.invoke для виртуального screen address. bind оборачивает методы только
  переданного ему GPU. Headless PTY и восстановление root вынесены в openos_scope.
- [thread.lua](https://github.com/MightyPirates/OpenComputers/blob/master-MC1.7.10/src/main/resources/assets/opencomputers/loot/openos/lib/thread.lua):
  отдельные process data.handlers/data.pull; create запускает функцию сразу до
  yield, pull регистрирует возобновление в attached handlers. kill снимает регистрацию.
- [event.lua](https://github.com/MightyPirates/OpenComputers/blob/master-MC1.7.10/src/main/resources/assets/opencomputers/loot/openos/lib/event.lua):
  computer.pullSignal перед pull проверяет Control+C и публикует interrupted
  через event.push. Поэтому remote C подавляется в private key state и преобразуется
  в частный interrupted до возврата из data.pull.
- [keyboard.lua](https://github.com/MightyPirates/OpenComputers/blob/master-MC1.7.10/src/main/resources/assets/opencomputers/loot/openos/lib/keyboard.lua),
  [92_keyboard.lua](https://github.com/MightyPirates/OpenComputers/blob/master-MC1.7.10/src/main/resources/assets/opencomputers/loot/openos/boot/92_keyboard.lua):
  функции читают pressedCodes/pressedChars при каждом вызове, boot handlers обновляют
  поля модуля, а не заранее захваченные таблицы. Это позволяет process-aware proxy.
- [process.lua](https://github.com/MightyPirates/OpenComputers/blob/master-MC1.7.10/src/main/resources/assets/opencomputers/loot/openos/lib/process.lua),
  [bin/sh.lua](https://github.com/MightyPirates/OpenComputers/blob/master-MC1.7.10/src/main/resources/assets/opencomputers/loot/openos/bin/sh.lua),
  [pipe.lua](https://github.com/MightyPirates/OpenComputers/blob/master-MC1.7.10/src/main/resources/assets/opencomputers/loot/openos/lib/pipe.lua):
  process.load с environment, inherited data/window, interactive sh с tty streams;
  terminal runner запускает программу через штатные load/continue в thread.
  Проверки на ПК используют стабы этих контрактов; нативное выполнение в игре ещё
  не проводилось. Несуществующий lib/component.lua вернул 404; этот файл не изучен.

CnC и журналы (проверено 2026-11-12):
- [Internet Card API](https://ocdoc.cil.li/component:internet) и
  [InternetCard.scala MC1.7.10](https://github.com/MightyPirates/OpenComputers/blob/master-MC1.7.10/src/main/scala/li/cil/oc/server/component/InternetCard.scala):
  connect создаёт nonblocking SocketChannel; finishConnect может быть false,
  read возвращает пустую строку без данных и nil при EOF, write — число реально
  записанных байтов. Используется исходящий TCP, не входящий Internet listener.
- [SQLite transactions](https://docs.python.org/3/library/sqlite3.html),
  [synchronous pragma](https://www.sqlite.org/pragma.html#pragma_synchronous):
  receipt выдаётся после commit; сервер сохраняет лог и notification intent
  одной транзакцией с synchronous=FULL. Физическая durability зависит и от ФС/диска.
- [Discord Execute Webhook](https://docs.discord.com/developers/resources/webhook#execute-webhook):
  JSON content, allowed_mentions и wait=true для подтверждения отправки;
  [rate limits](https://docs.discord.com/developers/topics/rate-limits)
  — повтор по retry_after. Реальный webhook не вызывался; HTTP sender покрыт mock.

Компонентные версии и обновления (2026-11-12):
- [git-log](https://git-scm.com/docs/git-log): path-limited log определяет commit
  версии; deleted paths добавляются из истории, иначе удаление последнего файла
  могло бы не изменить версию компонента. Данные читаются git show из exact commit.
- [GitHub release assets](https://docs.github.com/en/rest/releases/assets):
  binary asset download и browser_download_url. Source получает components.sc
  по release tag spacecross-<SHA>; raw source files по тому же immutable SHA.
- [gh release create](https://cli.github.com/manual/gh_release_create):
  --target задаёт исходный commit, files — release assets. Workflow не запускался.
- [OC application.conf](https://github.com/MightyPirates/OpenComputers/blob/master-MC1.7.10/src/main/resources/application.conf)
  и DataCard.scala: default soft limit 8192 bytes с pause, hard limit 1048576.
  Updater ограничивает файл 1 MiB, но реальные лимиты/задержки серверного конфига
  остаются игровым gate, не доказаны PC тестами.
