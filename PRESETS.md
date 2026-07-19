# Пресеты (форк Gentoo-HAI)

Этот форк разделяет установщик на **движок** (`install.sh`) и **пресеты**
(`presets/*.sh`) — небольшие файлы с переменными, определяющие набор пакетов,
службы, сеть и опции ядра. Региональные дефолты движка изменены на Россию
(`Europe/Moscow`, `ru`, `ru.pool.ntp.org`); всё по-прежнему переопределяется
переменными окружения.

## Выбор пресета

Через переменную окружения (ручной запуск с LiveCD):

```bash
PRESET=minimal sh install.sh
PRESET=gateway,xeon SET_PASS='МойПароль' sh install.sh
```

Или через kernel cmdline (`preset=minimal,xeon`) — при сборке авто-ISO:

```bash
sh gentoocd_unpack.sh auto --preset minimal          # тест в QEMU
sh gentoocd_unpack.sh --preset gateway,xeon          # ISO для реального сервера
```

Несколько пресетов перечисляются через запятую и применяются по порядку
(последний выигрывает при конфликте переменных). Если пресет не указан,
используется `minimal`. Каталог `presets/` ищется рядом с `install.sh`,
в текущем каталоге и на `/mnt/cdrom`.

## Имеющиеся пресеты

| Пресет | Что даёт |
|---|---|
| `minimal` | База движка: sshd (`PermitRootLogin no`), cron, syslog-ng, logrotate, smartmontools, iotop/iftop/tcpdump, mc, watchdog, nftables/iptables, git. Сеть — DHCP на eth0. Ничего не добавляет — служит шаблоном. |
| `gateway` | Стек автора оригинала: bind (chroot) + dhcpd (chroot, в runlevel не добавлен — сначала настроить subnets) + postfix (только локальная почта, алиас root → `ROOTEMAIL`) + tftp-hpa (PXE) + net-snmp + nmap. Сеть — мост br0 поверх eth0. |
| `xeon` | Железо-надстройка для сервера на Xeon E5450 (8 ГБ RAM): tmpfs сборки урезан до 4G, тяжёлые пакеты (qtwebengine, firefox, gcc, rust…) собираются на диске через `package.env`, nouveau и coretemp в ядре, `VIDEO_CARDS="nouveau"`. Система ставится строго на SSD (невращающийся диск), как бы BIOS ни пронумеровал диски. HDD становится data-диском (см. ниже). Создаёт пользователя `sam` (wheel+sudo, ставит `app-admin/sudo`). Комбинировать: `minimal,xeon`. |
| `vps` | Надстройка под KVM-VPS (VirtFusion и т.п.): вложенная виртуализация (KVM-хост на AMD — `CONFIG_KVM_AMD`, vhost/tun/bridge), явно включённый virtio-guest транспорт (диск/сеть/консоль), serial-консоль в GRUB+inittab для консоли провайдера, пользователь `sam` (wheel+sudo). Сеть — DHCP по умолчанию; статический IP через `VPS_IP`/`VPS_GW` (см. ниже). Система ставится на автодетект-диск (`nvme0n1`→`vda`→`sda`). qemu/libvirt не ставятся (долгая сборка) — ядро готово, доставить вручную. Комбинировать: `minimal,vps`. |
| `workstation` | Реплика основной системы: профиль desktop/plasma, Plasma 6 + NVIDIA/CUDA, NetworkManager, docker/libvirt/samba, Java/Haskell, медиастек. World-файл и конфиг portage основной системы лежат в `presets/workstation.d/` и копируются в систему хуком. `-march=native` вместо skylake, российские зеркала, `ACCEPT_LICENSE="*"`. ccache/distcc сознательно не переносятся (настройка под хост). |
| `kde` | Лёгкая GUI-надстройка: профиль desktop/plasma, plasma-meta + kdecore-meta + sddm + NetworkManager. Для QEMU сама ставит `VIDEO_CARDS="virtio"`. Комбинировать последним: `minimal,kde`, `minimal,xeon,kde`. |

Пользователь `sam` создаётся пресетами `xeon`, `kde`, `workstation` (общий
сниппет `presets/adduser.inc`). Переопределить имя: `INSTALLUSER=имя`,
отключить: `INSTALLUSER=""`. Группы: wheel/users в xeon, +audio/video/… в
десктопах (+docker/libvirt в workstation), wheel получает sudo. Начальный
пароль = `SET_PASS` (как у root) — сменить после первого входа. Если при
сборке ISO запечён ssh-ключ, `sam` наследует его из `/etc/skel`.

Замечания к `workstation`/`kde`:

- gcc/glibc исключены из пересборки ради времени — после установки при желании
  выполнить полный `emerge -uvDN world`.
- Раскладка X/Wayland настраивается в Plasma; движок задаёт только консольную (`ru`).

