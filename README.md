\# DPI Checker



\[🇷🇺 Русская версия / Russian version](./README.ru.md)



DPI Checker is a lightweight OpenWRT script for \*\*regular (e.g. daily) health checks of your selected DPI bypass strategy\*\*.



It tests target availability, compares results with the previous run, saves JSON reports, and sends a Telegram report with domain-level changes.



---



\## What this script is for



Use DPI Checker to monitor whether your current DPI bypass setup still works as expected over time.



Typical use case:

\- run once a day via cron

\- get a Telegram summary

\- quickly see if something degraded and which domains failed



---



\## Features



\- ✅ Checks a built-in list of blocked/throttled targets

\- ✅ Loads extra targets from `dpi-checkers` `suite.json`

\- ✅ Saves each run as a JSON report

\- ✅ Compares with the previous run

\- ✅ Telegram notifications (English / Russian)

\- ✅ Silent notifications for successful runs (optional)

\- ✅ Domain diff between runs:

&nbsp; - newly failed

&nbsp; - newly recovered

\- ✅ Detects DPI bypass tools status:

&nbsp; - `zapret`

&nbsp; - `zapret2`

&nbsp; - `youtubeUnblock`

&nbsp; - `goodbyedpi`

\- ✅ Warns if multiple DPI bypass tools are active at the same time

\- ✅ Cleans up old JSON files automatically (retention)

\- ✅ Interactive installer (Easy / Full)

\- ✅ OpenWRT 24/25 friendly



---



\## Installation (Easy mode)



> Run this in the folder where you want the project to be installed.  

> Examples use `~/DPIChecker` (user home directory). For cron, always use your real absolute path.



~~~sh

mkdir -p ~/DPIChecker \&\& cd ~/DPIChecker

wget -O - https://raw.githubusercontent.com/LoonyMan/DPI-Checker/master/install.sh | sh

~~~



The installer will:

\- download `dpi-checker.sh`

\- create `dpi-checker.env`

\- optionally add a cron job



\### Telegram credentials



You can get the required Telegram values here:



\- \*\*Bot token\*\* → \[@BotFather](https://t.me/BotFather)

\- \*\*Chat ID\*\* → \[@userinfobot](https://t.me/userinfobot)



\### Easy mode asks only



\- `TELEGRAM\_BOT\_TOKEN`

\- `TELEGRAM\_CHAT\_ID`

\- `Telegram message language`

\- `Notify on successful runs?`

\- `Make all Telegram messages silent?`



At the end, the installer also asks:

\- whether to add cron autostart

\- what time to run the check



---



\## Manual run



~~~sh

cd ~/DPIChecker

. ./dpi-checker.env \&\& ./dpi-checker.sh

~~~



---



\## Cron example



Run every day at \*\*06:00\*\* (router local time):



~~~cron

0 6 \* \* \* cd '/home/youruser/DPIChecker' \&\& . '/home/youruser/DPIChecker/dpi-checker.env' \&\& ./dpi-checker.sh >/dev/null 2>\&1 # DPI Checker

~~~



> Use your real absolute path here (cron should not rely on `~`).



---



\## ENV parameters



Below are all environment variables supported by `dpi-checker.sh`.



\### Telegram / notifications



\- `TELEGRAM\_BOT\_TOKEN`  

&nbsp; Telegram bot token. Empty value disables Telegram notifications.



\- `TELEGRAM\_CHAT\_ID`  

&nbsp; Telegram chat ID (user/group/channel where the bot can send messages).



\- `TG\_LANG`  

&nbsp; Telegram message language: `en` or `ru`.



\- `TG\_NOTIFY\_SUCCESS`  

&nbsp; - `1` = send reports for successful runs too  

&nbsp; - `0` = send only degraded/error runs



\- `TG\_ALL\_SILENT`  

&nbsp; - `1` = all Telegram messages are silent  

&nbsp; - `0` = degraded/error alerts are normal (audible), success can be silent



\- `TELEGRAM\_LIST\_MAX\_LINES`  

&nbsp; Max number of domains shown in each list (`newly failed`, `newly recovered`).



\- `TELEGRAM\_MESSAGE\_MAX`  

&nbsp; Max Telegram message length before truncation.



\### Reports / files



\- `OUT\_DIR`  

&nbsp; Directory where JSON reports are saved.



\- `OUT\_PREFIX`  

&nbsp; JSON filename prefix. Default: `dpi\_checker\_test\_`.



\- `TMP\_BASE\_DIR`  

&nbsp; Base directory for temporary runtime files.



\- `JSON\_RETENTION\_DAYS`  

&nbsp; Delete JSON report files older than this number of days.



\### Logging



\- `LOG\_FILE`  

&nbsp; Path to log file. Empty value disables file logging.



\- `LOG\_STDOUT`  

&nbsp; - `1` = print logs to console  

&nbsp; - `0` = disable console logs



\### Test behavior (advanced)



\- `PARALLEL` — number of parallel checks

\- `CURL\_CONNECT\_TIMEOUT` — curl connect timeout (seconds)

\- `CURL\_MAX\_TIME` — max curl runtime per target (seconds)

\- `CURL\_SPEED\_TIME` — low-speed time threshold for curl

\- `CURL\_SPEED\_LIMIT` — low-speed bytes/sec threshold for curl

\- `CURL\_RANGE` — HTTP range used for probe request

\- `CURL\_RETRIES` — retry attempts per target

\- `CURL\_RETRY\_DELAY` — delay between retries (seconds)

\- `USER\_AGENT` — custom curl User-Agent string

\- `NETCHECK\_URL` — internet availability check URL (default: `https://ya.ru`)

\- `DPI\_SUITE\_URL` — URL of `dpi-checkers` suite JSON used to load extra targets



---



\## Minimal ENV example



~~~sh

export TELEGRAM\_BOT\_TOKEN="123456:ABCDEF"

export TELEGRAM\_CHAT\_ID="123456789"



export OUT\_DIR="$HOME/DPIChecker/results"

export TMP\_BASE\_DIR="$HOME/DPIChecker/tmp"



export TG\_LANG="en"

export JSON\_RETENTION\_DAYS="12"



export TG\_NOTIFY\_SUCCESS="1"

export TG\_ALL\_SILENT="0"



export LOG\_FILE="$HOME/DPIChecker/dpi-checker.log"

export LOG\_STDOUT="1"

~~~



---



\## How to remove DPI Checker completely



\### 1) Remove cron entry



~~~sh

grep -v "DPI Checker" /etc/crontabs/root > /tmp/root.cron \&\& cat /tmp/root.cron > /etc/crontabs/root

rm -f /tmp/root.cron

/etc/init.d/cron restart

~~~



\### 2) Remove project folder



~~~sh

rm -rf ~/DPIChecker

~~~



---



\## Quick troubleshooting



\### No Telegram messages

Check:

\- `TELEGRAM\_BOT\_TOKEN`

\- `TELEGRAM\_CHAT\_ID`

\- bot has permission to send messages

\- you started a chat with the bot (for private chat)



\### Cron does not run

Check:



~~~sh

/etc/init.d/cron status

cat /etc/crontabs/root

/etc/init.d/cron restart

~~~



\### Script works manually but not in cron

This is usually a path/ENV issue.



Use a cron entry like this:



~~~sh

cd '/home/youruser/DPIChecker' \&\& . '/home/youruser/DPIChecker/dpi-checker.env' \&\& ./dpi-checker.sh

~~~

