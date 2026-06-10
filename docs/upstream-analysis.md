# Подробный разбор Gentoo-HAI (Headless Auto Installer)

Репозиторий: https://github.com/ASoft-se/Gentoo-HAI (автор Christian Nilsson, лицензия «copyleft, делайте что хотите»).
Назначение: **полностью автоматическая headless-установка Gentoo** (профиль amd64 + OpenRC) с минимального LiveCD — от разметки диска до первой перезагрузки. Заточен под серверы, в том числе виртуальные (QEMU/KVM, VMware).

Локальная копия: корень этого репозитория.

## Состав репозитория

| Файл | Роль |
|---|---|
| `install.sh` | Главный установочный скрипт (~700 строк) |
| `portagehelper.sh` | Библиотека функций для работы со squashfs-снапшотами дерева portage |
| `get_minimal_cd.sh` | Скачивание и криптографическая проверка последнего minimal LiveCD |
| `list_latest.sh` | Вывод имён последних ISO и stage3 |
| `gentoocd_unpack.sh` | Пересборка LiveCD в `install-amd64-mod.iso` с автозапуском установки |
| `cdhelpers/gentoo_cd_bashrc_addon` | Кусок `.bashrc`, запускающий установку при логине на LiveCD |
| `cdhelpers/cdupdate.sh` | Хук, дописывающий addon в `.bashrc` при загрузке CD |
| `grub.d/39_efitools` | Генератор пунктов GRUB-меню для chainload EFI-бинарников (iPXE, UEFI Shell) |
| `krn330.conf` | Базовый конфиг ядра (~75 КБ), используется как основа `.config` |
| `test_w_qemu.sh` | Обвязка для тестирования в QEMU/KVM |

## Общий сценарий использования

1. Загрузиться с официального minimal LiveCD (или с модифицированного `install-amd64-mod.iso`, который всё делает сам).
2. Сменить hostname (он станет именем устанавливаемой машины) — скрипт **отказывается работать**, если hostname == `livecd`.
3. `wget tinyurl.com/gto-hai -O install.sh && sh install.sh`.
4. Через несколько часов (компилируется ядро и мир) машина перезагружается в готовую систему.

---

# 1. install.sh — главный скрипт

## 1.1. Настройки через переменные окружения (строки 16–40)

Все параметры переопределяемы извне, со значениями по умолчанию «под автора»:

```bash
TIMEZONE=${TIMEZONE:-Europe/Stockholm}
NTPSERVER=${NTPSERVER:-ntp.se}
KEYMAP=${KEYMAP:-sv-latin1}        # шведская раскладка
ROOTEMAIL=${ROOTEMAIL:-root@asoft.se}
SET_PASS=${SET_PASS:-password}     # пароль root по умолчанию — "password"!
```

**Автовыбор целевого диска `IDEV`:**
- если есть `/dev/nvme0n1` → берётся он, плюс взводятся `NVMETOOLS=sys-apps/nvme-cli` и `NVMEKERNEL=CONFIG_BLK_DEV_NVME=y` (потом попадут в пакеты и конфиг ядра);
- иначе если есть `/dev/vda` и нет `/dev/sda` → virtio-диск (QEMU);
- иначе `/dev/sda`.

`IDEVP` — префикс имён разделов: если имя диска кончается цифрой (nvme0n1, vda… нет — vda цифрой не кончается; речь про nvme0n1, mmcblk0 и т.п.), добавляется `p` (`nvme0n1p1` против `sda1`).

Дальше включается `set -x -u` (трассировка + ошибка на неопределённых переменных).

## 1.2. Ранние фоновые задачи и автодетект железа (строки 43–60)

- `sntp -S $NTPSERVER &` — синхронизация времени запускается **в фоне**, PID запоминается; ожидание (`wait $pid_ntp`) происходит позже, прямо перед скачиванием stage3 — типичный для скрипта приём перекрытия операций.
- Платформа: `[ -d /sys/firmware/efi ] && PLATFORM=efi || PLATFORM=pcbios` (переменная, правда, дальше почти не используется — выбор ведётся повторными проверками `/sys/firmware/efi`).
- **Детект ИБП APC**: поиск USB-устройств с `idVendor == 051d` по `/sys/devices` → `APCUPSDTOOLS=apcupsd` (нюанс: присваивание происходит внутри пайпа `| while read`, т.е. в субшелле — наружу значение не выходит; ниже по тексту используется `${APCUPSDTOOLS:=}`, так что фактически это работает только как информационное сообщение — известная шероховатость скрипта).
- **Детект батареи**: `grep -l Battery /sys/class/power_supply/*/type` → `BATTERYTOOLS=sys-power/acpi` (ноутбук — поставим acpi).

