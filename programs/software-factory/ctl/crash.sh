# crash-log: the kernel crash dumps the root unit factory-crash-log copied out
# of pstore at boot (programs/software-factory/ops/crash-log.sh). Read-only.

# How much of the newest dump to show: the panic and the trace above it.
crash_tail_lines=80

cmd_crash_log() {
  local dumps newest dump
  # The directory is missing until the unit has run once.
  dumps=$(find "$crash_dir" -maxdepth 1 -name '*.txt' -printf '%T@ %f\n' 2>/dev/null | sort -rn | cut -d ' ' -f 2-) || true
  if [ -z "$dumps" ]; then
    echo "No kernel crash dumps saved."
    return 0
  fi
  echo "Kernel crash dumps, newest first ($crash_dir):"
  while read -r dump; do
    echo "  $dump  $(date -r "$crash_dir/$dump" '+%F %H:%M %Z')"
  done <<<"$dumps"
  newest=$(head -n 1 <<<"$dumps")
  echo
  echo "Last $crash_tail_lines lines of $newest:"
  tail -n "$crash_tail_lines" "$crash_dir/$newest"
}
