#!/usr/bin/env bash
set -euo pipefail

readonly HPDS_INSTALLER_URL="https://github.com/StanfordHPDS/hpds-cli/releases/latest/download/hpds-installer.sh"
readonly REBOOT_REQUIRED="${GCP_SETUP_REBOOT_REQUIRED:-/var/run/reboot-required}"
HPDS_INSTALLER=

# shellcheck disable=SC2329 # Called by the EXIT trap; the final exit hides that from shellcheck.
cleanup() {
  if [[ -n $HPDS_INSTALLER ]]; then
    rm -f "$HPDS_INSTALLER"
  fi
}
trap cleanup EXIT

apt_get() {
  sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 \
    apt-get -o DPkg::Lock::Timeout=600 "$@"
}

# Apply the updates published since the VM image was built. hpds installs
# only the packages it needs and never upgrades the rest of the system.
apt_get update
apt_get -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold upgrade -y

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

export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
if ! command -v hpds >/dev/null 2>&1; then
  printf 'hpds was installed but is not available on PATH\n' >&2
  exit 1
fi

status=0
hpds setup --profile server --yes || status=$?

if [[ -e $REBOOT_REQUIRED ]]; then
  printf '\nRebooting to finish the system updates. Reconnect in a minute or two.\n'
  sudo reboot
fi
exit "$status"
