#!/usr/bin/env bash
# Observe the packaged app in a fresh desktop session.
set -euo pipefail

evidence_root=${1:?An evidence directory is required}
shift
[[ $# -gt 0 ]] || { echo 'A launch command is required' >&2; exit 2; }
startup_seconds=${OCIDECK_PROBE_STARTUP_SECONDS:-20}
settle_seconds=${OCIDECK_PROBE_SETTLE_SECONDS:-3}
session_seconds=45
[[ "$startup_seconds" =~ ^[1-9][0-9]?$ && "$settle_seconds" =~ ^[1-9][0-9]?$ ]] || exit 2

mkdir -p -- "$evidence_root"
evidence=$(mktemp -d "$evidence_root/start.XXXXXX")
profile=$(mktemp -d)
probe_pid=
session_ready="$evidence/session-ready"
log_dir="$profile/data/com.dewinter.ocideck/logs"

snapshot_log() {
  local log
  for log in "$log_dir/ocideck.1.log" "$log_dir/ocideck.log"; do
    if [[ -f "$log" ]]; then cat -- "$log"; fi
  done
}

# The EXIT trap calls this function.
# shellcheck disable=SC2329
finish() {
  local result=$?
  trap - EXIT
  if [[ -n "$probe_pid" ]]; then
    kill -TERM "$probe_pid" 2>/dev/null || true
    wait "$probe_pid" 2>/dev/null || true
  fi
  if (( result != 0 )); then
    cat "$evidence/stdout.log" "$evidence/stderr.log" "$evidence/ocideck.log" >&2
  fi
  rm -rf -- "$profile"
  exit "$result"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

export HOME="$profile" XDG_DATA_HOME="$profile/data" XDG_CONFIG_HOME="$profile/config"
export XDG_CACHE_HOME="$profile/cache" XDG_STATE_HOME="$profile/state" XDG_RUNTIME_DIR="$profile/runtime"
unset DISPLAY WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS GNOME_KEYRING_CONTROL
export GDK_BACKEND=x11
mkdir -p -- "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"
install -d -m 0700 "$XDG_RUNTIME_DIR"

# The app reads Secret Service during startup. D-Bus activates the disposable
# session's provider before we launch, so a real keychain error stays fatal.
# The positional parameters below belong to the shell inside the session.
# shellcheck disable=SC2016
timeout --kill-after=3s "$((session_seconds + startup_seconds + settle_seconds + 4))s" \
  xvfb-run -a dbus-run-session -- bash -ec '
    ready=$1
    shift
    gdbus call --session --timeout 5 --dest org.freedesktop.secrets \
      --object-path /org/freedesktop/secrets \
      --method org.freedesktop.DBus.Peer.Ping >/dev/null
    : > "$ready"
    exec "$@"
  ' linux-start-probe "$session_ready" "$@" >"$evidence/stdout.log" 2>"$evidence/stderr.log" &
probe_pid=$!
session_deadline=$((SECONDS + session_seconds))
start_deadline=0
frame_seen=0
settle_deadline=0
while kill -0 "$probe_pid" 2>/dev/null; do
  snapshot_log > "$evidence/ocideck.log"
  if (( start_deadline == 0 )); then
    if [[ -f "$session_ready" ]]; then
      start_deadline=$((SECONDS + startup_seconds))
    elif (( SECONDS >= session_deadline )); then
      echo 'The desktop session did not become ready by the deadline' >&2
      exit 1
    fi
  fi
  if grep -Eq '^[^[:space:]]+ (ERROR |WARN opstart: nog geen eerste frame na 10 s($| ))' "$evidence/ocideck.log"; then
    echo 'OciDeck reported a startup error' >&2
    exit 1
  fi
  if (( frame_seen == 0 )) && grep -Eq '^[^[:space:]]+ INFO opstart: eerste frame \(\+[0-9]+ ms\)$' "$evidence/ocideck.log"; then
    frame_seen=1
    settle_deadline=$((SECONDS + settle_seconds))
  fi
  if (( frame_seen && SECONDS >= settle_deadline )); then
    echo "OciDeck rendered its first frame and stayed running. Evidence: $evidence"
    exit 0
  fi
  if (( !frame_seen && start_deadline && SECONDS >= start_deadline )); then
    echo 'OciDeck did not record a first rasterized frame by the deadline' >&2
    exit 1
  fi
  sleep 0.25
done

snapshot_log > "$evidence/ocideck.log"
result=0
wait "$probe_pid" || result=$?
probe_pid=
echo "OciDeck or its desktop session exited early (status $result)" >&2
exit 1
