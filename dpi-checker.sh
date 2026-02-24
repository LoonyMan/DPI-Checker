#!/bin/sh
set -eu

TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

OUT_DIR="${OUT_DIR:-/tmp}"
OUT_PREFIX="${OUT_PREFIX:-dpi_checker_test_}"
TMP_BASE_DIR="${TMP_BASE_DIR:-${OUT_DIR%/}/tmp}"

LOG_FILE="${LOG_FILE:-/var/log/dpi-checker.log}"
LOG_STDOUT="${LOG_STDOUT:-1}"

PARALLEL="${PARALLEL:-4}"
CURL_CONNECT_TIMEOUT="${CURL_CONNECT_TIMEOUT:-6}"
CURL_MAX_TIME="${CURL_MAX_TIME:-12}"
CURL_SPEED_TIME="${CURL_SPEED_TIME:-6}"
CURL_SPEED_LIMIT="${CURL_SPEED_LIMIT:-1}"
CURL_RANGE="${CURL_RANGE:-0-65535}"
CURL_RETRIES="${CURL_RETRIES:-2}"
CURL_RETRY_DELAY="${CURL_RETRY_DELAY:-1}"

TELEGRAM_LIST_MAX_LINES="${TELEGRAM_LIST_MAX_LINES:-30}"
TELEGRAM_MESSAGE_MAX="${TELEGRAM_MESSAGE_MAX:-3900}"
TG_LANG="${TG_LANG:-en}"                    # en | ru
JSON_RETENTION_DAYS="${JSON_RETENTION_DAYS:-12}"

TG_NOTIFY_SUCCESS="${TG_NOTIFY_SUCCESS:-1}" # 1=notify success runs, 0=only degraded/errors
TG_ALL_SILENT="${TG_ALL_SILENT:-0}"         # 1=all TG messages silent

USER_AGENT="${USER_AGENT:-Mozilla/5.0 (Windows NT 10.0; Win64; x64) curl/8.0}"
NETCHECK_URL="${NETCHECK_URL:-https://ya.ru}"
DPI_SUITE_URL="${DPI_SUITE_URL:-https://raw.githubusercontent.com/hyperion-cs/dpi-checkers/refs/heads/main/ru/tcp-16-20/suite.json}"

STATIC_TEST_TARGETS='
gosuslugi.ru|https://gosuslugi.ru
esia.gosuslugi.ru|https://esia.gosuslugi.ru
lkfl2.nalog.ru|https://lkfl2.nalog.ru
nalog.ru|https://nalog.ru
rutube.ru|https://rutube.ru
facebook.com|https://facebook.com
ntc.party|https://ntc.party/
instagram.com|https://instagram.com
spankbang.com|https://ru.spankbang.com
nnmclub.to|https://nnmclub.to
epidemz.net.co|https://epidemz.net.co
rutor.info|https://rutor.info
sxyprn.net|https://sxyprn.net
rutracker.org|https://rutracker.org
openwrt.org|https://openwrt.org
pornhub.com|https://pornhub.com
updates.discord.com|https://updates.discord.com
kinozal.tv|https://kinozal.tv
discord.com|https://discord.com
filmix.my|https://filmix.my
cub.red|https://cub.red
play.google.com|https://play.google.com
x.com|https://x.com
flightradar24.com|https://flightradar24.com
'

DATE_LOCAL="$(date '+%Y-%m-%d %H:%M')"
TS_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
STAMP="$(date '+%Y%m%d_%H%M%S')"

mkdir -p "$OUT_DIR" 2>/dev/null || true
mkdir -p "$TMP_BASE_DIR" 2>/dev/null || true
OUT_JSON="${OUT_DIR%/}/${OUT_PREFIX}${STAMP}.json"

TMP_WORK="${TMP_BASE_DIR%/}/dpi_checker_${STAMP}"
mkdir -p "$TMP_WORK"

TMP_OK="$TMP_WORK/ok.txt"
TMP_FAIL="$TMP_WORK/fail.txt"
TMP_TARGETS="$TMP_WORK/targets.txt"
TMP_TOTAL="$TMP_WORK/total.txt"
TMP_AVAILABLE="$TMP_WORK/available.txt"
TMP_DPI_STATUS="$TMP_WORK/dpi_status.txt"
TMP_DPI_ACTIVE="$TMP_WORK/dpi_active.txt"

: > "$TMP_OK"
: > "$TMP_FAIL"
: > "$TMP_DPI_STATUS"
: > "$TMP_DPI_ACTIVE"

