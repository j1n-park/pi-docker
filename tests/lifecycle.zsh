#!/usr/bin/env zsh

set -eu

repo_dir="${0:A:h:h}"
source "$repo_dir/pi.zsh"

typeset -gi tests_run=0

fail() {
  print -u2 -r -- "FAIL: $*"
  exit 1
}

assert_eq() {
  local expected="$1" actual="$2" message="$3"
  (( tests_run += 1 ))
  [[ "$actual" == "$expected" ]] || fail "$message (expected=$expected actual=$actual)"
}

test_commit_failure_preserves_container() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  local calls="$temp_dir/docker.calls"

  docker() {
    print -r -- "$*" >>"$calls"
    case "$1" in
      commit)
        print -u2 "simulated commit failure"
        return 42
        ;;
      rm)
        return 0
        ;;
    esac
  }

  PI_AGENT_CURRENT_IMAGE="test:current"
  set +e
  _pi_agent_commit_and_remove test-active test:snapshot 0 >/dev/null 2>"$temp_dir/error"
  local commit_status=$?
  set -e

  assert_eq 42 "$commit_status" "commit failure status must be preserved"
  assert_eq 0 "$(grep -c '^rm ' "$calls" || true)" "failed commit must not remove container"
  (( tests_run += 1 ))
  grep -q 'preserving container with uncommitted state' "$temp_dir/error" ||
    fail "commit failure must explain that the container was preserved"

  rm -rf "$temp_dir"
}

test_commit_success_removes_container() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  local calls="$temp_dir/docker.calls"

  docker() {
    print -r -- "$*" >>"$calls"
    return 0
  }

  PI_AGENT_CURRENT_IMAGE="test:current"
  _pi_agent_commit_and_remove test-active test:snapshot 0

  assert_eq 1 "$(grep -c '^commit ' "$calls")" "successful path must commit once"
  assert_eq 1 "$(grep -c '^rm -f test-active$' "$calls")" "container may be removed after commit"

  rm -rf "$temp_dir"
}

test_quick_fix_keeps_lock_file() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  PI_AGENT_STATE_DIR="$temp_dir/state"

  pi-quick-fix --verbose >/dev/null 2>"$temp_dir/error"
  pi-quick-fix --verbose >/dev/null 2>>"$temp_dir/error"

  (( tests_run += 1 ))
  [[ -f "$PI_AGENT_STATE_DIR/lifecycle.lock" ]] ||
    fail "quick fix must keep the persistent lock file"
  assert_eq 2 "$(grep -c 'lock is healthy and available' "$temp_dir/error")" \
    "unlock must allow the lock to be acquired again"
  (( tests_run += 1 ))
  [[ ! -s "$temp_dir/error" || "$(grep -c 'lock is healthy and available' "$temp_dir/error")" == 2 ]] ||
    fail "quick fix emitted an unexpected error"

  rm -rf "$temp_dir"
}

test_commit_failure_preserves_container
test_commit_success_removes_container
test_quick_fix_keeps_lock_file

print -r -- "PASS: $tests_run lifecycle assertions"
