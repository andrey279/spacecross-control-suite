# Матрица требований

«Реализовано» ниже означает код и проверки на ПК; игровая интеграция пока не доказана.
Весь исходный объём сохранён; строки «предстоит» не исключены из цели.

| Требование из spacecross.md | Текущее доказательство | Остаток |
|---|---|---|
| OpenOS, стандартный BIOS, без EEPROM | runtime/openos.lua, bootstrap.lua | Проверка в OpenOS |
| 3.1 HAL, реестр, экземпляры, hotplug, pcall | hal/*.lua; per-address bindings; HAL/driver tests; read-only OpenOS component inspector; upstream RFTools Shield callbacks and status/control; OMT driver/model | Shield durability is not exposed; exact installed mod version, wiring, and hardware behavior remain game gates |
| 3.2 core daemon, autopilot API, mutex, UI-плагин | autopilot/*.lua, core/mutex.lua, runtime/processes.lua; route/lifecycle/plugin/UI tests | Проверка WarpDrive и liveness в OpenOS |
| 3.3 спутник, heartbeat 10s, whitelist, encrypted cache, 2 режима мины | satellite/controller.lua/adapters.lua, security/local_cache.lua; CnC `_cnc` heartbeat/whitelist/alert, durable node-scoped server store, AES+HMAC cache, vector/charge count, owner ACL tests | Exact Data Card/mod APIs and physical radar/WarpDrive/HAL behavior require in-game validation |
| 3.4 маршруты, deployment, загрузка программы компьютера структуры | structures/deployer.lua/adapters.lua; route/navigation/deploy/provision/confirmation state machine, receipt-based computer lookup and tests | Exact builder/computer API and in-game route/provisioning test |
| 3.5 Entity Watcher, фоновый API, OpenSecurity или Computronics | entity/watcher.lua; OpenSecurity and Computronics Radar drivers with upstream `radar`/`getPlayers(distance)` defaults; mixed-source, normalization, and failure tests | Confirm installed mod version and run in-game detector integration |
| 3.6 энерготелеметрия, реакторы, порядок отключения нагрузок | power/controller.lua; Enan/EnderIO/NC/Thermal HAL adapters; threshold/priority/fault tests | Игровая проверка RF-привязок, redstone и стабилизаторов |
| 3.6 owners/admins, ник каждого ввода | defense/access.lua; UI/model/app tests; cert.subject привязан к RPC actor | Игровая проверка нескольких client identities |
| 3.6 условия самоуничтожения OR, admin alert, owner suppression | defense/*.lua; cnc/agent one-use heartbeat proof; defense/app/offline/reconnect tests | Проверка каналов и времени heartbeat в игре |
| 3.7 единый RPC-порт, сертификаты, OpenSecurity crypto | rpc/*.lua; certificates/signing_card; replay/revocation/recipient/grant tests; независимые ECDSA vectors и PKI tools | Проверка в игре; официальный OpenSecurity не имеет RSA/ECC, реализован явный альтернативный OC Tier3 provider |
| 3.7 виртуальный GPU, compression, OpenOS клиент | terminal/*.lua, bin/remote.lua; UTF-8/RLE/frame paging, owner/session/input/reentry tests; two-window adapter mocks и app/RPC integration | Реальная проверка OpenOS PTY/thread/GPU/Data Card; cached physical GPU libraries требуют адаптации |
| 3.7 исходящее соединение к real-life серверу | cnc/channel.lua, agent.lua; server/*.py; настоящий Lua↔Python localhost TCP с ECDSA/AES, owner RPC и heartbeat | Реальная Internet/Data Card и внешний deployment |
| 3.8 async logger, encrypted spool, retry, ACK deletion, Discord | logging/logger.lua; cnc upload; server crypto/store/outbox; SQLite rollback/duplicate/durable receipt, reconnect, HTTP sender/retry tests | Игровая интеграция и реальный webhook; OpenSecurity оговорка остаётся |
| 3.9 адреса карт, broadcast/directed, headers, discovery | network/*.lua, modem/tunnel adapters; multi-host/fragment/TTL/hotplug tests; app integration | Проверка реальных Network/Linked Card |
| 3.10 локальная и сетевая шина, формат, per-card whitelist/blacklist | bus/local_bus.lua, policy.lua, network_bridge.lua; policy/no-loop/fragmented-interface tests | Игровая проверка правил на нескольких картах |
| 3.11 локальное обновление latest main, syntax, atomic publish, reboot | update/*.lua; hash/profile/reuse/deletion/lease/cancellation/failure injection tests | Реальный репозиторий, release workflow и OpenOS rename |
| 3.11 LAN broadcast distribution, internet-less hosts, versions | components.json, tools/manifest.py, release.yml; update/service; Git-object/Python→Lua tests и четыре app с shared broadcast/repair/RPC identity/replay tests | GitHub deployment и игра/реальная Data Card/таймауты |
| 3.12 MVC, redraw, нет inactive cache, static draw, multiGPU, выбор/объединение remote моделей | ui/*.lua, remote_views.lua; multi-host MVC/actor/late-redraw tests incl. shield/turret views | Игровая интеграция and physical API gates |
| 4.1 unit mocks Lua5.2/5.3; game integration | 176 Lua tests pass under 5.2 and 5.4; Lua 5.3 runtime absent, apt download blocked by DNS | Run full suite under Lua 5.3 and perform game integration tests |
| 4.2–4.4 tests/stubs, функции/all_tests, runner/таблица/цвет/статистика | testing/runner.lua, run_tests.lua, runner tests | Добавлять тесты для новых компонентов |
| current_state.txt читать/обновлять | Корень проекта | Продолжать при каждой итерации |

Ссылки на API и результаты исследования хранятся в `docs/api_sources.md`.
