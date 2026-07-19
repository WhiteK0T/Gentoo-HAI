# Контекст проекта для Claude Code

Общение с пользователем — на русском.

## Что это

Форк https://github.com/ASoft-se/Gentoo-HAI — автоустановщика Gentoo
(amd64 + OpenRC) с минимального LiveCD. Рабочая ветка — `presets`
(remote `upstream` — оригинал, ветка `master` — его слепок).

Идея форка: один движок `install.sh` + подключаемые пресеты в `presets/`
вместо дублирования скриптов. Документация пользователя — `PRESETS.md`.
Подробный разбор апстримных скриптов — `docs/upstream-analysis.md`
(читать перед правками `install.sh`/`portagehelper.sh`/`gentoocd_unpack.sh`).

## Для кого и под что

Пользователь — опытный гентушник (Gentoo — основная ОС), русскоязычный.
Целевые сценарии:

1. **Домашний сервер**: Xeon E5450, 8 ГБ RAM, SSD 250 ГБ + HDD 320 ГБ,
   старая NVIDIA GT (только nouveau), монитор подключается через
   переключатель → пресеты `xeon` (+ опционально `kde`).
2. **QEMU/KVM-виртуалки** с GUI и без → `minimal`, `kde`.
3. **Рабочая станция** как главная машина пользователя (Plasma 6,
   nvidia/CUDA, skylake, NetworkManager, docker/libvirt/samba, sysklogd,
   chrony, ACCEPT_LICENSE="*", русские зеркала) → `workstation`.
4. **KVM-VPS** у провайдера (панель VirtFusion, AMD Ryzen, 16 ГБ, 200 ГБ
   NVMe, вложенная виртуализация) → пресет `vps` (+`minimal`). Serial-консоль,
   virtio, KVM-хост, статик/DHCP-сеть, юзер `sam`.

Русские дефолты запечены в движок: Europe/Moscow, раскладка ru,
ru.pool.ntp.org, ROOTEMAIL=uyiraqoyir041@gmail.com.

## Устройство пресетов

- `presets/<имя>.sh` — выполняется на LiveCD до chroot (переменные,
  разметка и т.п.); `presets/<имя>.chroot.sh` — внутри chroot.
- `presets/workstation.d/` — куратированные конфиги с главной машины
  пользователя (make.conf, package.use и пр.).
- Выбор: `PRESET=minimal,xeon sh install.sh`, либо `preset=` в kernel
  cmdline, либо `sh gentoocd_unpack.sh --preset ...` при сборке ISO.
- Учётка: пресеты `xeon`/`kde`/`workstation` создают пользователя `sam`
  (`INSTALLUSER`, пароль = `SET_PASS`, wheel+sudo) через общий сниппет
  `presets/adduser.inc`. `minimal` — без юзера. Без запечённого ssh-ключа
  root по ssh запрещён (`PermitRootLogin no`) — на сервер заходить либо
  юзером `sam`, либо запечь ключ (key-only root).
- SSH: ключ через `SSHKEY=` (строка или путь) или файл `authorized_keys`
  рядом со скриптом → key-only sshd; без ключа — парольный режим.

## Текущее состояние (2026-06-10)

Прошла волна фиксов по итогам отладки реальной установки: перепаковка
squashfs + префлайт-проверка декомпрессора, метка тома ISO,
инъекция `setupdonehalt`, запекание `SET_PASS`, hostname против
NetworkManager, бинхост сделан опциональным + таймаут зависшего fetch,
выпилен сломанный кастомный FETCHCOMMAND. См. `git log`.

2026-06-10: полный цикл в QEMU **подтверждён**: автоустановка
(minimal, `setupdonehalt`) прошла до конца (ядро 7.0.11-gentoo, GRUB,
65 пакетов, chroot ~7.7 ч), установленная система загрузилась с диска.
Ошибка efibootmgr при установке в BIOS-режиме ожидаема и безвредна
(`--removable` + i386-pc покрывают оба варианта загрузки).

HDD-логика xeon реализована (645c630): SSD под систему по rotational,
HDD → ext4 `LABEL=data` в `/srv` (samba/backup/vm + симлинк libvirt
images), переустановка данные не трогает; `DATADEV=none` отключает.
Движок получил generic-крючки `PRESET_DISKSETUP`/`PRESET_FSTAB`.

Обе ветки data-диска подтверждены в QEMU (2026-06-10): чистый vdb
отформатирован, при повторной установке — «keeping existing data
filesystem». Установка теперь логируется в /var/log/hai-install.log,
файлы krn330.conf/39_efitools едут на CD (без зависимости от github).

Уроки отладки QEMU-тестов (2026-06-10):
- Давать VM ≥6 ГБ (`-m 6`): с 2 ГБ гость уходит в своп (xeon tmpfs 4G).
- slirp-сеть: фейковый IPv6 «чернодырит» соединения → в test_w_qemu.sh
  ipv6=off; фетч индекса бинхоста у portage без таймаута → в QEMU
  GETBINPKG=no по умолчанию (детект по dmi sys_vendor). Симптом был:
  вис с ~0% CPU сразу после Global Updates (после `4Q-2025...`).