log_msg() {
  local level="$1"
  shift
  local ts line msg prefix rest
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  msg="$*"
  line="${ts} | ${level} | ${msg}"

  if [ -n "$LOG_FILE" ]; then
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    printf '%s\n' "$line" >> "$LOG_FILE" 2>/dev/null || true
  fi

  if [ "$LOG_STDOUT" = "1" ]; then
    case "$msg" in
      FAIL\ *)
        prefix="${ts} | ${level} | "
        rest="${msg#FAIL }"
        printf '%s\033[0;31mFAIL\033[0m %s\n' "$prefix" "$rest" >&2
        ;;
      *)
        printf '%s\n' "$line" >&2
        ;;
    esac
  fi
}

log_info() { log_msg INFO "$*"; }
log_warn() { log_msg WARN "$*"; }
log_err()  { log_msg ERROR "$*"; }

have() { command -v "$1" >/dev/null 2>&1; }

cleanup() { rm -rf "$TMP_WORK" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

normalize_lang() {
  case "$TG_LANG" in
    ru|RU|Ru|rU) TG_LANG="ru" ;;
    *) TG_LANG="en" ;;
  esac
}

normalize_bool_01() {
  case "$1" in
    1|true|TRUE|True|yes|YES|on|ON) printf '1\n' ;;
    *) printf '0\n' ;;
  esac
}

loc() {
  case "$TG_LANG" in
    ru)
      case "$1" in
        title_ok)            printf '✅ DPI Checker: прогон завершён\n' ;;
        title_bad)           printf '🚨 DPI Checker: деградация стратегии\n' ;;
        no_prev)             printf '🆕 Предыдущего результата нет (первый прогон)\n' ;;
        result)              printf '📊 Результат' ;;
        was)                 printf '📈 Было' ;;
        failed_total)        printf '❌ Всего не прошло' ;;
        dpi_statuses)        printf '⚙️ DPI' ;;
        dpi_multi_active)    printf '⚠️ Несколько DPI-обходчиков активны' ;;
        json)                printf '📋 JSON' ;;
        list_new_failed)     printf '🆕 Новые провалившиеся' ;;
        list_recovered)      printf '✅ Новые успешные' ;;
        no_changes)          printf 'ℹ️ Изменений по доменам нет\n' ;;
        net_fail)            printf 'No internet (ya.ru check failed)\n' ;;
        dpi_none)            printf 'нет' ;;
        dpi_status_on)       printf 'вкл' ;;
        dpi_status_off)      printf 'выкл' ;;
        dpi_status_starting) printf 'включается' ;;
        platform_warn)       printf 'OpenWRT version is not 24/25. DPI path detection heuristics may be incomplete.' ;;
        *)                   printf '%s\n' "$1" ;;
      esac
      ;;
    *)
      case "$1" in
        title_ok)            printf '✅ DPI Checker: run completed\n' ;;
        title_bad)           printf '🚨 DPI Checker: strategy degraded\n' ;;
        no_prev)             printf '🆕 No previous result (first run)\n' ;;
        result)              printf '📊 Result' ;;
        was)                 printf '📈 Was' ;;
        failed_total)        printf '❌ Failed total' ;;
        dpi_statuses)        printf '⚙️ DPI' ;;
        dpi_multi_active)    printf '⚠️ Multiple DPI bypass tools active' ;;
        json)                printf '📋 JSON' ;;
        list_new_failed)     printf '🆕 Newly failed' ;;
        list_recovered)      printf '✅ Newly recovered' ;;
        no_changes)          printf 'ℹ️ No domain changes\n' ;;
        net_fail)            printf 'No internet (ya.ru check failed)\n' ;;
        dpi_none)            printf 'none' ;;
        dpi_status_on)       printf 'on' ;;
        dpi_status_off)      printf 'off' ;;
        dpi_status_starting) printf 'starting' ;;
        platform_warn)       printf 'OpenWRT version is not 24/25. DPI path detection heuristics may be incomplete.' ;;
        *)                   printf '%s\n' "$1" ;;
      esac
      ;;
  esac
}

status_to_localized() {
  case "$1" in
    on) printf '%s' "$(loc dpi_status_on)" ;;
    starting) printf '%s' "$(loc dpi_status_starting)" ;;
    off) printf '%s' "$(loc dpi_status_off)" ;;
    *) printf '%s' "$1" ;;
  esac
}

