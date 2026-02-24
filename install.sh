#!/bin/sh
set -eu

RAW_BASE_URL_DEFAULT="${RAW_BASE_URL_DEFAULT:-https://raw.githubusercontent.com/LoonyMan/DPI-Checker/master}"

INSTALL_DIR="$(pwd)"
SCRIPT_NAME="dpi-checker.sh"
ENV_NAME="dpi-checker.env"
CRON_MARKER="# DPI Checker"

LANG_CODE="en"

DEFAULT_OUT_PREFIX="dpi_checker_test_"
DEFAULT_JSON_RETENTION_DAYS="12"
DEFAULT_LOG_STDOUT="1"
DEFAULT_TELEGRAM_LIST_MAX_LINES="30"
DEFAULT_TELEGRAM_MESSAGE_MAX="3900"
DEFAULT_NETCHECK_URL="https://ya.ru"
DEFAULT_DPI_SUITE_URL="https://raw.githubusercontent.com/hyperion-cs/dpi-checkers/refs/heads/main/ru/tcp-16-20/suite.json"

TTY_IN="/dev/tty"
TTY_OUT="/dev/tty"
[ -r "$TTY_IN" ] || TTY_IN="/dev/stdin"
[ -w "$TTY_OUT" ] || TTY_OUT="/dev/stderr"

say() { printf '%s\n' "$*" > "$TTY_OUT"; }
ask() { printf '%s' "$*" > "$TTY_OUT"; }

read_line() {
  IFS= read -r REPLY < "$TTY_IN" || REPLY=""
  REPLY="$(printf '%s' "$REPLY" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
}

t() {
  case "$LANG_CODE" in
    ru)
      case "$1" in
        welcome) printf '=== DPI Checker Installer ===' ;;
        choose_lang) printf 'Выберите язык [ru/en] (по умолчанию: ru): ' ;;
        lang_set_ru) printf 'Выбран язык: Русский' ;;
        lang_set_en) printf 'Выбран язык: English' ;;
        install_dir) printf 'Каталог установки' ;;
        downloading) printf 'Загрузка' ;;
        download_fail) printf 'Ошибка загрузки файла' ;;
        download_ok) printf 'Файл загружен' ;;
        mode_prompt) printf 'Режим генерации ENV: [1] Упрощённый, [2] Полный (по умолчанию: 1): ' ;;
        mode_simple) printf 'Упрощённый режим' ;;
        mode_full) printf 'Полный режим' ;;
        tg_token) printf 'TELEGRAM_BOT_TOKEN (пусто = отключить Telegram): ' ;;
        tg_chat) printf 'TELEGRAM_CHAT_ID (если токен указан): ' ;;
        tg_lang) printf 'Язык сообщений Telegram [ru/en]' ;;
        notify_success) printf 'Уведомлять об успешных прогонах? [y/N]' ;;
        all_silent) printf 'Все Telegram-сообщения тихие (silent)? [y/N]' ;;
        retention) printf 'Хранить JSON (дней)' ;;
        env_written) printf 'ENV-файл создан' ;;
        show_env_path) printf 'Путь к ENV' ;;
        cron_ask) printf 'Добавить в автозапуск (cron)? [Y/n]' ;;
        cron_time) printf 'Время запуска (HH:MM, локальное время роутера)' ;;
        cron_invalid) printf 'Неверный формат времени. Использую 06:00' ;;
        cron_added) printf 'Cron-задача добавлена/обновлена' ;;
        cron_restart_ok) printf 'Cron перезапущен' ;;
        cron_restart_skip) printf 'Не удалось перезапустить cron автоматически' ;;
        done) printf 'Установка завершена' ;;
        next_run) printf 'Ручной запуск' ;;
        auto_download) printf 'Автоматически скачиваю основной скрипт dpi-checker.sh из GitHub...' ;;
        *) printf '%s' "$1" ;;
      esac
      ;;
    *)
      case "$1" in
        welcome) printf '=== DPI Checker Installer ===' ;;
        choose_lang) printf 'Choose language [en/ru] (default: en): ' ;;
        lang_set_ru) printf 'Language selected: Russian' ;;
        lang_set_en) printf 'Language selected: English' ;;
        install_dir) printf 'Install directory' ;;
        downloading) printf 'Downloading' ;;
        download_fail) printf 'Failed to download file' ;;
        download_ok) printf 'File downloaded' ;;
        mode_prompt) printf 'ENV generation mode: [1] Simple, [2] Full (default: 1): ' ;;
        mode_simple) printf 'Simple mode' ;;
        mode_full) printf 'Full mode' ;;
        tg_token) printf 'TELEGRAM_BOT_TOKEN (empty = disable Telegram): ' ;;
        tg_chat) printf 'TELEGRAM_CHAT_ID (if token is set): ' ;;
        tg_lang) printf 'Telegram message language [en/ru]' ;;
        notify_success) printf 'Notify on successful runs? [y/N]' ;;
        all_silent) printf 'Make all Telegram messages silent? [y/N]' ;;
        retention) printf 'Keep JSON files (days)' ;;
        env_written) printf 'ENV file created' ;;
        show_env_path) printf 'ENV path' ;;
        cron_ask) printf 'Add cron autostart? [Y/n]' ;;
        cron_time) printf 'Run time (HH:MM, router local time)' ;;
        cron_invalid) printf 'Invalid time format. Using 06:00' ;;
        cron_added) printf 'Cron entry added/updated' ;;
        cron_restart_ok) printf 'Cron restarted' ;;
        cron_restart_skip) printf 'Could not restart cron automatically' ;;
        done) printf 'Installation completed' ;;
        next_run) printf 'Manual run' ;;
        auto_download) printf 'Automatically downloading main script dpi-checker.sh from GitHub...' ;;
        *) printf '%s' "$1" ;;
      esac
      ;;
  esac
}

