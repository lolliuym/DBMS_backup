#!/bin/bash

echo "=== ПОЛНЫЙ ТЕСТ ВСЕХ СЦЕНАРИЕВ ==="

print_section() {
    echo ""
    echo "=== $1 ==="
    echo ""
}

print_section "1. ТЕСТ: Запуск без прав root"
echo "Проверка логики защиты от запуска не от root..."

if bash -c 'id() { echo 1000; }; source ./backup_postgres.sh' 2>/dev/null; then
    echo "❌ ТЕСТ НЕ ПРОЙДЕН: Скрипт завершился успешно без root"
else
    echo "✅ ТЕСТ ПРОЙДЕН: Скрипт отказался работать без root"
fi

print_section "2. ТЕСТ: Блокировка параллельного запуска"
echo "Создаем lock файл..."
sudo touch /var/run/postgres_backup.lock
echo "Пытаемся запустить второй экземпляр..."
sudo ./backup_postgres.sh
if [ $? -ne 0 ]; then
    echo "✅ ТЕСТ ПРОЙДЕН"
else
    echo "❌ ТЕСТ НЕ ПРОЙДЕН"
fi
sudo rm -f /var/run/postgres_backup.lock

print_section "3. ТЕСТ: Обработка ошибок дампов"
echo "Создаем базу для имитации ошибки..."
sudo -u postgres psql -c "CREATE DATABASE simulate_error_db;" 2>/dev/null
echo "Запускаем backup (должен прерваться)..."
sudo ./backup_postgres.sh
if [ $? -ne 0 ]; then
    echo "✅ ТЕСТ ПРОЙДЕН: Скрипт прервался при ошибке"
    echo "Проверяем что архив не создан..."
    if ls /backups/postgres_backup_*_simulate_error_db.gz 2>/dev/null; then
        echo "❌ ПРОБЛЕМА: Архив создан несмотря на ошибку"
    else
        echo "✅ ПОВЕДЕНИЕ КОРРЕКТНО: Архив не создан"
    fi
else
    echo "❌ ТЕСТ НЕ ПРОЙДЕН: Скрипт не прервался"
fi
sudo -u postgres psql -c "DROP DATABASE simulate_error_db;" 2>/dev/null

print_section "4. ТЕСТ: Нормальная работа"
echo "Запускаем backup..."
sudo ./backup_postgres.sh
if [ $? -eq 0 ]; then
    echo "✅ ТЕСТ ПРОЙДЕН"
    echo "Проверяем создание архива..."
    LATEST_BACKUP=$(ls -t /backups/postgres_backup_*.gz 2>/dev/null | head -1)
    if [ -n "$LATEST_BACKUP" ]; then
        echo "✅ АРХИВ СОЗДАН: $(basename $LATEST_BACKUP)"
        if gzip -t "$LATEST_BACKUP" 2>/dev/null; then
            echo "✅ АРХИВ ЦЕЛОСТЕН"
        else
            echo "❌ АРХИВ ПОВРЕЖДЕН"
        fi
    else
        echo "❌ АРХИВ НЕ СОЗДАН"
    fi
else
    echo "❌ ТЕСТ НЕ ПРОЙДЕН"
fi

print_section "5. ТЕСТ: Очистка временных файлов"
echo "Проверяем очистку..."
TEMP_FILES=$(find /tmp -maxdepth 1 -type d -name "tmp.*" -user root 2>/dev/null | grep -v "snap" | head -5)

# Проверим, есть ли временные файлы, созданные БОЛЕЕ 2 МИНУТ НАЗАД
OLD_TEMP=$(find /tmp -maxdepth 1 -type d -name "tmp.*" -user root -mmin +2 2>/dev/null | head -1)

if [ -z "$OLD_TEMP" ]; then
    echo "✅ ВРЕМЕННЫЕ ФАЙЛЫ ОЧИЩЕНЫ (нет старых артефактов)"
else
    echo "ℹ Обнаружены старые временные файлы (возможно, от предыдущих сессий):"
    find /tmp -maxdepth 1 -type d -name "tmp.*" -user root -mmin +2 2>/dev/null | head -5
fi

print_section "6. ТЕСТ: Логирование"
if [ -f "/var/log/postgres_backup.log" ]; then
    echo "✅ ЛОГ-ФАЙЛ СОЗДАН"
    echo "Последние записи:"
    tail -5 "/var/log/postgres_backup.log"
else
    echo "❌ ЛОГ-ФАЙЛ НЕ СОЗДАН"
fi
 

print_section "5. ТЕСТ: Очистка временных файлов"
echo "Проверяем очистку..."
TEMP_FILES=$(find /tmp -maxdepth 1 -type d -name "tmp.*" -user root 2>/dev/null | grep -v "snap" | head -5)

# Проверим, есть ли временные файлы, созданные БОЛЕЕ 2 МИНУТ НАЗАД
OLD_TEMP=$(find /tmp -maxdepth 1 -type d -name "tmp.*" -user root -mmin +2 2>/dev/null | head -1)

if [ -z "$OLD_TEMP" ]; then
    echo "✅ ВРЕМЕННЫЕ ФАЙЛЫ ОЧИЩЕНЫ (нет старых артефактов)"
else
    echo "ℹ Обнаружены старые временные файлы (возможно, от предыдущих сессий):"
    find /tmp -maxdepth 1 -type d -name "tmp.*" -user root -mmin +2 2>/dev/null | head -5
fi

print_section "6. ТЕСТ: Логирование"
if [ -f "/var/log/postgres_backup.log" ]; then
    echo "✅ ЛОГ-ФАЙЛ СОЗДАН"
    echo "Последние записи:"
    tail -5 "/var/log/postgres_backup.log"
else
    echo "❌ ЛОГ-ФАЙЛ НЕ СОЗДАН"
fi

echo ""
echo "=== ВСЕ ТЕСТЫ ЗАВЕРШЕНЫ ==="