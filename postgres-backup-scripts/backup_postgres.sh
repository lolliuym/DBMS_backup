#!/bin/bash

# Конфигурация
LOG_FILE="/var/log/postgres_backup.log"
BACKUP_DIR="/backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_NAME="postgres_backup_${TIMESTAMP}.gz"
TEMP_DIR=$(mktemp -d)
LOCK_FILE="/var/run/postgres_backup.lock"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${YELLOW}ℹ $1${NC}"; }

# Функция логирования
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | sudo tee -a "$LOG_FILE" >/dev/null
    echo "$1"
}

# Функция очистки временных файлов
cleanup() {
    log "Выполняется очистка временных файлов..."

    # Удаляем только тот каталог, который создали
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
         print_info "Временный каталог $TEMP_DIR удалён"
    fi

    # Удаляем lock-файл
    if [ -f "$LOCK_FILE" ]; then
        rm -f "$LOCK_FILE"
        print_info "Lock-файл $LOCK_FILE удалён"
    fi
}

# Обработка ошибок с немедленным выходом
error_exit() {
    print_error "ОШИБКА: $1"
    log "АВАРИЙНОЕ ЗАВЕРШЕНИЕ СКРИПТА"
    exit 1
}

# Проверка прав root
if [ "$(id -u)" -ne 0 ]; then
    print_error "ОШИБКА: Скрипт должен быть запущен с правами root. Используйте: sudo ./backup_postgres.sh"
    exit 1
fi

# Блокировка параллельного запуска
if [ -f "$LOCK_FILE" ]; then
    print_error "ОШИБКА: Скрипт уже запущен. Если это ошибка, удалите файл: sudo rm -f $LOCK_FILE"
    exit 1
fi

# Создание файла блокировки
echo $$ > "$LOCK_FILE"
if [ $? -ne 0 ]; then
    print_error "ОШИБКА: Не удалось создать файл блокировки: $LOCK_FILE"
    exit 1
fi

# Гарантируем удаление временных файлов и lock при любом выходе
trap cleanup EXIT

# Начало работы
log "=== Начало процесса резервного копирования PostgreSQL ==="

# Проверка существования каталога для бэкапов
if [ ! -d "$BACKUP_DIR" ]; then
    log "Каталог $BACKUP_DIR не существует. Попытка создания..."
    if ! mkdir -p "$BACKUP_DIR"; then
        error_exit "Не удалось создать каталог $BACKUP_DIR. Проверьте права доступа."
    fi
    chmod 755 "$BACKUP_DIR"
    log "Каталог $BACKUP_DIR успешно создан"
fi

# Проверка свободного места (минимум 100MB = 102400 KB)
log "Проверка свободного места в каталоге $BACKUP_DIR..."
AVAILABLE_SPACE_KB=$(df "$BACKUP_DIR" | awk 'NR==2 {print $4}')
if [ "$AVAILABLE_SPACE_KB" -lt 102400 ]; then
    error_exit "Недостаточно свободного места в каталоге $BACKUP_DIR. Доступно: ${AVAILABLE_SPACE_KB}KB, требуется: 102400KB"
fi
print_info "Свободного места достаточно: ${AVAILABLE_SPACE_KB}KB"

# Проверка доступности утилит PostgreSQL
log "Проверка доступности утилит PostgreSQL..."
if ! command -v psql >/dev/null 2>&1; then
    error_exit "Утилита psql не найдена. Убедитесь что PostgreSQL установлен."
fi

if ! command -v pg_dump >/dev/null 2>&1; then
    error_exit "Утилита pg_dump не найдена. Убедитесь что PostgreSQL установлен."
fi
log "Утилиты PostgreSQL доступны"

# Проверка подключения к PostgreSQL
log "Проверка подключения к PostgreSQL..."
if ! sudo -u postgres psql -c "SELECT version();" >/dev/null 2>&1; then
    error_exit "Не удалось подключиться к PostgreSQL. Проверьте:
    - Запущен ли сервер PostgreSQL
    - Правильность аутентификации
    - Права пользователя postgres"
fi
log "Подключение к PostgreSQL успешно"

