# The Omen's 1 TB SSD, addressed by id so a USB stick plugged in at install time
# can never be the one wiped. An ESP for systemd-boot and an unencrypted root:
# an encrypted one would need someone at the keyboard after every reboot.
{
  disko.devices.disk.main = {
    type = "disk";
    # TODO(omen): read from `ls -l /dev/disk/by-id` on the box's Ubuntu.
    device = "/dev/disk/by-id/TODO-omen-ssd";
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
