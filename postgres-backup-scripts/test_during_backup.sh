#!/bin/bash

echo "=== МОНИТОРИНГ ВО ВРЕМЯ BACKUP ==="

# Проверяем что backup запущен
if [ ! -f "/var/run/postgres_backup.lock" ]; then
    echo "Backup не запущен. Запустите сначала: sudo ./backup_postgres.sh"
    exit 1
fi

LOCK_PID=$(cat /var/run/postgres_backup.lock 2>/dev/null)
echo "Backup запущен с PID: $LOCK_PID"

# Мониторинг в реальном времени
echo ""
echo "Мониторинг процесса backup..."
echo "Нажмите Ctrl+C для остановки мониторинга"

while true; do
    clear
    echo "=== МОНИТОРИНГ BACKUP $(date) ==="

    # Проверка процесса
    if ps -p $LOCK_PID >/dev/null 2>/dev/null; then
        echo "✓ Процесс backup активен (PID: $LOCK_PID)"
    else
        echo "✗ Процесс backup завершен"
        break
    fi

    # Проверка временных файлов
    echo ""
    echo "Временные файлы:"
    TEMP_DIRS=$(find /tmp -name "tmp.*" -type d -user root 2>/dev/null | head -5)
    if [ -n "$TEMP_DIRS" ]; then
        echo "Найдены временные каталоги:"
        echo "$TEMP_DIRS"
    else
        echo "Временные каталоги не найдены"
    fi

    # Мониторинг логов
    echo ""
    echo "Последние записи в логе:"
    tail -5 "/var/log/postgres_backup.log" 2>/dev/null || echo "Лог недоступен"

    # Использование ресурсов
    echo ""
    echo "Использование ресурсов процессом $LOCK_PID:"
    ps -p $LOCK_PID -o pid,ppid,pcpu,pmem,cmd --no-headers 2>/dev/null || echo "Процесс не найден"

    # Проверка созданных файлов
    echo ""
    echo "Файлы в /backups:"
    ls -la "/backups/" 2>/dev/null | head -10 || echo "Каталог /backups недоступен"

    sleep 5
done

echo ""
echo "Мониторинг завершен"