- НЕ советовать Ctrl+C в консоли установки: SIGINT убивает весь
  установщик (|| bash ловит ошибки, не сигналы). Вмешательство — только
  через рескью-шеллы. Случайный Ctrl+S (XOFF) морозит вывод — Ctrl+Q.
- `--- insufficient free space, parallelism reduced` в emerge — норма
  (встроенная оценка portage), едет последовательно.

Юзер `sam` в xeon + ssh подтверждены на прогоне (2026-06-16): установка
прошла, sam создан (wheel+sudo), ssh работает. xeon-пресет готов.

2026-07-05: добавлен пресет `vps` (KVM-VPS/VirtFusion). Ядро: KVM-хост
(KVM_AMD/INTEL, vhost/tun/bridge) для вложенной виртуализации + явный
virtio-guest транспорт (VIRTIO_PCI и пр.). Serial-консоль форсится в
vps.chroot.sh (grub+inittab) — работает и на non-auto ISO. Юзер `sam`.
Сеть: DHCP по умолчанию, статика через VPS_IP/VPS_GW/VPS_DNS — эти
переменные gentoocd_unpack.sh запекает в CD (как SET_PASS) и прокидывает
через su, чтобы пережить автоустановку. Диск — автодетект.
**Подтверждён в QEMU 2026-07-05**: virtio-загрузка (VIRTIO_PCI вкомпилен),
serial-консоль в cmdline, CONFIG_KVM=y, key-only ssh (root по ключу зашёл,
парольный root закрыт), юзер `sam` с `(ALL:ALL) ALL` sudo.

2026-07-18: первая заливка на боевой VPS (VirtFusion, IP 89.106.89.196/28)
вскрыла три особенности DDoS-скрабленного провайдера, из-за которых
автоустановка виснет и сеть не поднимается:
  1. **Off-link шлюз**: GW 11.0.0.1 вне подсети /28. Debian грузит его как
     `default via 11.0.0.1 dev eth0 onlink`. Пресет теперь генерит
     `routes_eth0="default via GW onlink"`.
  2. **MTU 1448** (тоннель): при 1500 крупные пакеты (stage3/TLS) чернодырят
     → установка виснет «в начале». Добавлен VPS_MTU (netifrc mtu_eth0 +
     live-NIC).
  3. **Static-only LiveCD**: VPS_IP пишется только в целевую систему, а сам
     установщик оставался без сети. vps.sh теперь поднимает NIC установщика
     статикой (addr+mtu+onlink-route+resolv.conf) ДО скачивания stage3.
Также подтверждён симптом «настройки не сохраняются на диск» = система
грузилась с примонтированного ISO (LiveCD-оверлей в tmpfs), а не с диска —
в панели надо отмонтировать ISO и переключить boot на диск. VPS_MTU
запекается в CD (gentoocd_unpack.sh). **На боевом VPS с новым ISO ещё не
переставлено** (сейчас там Debian).

**Незакрытое:**
- Переустановка на боевой VPS новым ISO (VPS_IP/GW/DNS/MTU + onlink).
- На новых minimal CD нет sntp и file — варнинги в логе; заменить
  sntp на chrony-вызов для реального железа.
- Прогоны kde/workstation-пресетов в QEMU.
- Установка на реальный Xeon-сервер (боевой ISO, без setupdonehalt/auto).
- Косметика: /var/log/hai-install.log сохраняется обрезанным (только
  хвост после chroot); диагностировать по install-run.log при случае.

## Как тестировать

- В песочнице Claude обычно нет KVM — только синтаксис (`sh -n`) и
  smoke-тесты генерации chrootstart.sh. Реальные прогоны — у пользователя.
- Полный автотест на машине с KVM:
  `sh gentoocd_unpack.sh auto --preset minimal setupdonehalt`
  (пересборка ISO → QEMU → автоустановка → halt по завершении).
- Обвязка QEMU — `test_w_qemu.sh` (см. docs/upstream-analysis.md, §4).

## Не переезжает через git (gitignored)

- `workstation/` — сырой дамп конфигов главной машины (~600 КБ);
  куратированная копия закоммичена в `presets/workstation.d/`.
  При переносе на другую машину сырой дамп при необходимости
  копировать вручную.
- `authorized_keys`, ISO/qcow2-образы.

## Прочее

- Стиль кода — как в апстриме: POSIX sh, `|| bash` как «точки спасения».
- В `install.sh` есть захардкоженные SHA512 на `portagehelper.sh` и
  `grub.d/39_efitools` — при правке этих файлов обновлять синхронно.
- Диск размечается без подтверждения; предохранитель — проверка hostname.
