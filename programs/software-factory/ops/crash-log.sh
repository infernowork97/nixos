# Copies the kernel crash dumps systemd-pstore archived, root-only, into a
# directory the agent account can read, for `factory-ctl crash-log`. Runs as
# root at boot and takes no input. A dump is <id>/<part>/dmesg.txt, so its copy
# is <id>-<part>.txt; copying again overwrites it with the same content.
main() {
  local dump part id
  install -d -m 0755 "$crash_dir"
  for dump in "$pstore_dir"/*/*/dmesg.txt; do
    [ -f "$dump" ] || continue
    part=$(dirname "$dump")
    id=$(basename "$(dirname "$part")")
    install -m 0644 -p "$dump" "$crash_dir/$id-$(basename "$part").txt"
  done
}

main