require_tools() {
  for t in curl jq awk sed grep wc tr date head sort sleep find rm cat dirname ls cut; do
    if ! have "$t"; then
      log_err "required tool missing: $t"
      echo "ERROR: required tool missing: $t" >&2
      exit 2
    fi
  done
}

check_openwrt_version_hint() {
  local rel ver
  rel="/etc/openwrt_release"
  [ -f "$rel" ] || return 0

  ver="$(grep -E "^DISTRIB_RELEASE=" "$rel" 2>/dev/null | head -n1 | cut -d"'" -f2 || true)"
  [ -z "$ver" ] && return 0

  case "$ver" in
    24.*|25.*)
      log_info "OpenWRT release detected: $ver"
      ;;
    *)
      log_warn "$(loc platform_warn) detected=$ver"
      ;;
  esac
}

prune_old_jsons() {
  local days list count file
  days="$JSON_RETENTION_DAYS"

  case "$days" in
    ''|*[!0-9]*)
      log_warn "Invalid JSON_RETENTION_DAYS='$days' (must be integer), skip cleanup"
      return 0
      ;;
  esac

  list="$TMP_WORK/prune_list.txt"
  : > "$list"

  find "$OUT_DIR" -maxdepth 1 -type f -name "${OUT_PREFIX}*.json" -mtime +"$days" -print > "$list" 2>/dev/null || true

  count=0
  if [ -s "$list" ]; then
    while IFS= read -r file; do
      [ -n "$file" ] || continue
      rm -f -- "$file" 2>/dev/null || true
      count=$((count + 1))
    done < "$list"
  fi

  log_info "Pruned old JSON files: ${count} (older than ${days}d)"
}

internet_sanity_check() {
  curl -sL \
    --connect-timeout 5 \
    --max-time 10 \
    --speed-time 5 \
    --speed-limit 1 \
    --range 0-65535 \
    -A "$USER_AGENT" \
    -o /dev/null \
    "$NETCHECK_URL" >/dev/null 2>&1
}

find_first_existing_path_csv() {
  local csv="$1" p
  for p in $(printf '%s' "$csv" | tr ',' ' '); do
    [ -n "$p" ] || continue
    if [ -e "$p" ]; then
      printf '%s\n' "$p"
      return 0
    fi
  done
  return 1
}

find_first_init_script_csv() {
  local csv="$1" n p
  for n in $(printf '%s' "$csv" | tr ',' ' '); do
    [ -n "$n" ] || continue
    p="/etc/init.d/$n"
    if [ -x "$p" ]; then
      printf '%s\n' "$p"
      return 0
    fi
  done
  return 1
}

find_first_command_csv() {
  local csv="$1" n c
  for n in $(printf '%s' "$csv" | tr ',' ' '); do
    [ -n "$n" ] || continue
    c="$(command -v "$n" 2>/dev/null || true)"
    if [ -n "$c" ]; then
      printf '%s\n' "$c"
      return 0
    fi
  done
  return 1
}

proc_running_csv() {
  local csv="$1" p
  if ! have pidof; then
    return 1
  fi

  for p in $(printf '%s' "$csv" | tr ',' ' '); do
    [ -n "$p" ] || continue
    if pidof "$p" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

service_status_key_by_init() {
  local init="$1" out rc low
  if [ ! -x "$init" ]; then
    printf 'off\n'
    return 0
  fi

  if out="$("$init" status 2>&1)"; then
    rc=0
  else
    rc=$?
  fi

  low="$(printf '%s' "$out" | tr '[:upper:]' '[:lower:]')"

  case "$low" in
    *starting*|*initializ*|*launching*|*progress*|*start\ pending*|*включает*|*запускает*)
      printf 'starting\n'
      return 0
      ;;
    *not\ running*|*stopped*|*inactive*|*dead*|*failed*|*disabled*|*не\ запущ*|*останов*)
      printf 'off\n'
      return 0
      ;;
    *running*|*active*|*started*|*работает*|*запущен*)
      printf 'on\n'
      return 0
      ;;
  esac

  if [ "$rc" -eq 0 ]; then
    printf 'on\n'
  else
    printf 'off\n'
  fi
}

