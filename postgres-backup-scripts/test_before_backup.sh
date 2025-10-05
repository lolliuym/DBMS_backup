#!/bin/bash

echo "=== ТЕСТИРОВАНИЕ СИСТЕМЫ ДО BACKUP ==="

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${YELLOW}ℹ $1${NC}"; }

# Проверка наличия скрипта
echo "1. Проверка основного скрипта..."
if [ -f "backup_postgres.sh" ]; then
    print_success "Скрипт backup_postgres.sh найден"
    chmod +x backup_postgres.sh
else
    print_error "Скрипт backup_postgres.sh не найден"
    exit 1
fi

# Проверка прав
echo ""
echo "2. Проверка прав доступа..."
if [ $(id -u) -eq 0 ]; then
    print_success "Текущий пользователь: root"
else
    print_info "Текущий пользователь: $(whoami)"
fi

# Проверка PostgreSQL
echo ""
echo "3. Проверка PostgreSQL..."
if systemctl is-active --quiet postgresql; then
    print_success "PostgreSQL запущен"
else
    print_error "PostgreSQL не запущен"
fi

if command -v psql >/dev/null 2>&1; then
    print_success "Утилита psql доступна"
else
    print_error "Утилита psql не найдена"
fi

if command -v pg_dump >/dev/null 2>&1; then
    print_success "Утилита pg_dump доступна"
else
    print_error "Утилита pg_dump не найдена"
fi

# Проверка подключения к БД
echo ""
echo "4. Проверка подключения к PostgreSQL..."
if sudo -u postgres psql -c "SELECT version();" >/dev/null 2>&1; then
    print_success "Подключение к PostgreSQL успешно"

    # Проверка списка баз данных — ИСПРАВЛЕНО
    DB_COUNT=$(sudo -u postgres psql -t -A -c "SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ('postgres', 'rdsadmin', 'template0', 'template1');" 2>/dev/null | grep -v '^\s*$' | wc -l)
    print_info "Найдено пользовательских баз данных: $DB_COUNT"

    echo "Список баз данных:"
    sudo -u postgres psql -t -A -c "SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ('postgres', 'rdsadmin', 'template0', 'template1');" 2>/dev/null | while read db; do
        if [ -n "$db" ]; then
            echo "  $db"
        fi
    done
else
    print_error "Не удалось подключиться к PostgreSQL"
fi

# Проверка места на диске
echo ""
echo "5. Проверка дискового пространства..."
if [ -d "/backups" ]; then
    AVAILABLE_SPACE=$(df /backups | awk 'NR==2 {print $4}')
    AVAILABLE_GB=$((AVAILABLE_SPACE / 1024 / 1024))
    print_success "Каталог /backups существует"
    print_info "Свободное место: ${AVAILABLE_GB}GB"

    if [ "$AVAILABLE_SPACE" -lt 102400 ]; then  # 100 MB = 102400 KB
        print_error "Внимание: Менее 100MB свободного места"
    fi
else
    print_info "Каталог /backups не существует, будет создан автоматически"
fi

# Проверка необходимых утилит
echo ""
echo "6. Проверка системных утилит..."
for util in tar gzip mktemp; do
    if command -v $util >/dev/null 2>&1; then
        print_success "$util доступен"
    else
        print_error "$util не найден"
    fi
done

# Проверка блокировки
echo ""
echo "7. Проверка блокировки..."
if [ -f "/var/run/postgres_backup.lock" ]; then
    print_error "Обнаружен файл блокировки. Скрипт уже запущен."
    LOCK_PID=$(cat /var/run/postgres_backup.lock 2>/dev/null)
    if ps -p $LOCK_PID >/dev/null 2>&1; then
        print_error "Процесс с PID $LOCK_PID все еще выполняется"
    else
        print_info "Процесс не активен, можно удалить lock файл"
    fi
else
    print_success "Файл блокировки не обнаружен"
fi

echo ""
echo "=== ТЕСТИРОВАНИЕ ЗАВЕРШЕНО ==="
echo "Рекомендации:"
echo "• Запустите тест во время backup: sudo ./test_during_backup.sh"
echo "• Запустите тест после backup: sudo ./test_after_backup.sh"
echo "• Для полного теста: sudo ./test_complete_scenario.sh"