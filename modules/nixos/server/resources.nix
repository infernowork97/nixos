# Memory, CPU and disk budgets, sized by myConfig.factory.size. Agents compiling
# Haskell and Next.js can exhaust any of these sizes; the limits make sure the
# box degrades by killing a build, not sshd or tailscaled.
{ config, lib, ... }:
let
  uid = toString config.users.users.${config.myConfig.user.name}.uid;
  gib = n: n * 1024 * 1024 * 1024;

  # One row per machine size. Each memory budget stays below physical RAM, so
  # the agents and the Nix daemon together still leave room for the system.
  sizes = {
    # 2 vCPU, 4 GB, 40-80 GB disk (e.g. Hetzner CPX22). One agent session at a
    # time; the swapfile carries the rest.
    small = {
      agents = {
        high = "2560M";
        max = "3G";
      };
      builds = {
        high = "2G";
        max = "2560M";
        jobs = 1;
        cores = 2;
      };
      disk = {
        minFree = 5;
        maxFree = 15;
      };
    };

    # 4 cores / 8 threads, 12 GB, 1 TB disk (the HP Omen 15-ax005). One build
    # at a time on six threads, leaving two for the agents so a deploy does not
    # stall live sessions; the agents get most of the memory, since idle Remote
    # Control servers cost about 70 MB each and a live session about 250 MB.
    # The caps overcommit RAM together, as `standard` does: zram and the
    # swapfile absorb the overlap, and oomd picks the victim.
    medium = {
      agents = {
        high = "9G";
        max = "9728M";
      };
      builds = {
        high = "5G";
        max = "6G";
        jobs = 1;
        cores = 6;
      };
      disk = {
        minFree = 20;
        maxFree = 60;
      };
    };

    # 8 vCPU, 16 GB, 160 GB disk (e.g. Hetzner CX43). Two builds at a time,
    # four cores each, leaving the agents themselves some.
    standard = {
      agents = {
        high = "12G";
        max = "13G";
      };
      builds = {
        high = "7G";
        max = "8G";
        jobs = 2;
        cores = 4;
      };
      disk = {
        minFree = 10;
        maxFree = 30;
      };
    };
  };

  size = sizes.${config.myConfig.factory.size};
in
{
  options.myConfig.factory.size = lib.mkOption {
    type = lib.types.enum (lib.attrNames sizes);
    description = ''
      The machine the server runs on, which sets its memory, build and disk
      limits. `small` is 2 vCPU / 4 GB, `medium` 4 cores / 8 threads / 12 GB (the
      HP Omen), `standard` 8 vCPU / 16 GB.
    '';
  };

  config = {
    zramSwap = {
      enable = true;
      algorithm = "zstd";
      memoryPercent = 50;
    };

    # Backstop for when zram is full.
    swapDevices = [
      {
        device = "/var/lib/swapfile";
        size = 8 * 1024;
      }
    ];

    nix.settings = {
      max-jobs = size.builds.jobs;
      cores = size.builds.cores;

      # Collect garbage during builds before the disk fills up.
      min-free = gib size.disk.minFree;
      max-free = gib size.disk.maxFree;
    };

    systemd = {
      # Agents leave build output in /tmp, `nix build` result links among it,
      # each an indirect GC root pinning its closure. Anything untouched for
      # three days goes, instead of systemd's default ten. tmpfiles applies the
      # first line for a path, and NixOS's 00-nixos.conf sorts before tmp.conf.
      tmpfiles.rules = [ "q /tmp 1777 root root 3d" ];

      # Under sustained memory pressure, oomd kills the heaviest process in a
      # user slice - in practice a compiler - instead of letting the kernel
      # choose.
      oomd = {
        enable = true;
        enableUserSlices = true;
      };

      # Everything the agent account runs: Claude Code, cabal, next build.
      slices."user-${uid}".sliceConfig = {
        MemoryHigh = size.agents.high;
        MemoryMax = size.agents.max;
      };

      # Nix builds run in the daemon's cgroup, not the user's, so they are
      # capped separately.
      services.nix-daemon.serviceConfig = {
        MemoryHigh = size.builds.high;
        MemoryMax = size.builds.max;
      };
    };
  };
}