# Получение списка баз данных — ИСПРАВЛЕНО: используем SQL-запрос
log "Получение списка баз данных PostgreSQL..."
DATABASES=$(sudo -u postgres psql -t -A -c "SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ('postgres', 'rdsadmin', 'template0', 'template1');" 2>/dev/null | grep -v '^\s*$')

if [ -z "$DATABASES" ]; then
    error_exit "Не удалось получить список баз данных или не найдено пользовательских баз данных"
fi

log "Найдены базы данных: $(echo $DATABASES | tr '\n' ' ')"

# Создание дампов для каждой базы данных с обработкой ошибок
for DB in $DATABASES; do
    DUMP_FILE="${TEMP_DIR}/${DB}.sql"
    log "Создание дампа базы данных: $DB"

    # Демонстрация обработки ошибок для определенной базы
    if [ "$DB" = "simulate_error_db" ]; then
        print_error "Имитация ошибки дампа для базы $DB"
        error_exit "Создание дампа базы $DB завершилось ошибкой. Резервное копирование прервано."
    fi

    # Реальное создание дампа
    if ! sudo -u postgres pg_dump "$DB" > "$DUMP_FILE" 2>> "$LOG_FILE"; then
        print_error " Ошибка при создании дампа базы $DB"

        if [ -f "$DUMP_FILE" ] && [ ! -s "$DUMP_FILE" ]; then
            rm -f "$DUMP_FILE"
        fi

        error_exit "Создание дампа базы $DB завершилось ошибкой. Резервное копирование прервано."
    fi

    if [ -s "$DUMP_FILE" ]; then
        DUMP_SIZE=$(du -h "$DUMP_FILE" | cut -f1)
        print_success " Дамп базы $DB успешно создан (размер: $DUMP_SIZE)"
    else
        error_exit "Дамп базы $DB создан, но пуст. Это недопустимо."
    fi
done

# Проверяем что есть хотя бы один SQL файл для архивации
SQL_FILES_COUNT=$(find "$TEMP_DIR" -name "*.sql" -type f | wc -l)
if [ "$SQL_FILES_COUNT" -eq 0 ]; then
    error_exit "Нет SQL файлов для архивации. Создание архива прервано."
fi

# Создание архива
log "Создание архива $BACKUP_NAME..."
cd "$TEMP_DIR" || error_exit "Не удалось перейти в каталог $TEMP_DIR"

SQL_FILES=$(ls *.sql 2>/dev/null)
if [ -z "$SQL_FILES" ]; then
    error_exit "Нет SQL файлов для архивации"
fi

log "Архивация файлов: $SQL_FILES"

if ! tar -czf "${TEMP_DIR}/${BACKUP_NAME}" *.sql 2>> "$LOG_FILE"; then
    error_exit "Ошибка при создании архива. Проверьте достаточно ли места и прав доступа."
fi

ARCHIVE_SIZE=$(du -h "${TEMP_DIR}/${BACKUP_NAME}" | cut -f1)
print_success " Архив успешно создан (размер: $ARCHIVE_SIZE)"

# Проверка целостности архива
log "Проверка целостности архива..."
if ! gzip -t "${TEMP_DIR}/${BACKUP_NAME}" 2>> "$LOG_FILE"; then
    error_exit "Архив поврежден и не прошел проверку целостности"
fi
print_success " Архив прошел проверку целостности"

# Перемещение архива в конечный каталог
log "Перемещение архива в $BACKUP_DIR..."
if ! mv "${TEMP_DIR}/${BACKUP_NAME}" "$BACKUP_DIR/"; then
    error_exit "Ошибка при перемещении архива в $BACKUP_DIR. Проверьте права доступа."
fi

# Финальная проверка что архив на месте
if [ ! -f "$BACKUP_DIR/$BACKUP_NAME" ]; then
    error_exit "Архив не найден в целевом каталоге после перемещения"
fi

FINAL_SIZE=$(du -h "$BACKUP_DIR/$BACKUP_NAME" | cut -f1)
print_success " Резервная копия успешно создана: $BACKUP_NAME ($FINAL_SIZE)"

log "=== Процесс резервного копирования завершен успешно ==="
log "Итог: создана резервная копия $BACKUP_NAME"
exit 0