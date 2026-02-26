#!/bin/sh
BRANCH="${BRANCH:-main}"

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
UI_PATH="$SCRIPT_DIR/lib/ui.sh"
UI_DOWNLOADED=0
cleanup_ui_library() {
    if [ "${UI_DOWNLOADED:-0}" -eq 1 ]; then
        local cleanup_msg="${MSG_CLEANUP_UI:-Cleaning UI library...}"
        if command -v show_progress >/dev/null 2>&1; then
            show_progress "$cleanup_msg"
        else
            echo "$cleanup_msg"
        fi
        rm -f -- "$UI_PATH"
        rmdir -- "$SCRIPT_DIR/lib" 2>/dev/null || true
    fi
}
ensure_ui_library() {
    if [ -f "$UI_PATH" ]; then
        . "$UI_PATH"
        return 0
    fi

    mkdir -p "$SCRIPT_DIR/lib" 2>/dev/null
    ui_url="https://raw.githubusercontent.com/jaymz665/luci-app-singbox-ui/$BRANCH/other/scripts/lib/ui.sh"
    if command -v wget >/dev/null 2>&1; then
        wget -O "$UI_PATH" "$ui_url" || return 1
    elif command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$UI_PATH" "$ui_url" || return 1
    else
        echo "Missing UI library and downloader (wget/curl)" >&2
        return 1
    fi

    UI_DOWNLOADED=1
    . "$UI_PATH"
}

ensure_ui_library || {
    echo "Missing UI library: $UI_PATH" >&2
    exit 1
}
trap cleanup_ui_library EXIT HUP INT TERM

# Функция для определения пакетного менеджера
detect_package_manager() {
    if command -v apk >/dev/null 2>&1; then
        echo "apk"
    elif command -v opkg >/dev/null 2>&1; then
        echo "opkg"
    else
        echo "unknown"
    fi
}

# Функция установки пакета
install_package() {
    local pkg="$1"
    local pm=$(detect_package_manager)
    
    case "$pm" in
        apk)
            apk add --no-cache "$pkg" 2>/dev/null || apk add "$pkg"
            ;;
        opkg)
            opkg update && opkg install "$pkg"
            ;;
        *)
            show_error "Неизвестный пакетный менеджер"
            return 1
            ;;
    esac
}

# Функция установки локального ipk файла
install_ipk_file() {
    local file="$1"
    local pm=$(detect_package_manager)
    
    case "$pm" в
        apk)
            # Конвертируем ipk в apk? Нет, просто распаковываем вручную
            show_progress "Распаковка ipk файла для apk..."
            local tmp_dir="/tmp/ipk_extract"
            mkdir -p "$tmp_dir"
            cd "$tmp_dir"
            
            # Распаковываем ipk (это архив ar)
            ar -x "$file"
            
            # Распаковываем data.tar.gz
            if [ -f data.tar.gz ]; then
                tar -xzf data.tar.gz -C /
            elif [ -f data.tar.xz ]; then
                tar -xJf data.tar.xz -C /
            fi
            
            cd /
            rm -rf "$tmp_dir"
            ;;
        opkg)
            opkg install "$file"
            ;;
    esac
}

# Инициализация языка / Language initialization
init_language() {
    local script_name="install.sh"

    if [ -z "$LANG" ]; then
        while true; do
            show_message "Выберите язык / Select language [1/2]:"
            show_message "1. Русский (Russian)"
            show_message "2. English (Английский)"
            read_input " Ваш выбор / Your choice [1/2]: " LANG
            case "$LANG" in
                1|2)
                    break
                    ;;
                *)
                    show_error "Неверный выбор / Invalid choice"
                    ;;
            esac
        done
    fi

    case ${LANG:-2} in
    1)
        MSG_INSTALL_TITLE="Запуск! ($script_name)"
        MSG_COMPLETE="Выполнено! ($script_name)"
        MSG_FINISHED="Все инструкции выполнены!"
        MSG_INSTALL="Переход к установочному скрипту..."
        MSG_CLEANUP_UI="Очистка UI библиотеки..."
        MSG_CLEANUP="Очистка файлов..."
        MSG_CLEANUP_DONE="Файлы удалены!"
        MSG_WAITING="Ожидание %d сек"
        MSG_PM_DETECTED="Обнаружен пакетный менеджер: %s"
        ;;
    *)
        MSG_INSTALL_TITLE="Starting! ($script_name)"
        MSG_COMPLETE="Done! ($script_name)"
        MSG_FINISHED="All instructions completed!"
        MSG_INSTALL="Transition to the installation script..."
        MSG_CLEANUP_UI="Cleaning UI library..."
        MSG_CLEANUP="Cleaning files..."
        MSG_CLEANUP_DONE="Files deleted!"
        MSG_WAITING="Waiting %d seconds"
        MSG_PM_DETECTED="Detected package manager: %s"
        ;;
