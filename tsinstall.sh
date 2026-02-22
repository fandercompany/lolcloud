#!/bin/bash

# Скрипт автоматической установки TeamSpeak сервера на Ubuntu
# Версия TeamSpeak: 3.13.7

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функция для вывода сообщений
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Проверка запуска от root
if [ "$EUID" -ne 0 ]; then 
    print_error "Пожалуйста, запустите скрипт с правами root (используйте sudo)"
    exit 1
fi

# Получаем имя текущего пользователя (не root)
CURRENT_USER=${SUDO_USER:-$USER}
print_message "Текущий пользователь: $CURRENT_USER"

# Запрос пароля администратора TeamSpeak
read -sp "Введите пароль администратора TeamSpeak (будет использован как serveradmin_password): " TS_PASSWORD
echo
if [ -z "$TS_PASSWORD" ]; then
    print_warning "Пароль не введен. Будет сгенерирован случайный пароль."
    TS_PASSWORD=$(openssl rand -base64 12)
    print_message "Сгенерированный пароль: $TS_PASSWORD"
fi

print_message "Начинаем установку TeamSpeak сервера..."

# 1. Создание пользователя teamspeak
print_message "Создание пользователя teamspeak..."
if id "teamspeak" &>/dev/null; then
    print_warning "Пользователь teamspeak уже существует. Пропускаем создание."
else
    sudo useradd -mrd /opt/teamspeak teamspeak -s "$(which bash)"
    if [ $? -eq 0 ]; then
        print_message "Пользователь teamspeak успешно создан"
    else
        print_error "Ошибка при создании пользователя teamspeak"
        exit 1
    fi
fi

# 2. Установка необходимых библиотек
print_message "Установка bzip2..."
sudo apt update
sudo apt install bzip2 wget -y
if [ $? -eq 0 ]; then
    print_message "bzip2 успешно установлен"
else
    print_error "Ошибка при установке bzip2"
    exit 1
fi

# 3. Скачивание и установка TeamSpeak сервера
print_message "Скачивание TeamSpeak сервера..."
sudo -u teamspeak bash << 'EOF'
cd /opt/teamspeak
wget https://files.teamspeak-services.com/releases/server/3.13.7/teamspeak3-server_linux_amd64-3.13.7.tar.bz2 -O teamspeak-server.tar.bz2
if [ $? -eq 0 ]; then
    echo "Архив успешно скачан"
else
    echo "Ошибка при скачивании архива"
    exit 1
fi

# Распаковка архива
echo "Распаковка архива..."
tar xvfj teamspeak-server.tar.bz2 --strip-components 1
if [ $? -eq 0 ]; then
    echo "Архив успешно распакован"
else
    echo "Ошибка при распаковке архива"
    exit 1
fi

# Удаление архива
rm teamspeak-server.tar.bz2

# Принятие лицензионного соглашения
touch ~/.ts3server_license_accepted
echo "Лицензионное соглашение принято"
EOF

if [ $? -ne 0 ]; then
    print_error "Ошибка при установке TeamSpeak сервера"
    exit 1
fi

# 4. Создание systemd сервиса
print_message "Создание systemd сервиса..."
cat > /etc/systemd/system/teamspeak.service << 'EOF'
[Unit]
Description=TeamSpeak 3 Server
After=network.target

[Service]
User=teamspeak
Group=teamspeak
WorkingDirectory=/opt/teamspeak
ExecStart=/opt/teamspeak/ts3server_startscript.sh start
ExecStop=/opt/teamspeak/ts3server_startscript.sh stop
ExecReload=/opt/teamspeak/ts3server_startscript.sh restart
Restart=always
RestartSec=15
Type=forking
PIDFile=/opt/teamspeak/ts3server.pid

[Install]
WantedBy=multi-user.target
EOF

if [ $? -eq 0 ]; then
    print_message "Сервис успешно создан"
else
    print_error "Ошибка при создании сервиса"
    exit 1
fi

# 5. Применение изменений systemd
print_message "Применение изменений systemd..."
sudo systemctl daemon-reload
if [ $? -eq 0 ]; then
    print_message "Systemd перезагружен"
else
    print_error "Ошибка при перезагрузке systemd"
    exit 1
fi

# 6. Установка пароля администратора
print_message "Установка пароля администратора..."
sudo systemctl stop teamspeak 2>/dev/null

sudo -u teamspeak bash << EOF
cd /opt/teamspeak
./ts3server_startscript.sh start serveradmin_password=$TS_PASSWORD
sleep 5
./ts3server_startscript.sh stop
EOF

if [ $? -eq 0 ]; then
    print_message "Пароль администратора успешно установлен"
else
    print_warning "Возможны проблемы при установке пароля"
fi

# 7. Запуск сервиса
print_message "Запуск TeamSpeak сервера..."
sudo systemctl start teamspeak
sleep 3

# 8. Проверка статуса
print_message "Проверка статуса сервиса..."
sudo systemctl status teamspeak --no-pager

# 9. Включение автозапуска
print_message "Включение автозапуска сервера..."
sudo systemctl enable teamspeak
if [ $? -eq 0 ]; then
    print_message "Автозапуск включен"
else
    print_warning "Ошибка при включении автозапуска"
fi

# 10. Получение токена
print_message "Поиск токена администратора..."
TOKEN=$(grep -i token /opt/teamspeak/logs/* 2>/dev/null | grep -o "token=[a-zA-Z0-9]*" | cut -d'=' -f2)

echo "======================================================"
echo -e "${GREEN}Установка TeamSpeak сервера завершена!${NC}"
echo "======================================================"
echo -e "${YELLOW}Важная информация:${NC}"
echo "Директория установки: /opt/teamspeak"
echo "Пользователь: teamspeak"
echo "Пароль администратора: $TS_PASSWORD"
if [ ! -z "$TOKEN" ]; then
    echo -e "Токен администратора: ${GREEN}$TOKEN${NC}"
else
    echo -e "${YELLOW}Токен не найден. Проверьте логи:${NC}"
    echo "sudo grep -i token /opt/teamspeak/logs/*"
fi
echo "======================================================"
echo -e "${GREEN}Команды для управления сервером:${NC}"
echo "sudo systemctl status teamspeak    # Проверка статуса"
echo "sudo systemctl stop teamspeak       # Остановка сервера"
echo "sudo systemctl start teamspeak      # Запуск сервера"
echo "sudo systemctl restart teamspeak    # Перезапуск сервера"
echo "sudo systemctl disable teamspeak    # Отключение автозапуска"
echo "======================================================"

# Проверка доступности сервера
sleep 2
if ss -tlnp | grep -q :9987; then
    print_message "Сервер успешно запущен и слушает порт 9987"
else
    print_warning "Сервер возможно не запущен. Проверьте логи:"
    print_warning "sudo journalctl -u teamspeak -n 50"
fi