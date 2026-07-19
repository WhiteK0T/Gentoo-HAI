# Portage-дерево как squashfs-снапшот

## Что это
Установщик Gentoo-HAI не разворачивает дерево Portage через `emerge-webrsync`,
а качает готовый **squashfs-снапшот** (`gentoo-YYYYMMDD.xz.sqfs`) и монтирует
его **read-only** в `/var/db/repos/gentoo`.

## Чем лучше emerge-webrsync
- Нет распаковки ~200k мелких файлов — образ остаётся сжатым на диске (сотни МБ).
- Экономия места и inode (важно в tmpfs/на малых дисках).
- Быстрее: один файл скачался (с докачкой `-C -`) → `mount` → дерево готово.
- Неизменяемость: ro-mount нельзя случайно испортить; на переустановке
  снапшот переиспользуется/заменяется целиком.
- Безопасность та же: снапшот подписан ключами Gentoo и сверяется по SHA512.

## Где что лежит
- Снапшоты:            /var/db/snapshots/gentoo-YYYYMMDD.xz.sqfs
- Текущий (симлинк):   /var/db/snapshots/gentoo-current.xz.sqfs
- Точка монтирования:  /var/db/repos/gentoo   (squashfs, ro)
- fstab-строка:        /var/db/snapshots/gentoo-current.xz.sqfs  /var/db/repos/gentoo  squashfs  ro,user,loop,nodev,noexec  0 0

## Про ошибку
    chown: changing ownership of '/var/db/repos/gentoo': Read-only file system
Безвредна. Это `emerge-webrsync`/gemato пытается сделать chown на read-only
mount. В этой схеме webrsync не нужен — снапшот УЖЕ и есть твоё дерево.

## Как обновить дерево (заменить снапшот новым)
Базовый URL зеркала (для RU быстрее yandex):
    MIRROR=https://mirror.yandex.ru/gentoo-distfiles      # или https://distfiles.gentoo.org

1. Узнать имя и ожидаемый SHA512 последнего снапшота:
    curl -s $MIRROR/snapshots/squashfs/sha512sum.txt | grep -E 'gentoo-[0-9]+\.xz\.sqfs$'
   (первое поле — SHA512, второе — имя файла SNAP)

2. Скачать снапшот (с докачкой и ретраями):
    cd /var/db/snapshots
    SNAP=gentoo-YYYYMMDD.xz.sqfs        # подставь имя из шага 1
    curl -C - --retry 10 --retry-all-errors --remote-name-all \
      "$MIRROR/snapshots/squashfs/$SNAP"

3. Проверить контрольную сумму:
    sha512sum "$SNAP"                   # должно совпасть с sha512sum.txt из шага 1

4. Переключить симлинк и перемонтировать:
    ln -sf "$SNAP" gentoo-current.xz.sqfs
    umount -l /var/db/repos/gentoo 2>/dev/null
    mount /var/db/repos/gentoo         # берёт параметры из fstab

5. Проверить:
    mount | grep repos/gentoo          # squashfs, ro
    ls /var/db/repos/gentoo | head

6. (Опционально) удалить старые снапшоты:
    ls -t gentoo-*.xz.sqfs | tail -n +3 | xargs -r rm -f

## Альтернатива: живое git-дерево (если нужны emerge --sync)
Если хочешь обычные обновления через `emerge --sync`/webrsync с записью на диск —
переходи на git-дерево (в установщике для этого есть kernel-флаг `usegitportage`,
который отключает snapshot-репозиторий и включает пишущий git-репозиторий).
Вручную, по вики Gentoo (Portage with Git):
    umount -l /var/db/repos/gentoo
    # убрать squashfs-строку из /etc/fstab
    emerge -1 app-eselect/eselect-repository
    eselect repository disable gentoo
    eselect repository enable gentoo
    emerge --sync
Тогда дерево лежит на записываемой ФС и chown/webrsync работают штатно.

Проверь одно перед использованием: точная fstab-строка и путь к снапшотам в твоей установке — они задаются в `portagehelper.sh` (`pathsnapshots`, `cursqfs`, `ensure_snapshot_fstab`); если у тебя переменные переопределены, подставь свои.