## 1.3. Разметка диска (строки 62–139)

GPT-таблица создаётся **скармливанием готового сценария интерактивному `fdisk`** через heredoc-пайп. Схема:

| № | Размер | Тип | Назначение |
|---|---|---|---|
| 99 | 2 MiB | BIOS boot (GUID `21686148-...`) , атрибут A (legacy bootable) | grub core.img для BIOS-загрузки с GPT |
| 1 | 128 MiB | Linux | `/boot`, ext2 |
| 2 | 128 MiB | EFI System | `/boot/efi`, FAT |
| 3 | 4 GiB | swap | метка `swap0` |
| 4 | остаток | Linux root x86-64 (GUID `4F68BCE3-...`) | `/`, ext4 |

То есть диск размечается сразу **и под BIOS, и под UEFI** — установленная система сможет грузиться в обоих режимах.

Закомментированный блок — заготовка под mdadm RAID при нескольких одинаковых дисках (не реализовано).

Создание ФС и монтирование:
```bash
mkswap -L swap0 ${IDEVP}3 && swapon -p1 ${IDEVP}3
mkfs.ext2 ${IDEVP}1; mkfs.vfat ${IDEVP}2; mkfs.ext4 ${IDEVP}4
mount ${IDEVP}4 /mnt/gentoo -o discard,noatime
mount ${IDEVP}1 /mnt/gentoo/boot
mount ${IDEVP}2 /mnt/gentoo/boot/efi
```
Каждый шаг с `|| exit 1`. Swap включается сразу — лишняя память пригодится при сборке.

## 1.4. Получение portagehelper.sh и stage3 (строки 148–183)

Характерный приём всего скрипта: **`|| bash` вместо `|| exit`** на критических шагах — при ошибке открывается интерактивный шелл, чтобы оператор починил проблему и продолжил выходом из шелла (отладочный fallback).

1. `portagehelper.sh` берётся локально или качается с GitHub (raw, ветка master) и проверяется по **захардкоженному SHA512** — защита от подмены и от рассинхронизации версий. Затем сорсится.
2. `ensure_key_and_snap_source` (из portagehelper) — импорт GPG-ключей Gentoo и получение подписанного `sha512sum.txt` для squashfs-снапшота portage.
3. `update_snapshot &` — скачивание снапшота дерева portage **в фоне**, параллельно со stage3.
4. Имя последнего stage3 выясняется скрейпингом каталога `releases/amd64/autobuilds/current-stage3-amd64-openrc/` (grep по `stage3-amd64-openrc-\w*\.tar\.xz`, `sort -r | head -1`).
5. stage3 + `.DIGESTS` + `.asc` качаются `curl --parallel`, затем тройная проверка: `gpg --verify` обоих файлов и `sha512sum -c` по строке из DIGESTS.
6. `tar xpf $FILE --xattrs-include='*.*' --numeric-owner` — распаковка с сохранением xattr и числовых владельцев (как требует Handbook), архив после удаляется.

Мелкий баг: `[ -f "*.tar.{bz2,xz,sqfs}" ]` — glob в кавычках не раскрывается, чистка «от прошлой попытки» фактически не срабатывает.

## 1.5. Ключевая особенность: дерево portage как squashfs (строка 181)

Вместо классического `emerge-webrsync`/`emerge --sync` дерево portage монтируется как **read-only squashfs-образ** (`mount_current_snapshot`): экономия времени, места и inode'ов, мгновенная «синхронизация» заменой одного файла. Подробнее — в разборе `portagehelper.sh` ниже. GPG trustdb копируется в `root/.gnupg` нового корня, чтобы внутри chroot работала проверка подписей.

## 1.6. Конфигурация до chroot (строки 185–259)

