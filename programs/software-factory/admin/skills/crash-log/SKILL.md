---
name: crash-log
description: Show the kernel crash dumps the software factory saved from earlier boots, and the panic in the newest one. Use when the person asks why the box crashed, rebooted on its own, hung at boot or booted to a blank screen.
---

# Crash log

Run `factory-ctl crash-log`. It only reads.

- No dumps: say so. A boot that died without leaving a dump in pstore shows
  nothing here.
- Dumps: give the list in one line, then the panic from the newest one's
  tail: the `Kernel panic` line, the module or driver in the call trace, and
  the `RIP` line. Quote those lines as they are; do not paraphrase a trace.
  Point at the full file it names under `/var/lib/factory-ops/crash/` for more.