esac
}

# Ожидание / Waiting
waiting() {
    local interval="${1:-30}"
    show_progress "$(printf "$MSG_WAITING" "$interval")"
    sleep "$interval"
}

# Установка зависимостей
install_dependencies() {
    local pm=$(detect_package_manager)
    show_progress "$(printf "$MSG_PM_DETECTED" "$pm")"
    
    case "$pm" in
        apk)
            apk update
            install_package "sing-box"
            install_package "curl"
            install_package "jq"
            install_package "coreutils-base64"
            install_package "luci-compat"  # может не быть в apk, но попробуем
            install_package "luci-lib-json"
            ;;
        opkg)
            opkg update
            install_package "sing-box"
            install_package "curl"
            install_package "jq"
            install_package "coreutils-base64"
            install_package "luci-compat"
            install_package "luci-lib-json"
            ;;
    esac
}

# Установка / Install
install() {
    show_warning "$MSG_INSTALL"
    
    # Устанавливаем зависимости
    install_dependencies
    
    # Скачиваем нужные скрипты
    wget -O /root/install-singbox+singbox-ui.sh https://raw.githubusercontent.com/jaymz665/luci-app-singbox-ui/$BRANCH/other/scripts/install-singbox+singbox-ui.sh &&
    chmod 0755 /root/install-singbox+singbox-ui.sh &&
    
    # Скачиваем сам пакет luci-app-singbox-ui
    mkdir -p /tmp/singbox_install
    cd /tmp/singbox_install
    
    # Определяем архитектуру для скачивания правильного пакета
    ARCH=$(uname -m)
    case "$ARCH" in
        mips|mipsel)  PKG_ARCH="mips_24kc" ;;
        aarch64)      PKG_ARCH="aarch64_cortex-a53" ;;
        x86_64)       PKG_ARCH="x86_64" ;;
        *)            PKG_ARCH="all" ;;
    esac
    
    # Пробуем скачать пакет
    wget https://github.com/jaymz665/luci-app-singbox-ui/releases/download/v1.4.0/luci-app-singbox-ui_all.ipk -O luci-app-singbox-ui.ipk
    
    # Устанавливаем пакет
    install_ipk_file "/tmp/singbox_install/luci-app-singbox-ui.ipk"
    
    # Копируем файлы вручную на всякий случай
    if [ -d "/tmp/singbox_install/usr" ]; then
        cp -r /tmp/singbox_install/usr/* /usr/ 2>/dev/null
    fi
    
    cd /
    
    # Перезапускаем веб-сервер
    /etc/init.d/uhttpd restart
    
    LANG="$LANG" BRANCH="$BRANCH" sh /root/install-singbox+singbox-ui.sh
}

# Очистка файлов / Cleanup
cleanup() {
    show_progress "$MSG_CLEANUP"
    rm -rf /tmp/singbox_install 2>/dev/null
    rm -- "$0"
    show_success "$MSG_CLEANUP_DONE"
}

# Завершение скрипта / Complete script
complete_script() {
    show_success "$MSG_COMPLETE"
    cleanup
}

# ======== Основной код / Main code ========

run_steps_with_separator \
    "::${BRANCH}" \
    init_language

run_steps_with_separator \
    "::$MSG_INSTALL_TITLE" \
    install \
    complete_script \
    "::$MSG_FINISHED"
