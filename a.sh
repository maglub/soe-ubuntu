new=Image.iso
source_iso=ubuntu-22.04-beta-live-server-amd64.iso
mbr=ubuntu-22.04-beta-live-server-amd64.mbr
efi=ubuntu-22.04-beta-live-server-amd64.efi

disk_title=soe-ubuntu-22

# Extract the MBR template
dd if="$source_iso" bs=1 count=446 of="$mbr"

# Extract EFI partition image
skip=$(/sbin/fdisk -l "$source_iso" | fgrep '.iso2 ' | awk '{print $2}')
size=$(/sbin/fdisk -l "$source_iso" | fgrep '.iso2 ' | awk '{print $4}')
dd if="$source_iso" bs=512 skip="$skip" count="$size" of="$efi"

xorriso -as mkisofs \
  -r -V "$disk_title" -J -joliet-long -l \
  -iso-level 3 \
  -partition_offset 16 \
  --grub2-mbr "$mbr" \
  --mbr-force-bootable \
  -append_partition 2 0xEF "$efi" \
  -appended_part_as_gpt \
  -c /boot.catalog \
  -b /boot/grub/i386-pc/eltorito.img \
    -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info \
  -eltorito-alt-boot \
  -e '--interval:appended_partition_2:all::' \
    -no-emul-boot \
  -o "$new" \
  work.22
