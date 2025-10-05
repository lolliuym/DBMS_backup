#!/bin/bash

echo "=== ПРОВЕРКА РЕЗУЛЬТАТОВ ПОСЛЕ BACKUP ==="

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${YELLOW}ℹ $1${NC}"; }

# Проверка что backup завершен
echo "1. Проверка завершения backup..."
if [ -f "/var/run/postgres_backup.lock" ]; then
    print_error "Backup все еще выполняется (обнаружен lock файл)"
    exit 1
else
    print_success "Backup завершен (lock файл удален)"
fi

# Проверка созданных бэкапов
echo ""
echo "2. Проверка созданных бэкапов..."
LATEST_BACKUP=$(ls -t /backups/postgres_backup_*.gz 2>/dev/null | head -1)

if [ -n "$LATEST_BACKUP" ]; then
    print_success "Найден последний бэкап: $(basename $LATEST_BACKUP)"

    # Проверка размера
    BACKUP_SIZE=$(du -h "$LATEST_BACKUP" | cut -f1)
    print_info "Размер бэкапа: $BACKUP_SIZE"

    # Проверка целостности архива
    echo ""
    echo "3. Проверка целостности архива..."
    if gzip -t "$LATEST_BACKUP" 2>/dev/null; then
        print_success "Архив не поврежден"
    else
        print_error "Архив поврежден!"
    fi

    # Проверка содержимого архива
    echo ""
    echo "4. Проверка содержимого архива..."
    ARCHIVE_CONTENT=$(tar -tzf "$LATEST_BACKUP" 2>/dev/null | head -10)
    if [ -n "$ARCHIVE_CONTENT" ]; then
        print_success "Архив содержит файлы:"
        echo "$ARCHIVE_CONTENT"
    else
        print_error "Не удалось прочитать содержимое архива"
    fi
else
    print_error "Бэкапы не найдены в /backups/"
fi

# Проверка очистки временных файлов
echo ""
echo "5. Проверка очистки временных файлов..."
OLD_TEMP=$(find /tmp -maxdepth 1 -type d -name "tmp.*" -user root -mmin +2 2>/dev/null | head -1)
if [ -z "$OLD_TEMP" ]; then
    print_success "Временные файлы очищены (нет старых артефактов)"
else
    print_info "Обнаружены старые временные файлы (от предыдущих сессий):"
    find /tmp -maxdepth 1 -type d -name "tmp.*" -user root -mmin +2 2>/dev/null | head -5
fi

# Проверка логов
echo ""
echo "6. Проверка логов..."
if [ -f "/var/log/postgres_backup.log" ]; then
    LOG_ENTRIES=$(wc -l < "/var/log/postgres_backup.log")
    print_success "Лог-файл создан, записей: $LOG_ENTRIES"

    echo "Последние 10 записей в логе:"
    tail -10 "/var/log/postgres_backup.log"
else
    print_error "Лог-файл не найден"
fi

# Статистика по бэкапам
echo ""
echo "7. Статистика бэкапов..."
BACKUP_COUNT=$(ls /backups/postgres_backup_*.gz 2>/dev/null | wc -l)
if [ "$BACKUP_COUNT" -gt 0 ]; then
    print_info "Всего бэкапов в каталоге: $BACKUP_COUNT"

    echo "5 последних бэкапов:"
    ls -lt /backups/postgres_backup_*.gz 2>/dev/null | head -5 | awk '{print $9, $5, $6, $7, $8}'
else
    print_info "В каталоге нет бэкапов"
fi

echo ""
echo "=== ПРОВЕРКА ЗАВЕРШЕНА ==="