- `etc/conf.d/hostname` — имя машины = текущий hostname LiveCD (поэтому и запрет на `livecd`).
- **fstab**: дописываются строки под созданную разметку (boot/efi как `noauto`, root с `discard,noatime`, swap по LABEL), шаблонные строки stage3 (`/dev/BOOT` и пр.) вычищаются sed'ом. Плюс примечательная строка: `none /var/tmp tmpfs size=6G` — **сборка пакетов ведётся в tmpfs** (быстро, бережёт SSD); в chroot она монтируется (`mount /var/tmp`), а после установки размонтируется и из make.conf убирается опция `--jobs-tmpdir-require-free-gb`.
- Монтирование псевдо-ФС по Handbook: `proc` (types proc), `sys`/`dev` rbind+rslave, `run` bind+slave.
- **make.conf** дополняется:
  ```
  MAKEOPTS="-j$(nproc)"
  EMERGE_DEFAULT_OPTS="... --getbinpkg --jobs-tmpdir-require-free-gb=1"
  FEATURES="parallel-fetch buildpkg"
  USE="${USE} -X iproute2 logrotate snmp"
  ```
  То есть: использовать **официальные бинарные пакеты** (`--getbinpkg`) где можно, собранное паковать в свои binpkg, без X11, серверный уклон.
- `etc/conf.d/net` — заливается **личный шаблон сети автора**: мост `br0` поверх eth0 с DHCP, второй мост `br1` со статикой 10.100.1.254/24, VLAN'ы 101/120/140 на eth1, tap-интерфейс `vpnUA` для OpenVPN с фиксированным MAC. Это явно конфиг конкретного шлюза — при ручной установке его предлагается отредактировать.
- **Интерактивность**: если в `/proc/cmdline` нет флага `autoinstall`, скрипт открывает `nano` для make.conf и conf.d/net. С флагом (его ставит модифицированный ISO) — едет без остановок.

## 1.7. chrootstart.sh — генерируемый скрипт внутри chroot (строки 262–697)

Самая большая часть: heredoc `cat > chrootstart.sh << EOF` (без кавычек у EOF, поэтому часть переменных — `$SET_PASS`, `$NTPSERVER`, `$GHBASEURL`, `${IDEV}`, `$TIMEZONE`, `$ROOTEMAIL` — подставляется **снаружи**, а `\$`-экранированные вычисляются уже внутри chroot). Затем `chroot . ./chrootstart.sh`.

### Этап A: базовая настройка и portage
- `env-update; source /etc/profile`; пароль root: `echo "root:${SET_PASS}" | chpasswd -c BCRYPT`.
- `mount /var/tmp` (tmpfs из fstab), `ensure_snapshot_fstab` — строка squashfs-снапшота прописывается в fstab новой системы.
- `getuto &` — установка цепочки доверия для **бинарных пакетов Gentoo**.
- `ln -snf /proc/self/mounts /etc/mtab`.
- Раскладываются `package.accept_keywords` (gentoo-sources ~amd64), `package.use` (bind: dlz/idn/caps/threads; nftables: xtables; net-snmp: lm-sensors; installkernel: grub; apcupsd: -snmp + util-linux tty-helpers — если найден ИБП).
- **Война с Predictable Network Interface Names**: `touch /etc/udev/rules.d/80-net-name-slot.rules` и `80-net-setup-link.rules` (пустые файлы-маски), чтобы интерфейсы остались `eth0/eth1`. Та же операция продублирована в LiveCD-пересборке и в `local.d`-скрипте (см. ниже) — автор борется с этим на всех уровнях.
- `emerge -uvN1 -j8 ... portage curl ntp gentoolkit cpuid2cpuflags` — сначала обновляется сам portage и инструменты.
- `echo "*/* \$(cpuid2cpuflags)" > /etc/portage/package.use/00cpuflags` — **CPU_FLAGS_X86 определяются по реальному CPU**.
- `emerge -uvDN -j4 world --exclude gcc glibc` — обновление мира, но **без пересборки gcc/glibc** (экономия часов времени); `etc-update --automode -5` — автопринятие новых конфигов.