## Data-диск пресета `xeon` (HDD → /srv)

Второй диск (HDD 320 ГБ) пресет оформляет как data-диск: GPT, один
ext4-раздел с меткой `data`, в fstab монтируется в `/srv`. Внутри создаются
`/srv/samba` (шары), `/srv/backup` (бэкапы), `/srv/vm` (образы VM) и симлинк
`/var/lib/libvirt/images → /srv/vm`, так что libvirt по умолчанию кладёт
образы на HDD.

Правила безопасности:

- **форматируется только чистый диск** (без таблицы разделов и ФС);
- раздел с существующей меткой `data` переиспользуется как есть —
  **данные переживают переустановку системы**;
- диск с любой другой ФС не трогается (предупреждение в лог); чтобы отдать
  его установщику — `e2label <раздел> data` либо стереть `wipefs -a`.

Управление: `DATADEV=/dev/sdX` — указать диск явно, `DATADEV=none` (или
`datadev=none` в kernel cmdline) — не трогать второй диск вообще.
Авто-выбор: первый несъёмный диск, не являющийся системным. Сама система
при этом ставится на SSD — пресет выбирает невращающийся диск под `IDEV`.

## Пресет `vps` (KVM-VPS, VirtFusion)

Роль-надстройка под виртуалку у провайдера (KVM/libvirt, панель VirtFusion).
Комбинируется с базой: `PRESET="minimal,vps"`.

Что делает:

- **Вложенная виртуализация**: в ядро добавлены KVM-хост (`CONFIG_KVM`,
  `CONFIG_KVM_AMD=m` под Ryzen; `KVM_INTEL=m` тоже — образ загрузится и на
  Intel-хосте), `vhost`/`vhost_net`, `tun`, `bridge`. Userland qemu/libvirt
  **не ставится** (часы сборки) — ядро готово, при надобности:
  `emerge app-emulation/qemu app-emulation/libvirt`.
- **virtio-guest транспорт** прописан явно (`VIRTIO_PCI`, `SCSI_VIRTIO`,
  `HW_RANDOM_VIRTIO`, `VIRTIO_CONSOLE`, `VIRTIO_BALLOON`…) — на KVM-VPS без
  `VIRTIO_PCI` не будет ни диска, ни сети.
- **Serial-консоль** (`console=ttyS0,115200`) в GRUB и getty в inittab —
  чтобы работала консоль провайдера (в т.ч. когда ISO собран без `auto`).
- Пользователь `sam` (wheel+sudo). На headless-VPS без запечённого
  ssh-ключа root по ssh запрещён — заходить юзером `sam` или запечь ключ.

**Диск**: автодетект движка (`nvme0n1`→`vda`→`sda`) — неважно, как провайдер
отдаёт 200 ГБ (virtio-blk/scsi/эмуляция NVMe).

**Сеть**: по умолчанию DHCP на eth0. Для статики задать при сборке ISO
CIDR-адрес, шлюз, DNS и (при необходимости) MTU — `gentoocd_unpack.sh`
запекает `VPS_IP`/`VPS_GW`/`VPS_DNS`/`VPS_MTU` в CD, они переживают
автоустановку:

```bash
VPS_IP=89.106.89.196/28 VPS_GW=11.0.0.1 VPS_DNS="1.1.1.1 1.0.0.1" VPS_MTU=1448 \
  SET_PASS='МойПароль' sh gentoocd_unpack.sh --preset minimal,vps setupdonehalt
```

`VPS_DNS` по умолчанию `1.1.1.1 1.0.0.1` (переопределить списком через пробел).

Пресет учитывает три особенности реальных DDoS-защищённых VirtFusion-хостов:

- **Off-link шлюз** — шлюз (напр. `11.0.0.1`) **вне** подсети адреса. Обычный
  `default via GW` падает (`nexthop has invalid gateway`); пресет ставит флаг
  `onlink` (`routes_eth0="default via GW onlink"`), и ядро принимает шлюз как
  доступный на линке. Проверить у себя: `ip route` на рабочей системе — если
  видишь `default via … onlink`, это твой случай.
- **Урезанный MTU** — трафик тоннелируется, реальный MTU <1500 (часто 1448 /
  1400). При 1500 мелкие пакеты проходят, крупные (stage3, TLS) уходят в
  чёрную дыру → установка виснет в начале. Узнать MTU: `ip link show eth0`
  (поле `mtu`) на любой рабочей ОС этого VPS. Задать через `VPS_MTU`.
- **Static-only** — сам LiveCD-установщик тут не получает DHCP. Пресет при
  заданном `VPS_IP` поднимает NIC установщика статикой **до** скачивания
  stage3 (иначе unattended-установка стопорится на загрузке).

Значения `VPS_IP`/`VPS_GW`/`VPS_MTU` берутся из панели провайдера либо из
вывода `ip addr` / `ip route` / `ip link` уже работающей на этом VPS ОС.

