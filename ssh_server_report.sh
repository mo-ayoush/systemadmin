#!/usr/bin/env bash
# Check hosts declared in an OpenSSH client config and report remote health/authentication data.
set -uo pipefail

usage() {
  cat <<'EOF'
Usage: ssh_server_report.sh [-h] [-v] [-f CONFIG] [-o REPORT]

Options:
  -h            Show this help and exit.
  -f CONFIG     OpenSSH config file (default: ~/.ssh/config).
  -v            Show detailed output. Without -v, show a compact report.
  -o REPORT     Save report to this path as well as displaying it.
                Without -o, no report file is created.

The script checks each concrete Host alias in the config. SSH must be configured
for non-interactive authentication (for example, keys or ssh-agent). Authentication
log counts are read on the remote server; access to its journal/log files is needed.
EOF
}

config="${HOME}/.ssh/config"
verbose=0
output_file=""
while getopts ':hvf:o:' opt; do
  case "$opt" in
    h) usage; exit 0 ;;
    v) verbose=1 ;;
    f) config=$OPTARG ;;
    o) output_file=$OPTARG ;;
    :) printf 'Error: option -%s requires an argument.\n' "$OPTARG" >&2; usage >&2; exit 2 ;;
    \?) printf 'Error: unknown option -%s.\n' "$OPTARG" >&2; usage >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))
if (($#)); then printf 'Error: unexpected argument: %s\n' "$1" >&2; usage >&2; exit 2; fi
if [[ ! -r $config ]]; then printf 'Error: cannot read SSH config: %s\n' "$config" >&2; exit 1; fi

declare -a hosts=()
while IFS= read -r line; do
  # Host patterns may list several aliases; ignore wildcard/negated patterns.
  for alias in $line; do
    [[ $alias == \#* ]] && break
    [[ $alias == *'*'* || $alias == *'?'* || $alias == '!'* ]] && continue
    hosts+=("$alias")
  done
done < <(awk 'tolower($1)=="host" { $1=""; sub(/^[[:space:]]+/, ""); print }' "$config")

if ((${#hosts[@]} == 0)); then printf 'No concrete Host aliases found in %s.\n' "$config"; exit 1; fi

report="SSH server report — $(date '+%Y-%m-%d %H:%M:%S %Z')\nConfig: $config\n"
for host in "${hosts[@]}"; do
  report+="\n[$host]\n"
  if ! command -v ssh >/dev/null 2>&1; then
    report+="Status: FAILED — ssh client not found.\n"
    continue
  fi
  # Send the collector over stdin, avoiding interpolation of remote shell code.
  remote_output=$(ssh -T -o BatchMode=yes -o ConnectTimeout=8 -o ConnectionAttempts=1 \
    "$host" 'sh -s' 2>&1 <<'REMOTE_COLLECTOR'
set +e
printf 'REMOTE_UPTIME: '
uptime -p 2>/dev/null || uptime 2>/dev/null || echo unavailable
printf 'REMOTE_DISK:\n'
df -hP -- / 2>/dev/null | tail -n 1 || echo unavailable
logdata=''
if command -v journalctl >/dev/null 2>&1; then
  logdata=$(journalctl --no-pager -q -o cat -u ssh -u sshd 2>/dev/null)
fi
if [ -z "$logdata" ]; then
  for f in /var/log/auth.log /var/log/secure; do
    if [ -r "$f" ]; then logdata="$logdata
$(cat "$f" 2>/dev/null)"; fi
  done
fi
if [ -z "$logdata" ]; then
  echo 'SSH_LOGS: unavailable (no readable journal or auth log)'
else
  # Match sshd authentication outcomes; counts are log entries, not necessarily unique sessions.
  failed=$(printf '%s\n' "$logdata" | grep -Eic 'sshd.*(Failed password| authentication failure|Invalid user| maximum authentication attempts)' || true)
  succeeded=$(printf '%s\n' "$logdata" | grep -Eic 'sshd.*Accepted (password|publickey|keyboard-interactive)' || true)
  printf 'SSH_LOGS: readable\nSSH_FAILED: %s\nSSH_SUCCEEDED: %s\n' "$failed" "$succeeded"
fi
REMOTE_COLLECTOR
  )
  ssh_rc=$?
  if ((ssh_rc != 0)); then
    # Avoid a possibly multiline ssh diagnostic breaking the report layout.
    diagnostic=${remote_output//$'\n'/'; '}
    report+="Status: FAILED — SSH exit code $ssh_rc. Reason: ${diagnostic:-no diagnostic returned}\n"
    continue
  fi
  uptime_line=$(sed -n 's/^REMOTE_UPTIME: //p' <<<"$remote_output" | head -n 1)
  disk_line=$(sed -n '/^REMOTE_DISK:/{n;p;}' <<<"$remote_output" | head -n 1)
  fail_count=$(sed -n 's/^SSH_FAILED: //p' <<<"$remote_output" | head -n 1)
  success_count=$(sed -n 's/^SSH_SUCCEEDED: //p' <<<"$remote_output" | head -n 1)
  log_status=$(sed -n 's/^SSH_LOGS: //p' <<<"$remote_output" | head -n 1)
  report+="Status: OK\nUptime: ${uptime_line:-unavailable}\nDisk (/): ${disk_line:-unavailable}\n"
  if [[ -n $fail_count && -n $success_count ]]; then
    report+="SSH authentication log entries: failed=$fail_count, successful=$success_count\n"
  else
    report+="SSH authentication logs: ${log_status:-unavailable (no readable log data)}\n"
  fi
  if ((verbose)); then
    report+="\nDetailed remote output:\n$remote_output\n"
  fi
done

printf '%b' "$report"
if [[ -n $output_file ]]; then
  if ! printf '%b' "$report" >"$output_file"; then
    printf 'Error: could not write report to %s\n' "$output_file" >&2
    exit 1
  fi
fi
