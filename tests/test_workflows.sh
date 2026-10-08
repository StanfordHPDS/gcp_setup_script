#!/usr/bin/env bash
# shellcheck disable=SC2016 # GitHub expressions and shell variables are tested literally.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CI="$ROOT/.github/workflows/ci.yml"
RELEASE="$ROOT/.github/workflows/release.yml"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local file=$1
  local expected=$2
  grep -Fq -- "$expected" "$file" || fail "$file does not contain: $expected"
}

assert_count() {
  local expected_count=$1
  local file=$2
  local text=$3
  local actual_count
  actual_count=$(grep -Fc -- "$text" "$file" || true)
  [[ $actual_count == "$expected_count" ]] ||
    fail "$file contains $actual_count copies of '$text'; expected $expected_count"
}

assert_contains "$CI" 'pull_request:'
assert_contains "$CI" 'branches: [main]'
assert_contains "$CI" 'contents: read'
assert_contains "$CI" 'docker://rhysd/actionlint:1.7.7'
assert_contains "$CI" 'bash tests/test_wrappers.sh'
assert_contains "$CI" 'bash tests/test_workflows.sh'
assert_count 1 "$CI" 'persist-credentials: false'

assert_contains "$RELEASE" 'tags:'
assert_contains "$RELEASE" '- "v*"'
assert_contains "$RELEASE" 'contents: read'
assert_contains "$RELEASE" 'needs: validate'
assert_contains "$RELEASE" 'contents: write'
assert_count 2 "$RELEASE" 'persist-credentials: false'
assert_contains "$RELEASE" '[[ ! $RELEASE_TAG =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]'
assert_contains "$RELEASE" 'git rev-list -n 1 "$RELEASE_TAG"'
assert_contains "$RELEASE" 'if gh release view "$RELEASE_TAG"'
assert_contains "$RELEASE" 'gh release create "$RELEASE_TAG"'
assert_contains "$RELEASE" 'gh release upload "$RELEASE_TAG" setup.sh update.sh --clobber'
assert_count 1 "$RELEASE" 'gh release upload '
assert_contains "$RELEASE" 'GH_TOKEN: ${{ secrets.NERO_REPO_TOKEN }}'
assert_contains "$RELEASE" 'event_type=gcp_setup_released'
assert_contains "$RELEASE" '-F "client_payload[tag]=$RELEASE_TAG"'

printf 'workflow tests passed\n'