probe_dpi_tool() {
  local name="$1"
  local init_names_csv="$2"
  local path_candidates_csv="$3"
  local cmd_names_csv="$4"
  local proc_names_csv="$5"

  local init_path install_path cmd_path status found_path installed
  init_path="$(find_first_init_script_csv "$init_names_csv" 2>/dev/null || true)"
  install_path="$(find_first_existing_path_csv "$path_candidates_csv" 2>/dev/null || true)"
  cmd_path="$(find_first_command_csv "$cmd_names_csv" 2>/dev/null || true)"

  status="off"

  if [ -n "$init_path" ]; then
    status="$(service_status_key_by_init "$init_path")"
  elif proc_running_csv "$proc_names_csv"; then
    status="on"
  fi

  installed=0
  found_path=""
  if [ -n "$install_path" ]; then
    installed=1
    found_path="$install_path"
  elif [ -n "$cmd_path" ]; then
    installed=1
    found_path="$cmd_path"
  elif [ -n "$init_path" ]; then
    installed=1
    found_path="$init_path"
  elif [ "$status" = "on" ] || [ "$status" = "starting" ]; then
    installed=1
    found_path="-"
  fi

  printf '%s|%s|%s|%s|%s\n' "$name" "$installed" "$status" "$found_path" "${init_path:-}" >> "$TMP_DPI_STATUS"
}

dpi_status_from_cache() {
  local name="$1"
  awk -F'|' -v n="$name" '$1==n {print $3; found=1; exit} END{if(!found) print "off"}' "$TMP_DPI_STATUS"
}

detect_zapret_status() {
  local s
  if [ -s "$TMP_DPI_STATUS" ]; then
    s="$(dpi_status_from_cache "zapret")"
  else
    s="off"
  fi
  status_to_localized "$s"
}

detect_strategy_string() {
  local s="" cfg=""
  for cfg in /opt/zapret/config /etc/zapret/config /usr/share/zapret/config /usr/local/share/zapret/config; do
    if [ -f "$cfg" ]; then
      . "$cfg" 2>/dev/null || true
      [ "${MODE:-}" != "" ] && s="$MODE"
      [ "${NFQWS_OPT:-}" != "" ] && s="${s:+$s }nfqws"
      [ "${TPWS_OPT:-}" != "" ] && s="${s:+$s }tpws"
      [ "${PKTWS_OPT:-}" != "" ] && s="${s:+$s }pktws"
      break
    fi
  done
  [ -z "$s" ] && s="current (unknown)"
  printf '%s\n' "$s"
}

dpi_status_summary_for_log() {
  local summary item name installed status path initp
  summary=""
  while IFS='|' read -r name installed status path initp; do
    [ -n "$name" ] || continue
    [ "$installed" = "1" ] || continue
    item="${name}=${status}"
    if [ -z "$summary" ]; then
      summary="$item"
    else
      summary="${summary}, ${item}"
    fi
  done < "$TMP_DPI_STATUS"

  [ -z "$summary" ] && summary="none detected"
  printf '%s\n' "$summary"
}

collect_dpi_runtime_status() {
  local active_count active_names summary name installed status path initp
  : > "$TMP_DPI_STATUS"
  : > "$TMP_DPI_ACTIVE"

  probe_dpi_tool \
    "zapret" \
    "zapret" \
    "/opt/zapret,/etc/zapret,/usr/share/zapret,/usr/local/share/zapret,/usr/lib/zapret" \
    "zapret" \
    "nfqws,tpws,pktws"

  probe_dpi_tool \
    "zapret2" \
    "zapret2" \
    "/opt/zapret2,/etc/zapret2,/usr/share/zapret2,/usr/local/share/zapret2,/usr/lib/zapret2" \
    "zapret2" \
    "zapret2"

  probe_dpi_tool \
    "youtubeUnblock" \
    "youtubeUnblock,youtubeunblock" \
    "/opt/youtubeUnblock,/etc/youtubeUnblock,/usr/share/youtubeUnblock,/usr/bin/youtubeUnblock,/usr/sbin/youtubeUnblock,/usr/bin/youtubeunblock,/usr/sbin/youtubeunblock" \
    "youtubeUnblock,youtubeunblock" \
    "youtubeUnblock,youtubeunblock"

  probe_dpi_tool \
    "goodbyedpi" \
    "goodbyedpi,goodbyeDPI,GoodByeDPI" \
    "/opt/goodbyedpi,/etc/goodbyedpi,/usr/share/goodbyedpi,/usr/bin/goodbyedpi,/usr/sbin/goodbyedpi,/usr/bin/GoodByeDPI,/usr/sbin/GoodByeDPI" \
    "goodbyedpi,goodbyeDPI,GoodByeDPI" \
    "goodbyedpi,goodbyeDPI,GoodByeDPI"

  while IFS='|' read -r name installed status path initp; do
    [ -n "$name" ] || continue
    case "$status" in
      on|starting) printf '%s\n' "$name" >> "$TMP_DPI_ACTIVE" ;;
    esac
  done < "$TMP_DPI_STATUS"

  summary="$(dpi_status_summary_for_log)"
  log_info "DPI status: $summary"

  active_count="$(wc -l < "$TMP_DPI_ACTIVE" | tr -d ' ')"
  if [ "$active_count" -gt 1 ]; then
    active_names="$(awk 'BEGIN{f=1} {if(!f) printf ", "; printf "%s",$0; f=0} END{if(f) printf "-"}' "$TMP_DPI_ACTIVE")"
    log_warn "Multiple DPI bypass tools active: $active_names"
  fi
}

