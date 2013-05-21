#!/bin/ksh
##
## ZFS backup script
## Copyright (c) 2011-2013 SATOH Fumiyasu @ OSS Technology Corp., Japan
##               https://github.com/fumiyas/zfs-backup
##               https://twitter.com/satoh_fumiyasu
##
## License: GNU General Public License version 3
## Date: 2012-01-18, since 2011-01-28
##

if ! PATH= type builtin >/dev/null 2>&1; then
  if [[ -x "/bin/ksh93" ]]; then
    exec /bin/ksh93 "$0" "$@"
    exit 1
  fi
  if [[ -x "/bin/zsh" ]]; then
    exec /bin/zsh "$0" "$@"
    exit 1
  fi
  echo "$0: ERROR: ksh93 or zsh required"
  exit 1
fi

if [[ -n "$ZSH_VERSION" ]] && [[ $(emulate 2>/dev/null) != "ksh" ]]; then
  sh_opts="$-"
  emulate -R ksh
  [[ -z "${sh_opts##*x*}" ]] && set -x
  unset sh_opts
fi

## ======================================================================

set -u

export LC_ALL="C"
export PATH="/usr/xpg4/bin:/usr/bin:/bin:/usr/sbin:/sbin"

pinfo()
{
  print -r "$0: INFO: $1" 1>&2
}

perr()
{
  print -r "$0: ERROR: $1" 1>&2
}

pdie()
{
  perr "$1"
  exit "${2-1}"
}

if ! type tac >/dev/null 2>&1; then
  alias tac='tail -r'
fi