yn_to_01() {
  case "$1" in
    y|Y|yes|YES|Yes|д|Д|да|Да|ДА) printf '1' ;;
    *) printf '0' ;;
  esac
}

pick_lang() {
  local ans
  ask "$(t choose_lang)"
  read_line
  ans="$REPLY"

  case "$ans" in
    ru|RU|Ru|rU) LANG_CODE="ru" ;;
    en|EN|En|eN|"") LANG_CODE="en" ;;
    *) LANG_CODE="en" ;;
  esac

  if [ "$LANG_CODE" = "ru" ]; then
    say "$(t lang_set_ru)"
  else
    say "$(t lang_set_en)"
  fi
}

download_file() {
  local url="$1"
  local dst="$2"

  if command -v wget >/dev/null 2>&1; then
    wget -q -O "$dst" "$url" && return 0
  fi
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$dst" "$url" && return 0
  fi
  return 1
}

prompt_default() {
  local p="$1" d="$2" v
  ask "$p [$d]: "
  read_line
  v="$REPLY"
  [ -z "$v" ] && v="$d"
  printf '%s' "$v"
}

prompt_optional() {
  local p="$1"
  ask "$p"
  read_line
  printf '%s' "$REPLY"
}

ensure_dirs() {
  mkdir -p "$INSTALL_DIR/results" "$INSTALL_DIR/tmp"
}

download_main_script() {
  local url_main script_path

  url_main="${RAW_BASE_URL_DEFAULT%/}/$SCRIPT_NAME"
  script_path="$INSTALL_DIR/$SCRIPT_NAME"

  say "$(t auto_download)"
  say "$(t downloading): $url_main"

  if ! download_file "$url_main" "$script_path"; then
    say "$(t download_fail): $url_main"
    exit 1
  fi

  chmod +x "$script_path" 2>/dev/null || true
  say "$(t download_ok): $script_path"
}

write_env_simple() {
  local env_path="$1"
  local tg_token tg_chat tg_lang notify_success all_silent
  local default_log_file

  default_log_file="$INSTALL_DIR/dpi-checker.log"

  tg_token="$(prompt_optional "$(t tg_token)")"
  tg_chat=""
  if [ -n "$tg_token" ]; then
    tg_chat="$(prompt_optional "$(t tg_chat)")"
  fi

  tg_lang="$(prompt_default "$(t tg_lang)" "$LANG_CODE")"

  ask "$(t notify_success) "
  read_line
  notify_success="$(yn_to_01 "$REPLY")"

  ask "$(t all_silent) "
  read_line
  all_silent="$(yn_to_01 "$REPLY")"

  cat > "$env_path" <<EOF
export TELEGRAM_BOT_TOKEN="$tg_token"
export TELEGRAM_CHAT_ID="$tg_chat"

export OUT_DIR="$INSTALL_DIR/results"
export OUT_PREFIX="$DEFAULT_OUT_PREFIX"
export TMP_BASE_DIR="$INSTALL_DIR/tmp"

export TG_LANG="$tg_lang"
export JSON_RETENTION_DAYS="$DEFAULT_JSON_RETENTION_DAYS"

export TG_NOTIFY_SUCCESS="$notify_success"
export TG_ALL_SILENT="$all_silent"

export LOG_FILE="$default_log_file"
export LOG_STDOUT="$DEFAULT_LOG_STDOUT"

export TELEGRAM_LIST_MAX_LINES="$DEFAULT_TELEGRAM_LIST_MAX_LINES"
export TELEGRAM_MESSAGE_MAX="$DEFAULT_TELEGRAM_MESSAGE_MAX"

export NETCHECK_URL="$DEFAULT_NETCHECK_URL"
export DPI_SUITE_URL="$DEFAULT_DPI_SUITE_URL"
EOF
}

