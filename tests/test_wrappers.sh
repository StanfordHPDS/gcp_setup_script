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

assert_has() {
  local text=$1
  local expected=$2
  local what=$3
  [[ $text == *"$expected"* ]] || fail "$what does not contain: $expected"
}

assert_lacks() {
  local text=$1
  local unexpected=$2
  local what=$3
  [[ $text != *"$unexpected"* ]] || fail "$what contains: $unexpected"
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
  assert_not_contains "$ROOT/$script" 'apt-get'
  assert_not_contains "$ROOT/$script" 'QUARTO_VERSION|RSTUDIO_SERVER_VERSION|apt-get (-[^ ]+ )*install|apt2|Miniconda|install\.duckdb|rustup\.rs|code-server\.dev|rig\.r-pkg\.org'
done
assert_contains "$ROOT/setup.sh" 'releases/latest/download/hpds-installer.sh'
assert_contains "$ROOT/update.sh" 'hpds upgrade'
if grep -Fq 'reboot' "$ROOT/update.sh"; then
  fail 'update.sh mentions a reboot; hpds reports pending reboots itself'
fi

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/gcp-wrapper-tests.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

new_case() {
  CASE_DIR=$(mktemp -d "$TEST_ROOT/case.XXXXXX")
  export HOME="$CASE_DIR/home"
  export CALLS="$CASE_DIR/calls"
  export TMPDIR="$CASE_DIR/tmp"
  export PATH="$CASE_DIR/bin:/usr/bin:/bin"
  export GCP_SETUP_REBOOT_REQUIRED="$CASE_DIR/reboot-required"
  LOG="$HOME/hpds-setup.log"
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
if [[ ${INSTALLER_READS_STDIN:-0} == 1 ]]; then
  cat > /dev/null
fi
for i in $(seq 1 15); do
  printf 'installer progress %s\n' "$i"
done
printf 'installer warning on stderr\n' >&2
[[ ${INSTALL_FAIL:-0} != 1 ]] || exit 1
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/hpds" <<'HPDS'
#!/usr/bin/env bash
set -euo pipefail
printf 'hpds %s\n' "$*" >> "$CALLS"
if [[ ${1:-} == upgrade ]]; then
  for i in $(seq 1 15); do
    printf 'upgrade progress %s\n' "$i"
  done
  printf 'upgrade warning on stderr\n' >&2
  [[ ${HPDS_UPGRADE_FAIL:-0} != 1 ]] || exit 1
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
STUB
  chmod +x "$CASE_DIR/bin/curl" "$CASE_DIR/bin/sh" "$CASE_DIR/bin/sudo"
}

install_existing_hpds() {
  "$CASE_DIR/bin/sh" /dev/null >/dev/null 2>&1
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

new_case
output=$(bash "$ROOT/setup.sh" 2>&1) || fail 'expected setup to succeed'
assert_order "$CALLS" 'curl ' 'installer ' 'hpds setup --profile server --yes'
if grep -Fq 'apt-get' "$CALLS"; then
  fail 'setup ran apt-get itself; hpds applies the system updates'
fi
assert_has "$output" 'Installing hpds... done' 'setup output'
assert_lacks "$output" 'installer progress' 'setup output'
assert_lacks "$output" 'installer warning' 'setup output'
[[ $output != *reboot* ]] || fail 'setup asked for a reboot that no update required'
if grep -Fq 'sudo reboot' "$CALLS"; then
  fail 'setup rebooted although no update required it'
fi
assert_contains "$LOG" '=== hpds installer ==='
assert_contains "$LOG" 'installer progress 15'
assert_contains "$LOG" 'installer warning on stderr'

new_case
printf 'earlier run\n' > "$LOG"
run_success bash "$ROOT/setup.sh"
assert_order "$LOG" 'earlier run' '=== hpds installer ===' 'installer progress 1'

new_case
output=$(INSTALLER_READS_STDIN=1 bash < "$ROOT/setup.sh" 2>&1) ||
  fail "expected piped setup to succeed: $output"
assert_order "$CALLS" 'curl ' 'installer ' 'hpds setup --profile server --yes'

new_case
touch "$GCP_SETUP_REBOOT_REQUIRED"
output=$(bash "$ROOT/setup.sh" 2>&1) || fail 'expected setup to succeed'
assert_order "$CALLS" 'curl ' 'installer ' 'hpds setup --profile server --yes' 'sudo reboot'
[[ $(tail -1 "$CALLS") == 'sudo reboot' ]] || fail 'setup did not reboot last when the updates required it'
assert_has "$output" 'Rebooting to finish the system updates' 'setup output'

new_case
touch "$GCP_SETUP_REBOOT_REQUIRED"
run_failure env HPDS_SETUP_FAIL=1 bash "$ROOT/setup.sh"
[[ $(tail -1 "$CALLS") == 'sudo reboot' ]] || fail 'setup did not reboot after hpds setup failed'

new_case
install_existing_hpds
output=$(bash "$ROOT/update.sh" 2>&1) || fail 'expected update to succeed'
assert_order "$CALLS" 'hpds upgrade' 'hpds setup --profile server --yes'
if grep -Fq 'curl ' "$CALLS"; then
  fail 'update downloaded hpds even though it was already installed'
fi
assert_has "$output" 'Updating hpds... done' 'update output'
assert_lacks "$output" 'upgrade progress' 'update output'
assert_lacks "$output" 'upgrade warning' 'update output'
assert_contains "$LOG" '=== hpds upgrade ==='
assert_contains "$LOG" 'upgrade progress 15'
assert_contains "$LOG" 'upgrade warning on stderr'

new_case
output=$(bash "$ROOT/update.sh" 2>&1) || fail 'expected update to succeed'
assert_order "$CALLS" 'curl ' 'installer ' 'hpds setup --profile server --yes'
if grep -Fq 'hpds upgrade' "$CALLS"; then
  fail 'update tried to upgrade hpds after fallback bootstrap'
fi
assert_has "$output" 'Installing hpds... done' 'update output'
assert_lacks "$output" 'installer progress' 'update output'
assert_contains "$LOG" '=== hpds installer ==='
assert_contains "$LOG" 'installer progress 15'

new_case
install_existing_hpds
touch "$GCP_SETUP_REBOOT_REQUIRED"
run_success bash "$ROOT/update.sh"
if grep -Fq 'reboot' "$CALLS"; then
  fail 'update rebooted; it leaves pending reboots to the user'
fi

new_case
run_failure env CURL_FAIL=1 bash "$ROOT/setup.sh"
[[ ! -s $CALLS || $(tail -1 "$CALLS") == curl\ * ]] || fail 'setup continued after download failure'
[[ -z $(find "$TMPDIR" -type f -print -quit) ]] || fail 'setup left its failed download behind'

new_case
if output=$(INSTALL_FAIL=1 bash "$ROOT/setup.sh" 2>"$CASE_DIR/stderr"); then
  fail 'expected setup to fail when the installer fails'
fi
errors=$(cat "$CASE_DIR/stderr")
[[ $(tail -1 "$CALLS") == installer\ * ]] || fail 'setup continued after installer failure'
[[ -z $(find "$TMPDIR" -type f -print -quit) ]] || fail 'setup left its failed installer behind'
assert_has "$output" 'Installing hpds... failed' 'setup output'
assert_lacks "$output" 'installer progress' 'setup output'
assert_has "$errors" 'installer progress 15' 'setup errors'
assert_has "$errors" 'installer warning on stderr' 'setup errors'
assert_has "$errors" 'installer progress 7' 'setup errors'
assert_lacks "$errors" 'installer progress 6' 'setup errors'
assert_has "$errors" "$LOG" 'setup errors'

new_case
install_existing_hpds
if output=$(HPDS_UPGRADE_FAIL=1 bash "$ROOT/update.sh" 2>"$CASE_DIR/stderr"); then
  fail 'expected update to fail when hpds upgrade fails'
fi
errors=$(cat "$CASE_DIR/stderr")
[[ $(tail -1 "$CALLS") == 'hpds upgrade' ]] || fail 'update continued after upgrade failure'
assert_has "$output" 'Updating hpds... failed' 'update output'
assert_lacks "$output" 'upgrade progress' 'update output'
assert_has "$errors" 'upgrade progress 15' 'update errors'
assert_lacks "$errors" 'upgrade progress 6' 'update errors'
assert_has "$errors" "$LOG" 'update errors'

new_case
if output=$(INSTALL_FAIL=1 bash "$ROOT/update.sh" 2>"$CASE_DIR/stderr"); then
  fail 'expected update to fail when the installer fails'
fi
errors=$(cat "$CASE_DIR/stderr")
[[ $(tail -1 "$CALLS") == installer\ * ]] || fail 'update continued after installer failure'
[[ -z $(find "$TMPDIR" -type f -print -quit) ]] || fail 'update left its failed installer behind'
assert_has "$output" 'Installing hpds... failed' 'update output'
assert_has "$errors" 'installer progress 15' 'update errors'
assert_has "$errors" "$LOG" 'update errors'

new_case
install_existing_hpds
run_failure env HPDS_SETUP_FAIL=1 bash "$ROOT/update.sh"
assert_order "$CALLS" 'hpds upgrade' 'hpds setup --profile server --yes'

printf 'wrapper tests passed\n'
