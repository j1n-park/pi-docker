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
  local PI_AGENT_STATE_DIR="$temp_dir/state"

  docker() {
    return 1
  }

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

test_flatten_returns_cleanly_and_releases_lock() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  local PI_AGENT_STATE_DIR="$temp_dir/state"
  local PI_AGENT_ACTIVE_CONTAINER="test-active"
  local PI_AGENT_BASE_IMAGE="test:base"
  local PI_AGENT_CURRENT_IMAGE="test:current"

  set +e
  (
    docker() {
      case "$1 $2" in
        "image inspect")
          return 0
          ;;
        "container inspect")
          return 1
          ;;
        *)
          return 0
          ;;
      esac
    }

    _pi_agent_flatten_current_image() {
      return 0
    }

    pi-flatten
    pi-flatten
  ) >/dev/null 2>"$temp_dir/error"
  local flatten_status=$?
  set -e

  assert_eq 0 "$flatten_status" \
    "flatten must return successfully and release its lifecycle lock"
  (( tests_run += 1 ))
  ! grep -q 'read-only variable: status' "$temp_dir/error" ||
    fail "flatten must not assign zsh's read-only status parameter"

  rm -rf "$temp_dir"
}

test_quick_fix_saves_and_stops_idle_container() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  local calls="$temp_dir/docker.calls"
  local PI_AGENT_STATE_DIR="$temp_dir/state"
  local PI_AGENT_ACTIVE_CONTAINER="test-active"
  local PI_AGENT_CURRENT_IMAGE="test:current"
  local PI_AGENT_IMAGE_REPO="test"
  local PI_AGENT_AUTO_PRUNE=0

  docker() {
    print -r -- "$*" >>"$calls"
    case "$1 $2" in
      "container inspect")
        if [[ "$*" == *"--format"* ]]; then
          print -r -- true
        fi
        return 0
        ;;
      "image inspect")
        return 1
        ;;
      *)
        return 0
        ;;
    esac
  }

  pi-quick-fix --verbose >/dev/null 2>"$temp_dir/error"

  assert_eq 1 "$(grep -Ec '^tag test:current test:snap-[0-9]{8}-[0-9]{6}$' "$calls")" \
    "quick fix must snapshot the previous current image"
  assert_eq 1 "$(grep -c '^commit ' "$calls")" \
    "quick fix must commit the idle container"
  assert_eq 1 "$(grep -c '^rm -f test-active$' "$calls")" \
    "quick fix must remove the container after saving it"

  rm -rf "$temp_dir"
}

test_quick_fix_recovers_interrupted_session() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  local calls="$temp_dir/docker.calls"
  local PI_AGENT_STATE_DIR="$temp_dir/state"
  local PI_AGENT_ACTIVE_CONTAINER="test-active"
  local PI_AGENT_CURRENT_IMAGE="test:current"
  local PI_AGENT_IMAGE_REPO="test"
  local PI_AGENT_AUTO_PRUNE=0
  mkdir -p "$PI_AGENT_STATE_DIR/sessions"
  print -r -- "pending 999999 interrupted-launcher" >"$PI_AGENT_STATE_DIR/sessions/session.stale"

  docker() {
    print -r -- "$*" >>"$calls"
    case "$1 $2" in
      "container inspect")
        if [[ "$*" == *"--format"* ]]; then
          print -r -- true
        fi
        return 0
        ;;
      "image inspect")
        return 1
        ;;
      "exec "*)
        # The container-side process survived, but its host launcher did not.
        print -r -- alive
        return 0
        ;;
      *)
        return 0
        ;;
    esac
  }

  pi-quick-fix >/dev/null 2>"$temp_dir/error"

  assert_eq 0 "$(_pi_agent_session_count)" \
    "quick fix must remove an interrupted host session marker"
  assert_eq 0 "$(grep -c '^exec ' "$calls" || true)" \
    "quick fix must not require exec access to the container"
  assert_eq 1 "$(grep -c '^commit ' "$calls")" \
    "quick fix must save a container left by an interrupted session"
  assert_eq 1 "$(grep -c '^rm -f test-active$' "$calls")" \
    "quick fix must stop the recovered orphan container"

  rm -rf "$temp_dir"
}