### Этап B: ядро (самая интересная часть)
- Ставятся `gentoo-sources` (~amd64), `installkernel` (с USE=grub), `eselect kernel set 1`.
- За основу берётся **`krn330.conf` из репозитория** (готовый конфиг под серверы), скачивается как `.config`.
- К нему **дописывается** большой блок опций (в `.config` поздние строки выигрывают): Gentoo-специфика, squashfs, xHCI/USB-serial, мыши, VMware (FUSION, VMXNET3, PVSCSI), KVM/virtio (VIRTIO_BLK/NET, paravirt), e1000/igb/r8169, nftables/NAT, WireGuard/OVPN/VLAN/bonding, EFI_STUB + simpledrm, serial-консоль 8250, IPMI/watchdog, crypto для iwd, XATTR/ACL, LZ4-сжатие ядра, `CONFIG_X86_NATIVE_CPU=y` (march=native). Если найден NVMe — `${NVMEKERNEL}` добавит `CONFIG_BLK_DEV_NVME=y`.
- Если диск один — MD/RAID переводится из `y` в модули sed'ом.
- **Автодетект драйверов под реальное железо** (строки 556–582): берётся `lspci -k` → имена используемых драйверов/модулей → для каждого ищется соответствующий `CONFIG_*`-символ: сначала grep по Makefile'ам дерева ядра (`obj-$(CONFIG_X) += drv.o`), если не нашлось — поиск строки имени драйвера в `.c`-файлах (`DRV_NAME`, `.name =`, `MODULE_ALIAS`) и обратное сопоставление объекта с Makefile. Найденные символы дописываются в `.config` как `=y` (USB-устройства — `=m`). Это мини-аналог `make localyesconfig`, но работающий от lspci без загруженных модулей.
- `echo -e "x\ny\n" | make menuconfig > /dev/null` — хитрый способ нормализовать `.config` (olddefconfig с сохранением через TUI).
- Сборка: `make -s -j$(($(nproc)*2)) bzImage modules && make modules_install install` — installkernel с USE=grub сам запускает grub-mkconfig.

### Этап C: загрузчик
- `/etc/default/grub`: `GRUB_DISABLE_LINUX_UUID=true`, cmdline `rootfstype=ext4 net.ifnames=0 panic=30` (+`vga=791` на BIOS), таймаут 3 с, `GRUB_TERMINAL=console`, текстовый gfxpayload; добавлен sed-хак, эмулирующий старый `GRUB_LINUX_KERNEL_GLOBS` (меню только из `/boot/vmlinuz` и `vmlinuz.old`, без россыпи версий).
- В EFI-раздел докачиваются **iPXE** (`ipxex64.efi`) и **UEFI Shell** (`shellx64.efi`); из репозитория ставится `grub.d/39_efitools` (тоже с проверкой SHA512), который генерирует для них пункты GRUB-меню через chainloader.
- GRUB ставится **трижды**: `x86_64-efi`, `x86_64-efi --removable` (fallback `BOOTX64.EFI`) и `i386-pc` — машина загрузится в любом режиме.
- Если в cmdline LiveCD была `console=` (serial) — serial-консоль прописывается в grub (`ttyS0,115200`) и в `/etc/inittab`.

### Этап D: серверный набор пакетов и службы
Один большой emerge: `iptables nftables net-snmp git apcupsd iotop iftop ddrescue pv tcpdump nmap netkit-telnetd dmidecode hdparm mlocate postfix bind dhcp watchdog tftp-hpa dhcpcd mc smartmontools syslog-ng cron logrotate lsof [acpi]` — профиль «сетевой сервер/шлюз» (DNS, DHCP, почта, TFTP для PXE, мониторинг).

Настройка служб:
- bind и dhcpd — в **chroot** (`CHROOT=` в conf.d, `emerge --config net-dns/bind`);
- `rc-update add`: watchdog (boot), syslog-ng, cron, in.tftpd (с `/tftproot`), sshd, postfix, named, local, net.br0; `rc-update delete netmount`;
- ssh: `PermitRootLogin no` (при том что на самом LiveCD root-вход по паролю открыт — см. ниже);
- `/etc/local.d/remove.net.rules.start` (+симлинк `.stop`) — при каждой загрузке/выключении удаляет udev-правила predictable names и `setterm -blank 0`;
- postfix: smtp-приём по сети закомментирован в master.cf (только локальная почта), алиас root → `$ROOTEMAIL`;
- крон-задача `*/30 * * * * sntp -S ntp.se` вместо демона ntp;
- опция `usegitportage` в cmdline — миграция дерева portage на **git-синхронизацию** (eselect-repository, удаление снапшотов);
- `--noclear` для getty на tty1 (видеть сообщения загрузки).

