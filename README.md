# DPI Checker

[🇷🇺 Русская версия / Russian version](./README.ru.md)

DPI Checker is a lightweight OpenWRT script for **regular (e.g. daily) health checks of your selected DPI bypass strategy**.

It tests target availability, compares results with the previous run, saves JSON reports, and sends a Telegram report with domain-level changes.

<img width="326" height="181" alt="изображение" src="https://github.com/user-attachments/assets/dbef2992-d387-4b8e-b276-2b905e7ae913" />

<details>
  <summary>Logs</summary>
  <img width="1427" height="1245" alt="изображение" src="https://github.com/user-attachments/assets/1c5ce7ef-0673-43b0-ae16-c42140f1a688" />
</details>

---

## What this script is for

Use DPI Checker to monitor whether your current DPI bypass setup still works as expected over time.

Typical use case:
- run once a day via cron
- get a Telegram summary
- quickly see if something degraded and which domains failed

---

## Features

- ✅ Checks a built-in list of blocked/throttled targets
- ✅ Loads extra targets from `dpi-checkers` `suite.json`
- ✅ Saves each run as a JSON report
- ✅ Compares with the previous run
- ✅ Telegram notifications (English / Russian)
- ✅ Silent notifications for successful runs (optional)
- ✅ Domain diff between runs:
  - newly failed
  - newly recovered
- ✅ Detects DPI bypass tools status:
  - `zapret`
  - `zapret2`
  - `youtubeUnblock`
  - `goodbyedpi`
- ✅ Warns if multiple DPI bypass tools are active at the same time
- ✅ Cleans up old JSON files automatically (retention)
- ✅ Interactive installer (Easy / Full)
- ✅ OpenWRT 24/25 friendly

---

## Installation (Easy mode)

> Run this in the folder where you want the project to be installed.  
> Examples use `~/DPIChecker` (user home directory). For cron, always use your real absolute path.

~~~sh
mkdir -p ~/DPIChecker && cd ~/DPIChecker
wget -O - https://raw.githubusercontent.com/LoonyMan/DPI-Checker/master/install.sh | sh
~~~

The installer will:
- download `dpi-checker.sh`
- create `dpi-checker.env`
- optionally add a cron job

### Telegram credentials

You can get the required Telegram values here:

- **Bot token** → [@BotFather](https://t.me/BotFather)
- **Chat ID** → [@userinfobot](https://t.me/userinfobot)

### Easy mode asks only

- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_CHAT_ID`
- `Telegram message language`
- `Notify on successful runs?`
- `Make all Telegram messages silent?`

At the end, the installer also asks:
- whether to add cron autostart
- what time to run the check

---

## Manual run

~~~sh
cd ~/DPIChecker
. ./dpi-checker.env && ./dpi-checker.sh
~~~

---

## Cron example

Run every day at **06:00** (router local time):

~~~cron
0 6 * * * cd '/home/youruser/DPIChecker' && . '/home/youruser/DPIChecker/dpi-checker.env' && ./dpi-checker.sh >/dev/null 2>&1 # DPI Checker
~~~

> Use your real absolute path here (cron should not rely on `~`).

---

## ENV parameters

Below are all environment variables supported by `dpi-checker.sh`.

### Telegram / notifications

- `TELEGRAM_BOT_TOKEN`  
  Telegram bot token. Empty value disables Telegram notifications.

- `TELEGRAM_CHAT_ID`  
  Telegram chat ID (user/group/channel where the bot can send messages).

- `TG_LANG`  
  Telegram message language: `en` or `ru`.

- `TG_NOTIFY_SUCCESS`  
  - `1` = send reports for successful runs too  
  - `0` = send only degraded/error runs

- `TG_ALL_SILENT`  
  - `1` = all Telegram messages are silent  
  - `0` = degraded/error alerts are normal (audible), success can be silent

- `TELEGRAM_LIST_MAX_LINES`  
  Max number of domains shown in each list (`newly failed`, `newly recovered`).

- `TELEGRAM_MESSAGE_MAX`  
  Max Telegram message length before truncation.

### Reports / files

- `OUT_DIR`  
  Directory where JSON reports are saved.

- `OUT_PREFIX`  
  JSON filename prefix. Default: `dpi_checker_test_`.

- `TMP_BASE_DIR`  
  Base directory for temporary runtime files.

- `JSON_RETENTION_DAYS`  
  Delete JSON report files older than this number of days.

### Logging

- `LOG_FILE`  
  Path to log file. Empty value disables file logging.

- `LOG_STDOUT`  
  - `1` = print logs to console  
  - `0` = disable console logs

### Test behavior (advanced)

- `PARALLEL` — number of parallel checks
- `CURL_CONNECT_TIMEOUT` — curl connect timeout (seconds)
- `CURL_MAX_TIME` — max curl runtime per target (seconds)
- `CURL_SPEED_TIME` — low-speed time threshold for curl
- `CURL_SPEED_LIMIT` — low-speed bytes/sec threshold for curl
- `CURL_RANGE` — HTTP range used for probe request
- `CURL_RETRIES` — retry attempts per target
- `CURL_RETRY_DELAY` — delay between retries (seconds)
- `USER_AGENT` — custom curl User-Agent string
- `NETCHECK_URL` — internet availability check URL (default: `https://ya.ru`)
- `DPI_SUITE_URL` — URL of `dpi-checkers` suite JSON used to load extra targets

---

## Minimal ENV example

~~~sh
export TELEGRAM_BOT_TOKEN="123456:ABCDEF"
export TELEGRAM_CHAT_ID="123456789"

export OUT_DIR="$HOME/DPIChecker/results"
export TMP_BASE_DIR="$HOME/DPIChecker/tmp"

export TG_LANG="en"
export JSON_RETENTION_DAYS="12"

export TG_NOTIFY_SUCCESS="1"
export TG_ALL_SILENT="0"

export LOG_FILE="$HOME/DPIChecker/dpi-checker.log"
export LOG_STDOUT="1"
~~~

---

## How to remove DPI Checker completely

### 1) Remove cron entry

~~~sh
grep -v "DPI Checker" /etc/crontabs/root > /tmp/root.cron && cat /tmp/root.cron > /etc/crontabs/root
rm -f /tmp/root.cron
/etc/init.d/cron restart
~~~

### 2) Remove project folder

~~~sh
rm -rf ~/DPIChecker
~~~

---

## Quick troubleshooting

### No Telegram messages
Check:
- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_CHAT_ID`
- bot has permission to send messages
- you started a chat with the bot (for private chat)

### Cron does not run
Check:

~~~sh
/etc/init.d/cron status
cat /etc/crontabs/root
/etc/init.d/cron restart
~~~

### Script works manually but not in cron
This is usually a path/ENV issue.

Use a cron entry like this:

~~~sh
cd '/home/youruser/DPIChecker' && . '/home/youruser/DPIChecker/dpi-checker.env' && ./dpi-checker.sh
~~~