**Установка на VPS** (VirtFusion): загрузить ISO с образа/через панель,
в VNC-консоли пройти установку. Для полностью автоматической:
`sh gentoocd_unpack.sh auto --preset minimal,vps setupdonehalt` — установщик
отработает сам и **остановится** (`halt`); после этого в панели отключить ISO
и переключить загрузку на диск (иначе с примонтированным ISO будет цикл
переустановки). Без `setupdonehalt` система после установки перезагрузится.

## Интерфейс пресета

Файл `presets/<имя>.sh` сорсится движком в самом начале. Переменные
**дописывать**, не перезаписывать (`PRESET_PACKAGES="${PRESET_PACKAGES} …"`),
чтобы пресеты комбинировались:

| Переменная | Назначение |
|---|---|
| `PRESET_PACKAGES` | пакеты, добавляемые к основному emerge |
| `PRESET_USE` | глобальные USE-флаги в make.conf |
| `BASEUSE` | базовые USE движка (по умолчанию `-X iproute2 logrotate`; десктоп-пресеты убирают `-X`) |
| `PRESET_PACKAGE_USE` | строки для `/etc/portage/package.use/preset` |
| `PRESET_KERNEL_EXTRA` | строки, дописываемые в `.config` ядра |
| `TMPFSSIZE` | размер tmpfs `/var/tmp` (сборочное место), по умолчанию 6G |
| `NETCONF` | полное содержимое `/etc/conf.d/net` |
| `NETSVC` | служба `net.*`, добавляемая в default runlevel (по умолчанию `net.eth0`; пустая строка — netifrc не включать, например при NetworkManager) |
| `PRESET_FSTAB` | дополнительные строки fstab устанавливаемой системы |
| `PRESET_DISKSETUP` | имена функций, которые движок вызовет после разметки и монтирования системного диска (доп. диски: можно монтировать под `/mnt/gentoo` и дописывать `PRESET_FSTAB`) |
| `IDEV` | целевой диск; пресет может задать его до автодетекта движка (`IDEV=${IDEV:-/dev/sdX}`) |

Опционально `presets/<имя>.chroot.sh` — хук, выполняемый **внутри chroot**
после основного emerge (настройка служб, rc-update и т.п.). Хуку доступны
`ROOTEMAIL`, `NTPSERVER`, `SET_PASS`, `INSTALLUSER` из окружения. Данные для
хука можно положить в `presets/<имя>.d/` — каталог копируется в chroot рядом
с хуком (`/preset-hooks/<имя>.d/`). При ошибке хука установщик, как и
везде, падает в интерактивный shell (`|| bash`) — починить и `exit`.

Общий код для хуков — в файлах `presets/*.inc` (расширение `.inc`, не `.sh`,
чтобы движок не запускал их как самостоятельные хуки). Движок копирует их в
`/preset-hooks/`, хук подключает через `. "$(dirname "$0")/файл.inc"`. Так
сделано создание пользователя: `presets/adduser.inc` (параметр `USER_GROUPS`).

## Прочие отличия форка от оригинала

- Сетевой конфиг по умолчанию — простой DHCP вместо личного конфига автора
  (мосты + VLAN + OpenVPN); шлюзовой вариант перенесён в пресет `gateway`.
- Исправлен детект ИБП APC (переменная терялась в субшелле пайпа).
- Исправлена неработавшая чистка старых stage3-архивов (glob в кавычках).
- `TMPFSSIZE` сделан переменной (был захардкоженный 6G).
- USE-флаг `snmp` убран из базовых (теперь его даёт `gateway`).

## Доступ: SSH-ключ или пароль

Публичный ключ можно «запечь» в установку тремя способами:

```bash
SSHKEY="ssh-ed25519 AAAA... user@host" sh install.sh   # строкой
SSHKEY=~/.ssh/id_ed25519.pub sh install.sh             # путём к файлу
cp ~/.ssh/id_ed25519.pub authorized_keys               # файлом рядом со скриптом
sh gentoocd_unpack.sh auto --preset minimal            #   (попадёт и на ISO)
```

С ключом: он кладётся в `/root/.ssh/authorized_keys` и в `/etc/skel/.ssh/`
(все создаваемые пользователи, включая `sam`, получают его автоматически),
ssh переводится в key-only режим — `PermitRootLogin prohibit-password`,
`PasswordAuthentication no`. Вход по паролю в консоли при этом работает.
Оставить парольный ssh для обычных пользователей: `SSHPASSAUTH=yes`.

Без ключа — прежнее поведение: вход по паролю, root по ssh запрещён.
Файл `authorized_keys` в корне репозитория в git не попадает (.gitignore).

Напоминание: пароль root по умолчанию `password` — задавайте `SET_PASS`.
