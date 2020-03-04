#!/usr/bin/env bash

export PATH="${PATH}:/etc/zabbix/bin"

REPO_SYNC_INTERVAL=${REPO_SYNC_INTERVAL:-7200}

usage() {
  echo "Usage: $(basename "$0") last|list|count"
}

_chroot() {
  if [[ -e /.dockerenv ]]
  then
    sudo -E chroot.sh bash -c "$*"
  else
    eval "$@"
  fi
}

arch_pkg() {
  if _chroot command -v yay > /dev/null
  then
    _chroot yay "$@"
  else
    _chroot pacman "$@"
  fi
}

arch_get_pkg_updates() {
  arch_pkg -Qu 2>/dev/null
}

ubuntu_get_pkg_updates() {
  _chroot \
    apt list --upgradable 2>/dev/null | grep -v '^Listing...'
}

arch_repo_sync() {
  local last_sync now tdiff

  last_sync=$(arch_get_last_repo_sync_ts)
  now="$(date '+%s')"

  tdiff=$(( now - last_sync ))
  # echo "$now - $last_sync = $tdiff vs $REPO_SYNC_INTERVAL"
  if [[ "$tdiff" -gt "$REPO_SYNC_INTERVAL" ]]
  then
    # echo "Syncing repos..." >&2
    arch_pkg -Syy >/dev/null 2>&1
  else
    # echo "No need to sync." >&2
    :
  fi
}

ubuntu_repo_sync() {
  local cfile now tdiff last_sync

  cfile="$(_ubuntu_get_cache_file)"
  last_sync="$(ubuntu_get_last_repo_sync_ts)"
  now="$(date '+%s')"

  tdiff=$(( now - last_sync ))
  # echo "$now - $last_sync = $tdiff vs $REPO_SYNC_INTERVAL"
  if [[ "$tdiff" -gt "$REPO_SYNC_INTERVAL" ]]
  then
    _chroot apt-get update >/dev/null 2>&1
    echo "$now" > "$cfile"
  fi
}

_ubuntu_get_cache_file() {
  echo "/tmp/$(basename "$0")_last_sync"
}

ubuntu_get_last_repo_sync_ts() {
  local cfile

  cfile="$(_ubuntu_get_cache_file)"
  if ! [[ -e "$cfile" ]]
  then
    echo -1
    return 1
  fi
  cat "$cfile"
}

ubuntu_get_last_upgrade_ts() {
  echo "Not supported yet."
}

arch_pkg_updates_count() {
  arch_get_pkg_updates | wc -l
}

ubuntu_pkg_updates_count() {
  ubuntu_get_pkg_updates | wc -l
}

arch_get_last_upgrade_ts() {
  pacman_log_extract_date_ts "starting full system upgrade"
}

arch_get_last_repo_sync_ts() {
  pacman_log_extract_date_ts "synchronizing package lists"
}

pacman_log_extract_date_ts() {
  local d
  d=$(_chroot grep "'$*'" /var/log/pacman.log | \
    tail -1 | sed -nr 's/^\[([^]]+)\].*/\1/p')
  if [[ -z "$d" ]]
  then
    echo "Failed to determine last update time" >&2
    return 2
  fi
  date -d "$d" '+%s'
}

determine_os() {
  _chroot cat /etc/os-release | sed -nr 's/^ID=(.+)/\1/p'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  HOST_ID="$(determine_os)"

  case "$1" in
    help|h|--help|-h)
      usage
      ;;
    count|c|--count|-c)
      ACTION=count
      ;;
    last|last_update|last-update|l|lu|-l|--last|--last-update)
      ACTION=last
      ;;
    last_repo_sync|lrs|-L|--last-repo-sync|--lrs)
      ACTION=last_repo_sync
      ;;
    list|ls|--ls|--list|--list-available-updates)
      ACTION=list
      ;;
    *)
      usage
      exit 2
  esac

  case "$HOST_ID" in
    arch)
      fn=arch
      ;;
    ubuntu|debian|raspbian)
      fn=ubuntu
      ;;
  esac

  ${fn}_repo_sync

  case "$ACTION" in
    count)
      ${fn}_pkg_updates_count
      ;;
    last)
      ${fn}_get_last_upgrade_ts
      ;;
    last_repo_sync)
      ${fn}_get_last_repo_sync_ts
      ;;
    list)
      ${fn}_get_pkg_updates
      ;;
  esac
fi