function run_on
{
  typeset no_run_flag=""
  typeset verbose_flag=""
  [[ "$1" = "-n" ]] && { no_run_flag="set"; shift; }
  [[ "$1" = "-v" ]] && { verbose_flag="set"; shift; }
  typeset host="$1"; shift

  if [[ -n "$host" ]] && [[ "$host" != "localhost" ]]; then
    set -- "${@//\\/\\\\}"
    set -- "${@//\$/\\\$}"
    set -- "${@//\`/\\\`}"
    set -- "${@//\"/\\\"}"
    typeset -a args
    typeset arg
    for arg in "$@"; do
      args[${#args[@]}]=\""$arg"\"
    done

    set -- ${ZFS_BACKUP_SSH_COMMAND:-ssh} \
      -C \
      ${ZFS_BACKUP_SSH_CONFIG_FILE:+-F "$ZFS_BACKUP_SSH_CONFIG_FILE"} \
      ${ZFS_BACKUP_SSH_BIND_ADDRESS:+-b "$ZFS_BACKUP_SSH_BIND_ADDRESS"} \
      ${ZFS_BACKUP_SSH_IDENTITY_FILE:+-i "$ZFS_BACKUP_SSH_IDENTITY_FILE"} \
      ${ZFS_BACKUP_SSH_CIPHER_SPEC:+-c "$ZFS_BACKUP_SSH_CIPHER_SPEC"} \
      "$host" "${args[@]}"
  fi

  if [[ -n "$verbose_flag" ]]; then
    pinfo "$*"
  fi

  if [[ -n "$no_run_flag" ]]; then
    return 0
  fi

  "$@"
  return $?
}

function zfs_list_snapshot
{
  typeset host="$1"; shift
  typeset zfs_trunk="$1"; shift
  typeset zfs_ss_glob="$1"; shift
  typeset ignore_count="${1-}"
  typeset count="0"
  typeset zfs_ss

  run_on \
    "$host" \
    /sbin/zfs list -r -t snapshot -H -o name -s creation "$zfs_trunk" \
  2>/dev/null \
  |tac \
  |while read -r zfs_ss && [[ -n "$zfs_ss" ]]; do
    typeset zfs="${zfs_ss%@*}"
    [[ "$zfs" = "$zfs_trunk" ]] || continue
    typeset zfs_ss_name="${zfs_ss##*@}"
    [[ "$zfs_ss_name" = @($zfs_ss_glob) ]] || continue
    let count++
    [[ -n "$ignore_count" ]] && [[ "$count" -le "$ignore_count" ]] && continue

    print -r "$zfs_ss"
  done
}

function zfs_canonical_name
{
  typeset host="$1"; shift
  typeset zfs_name="$1"; shift

  case "$zfs_name" in
  /*)
    zfs_mountpoint="$zfs_name"
    zfs_name=""
    run_on \
      "$host" \
      /sbin/zfs get -H -o name,value mountpoint \
    |while read -r zfs_name_c zfs_mountpoint_c; do
      if [[ $zfs_mountpoint_c = $zfs_mountpoint ]]; then
	zfs_name="$zfs_name_c"
	break
      fi
    done
    if [[ -z $zfs_name ]]; then
      pdie "$host: ZFS not found for mount point: $zfs_mountpoint"
    fi
    ;;
  *)
    zfs_mountpoint=$(run_on "$host" /sbin/zfs get -H -o value mountpoint "$zfs_name")
    if [[ -z $zfs_mountpoint ]]; then
      pdie "$host: ZFS not found: $zfs_name"
    fi
    ;;
  esac

  echo "$zfs_name $zfs_mountpoint"
}

## ======================================================================

no_run_flag=""
verbose_flag=""
recursive_flag=""
property_flag=""
zfs_ss_format='%Y-%m-%dT%H:%M:%S'
zfs_ss_glob='20[0-9][0-9]-[01][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-6][0-9]'
zfs_ss_time=$(unset TZ; date "+$zfs_ss_format")
target_zfs_ss_count_limit="31"
backup_zfs_ss_count_limit="31"

cmd_usage="Usage: $0 [OPTIONS] TARGET BACKUP

Options:
 -n, --no-run
    Dry run mode
 -v, --verbose
    Verbose output
 -N, --no-create-snapshot
    Do not create new snapshot
 -R, --recursive
    Recursively backup all children
 -p, --property
    Backup properties
 -t, --target-snapshot-limit NUMBER
    Maximam number of snapshots for the target ZFS
    (default: $target_zfs_ss_count_limit)
 -b, --backup-snapshot-limit NUMBER
    Maximam number of snapshots for the backup ZFS
    (default: $backup_zfs_ss_count_limit)
"

function getopts_want_arg
{
  if [ $# -lt 2 ]; then
    pdie "Option requires an argument: $1"
  fi

  if [ $# -eq 2 ]; then
    return 0
  fi

  typeset opt="$1"; shift
  typeset value="$1"; shift
  typeset glob
  for glob in "$@"; do
    case "$value" in
    $glob)
      return 0
      ;;
    esac
  done

  pdie "Invalid value for option: $opt $value"
}

while [ "$#" -gt 0 ]; do
  OPT="$1"; shift
  if [[ -z "${OPT##--*=*}" ]]; then
    set -- "${OPT#--*=}" ${1+"$@"}
    OPT="${OPT%%=*}"
  fi
  case "$OPT" in
  -n|--no-run)
    no_run_flag="set"
    ;;
  -v|--verbose)
    verbose_flag="set"
    ;;
 -N|--no-create-snapshot)
    zfs_ss_time=""
    ;;
 -R|--recursive)
    recursive_flag="set"
    ;;
 -p|--property)
    property_flag="set"
    ;;
 -t|--target-snapshot-limit)
    getopts_want_arg "$OPT" ${1+"$1"}
    if [[ -z "$1" ]] || [[ "$1" = @([!0-9]) ]]; then
      pdie "Invalid value for option: $OPT $1"
    fi
    target_zfs_ss_count_limit="$1"; shift
    ;;
 -b|--backup-snapshot-limit)
    getopts_want_arg "$OPT" ${1+"$1"}
    if [[ -z "$1" ]] || [[ "$1" = @([!0-9]) ]]; then
      pdie "Invalid value for option: $OPT $1"
    fi
    backup_zfs_ss_count_limit="$1"; shift
    ;;
  --)
    break
    ;;
  -*)
    pdie "Invalid option: $OPT"
    ;;
  *)
    set -- "$OPT" ${1+"$@"}
    break
    ;;
  esac
done

if [[ "$#" -ne 2 ]]; then
  print -r "$cmd_usage"
  exit 1
fi

target_zfs="$1"; shift
backup_zfs_base="$1"; shift

## ======================================================================

target_host="localhost"
if [[ -z "${target_zfs##*:*}" ]]; then
  print -r "$target_zfs" |IFS=: read -r target_host target_zfs
fi

zfs_canonical_name "$target_host" "$target_zfs" \
|read -r target_zfs target_zfs_mountpoint \
|| exit 1

backup_host="localhost"
if [[ -z "${backup_zfs_base##*:*}" ]]; then
  print -r "$backup_zfs_base" |IFS=: read -r backup_host backup_zfs_base
fi

zfs_canonical_name "$backup_host" "$backup_zfs_base" \
|read -r backup_zfs_base backup_zfs_base_mountpoint \
|| exit 1

backup_zfs="$backup_zfs_base/${target_zfs#*/}"

if [[ $backup_zfs_base_mountpoint = - ]]; then
  backup_zfs_mountpoint="-"
else
  backup_zfs_mountpoint="$backup_zfs_base_mountpoint/${target_zfs#*/}"
fi

## Check if the target ZFS exists
## ----------------------------------------------------------------------

e=$(run_on "$target_host" /sbin/zfs list -H -o name "$target_zfs" 2>&1 >/dev/null)
if [[ $? -ne 0 ]]; then
  pdie "$target_host: $e"
fi

## Check if the backup ZFS exists
## ----------------------------------------------------------------------

e=$(run_on "$backup_host" /sbin/zfs list -H -o name "$backup_zfs_base" 2>&1 >/dev/null)
if [[ $? -ne 0 ]]; then
  pdie "$backup_host: $e"
fi

## Determine snapshot names
## ======================================================================

if [[ -n "$zfs_ss_time" ]]; then
  target_zfs_ss_last="$target_zfs@$zfs_ss_time"
  target_zfs_ss_new="$target_zfs_ss_last"
else
  zfs_list_snapshot \
    "$target_host" \
    "$target_zfs" \
    "$zfs_ss_glob" \
  |head -n 1 \
  |read -r zfs_ss
  if [[ -z "$zfs_ss" ]]; then
    pdie "$taget_host: No ZFS snapshot found: $target_zfs"
  fi
  zfs_ss_time="${zfs_ss##*@}"
  target_zfs_ss_last="$target_zfs@$zfs_ss_time"
  target_zfs_ss_new=""
fi

backup_zfs_ss_new="$backup_zfs@$zfs_ss_time"

## ----------------------------------------------------------------------

target_zfs_ss_prev=""
backup_zfs_ss_prev=""

zfs_list_snapshot \
  "$backup_host" \
  "$backup_zfs" \
  "$zfs_ss_glob" \
|while read -r zfs_ss; do
  target_zfs_ss="$target_zfs@${zfs_ss##*@}"
  if run_on "$target_host" /sbin/zfs list "$target_zfs_ss" >/dev/null 2>&1; then
    target_zfs_ss_prev="$target_zfs_ss"
    backup_zfs_ss_prev="$zfs_ss"
    break
  fi
done

## ----------------------------------------------------------------------

if [[ "$target_zfs_ss_prev" = "$target_zfs_ss_last" ]]; then
  pdie "$backup_host: Backup is already updated"
fi

## ======================================================================

if [[ -n "$verbose_flag" ]]; then
  echo "Target:"
  echo "  Host:			$target_host"
  echo "  Mount point:		$target_zfs_mountpoint"
  echo "  ZFS:			$target_zfs"
  echo "  New snapshot:		${target_zfs_ss_new:-$target_zfs_ss_last}"
  echo "  Previous snapshot:	${target_zfs_ss_prev:--}"
  echo "Backup:"
  echo "  Host:			$backup_host"
  echo "  Mount point:		$backup_zfs_mountpoint"
  echo "  ZFS:			$backup_zfs"
  echo "  New snapshot:		$backup_zfs_ss_new"
  echo "  Previous snapshot:	${backup_zfs_ss_prev:--}"
fi

## Create new snapshot ZFS for the target ZFS
## ----------------------------------------------------------------------

if [[ -n "$target_zfs_ss_new" ]]; then
  e=$(
    run_on \
      ${no_run_flag:+-n} \
      ${verbose_flag:+-v} \
      "$target_host" \
      /sbin/zfs snapshot "$target_zfs_ss_new" 2>&1
  )
  if [[ $? -ne 0 ]]; then
    pdie "$target_host: $e"
  fi
  [[ -n "$e" ]] && print -r "$e" 1>&2
fi

## ZFS send and receive
## ----------------------------------------------------------------------

run_on \
  ${no_run_flag:+-n} \
  ${verbose_flag:+-v} \
  "$target_host" \
  /sbin/zfs send \
    ${verbose_flag:+-v} \
    ${recursive_flag:+-R} \
    ${property_flag:+-p} \
    ${target_zfs_ss_prev:+-i "$target_zfs_ss_prev"} \
    "$target_zfs_ss_last" \
|run_on \
  ${no_run_flag:+-n} \
  ${verbose_flag:+-v} \
  "$backup_host" \
  /sbin/zfs receive \
    ${verbose_flag:+-v} \
    -dF \
    "$backup_zfs_base" \
  ;
if [[ $? -ne 0 ]]; then
  pdie "ZFS send and/or receive failed"
fi

## Remove old snapshot on the target ZFS
## ----------------------------------------------------------------------

if [[ "$target_zfs_ss_count_limit" -ge 1 ]]; then
  zfs_list_snapshot \
    "$target_host" \
    "$target_zfs" \
    "$zfs_ss_glob" \
    "$target_zfs_ss_count_limit" \
  |while read -r zfs_ss && [[ -n "$zfs_ss" ]]; do
    run_on \
      ${no_run_flag:+-n} \
      ${verbose_flag:+-v} \
      "$target_host" \
      /sbin/zfs destroy  \
	${recursive_flag:+-r} \
	"$zfs_ss" \
      ;
  done
fi

## Remove old snapshot on the backup ZFS
## ----------------------------------------------------------------------

if [[ "$backup_zfs_ss_count_limit" -ge 1 ]]; then
  zfs_list_snapshot \
    "$backup_host" \
    "$backup_zfs" \
    "$zfs_ss_glob" \
    "$backup_zfs_ss_count_limit" \
  |while read -r zfs_ss && [[ -n "$zfs_ss" ]]; do
    run_on \
      ${no_run_flag:+-n} \
      ${verbose_flag:+-v} \
      "$backup_host" \
      /sbin/zfs destroy \
	${recursive_flag:+-r} \
	"$zfs_ss" \
      ;
  done
fi

## ----------------------------------------------------------------------

exit 0
