#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local file=$1
  local expected=$2
  grep -Fq -- "$expected" "$file" || fail "$file does not contain: $expected"
}

assert_not_contains() {
  local file=$1
  local unexpected=$2
  if grep -Eq -- "$unexpected" "$file"; then
    fail "$file still contains duplicated provisioning: $unexpected"
  fi
}

assert_order() {
  local file=$1
  shift
  local previous=0
  local expected line
  for expected in "$@"; do
    line=$(grep -nF -- "$expected" "$file" | head -1 | cut -d: -f1 || true)
    [[ -n $line ]] || fail "$file does not contain: $expected"
    (( line > previous )) || fail "$expected appeared out of order in $file"
    previous=$line
  done
}

for script in setup.sh update.sh; do
  bash -n "$ROOT/$script"
  assert_contains "$ROOT/$script" 'hpds setup --profile server --yes'
  assert_not_contains "$ROOT/$script" 'QUARTO_VERSION|RSTUDIO_SERVER_VERSION|apt-get (-[^ ]+ )*install|apt2|Miniconda|install\.duckdb|rustup\.rs|code-server\.dev|rig\.r-pkg\.org'
done
assert_contains "$ROOT/setup.sh" 'releases/latest/download/hpds-installer.sh'
assert_contains "$ROOT/update.sh" 'hpds upgrade'
assert_not_contains "$ROOT/update.sh" 'apt-get'

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/gcp-wrapper-tests.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

new_case() {
  CASE_DIR=$(mktemp -d "$TEST_ROOT/case.XXXXXX")
  export HOME="$CASE_DIR/home"
  export CALLS="$CASE_DIR/calls"
  export TMPDIR="$CASE_DIR/tmp"
  export PATH="$CASE_DIR/bin:/usr/bin:/bin"
  export GCP_SETUP_REBOOT_REQUIRED="$CASE_DIR/reboot-required"
  mkdir -p "$HOME" "$TMPDIR" "$CASE_DIR/bin"
  : > "$CALLS"

  cat > "$CASE_DIR/bin/curl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'curl %s\n' "$*" >> "$CALLS"
[[ ${CURL_FAIL:-0} != 1 ]] || exit 22
output=
while (( $# )); do
  case $1 in
    -o|--output)
      output=$2
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
[[ -n $output ]] || exit 2
printf '#!/bin/sh\n' > "$output"
STUB

  cat > "$CASE_DIR/bin/sh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'installer %s\n' "$*" >> "$CALLS"
[[ ${INSTALL_FAIL:-0} != 1 ]] || exit 1
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/hpds" <<'HPDS'
#!/usr/bin/env bash
set -euo pipefail
printf 'hpds %s\n' "$*" >> "$CALLS"
if [[ ${1:-} == upgrade && ${HPDS_UPGRADE_FAIL:-0} == 1 ]]; then
  exit 1
fi
if [[ ${1:-} == setup && ${HPDS_SETUP_FAIL:-0} == 1 ]]; then
  exit 1
fi
HPDS
chmod +x "$HOME/.local/bin/hpds"
STUB
  cat > "$CASE_DIR/bin/sudo" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'sudo %s\n' "$*" >> "$CALLS"
if [[ " $* " == *' upgrade '* && ${UPGRADE_FAIL:-0} == 1 ]]; then
  exit 100
fi
STUB
  chmod +x "$CASE_DIR/bin/curl" "$CASE_DIR/bin/sh" "$CASE_DIR/bin/sudo"
}

install_existing_hpds() {
  "$CASE_DIR/bin/sh" /dev/null
  : > "$CALLS"
}

run_success() {
  "$@" >/dev/null 2>&1 || fail "expected success: $*"
}

run_failure() {
  if "$@" >/dev/null 2>&1; then
    fail "expected failure: $*"
  fi
}

readonly APT='sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 apt-get -o DPkg::Lock::Timeout=600'

new_case
output=$(bash "$ROOT/setup.sh" 2>&1) || fail 'expected setup to succeed'
assert_order "$CALLS" "$APT update" "$APT -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold upgrade -y" 'curl ' 'installer ' 'hpds setup --profile server --yes'
[[ $output != *reboot* ]] || fail 'setup asked for a reboot that no update required'
if grep -Fq 'sudo reboot' "$CALLS"; then
  fail 'setup rebooted although no update required it'
fi

new_case
touch "$GCP_SETUP_REBOOT_REQUIRED"
run_success bash "$ROOT/setup.sh"
assert_order "$CALLS" "$APT update" 'hpds setup --profile server --yes' 'sudo reboot'
[[ $(tail -1 "$CALLS") == 'sudo reboot' ]] || fail 'setup did not reboot last when the updates required it'

new_case
touch "$GCP_SETUP_REBOOT_REQUIRED"
run_failure env HPDS_SETUP_FAIL=1 bash "$ROOT/setup.sh"
[[ $(tail -1 "$CALLS") == 'sudo reboot' ]] || fail 'setup did not reboot after hpds setup failed'

new_case
run_failure env UPGRADE_FAIL=1 bash "$ROOT/setup.sh"
[[ $(tail -1 "$CALLS") == *' upgrade -y' ]] || fail 'setup continued after the system upgrade failed'

new_case
install_existing_hpds
run_success bash "$ROOT/update.sh"
assert_order "$CALLS" 'hpds upgrade' 'hpds setup --profile server --yes'
if grep -Fq 'curl ' "$CALLS"; then
  fail 'update downloaded hpds even though it was already installed'
fi

new_case
run_success bash "$ROOT/update.sh"
assert_order "$CALLS" 'curl ' 'installer ' 'hpds setup --profile server --yes'
if grep -Fq 'hpds upgrade' "$CALLS"; then
  fail 'update tried to upgrade hpds after fallback bootstrap'
fi

new_case
run_failure env CURL_FAIL=1 bash "$ROOT/setup.sh"
[[ ! -s $CALLS || $(tail -1 "$CALLS") == curl\ * ]] || fail 'setup continued after download failure'
[[ -z $(find "$TMPDIR" -type f -print -quit) ]] || fail 'setup left its failed download behind'

new_case
run_failure env INSTALL_FAIL=1 bash "$ROOT/setup.sh"
[[ $(tail -1 "$CALLS") == installer\ * ]] || fail 'setup continued after installer failure'
[[ -z $(find "$TMPDIR" -type f -print -quit) ]] || fail 'setup left its failed installer behind'

new_case
install_existing_hpds
run_failure env HPDS_UPGRADE_FAIL=1 bash "$ROOT/update.sh"
[[ $(tail -1 "$CALLS") == 'hpds upgrade' ]] || fail 'update continued after upgrade failure'

new_case
install_existing_hpds
run_failure env HPDS_SETUP_FAIL=1 bash "$ROOT/update.sh"
assert_order "$CALLS" 'hpds upgrade' 'hpds setup --profile server --yes'

printf 'wrapper tests passed\n'
