#!/usr/bin/env bash
set -euo pipefail

readonly HPDS_INSTALLER_URL="https://github.com/StanfordHPDS/hpds-cli/releases/latest/download/hpds-installer.sh"
HPDS_INSTALLER=

cleanup() {
  if [[ -n $HPDS_INSTALLER ]]; then
    rm -f "$HPDS_INSTALLER"
  fi
}
trap cleanup EXIT

export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

if command -v hpds >/dev/null 2>&1; then
  hpds upgrade
else
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
  sh "$HPDS_INSTALLER"
  rm -f "$HPDS_INSTALLER"
  HPDS_INSTALLER=
fi

if ! command -v hpds >/dev/null 2>&1; then
  printf 'hpds was installed but is not available on PATH\n' >&2
  exit 1
fi

hpds setup --profile server --yes
