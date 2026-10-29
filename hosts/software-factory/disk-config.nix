# The Omen's 1 TB NVMe SSD, addressed by id so a USB stick plugged in at install time
# can never be the one wiped. An ESP for systemd-boot and an unencrypted root:
# an encrypted one would need someone at the keyboard after every reboot.
{
  disko.devices.disk.main = {
    type = "disk";
    # The 1 TB NVMe (CA5-8D1024), from `ls -l /dev/disk/by-id` on the box.
    device = "/dev/disk/by-id/nvme-NVMe_CA5-8D1024_00210650002E";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