write_env_full() {
  local env_path="$1"
  local tg_token tg_chat tg_lang notify_success all_silent retention
  local default_log_file

  default_log_file="$INSTALL_DIR/dpi-checker.log"

  tg_token="$(prompt_optional "$(t tg_token)")"
  tg_chat=""
  if [ -n "$tg_token" ]; then
    tg_chat="$(prompt_optional "$(t tg_chat)")"
  fi

  tg_lang="$(prompt_default "$(t tg_lang)" "$LANG_CODE")"

  ask "$(t notify_success) "
  read_line
  notify_success="$(yn_to_01 "$REPLY")"

  ask "$(t all_silent) "
  read_line
  all_silent="$(yn_to_01 "$REPLY")"

  retention="$(prompt_default "$(t retention)" "$DEFAULT_JSON_RETENTION_DAYS")"

  cat > "$env_path" <<EOF
export TELEGRAM_BOT_TOKEN="$tg_token"
export TELEGRAM_CHAT_ID="$tg_chat"

export OUT_DIR="$INSTALL_DIR/results"
export OUT_PREFIX="$DEFAULT_OUT_PREFIX"
export TMP_BASE_DIR="$INSTALL_DIR/tmp"

export LOG_FILE="$default_log_file"
export LOG_STDOUT="$DEFAULT_LOG_STDOUT"

export TG_LANG="$tg_lang"
export JSON_RETENTION_DAYS="$retention"

export TG_NOTIFY_SUCCESS="$notify_success"
export TG_ALL_SILENT="$all_silent"

export TELEGRAM_LIST_MAX_LINES="$DEFAULT_TELEGRAM_LIST_MAX_LINES"
export TELEGRAM_MESSAGE_MAX="$DEFAULT_TELEGRAM_MESSAGE_MAX"

export NETCHECK_URL="$DEFAULT_NETCHECK_URL"
export DPI_SUITE_URL="$DEFAULT_DPI_SUITE_URL"
EOF
}

shell_quote() {
  printf "'%s'" "$(printf "%s" "$1" | sed "s/'/'\\\\''/g")"
}

setup_cron() {
  local env_path="$1" script_path="$2"
  local ans run_hm hh mm cron_file cron_cmd dir_q env_q script_q tmpf

  ask "$(t cron_ask) "
  read_line
  ans="$REPLY"
  case "$ans" in
    n|N|no|NO|No|н|Н|нет|Нет|НЕТ) return 0 ;;
  esac

  run_hm="$(prompt_default "$(t cron_time)" "06:00")"
  case "$run_hm" in
    [0-1][0-9]:[0-5][0-9]|2[0-3]:[0-5][0-9]) ;;
    *)
      say "$(t cron_invalid)"
      run_hm="06:00"
      ;;
  esac

  hh="${run_hm%:*}"
  mm="${run_hm#*:}"

  cron_file="/etc/crontabs/root"
  [ -f "$cron_file" ] || touch "$cron_file" 2>/dev/null || true

  dir_q="$(shell_quote "$INSTALL_DIR")"
  env_q="$(shell_quote "$env_path")"
  script_q="$(shell_quote "$script_path")"

  cron_cmd="$mm $hh * * * cd $dir_q && . $env_q && $script_q >/dev/null 2>&1 $CRON_MARKER"

  tmpf="$INSTALL_DIR/.dpi-checker.cron.tmp"
  { grep -v "DPI Checker" "$cron_file" 2>/dev/null || true; printf '%s\n' "$cron_cmd"; } > "$tmpf"
  cat "$tmpf" > "$cron_file"
  rm -f "$tmpf"

  say "$(t cron_added)"

  if [ -x /etc/init.d/cron ]; then
    if /etc/init.d/cron restart >/dev/null 2>&1; then
      say "$(t cron_restart_ok)"
    else
      say "$(t cron_restart_skip)"
    fi
  else
    say "$(t cron_restart_skip)"
  fi
}

main() {
  local mode env_path script_path

  say "$(t welcome)"
  pick_lang
  say "$(t install_dir): $INSTALL_DIR"

  ensure_dirs
  download_main_script

  script_path="$INSTALL_DIR/$SCRIPT_NAME"
  if [ ! -f "$script_path" ]; then
    say "ERROR: $SCRIPT_NAME not found in $INSTALL_DIR"
    exit 1
  fi

  ask "$(t mode_prompt)"
  read_line
  mode="$REPLY"
  case "$mode" in
    2) say "$(t mode_full)" ;;
    *) mode="1"; say "$(t mode_simple)" ;;
  esac

  env_path="$INSTALL_DIR/$ENV_NAME"
  if [ "$mode" = "2" ]; then
    write_env_full "$env_path"
  else
    write_env_simple "$env_path"
  fi

  say "$(t env_written)"
  say "$(t show_env_path): $env_path"

  setup_cron "$env_path" "./$SCRIPT_NAME"

  say "$(t done)"
  say "$(t next_run):"
  printf '  cd %s && . ./%s && ./%s\n' "$INSTALL_DIR" "$ENV_NAME" "$SCRIPT_NAME" > "$TTY_OUT"
}

main "$@"