test_quick_fix_refuses_active_session() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  local calls="$temp_dir/docker.calls"
  local PI_AGENT_STATE_DIR="$temp_dir/state"
  local PI_AGENT_ACTIVE_CONTAINER="test-active"
  local PI_AGENT_CURRENT_IMAGE="test:current"
  local PI_AGENT_IMAGE_REPO="test"
  local launcher_pid=123
  local launcher_started="active-launcher"
  mkdir -p "$PI_AGENT_STATE_DIR/sessions"
  print -r -- "pending $launcher_pid $launcher_started" >"$PI_AGENT_STATE_DIR/sessions/session.active"

  _pi_agent_process_started_at() {
    print -r -- "active-launcher"
  }

  docker() {
    print -r -- "$*" >>"$calls"
    case "$1 $2" in
      "container inspect")
        if [[ "$*" == *"--format"* ]]; then
          print -r -- true
        fi
        return 0
        ;;
      "image inspect")
        return 1
        ;;
      "exec "*)
        print -r -- alive
        return 0
        ;;
      *)
        return 0
        ;;
    esac
  }

  set +e
  pi-quick-fix >/dev/null 2>"$temp_dir/error"
  local quick_fix_status=$?
  set -e

  assert_eq 75 "$quick_fix_status" "quick fix must refuse a live session"
  assert_eq 0 "$(grep -Ec '^(tag|commit|rm) ' "$calls" || true)" \
    "quick fix must not save or stop a container with a live session"
  (( tests_run += 1 ))
  grep -q 'still has 1 active host session' "$temp_dir/error" ||
    fail "quick fix must explain why an active container was preserved"

  rm -rf "$temp_dir"
}

test_quick_fix_commits_before_removing_orphan_with_busy_lock() {
  setopt localoptions nobgnice
  local temp_dir
  temp_dir="$(mktemp -d)"
  local calls="$temp_dir/docker.calls"
  local release_lock="$temp_dir/release-lock"
  local PI_AGENT_STATE_DIR="$temp_dir/state"
  local PI_AGENT_ACTIVE_CONTAINER="test-active"
  local PI_AGENT_CURRENT_IMAGE="test:current"
  local PI_AGENT_IMAGE_REPO="test"
  local PI_AGENT_AUTO_PRUNE=0
  local PI_AGENT_LOCK_TIMEOUT=2
  mkdir -p "$PI_AGENT_STATE_DIR/sessions"
  : >"$PI_AGENT_STATE_DIR/lifecycle.lock"

  zsh -c '
    zmodload zsh/system
    zsystem flock -f lock_fd "$1"
    print -r -- locked >"$2"
    while [[ ! -e "$3" ]]; do sleep 0.05; done
  ' zsh "$PI_AGENT_STATE_DIR/lifecycle.lock" "$temp_dir/locked" "$release_lock" 2>/dev/null &
  local holder_pid=$!
  while [[ ! -e "$temp_dir/locked" ]]; do sleep 0.05; done

  docker() {
    print -r -- "$*" >>"$calls"
    case "$1 $2" in
      "container inspect")
        if [[ "$*" == *"--format"* ]]; then
          print -r -- true
        fi
        return 0
        ;;
      "rm -f")
        : >"$release_lock"
        return 0
        ;;
      "image inspect")
        return 1
        ;;
      *)
        return 0
        ;;
    esac
  }

  pi-quick-fix --verbose >/dev/null 2>"$temp_dir/error"
  wait "$holder_pid"

  assert_eq 0 "$(grep -c '^stop ' "$calls" || true)" \
    "quick fix must not stop an orphan before saving it"
  assert_eq 1 "$(grep -c '^commit ' "$calls")" \
    "quick fix must commit the orphan despite the busy lifecycle lock"
  assert_eq 1 "$(grep -c '^rm -f test-active$' "$calls")" \
    "quick fix must remove the orphan after committing it"
  local commit_line remove_line
  commit_line="$(grep -n '^commit ' "$calls" | cut -d: -f1)"
  remove_line="$(grep -n '^rm -f test-active$' "$calls" | cut -d: -f1)"
  (( tests_run += 1 ))
  (( commit_line < remove_line )) ||
    fail "quick fix must commit the orphan before removing it"
  (( tests_run += 1 ))
  ! grep -q 'failed to lock file' "$temp_dir/error" ||
    fail "quick fix must suppress the low-level nonblocking flock error"

  rm -rf "$temp_dir"
}

test_commit_failure_preserves_container
test_commit_success_removes_container
test_quick_fix_keeps_lock_file
test_flatten_returns_cleanly_and_releases_lock
test_quick_fix_saves_and_stops_idle_container
test_quick_fix_recovers_interrupted_session
test_quick_fix_refuses_active_session
test_quick_fix_commits_before_removing_orphan_with_busy_lock

print -r -- "PASS: $tests_run lifecycle assertions"