dpi_status_summary_for_tg() {
  local summary item name installed status path initp
  summary=""
  while IFS='|' read -r name installed status path initp; do
    [ -n "$name" ] || continue
    [ "$installed" = "1" ] || continue
    item="${name}=$(status_to_localized "$status")"
    if [ -z "$summary" ]; then
      summary="$item"
    else
      summary="${summary}, ${item}"
    fi
  done < "$TMP_DPI_STATUS"
  [ -z "$summary" ] && summary="$(loc dpi_none)"
  printf '%s\n' "$summary"
}

dpi_active_count() {
  if [ -f "$TMP_DPI_ACTIVE" ]; then
    wc -l < "$TMP_DPI_ACTIVE" | tr -d ' '
  else
    printf '0\n'
  fi
}

dpi_active_list_csv() {
  if [ ! -s "$TMP_DPI_ACTIVE" ]; then
    printf '%s\n' "$(loc dpi_none)"
    return 0
  fi
  awk 'BEGIN{f=1} {if(!f) printf ", "; printf "%s",$0; f=0} END{printf "\n"}' "$TMP_DPI_ACTIVE"
}

append_all_dpi_targets_from_suite() {
  local out_file="$1"
  local tmp_json="$TMP_WORK/dpi_suite.json"
  local tmp_pairs="$TMP_WORK/dpi_pairs.txt"
  local suite_count

  if ! curl -fsSL \
      --connect-timeout "$CURL_CONNECT_TIMEOUT" \
      --max-time "$((CURL_MAX_TIME * 3))" \
      -o "$tmp_json" "$DPI_SUITE_URL" 2>/dev/null; then
    log_warn "DPI suite download failed: $DPI_SUITE_URL"
    return 1
  fi

  if ! jq -e . "$tmp_json" >/dev/null 2>&1; then
    log_warn "DPI suite invalid JSON: $DPI_SUITE_URL"
    return 1
  fi

  jq -r '
    .. | objects
    | select((.id? != null) and (.url? != null))
    | select((.id|type) == "string" and (.url|type) == "string")
    | select((.id|length) > 0 and (.url|length) > 0)
    | "\(.id)|\(.url)"
  ' "$tmp_json" 2>/dev/null > "$tmp_pairs" || true

  suite_count="$(wc -l < "$tmp_pairs" | tr -d ' ')"
  cat "$tmp_pairs" >> "$out_file"
  log_info "DPI suite targets loaded: ${suite_count}"
  return 0
}

build_target_list() {
  local raw="$TMP_WORK/targets_raw.txt"
  local total_count

  : > "$raw"

  printf "%s\n" "$STATIC_TEST_TARGETS" \
    | sed -e 's/#.*$//' \
          -e 's/^[[:space:]]*//;s/[[:space:]]*$//' \
          -e '/^$/d' >> "$raw"

  append_all_dpi_targets_from_suite "$raw" || true

  awk -F'|' '
    NF>=2 && $1 != "" && $2 != "" && !seen[$1]++ { print $1 "|" $2 }
  ' "$raw" > "$TMP_TARGETS"

  total_count="$(wc -l < "$TMP_TARGETS" | tr -d ' ')"
  log_info "Total targets after dedupe: ${total_count}"
}

curl_check_once() {
  local url="$1"
  curl -sL \
    --connect-timeout "$CURL_CONNECT_TIMEOUT" \
    --max-time "$CURL_MAX_TIME" \
    --speed-time "$CURL_SPEED_TIME" \
    --speed-limit "$CURL_SPEED_LIMIT" \
    --range "$CURL_RANGE" \
    -A "$USER_AGENT" \
    -o /dev/null \
    "$url" >/dev/null 2>&1
}

