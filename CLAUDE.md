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
Три целевых сценария:

1. **Домашний сервер**: Xeon E5450, 8 ГБ RAM, SSD 250 ГБ + HDD 320 ГБ,
   старая NVIDIA GT (только nouveau), монитор подключается через
   переключатель → пресеты `xeon` (+ опционально `kde`).
2. **QEMU/KVM-виртуалки** с GUI и без → `minimal`, `kde`.
3. **Рабочая станция** как главная машина пользователя (Plasma 6,
   nvidia/CUDA, skylake, NetworkManager, docker/libvirt/samba, sysklogd,
   chrony, ACCEPT_LICENSE="*", русские зеркала) → `workstation`.

Русские дефолты запечены в движок: Europe/Moscow, раскладка ru,
ru.pool.ntp.org, ROOTEMAIL=uyiraqoyir041@gmail.com.

## Устройство пресетов

- `presets/<имя>.sh` — выполняется на LiveCD до chroot (переменные,
  разметка и т.п.); `presets/<имя>.chroot.sh` — внутри chroot.
- `presets/workstation.d/` — куратированные конфиги с главной машины
  пользователя (make.conf, package.use и пр.).
- Выбор: `PRESET=minimal,xeon sh install.sh`, либо `preset=` в kernel
  cmdline, либо `sh gentoocd_unpack.sh --preset ...` при сборке ISO.
- Учётка: десктопные пресеты создают пользователя `sam`
  (`INSTALLUSER`, пароль = `SET_PASS`, wheel+sudo).
- SSH: ключ через `SSHKEY=` (строка или путь) или файл `authorized_keys`
  рядом со скриптом → key-only sshd; без ключа — парольный режим.

## Текущее состояние (2026-06-10)

Прошла волна фиксов по итогам отладки реальной установки: перепаковка
squashfs + префлайт-проверка декомпрессора, метка тома ISO,
инъекция `setupdonehalt`, запекание `SET_PASS`, hostname против
NetworkManager, бинхост сделан опциональным + таймаут зависшего fetch,
выпилен сломанный кастомный FETCHCOMMAND. См. `git log`.

2026-06-10: полный прогон в QEMU (minimal, `setupdonehalt`) **прошёл до
конца** — ядро 7.0.11-gentoo, GRUB (efibootmgr-ошибка в BIOS-режиме
ожидаема, `--removable` + i386-pc встали), 65 пакетов, halt по флагу.
Этап chroot занял ~7.7 ч.

**Незакрытое:**
- Загрузка установленной системы с диска (test_w_qemu.sh без -cdrom):
  GRUB → логин root, rc-status, DHCP на eth0, sshd.
- Разметка/назначение HDD 320 ГБ в пресете `xeon` — ждёт решения
  пользователя (подо что второй диск).

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
