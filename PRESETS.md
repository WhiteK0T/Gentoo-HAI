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
| `xeon` | Железо-надстройка для сервера на Xeon E5450 (8 ГБ RAM): tmpfs сборки урезан до 4G, тяжёлые пакеты (qtwebengine, firefox, gcc, rust…) собираются на диске через `package.env`, nouveau и coretemp в ядре, `VIDEO_CARDS="nouveau"`. Комбинировать: `minimal,xeon`. HDD (второй диск) установщик не трогает — разметить вручную после первой загрузки. |
| `workstation` | Реплика основной системы: профиль desktop/plasma, Plasma 6 + NVIDIA/CUDA, NetworkManager, docker/libvirt/samba, Java/Haskell, медиастек. World-файл и конфиг portage основной системы лежат в `presets/workstation.d/` и копируются в систему хуком. `-march=native` вместо skylake, российские зеркала, `ACCEPT_LICENSE="*"`. ccache/distcc сознательно не переносятся (настройка под хост). |
| `kde` | Лёгкая GUI-надстройка: профиль desktop/plasma, plasma-meta + kdecore-meta + sddm + NetworkManager. Для QEMU сама ставит `VIDEO_CARDS="virtio"`. Комбинировать последним: `minimal,kde`, `minimal,xeon,kde`. |

Замечания к `workstation`/`kde`:

- gcc/glibc исключены из пересборки ради времени — после установки при желании
  выполнить полный `emerge -uvDN world`.
- Создаётся пользователь `sam` (переопределить: `INSTALLUSER=имя`, отключить:
  `INSTALLUSER=""`) с группами wheel/audio/video/… (+docker/libvirt в workstation),
  wheel получает sudo. Начальный пароль = `SET_PASS` (как у root) — сменить после
  первого входа.
- Раскладка X/Wayland настраивается в Plasma; движок задаёт только консольную (`ru`).

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

Опционально `presets/<имя>.chroot.sh` — хук, выполняемый **внутри chroot**
после основного emerge (настройка служб, rc-update и т.п.). Хуку доступны
`ROOTEMAIL` и `NTPSERVER` из окружения. Данные для хука можно положить в
`presets/<имя>.d/` — каталог копируется в chroot рядом с хуком
(`/preset-hooks/<имя>.d/`). При ошибке хука установщик, как и
везде, падает в интерактивный shell (`|| bash`) — починить и `exit`.

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