curl_check_with_retries() {
  local url="$1"
  local attempt=1

  while [ "$attempt" -le "$CURL_RETRIES" ]; do
    if curl_check_once "$url"; then
      return 0
    fi
    [ "$attempt" -lt "$CURL_RETRIES" ] && sleep "$CURL_RETRY_DELAY" || true
    attempt=$((attempt + 1))
  done

  return 1
}

check_target_bg() {
  local idx="$1"
  local total="$2"
  local label="$3"
  local url="$4"

  if curl_check_with_retries "$url"; then
    printf '%s\n' "$label" >> "$TMP_OK"
    log_info " OK  ${label} (${idx}/${total})"
  else
    printf '%s\n' "$label" >> "$TMP_FAIL"
    log_warn "FAIL ${label} (${idx}/${total})"
  fi
}

run_tests() {
  build_target_list

  local total idx running line label url
  total="$(awk -F'|' 'NF>=2{c++} END{print c+0}' "$TMP_TARGETS")"
  idx=0
  running=0

  if [ "$total" -le 0 ]; then
    log_err "Target list is empty"
    printf '0\n' > "$TMP_TOTAL"
    printf '0\n' > "$TMP_AVAILABLE"
    return 1
  fi

  log_info "Starting test: total=${total}, parallel=${PARALLEL}, retries=${CURL_RETRIES}, out=${OUT_JSON}"

  while IFS= read -r line; do
    [ -z "$line" ] && continue

    case "$line" in
      *'|'*)
        label="${line%%|*}"
        url="${line#*|}"
        ;;
      *)
        continue
        ;;
    esac

    [ -z "$label" ] && continue
    [ -z "$url" ] && continue

    idx=$((idx + 1))
    check_target_bg "$idx" "$total" "$label" "$url" &
    running=$((running + 1))

    if [ "$running" -ge "$PARALLEL" ]; then
      wait
      running=0
    fi
  done < "$TMP_TARGETS"

  [ "$running" -gt 0 ] && wait || true

  printf '%s\n' "$total" > "$TMP_TOTAL"
  printf '%s\n' "$(wc -l < "$TMP_OK" | tr -d ' ')" > "$TMP_AVAILABLE"

  log_info "Test finished: result $(cat "$TMP_AVAILABLE")/$(cat "$TMP_TOTAL")"
  return 0
}

latest_previous_json() {
  ls -1 "${OUT_DIR%/}/${OUT_PREFIX}"*.json 2>/dev/null | sort -r | head -n 1 || true
}

write_json() {
  local prev_avail="${1:-null}"
  local total available failed_json strategy zapret_status
  local dpi_active_count_val dpi_multi_warn_val dpi_summary

  total="$(cat "$TMP_TOTAL")"
  available="$(cat "$TMP_AVAILABLE")"
  strategy="$(detect_strategy_string)"
  zapret_status="$(detect_zapret_status)"

  if [ -s "$TMP_FAIL" ]; then
    failed_json="$(jq -R -s -c 'split("\n") | map(select(length>0))' < "$TMP_FAIL")"
  else
    failed_json="[]"
  fi

  dpi_active_count_val="$(dpi_active_count)"
  if [ "$dpi_active_count_val" -gt 1 ]; then
    dpi_multi_warn_val=true
  else
    dpi_multi_warn_val=false
  fi
  dpi_summary="$(dpi_status_summary_for_tg)"

  jq -n \
    --arg timestamp "$TS_UTC" \
    --arg strategy "$strategy" \
    --arg zapret_status "$zapret_status" \
    --arg dpi_summary "$dpi_summary" \
    --argjson dpi_active_count "$dpi_active_count_val" \
    --argjson dpi_multi_active "$dpi_multi_warn_val" \
    --argjson total_sites "$total" \
    --argjson available "$available" \
    --argjson previous_available "$prev_avail" \
    --argjson failed_sites "$failed_json" \
    '{
      timestamp: $timestamp,
      total_sites: $total_sites,
      available: $available,
      previous_available: $previous_available,
      failed_sites: $failed_sites,
      test_strategy: $strategy,
      zapret_status: $zapret_status,
      dpi_summary: $dpi_summary,
      dpi_active_count: $dpi_active_count,
      dpi_multi_active: $dpi_multi_active
    }' > "$OUT_JSON"
}

extract_prev_failed() {
  local prev_json="$1"
  local out_file="$2"

  : > "$out_file"
  [ -n "$prev_json" ] || return 0
  [ -f "$prev_json" ] || return 0

  jq -r '.failed_sites[]?' "$prev_json" 2>/dev/null | sed '/^$/d' > "$out_file" || true
}

