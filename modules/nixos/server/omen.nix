# HP Omen 15-ax005: i7-6700HQ (4 cores, 8 threads), 12 GB, a 1 TB NVMe SSD,
# Intel 7265 Wi-Fi, Realtek RTL8111 ethernet and an NVIDIA GTX 965M behind
# Optimus. It runs lid-closed at home, on Wi-Fi, plugged in; the battery
# doubles as a UPS.
{ config, ... }:
{
  boot = {
    initrd.availableKernelModules = [
      "xhci_pci"
      "ahci"
      "nvme"
      "usb_storage"
      "usbhid"
      "sd_mod"
      "rtsx_pci_sdmmc"
    ];
    kernelModules = [ "kvm-intel" ];

    loader = {
      systemd-boot = {
        enable = true;
        # The boot menu offers the two generations factory-gc keeps.
        configurationLimit = 2;
        # A RAM test in the boot menu, picked at the box with the lid open.
        # Early-boot oopses on a bad pointer point at memory corruption.
        memtest86.enable = true;
      };
      efi.canTouchEfiVariables = true;
    };

    # Headless: the dGPU is never used, and nouveau on Maxwell only adds
    # suspend and fan bugs. The iGPU drives the console.
    blacklistedKernelModules = [ "nouveau" ];

    # Nobody is at the box to power-cycle it, so a crash or a kernel lockup
    # reboots it 10s later instead of hanging. The BIOS disables the iTCO
    # hardware watchdog, so the kernel's NMI and soft-lockup detectors are
    # the only ones; a freeze they miss still needs a power-cycle.
    kernelParams = [
      "panic=10"
      "panic_on_oops=1"
      "softlockup_panic=1"
      "nmi_watchdog=panic"
    ];
  };

  # iwlwifi for the 7265 and rtl_nic for the RTL8111 are both in here.
  hardware = {
    enableRedistributableFirmware = true;
    cpu.intel.updateMicrocode = true;
  };

  # A server with its lid closed: never suspend, on any power source.
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
  };
  systemd.sleep.settings.Sleep = {
    AllowSuspend = "no";
    AllowHibernation = "no";
    AllowHybridSleep = "no";
    AllowSuspendThenHibernate = "no";
  };

  # Wi-Fi in normal operation, ethernet (DHCP, NetworkManager's default
  # profile) for the install and as a fallback. The SSID and PSK are both
  # secret: the repository is public and an SSID geolocates the house.
  networking.networkmanager = {
    enable = true;
    # DNS comes from the static nameservers below, never the router.
    dns = "none";
    ensureProfiles = {
      environmentFiles = [ config.sops.secrets.wifi-env.path ];
      profiles.home-wifi = {
        connection = {
          id = "home-wifi";
          type = "wifi";
          autoconnect = true;
        };
        wifi = {
          mode = "infrastructure";
          ssid = "$WIFI_SSID";
        };
        wifi-security = {
          key-mgmt = "wpa-psk";
          psk = "$WIFI_PSK";
        };
        ipv4.method = "auto";
        ipv6.method = "auto";
      };
    };
  };

  # WIFI_SSID=... and WIFI_PSK=..., read by NetworkManager's profile service.
  myConfig.secrets.wifi-env.owner = "root";

  # Public resolvers. A home router hands out its own LAN address as DNS, and
  # egress.nix bars the agent account from every private range, so anything
  # resolving without glibc (gh, other Go binaries) would fail against it.
  networking.nameservers = [
    "1.1.1.1"
    "9.9.9.9"
  ];

  # No timezone surprises in logs and commit dates.
  time.timeZone = "UTC";
}
