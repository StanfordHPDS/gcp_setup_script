#!/usr/bin/env bash
set -euo pipefail

readonly HPDS_INSTALLER_URL="https://github.com/StanfordHPDS/hpds-cli/releases/latest/download/hpds-installer.sh"
readonly REBOOT_REQUIRED="${GCP_SETUP_REBOOT_REQUIRED:-/var/run/reboot-required}"
readonly LOG_FILE="$HOME/hpds-setup.log"
HPDS_INSTALLER=

# shellcheck disable=SC2317,SC2329 # Called by the EXIT trap; the final exit hides that from shellcheck.
cleanup() {
  if [[ -n $HPDS_INSTALLER ]]; then
    rm -f "$HPDS_INSTALLER"
  fi
}
trap cleanup EXIT

# Runs a command with its output appended to the setup log under a header,
# printing only "<label>... done" or "<label>... failed". On failure the last
# lines of the command's output and the log path go to stderr. Stdin comes
# from /dev/null so a command cannot consume this script when it is piped
# into bash.
run_logged() {
  local label=$1
  local header=$2
  shift 2
  local start=0
  local status=0
  if [[ -f $LOG_FILE ]]; then
    start=$(wc -l < "$LOG_FILE")
  fi
  printf '=== %s ===\n' "$header" >> "$LOG_FILE"
  printf '%s... ' "$label"
  "$@" < /dev/null >> "$LOG_FILE" 2>&1 || status=$?
  if (( status == 0 )); then
    printf 'done\n'
    return 0
  fi
  printf 'failed\n'
  {
    printf '\n%s failed. Last lines of output:\n' "$header"
    tail -n +"$((start + 2))" "$LOG_FILE" | tail -n 10 | sed 's/^/  /'
    printf '\nFull log: %s\n' "$LOG_FILE"
  } >&2
  return "$status"
}

HPDS_INSTALLER=$(mktemp "${TMPDIR:-/tmp}/hpds-installer.XXXXXX")
curl \
  --proto '=https' \
  --tlsv1.2 \
  --fail \
  --location \
  --silent \
  --show-error \
  --output "$HPDS_INSTALLER" \
  "$HPDS_INSTALLER_URL"
run_logged 'Installing hpds' 'hpds installer' sh "$HPDS_INSTALLER"
rm -f "$HPDS_INSTALLER"
HPDS_INSTALLER=

export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
if ! command -v hpds >/dev/null 2>&1; then
  printf 'hpds was installed but is not available on PATH\n' >&2
  exit 1
fi

# hpds applies pending system updates, prints one line per step, and appends
# the full output to the same log.
status=0
hpds setup --profile server --yes || status=$?

if [[ -e $REBOOT_REQUIRED ]]; then
  printf '\nRebooting to finish the system updates. Reconnect in a minute or two.\n'
  sudo reboot
fi
exit "$status"