set_diff() {
  local left="$1"
  local right="$2"
  local out="$3"
  local left_s="$TMP_WORK/left.sorted"
  local right_s="$TMP_WORK/right.sorted"

  : > "$out"
  [ -s "$left" ] || return 0

  sort -u "$left" > "$left_s"

  if [ ! -s "$right" ]; then
    cat "$left_s" > "$out"
    return 0
  fi

  sort -u "$right" > "$right_s"
  grep -Fvx -f "$right_s" "$left_s" > "$out" 2>/dev/null || true
}

telegram_send_message() {
  [ -n "$TELEGRAM_BOT_TOKEN" ] || return 0
  [ -n "$TELEGRAM_CHAT_ID" ] || return 0

  local msg="$1"
  local silent="${2:-0}"
  local disable="false"

  [ "$silent" = "1" ] && disable="true"

  if [ "${#msg}" -gt "$TELEGRAM_MESSAGE_MAX" ]; then
    msg="$(printf '%s\n%s' "$(echo "$msg" | head -c "$TELEGRAM_MESSAGE_MAX")" "… (truncated)")"
  fi

  curl -sS -o /dev/null \
    --connect-timeout 8 --max-time 20 \
    -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" \
    -d "disable_notification=${disable}" \
    --data-urlencode "text=${msg}" \
    -d "disable_web_page_preview=true" \
    >/dev/null 2>&1 || log_warn "Telegram sendMessage failed"
}

render_more_line() {
  local n="$1"
  if [ "$TG_LANG" = "ru" ]; then
    printf '… и ещё %s\n' "$n"
  else
    printf '… and %s more\n' "$n"
  fi
}

render_list_block() {
  local title="$1"
  local file="$2"
  local max_lines="$3"
  local count shown

  count=0
  [ -f "$file" ] && count="$(wc -l < "$file" | tr -d ' ')" || true
  [ "$count" -le 0 ] && return 0

  printf '\n%s (%s):\n' "$title" "$count"

  shown="$max_lines"
  [ "$count" -lt "$max_lines" ] && shown="$count"

  head -n "$shown" "$file" | sed 's/^/• /'

  if [ "$count" -gt "$shown" ]; then
    render_more_line "$((count - shown))"
  fi
}

send_completion_report() {
  local prev_json="$1"
  local prev_avail="$2"
  local degraded="$3"

  local total available failed_count silent delta sign json_name
  local dpi_summary dpi_multi_count dpi_multi_list
  local prev_fail_file="$TMP_WORK/prev_fail.txt"
  local recovered_file="$TMP_WORK/recovered.txt"
  local new_failed_file="$TMP_WORK/new_failed.txt"
  local msg_file="$TMP_WORK/tg_message.txt"

  total="$(cat "$TMP_TOTAL")"
  available="$(cat "$TMP_AVAILABLE")"
  failed_count="$(wc -l < "$TMP_FAIL" | tr -d ' ')"
  json_name="${OUT_JSON##*/}"

  dpi_summary="$(dpi_status_summary_for_tg)"
  dpi_multi_count="$(dpi_active_count)"
  dpi_multi_list="$(dpi_active_list_csv)"

  extract_prev_failed "$prev_json" "$prev_fail_file"
  set_diff "$TMP_FAIL" "$prev_fail_file" "$new_failed_file"
  set_diff "$prev_fail_file" "$TMP_FAIL" "$recovered_file"

  if [ "$degraded" != "1" ] && [ "$TG_NOTIFY_SUCCESS" = "0" ]; then
    log_info "TG success notification skipped by TG_NOTIFY_SUCCESS=0"
    return 0
  fi

  silent=1
  [ "$degraded" = "1" ] && silent=0
  [ "$TG_ALL_SILENT" = "1" ] && silent=1

  : > "$msg_file"

  if [ "$degraded" = "1" ]; then
    loc title_bad >> "$msg_file"
  else
    loc title_ok >> "$msg_file"
  fi

  printf '⏰ %s\n' "$DATE_LOCAL" >> "$msg_file"
  printf '%s: %s/%s\n' "$(loc result)" "$available" "$total" >> "$msg_file"

  if [ "$prev_avail" = "null" ]; then
    loc no_prev >> "$msg_file"
  else
    delta=$((available - prev_avail))
    sign=""
    [ "$delta" -gt 0 ] && sign="+"
    printf '%s: %s/%s (%s%s)\n' "$(loc was)" "$prev_avail" "$total" "$sign" "$delta" >> "$msg_file"
  fi

  printf '%s: %s\n' "$(loc failed_total)" "$failed_count" >> "$msg_file"
  printf '%s: %s\n' "$(loc dpi_statuses)" "$dpi_summary" >> "$msg_file"

  if [ "$dpi_multi_count" -gt 1 ]; then
    printf '%s: %s\n' "$(loc dpi_multi_active)" "$dpi_multi_list" >> "$msg_file"
  fi

  printf '%s: %s\n' "$(loc json)" "$json_name" >> "$msg_file"

  render_list_block "$(loc list_new_failed)" "$new_failed_file" "$TELEGRAM_LIST_MAX_LINES" >> "$msg_file"
  render_list_block "$(loc list_recovered)" "$recovered_file" "$TELEGRAM_LIST_MAX_LINES" >> "$msg_file"

  if [ ! -s "$new_failed_file" ] && [ ! -s "$recovered_file" ]; then
    printf '\n%s' "$(loc no_changes)" >> "$msg_file"
  fi

  telegram_send_message "$(cat "$msg_file")" "$silent"
}