## 1.8. Финал (строки 700–713)

`chroot . ./chrootstart.sh` → удаление скрипта → чистка (`var/tmp`, `var/cache/distfiles`) → размонтирование (`umount -l /mnt/gentoo` — lazy, потому что «что-то стало держать») → `reboot`, либо `halt`, если в cmdline `setupdonehalt` (для автотестов в QEMU: завершение VM = успех установки).

---

# 2. portagehelper.sh — снапшоты portage как squashfs

Двухрежимный файл: при сорсинге отдаёт функции, при прямом запуске выполняет `main_portagehelper` (обновление снапшота на живой системе) — трюк `return 0 2>/dev/null || main_portagehelper` в последней строке.

Переменные: `DISTMIRROR` (distfiles.gentoo.org), `TRUSTKEY` (отпечаток Gentoo L1 signing key `ABD00913...96198B1`), пути `var/db/repos/gentoo` и `var/db/snapshots`, симлинк `gentoo-current.xz.sqfs`.

Функции:
- `ensure_key_and_snap_source` — качает `service-keys.gpg` с qa-reports.gentoo.org и подписанный `sha512sum.txt`; импортирует ключи с доверием к L1; через `gpg --verify -o-` извлекает **проверенное** содержимое sha512sum.txt и берёт из него последний `gentoo-YYYYMMDD.xz.sqfs` + его SHA512.
- `update_snapshot` — докачивает (`curl -C -`) снапшот, сверяет SHA512, кладёт в `snapshots/`, переключает симлинк `gentoo-current.xz.sqfs` на новый файл.
- `ensure_snapshot_fstab` — добавляет в fstab строку `…/gentoo-current.xz.sqfs /var/db/repos/gentoo squashfs ro,user,loop,nodev,noexec`.
- `mount_current_snapshot` / `snapshot_ismounted` — (пере)монтирование read-only loop.
- `clean_old_snapshots` — удаляет все снапшоты, кроме текущего и предыдущего.

Итог: «синхронизация портейджа» = скачать один sqfs-файл, проверить подпись, перекинуть симлинк, перемонтировать. Дерево не занимает inode'ы и не пишется на диск вообще.

---

# 3. Подготовка LiveCD

### get_minimal_cd.sh
Скрейпит `current-install-amd64-minimal/`, качает последний ISO + DIGESTS + asc, проверяет: `gpg --locate-key releng@gentoo.org` (WKD), `gpg --verify` обоих файлов, затем SHA512 **и** BLAKE2 из DIGESTS.

### gentoocd_unpack.sh
Пересобирает официальный ISO в `install-amd64-mod.iso` с автозапуском:
1. Требует root (tmpfs + права в squashfs); если запущен не-root — `su -c` на самого себя, а после сборки при флаге `auto` сразу удаляет старый qcow2 и запускает `test_w_qemu.sh -cdrom install-amd64-mod.iso`.
2. Распаковка ISO в **tmpfs 3 ГБ** (через `isoinfo -X` из cdrtools — 7z, как отмечено, ломался).
3. Два режима модификации:
   - `dosquash`: распаковать `image.squashfs`, занулить udev-правила predictable names, дописать `gentoo_cd_bashrc_addon` в `/root/.bashrc`, запаковать обратно;
   - по умолчанию (быстрее): просто скопировать `cdhelpers/*` в корень CD — LiveCD сам вызывает `cdupdate.sh` при загрузке, и тот дописывает addon в bashrc уже в рантайме.
4. Правка `boot/grub/grub.cfg`: `dokeymap` → `net.ifnames=0 keymap=<KEYMAP> autoinstall` (+ при `auto`: serial-консоль, удаление `vga=791`; при `setupdonehalt` — одноимённый флаг). На CD кладутся `install.sh` (как `g-install.sh`) и `portagehelper.sh`.
5. Опционально подмешивает файлы в initrd (`cpiofiles/` → cpio+xz, дописывается к `gentoo.igz` — у initramfs допустима конкатенация архивов).
6. Сборка ISO: `grub-mkrescue -joliet -iso-level 3` (гибридный BIOS+EFI образ).