compare_and_notify() {
  local prev_json="$1"
  local total available prev_avail degraded

  total="$(cat "$TMP_TOTAL")"
  available="$(cat "$TMP_AVAILABLE")"
  degraded=0

  if [ -z "$prev_json" ] || [ ! -f "$prev_json" ]; then
    prev_avail="null"
    write_json "null"
    log_info "No previous JSON. Saved: $OUT_JSON"
    send_completion_report "" "null" "0"
    return 0
  fi

  prev_avail="$(jq -r '.available // empty' "$prev_json" 2>/dev/null || true)"
  if [ -z "$prev_avail" ] || ! echo "$prev_avail" | grep -Eq '^[0-9]+$'; then
    prev_avail="null"
    write_json "null"
    log_warn "Previous JSON unreadable. Saved: $OUT_JSON"
    send_completion_report "$prev_json" "null" "0"
    return 0
  fi

  write_json "$prev_avail"

  if [ "$available" -lt "$prev_avail" ]; then
    degraded=1
    log_warn "DEGRADED: now=${available}/${total} was=${prev_avail}/${total} json=$OUT_JSON"
  else
    log_info "OK summary: now=${available}/${total} was=${prev_avail}/${total} json=$OUT_JSON"
  fi

  send_completion_report "$prev_json" "$prev_avail" "$degraded"
}

main() {
  normalize_lang
  TG_NOTIFY_SUCCESS="$(normalize_bool_01 "$TG_NOTIFY_SUCCESS")"
  TG_ALL_SILENT="$(normalize_bool_01 "$TG_ALL_SILENT")"

  require_tools
  check_openwrt_version_hint

  if [ -n "$LOG_FILE" ]; then
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    touch "$LOG_FILE" 2>/dev/null || true
  fi

  log_info "DPI Checker started"
  log_info "Config: OUT_DIR=$OUT_DIR TMP_BASE_DIR=$TMP_BASE_DIR LOG_FILE=$LOG_FILE PARALLEL=$PARALLEL RETRIES=$CURL_RETRIES TG_LANG=$TG_LANG JSON_RETENTION_DAYS=$JSON_RETENTION_DAYS TG_NOTIFY_SUCCESS=$TG_NOTIFY_SUCCESS TG_ALL_SILENT=$TG_ALL_SILENT"
  log_info "Curl: connect_timeout=$CURL_CONNECT_TIMEOUT max_time=$CURL_MAX_TIME speed_time=$CURL_SPEED_TIME speed_limit=$CURL_SPEED_LIMIT range=$CURL_RANGE"

  prune_old_jsons

  if ! internet_sanity_check; then
    collect_dpi_runtime_status
    log_err "$(loc net_fail)"
    printf '0\n' > "$TMP_TOTAL"
    printf '0\n' > "$TMP_AVAILABLE"
    : > "$TMP_FAIL"
    write_json "null"
    log_warn "Saved diagnostic JSON without tests: $OUT_JSON"
    send_completion_report "" "null" "1"
    exit 0
  fi

  if ! run_tests; then
    collect_dpi_runtime_status
    write_json "null"
    log_err "Test run failed; diagnostic JSON saved: $OUT_JSON"
    send_completion_report "" "null" "1"
    exit 1
  fi

  collect_dpi_runtime_status

  prev_json="$(latest_previous_json)"
  [ "$prev_json" = "$OUT_JSON" ] && prev_json=""

  compare_and_notify "$prev_json"
  log_info "DPI Checker finished"
}

main "$@"