### cdhelpers/gentoo_cd_bashrc_addon
Запускается при логине root на LiveCD, только если hostname ещё `livecd` и tty — `tty1`/`ttyS0`:
- копирует `g-install.sh`/`portagehelper.sh` с CD, ставит hostname `gtestinst`, задаёт пароль root (`SET_PASS`, иначе `password`), **поднимает sshd**;
- ждёт сеть циклом `curl raw.githubusercontent.com` (ping в QEMU user-network не работает — поэтому HTTP-проба);
- синхронизирует время (chronyd + sntp), при отсутствии качает install.sh с GitHub;
- если в cmdline есть `autoinstall` — запускает установку. Без флага просто оставляет скрипт готовым к ручному запуску.

---

# 4. test_w_qemu.sh — тестовый стенд

Обвязка `qemu-system-x86_64 -enable-kvm -M q35 -cpu host`, память по умолчанию 2 ГБ, половина ядер хоста. Опции:
- `useefi` — OVMF (отдельная копия VARS-флеша);
- `usenvme` — диск как NVMe-устройство (проверка nvme-ветки установщика);
- `auto` — `-nographic` (серийная консоль в терминал);
- `-netdev <tap>` / `-bridge <br>` — варианты сети, по умолчанию user-mode virtio NIC;
- `-cdrom <iso>` — подключение через AHCI;
- диск `kvm_lxgentootest.qcow2` 20 ГБ создаётся автоматически, `cache=unsafe` (только для тестов);
- виртуальный watchdog `i6300esb -action watchdog=reset` — установленная система ставит `watchdog` в boot runlevel, и это проверяется;
- без `auto` — VNC на `127.0.0.1:22` и автозапуск vncviewer.

Полный автотест одной командой: `sh gentoocd_unpack.sh auto useefi usenvme [setupdonehalt]` — пересборка ISO → свежий диск → QEMU → автоустановка → halt по завершении.

---

# 5. Наблюдения, особенности, шероховатости

**Сильные стороны:**
- Сквозная криптопроверка всего скачиваемого: stage3 (GPG+SHA512), снапшот portage (подписанный sha512sum.txt), ISO (GPG+SHA512+BLAKE2), собственные файлы репозитория (захардкоженные SHA512).
- Squashfs-снапшоты вместо rsync — быстро и атомарно.
- Агрессивная параллелизация: ntp, снапшот, getuto, emerge -f — в фоне; curl --parallel; tmpfs для сборки; `--getbinpkg`; world без gcc/glibc; ядро с LZ4.
- Автодетект железа: NVMe, ИБП APC, батарея, CPU-флаги (cpuid2cpuflags), драйверы по lspci → CONFIG_-символы.
- Двойная загрузочная совместимость BIOS+UEFI у результата, плюс iPXE/UEFI Shell в меню GRUB.
- `|| bash` — «точки спасения»: при сбое падаешь в шелл, чинишь, `exit` — установка продолжается.

**Что нужно учитывать / менять под себя:**
- Пароль root по умолчанию `password`, причём sshd поднимается на LiveCD сразу после его установки — на реальной сети обязательно передавать `SET_PASS`.
- `etc/conf.d/net` — это конфиг конкретного шлюза автора (мосты, VLAN 101/120/140, OpenVPN tap); для автоустановки на другой машине его надо править.
- Шведские дефолты: KEYMAP=sv-latin1, ntp.se, Europe/Stockholm, root@asoft.se.
- Диск затирается **без подтверждения** (fdisk-сценарий пишет таблицу сразу) — единственный предохранитель это проверка hostname.
- Мелкие баги: детект APC UPS теряется в субшелле пайпа; `[ -f "*.tar.{bz2,xz,sqfs}" ]` не раскрывает glob; `umount *` и lazy umount в конце — признак неотслеженного держателя монтирования.
- Захардкоженные SHA512 для `portagehelper.sh` и `39_efitools` означают, что при изменении этих файлов в репозитории строки в `install.sh` должны обновляться синхронно.
- Флаги kernel cmdline, управляющие поведением: `autoinstall` (без интерактива), `setupdonehalt` (halt вместо reboot), `usegitportage` (git-синхронизация portage), `console=` (включить serial-консоль в целевой системе).
