#!/usr/bin/env bash
# Update copies of the existing Arch images with the matching BOE device layer.
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
base=$(realpath "${1:?base artifact directory}")
kernel=$(realpath "${2:?BOE kernel artifact directory}")
out=${3:?output directory}
mkdir -p "$out"
out=$(realpath "$out")
work=$(mktemp -d)
mounted=0
cleanup() {
  if [ "$mounted" = 1 ]; then umount "$work/root" || return; fi
  rm -rf "$work"
}
trap cleanup EXIT
test "$(id -u)" = 0 || { echo 'Run as root in the disposable Linux CI runner.' >&2; exit 1; }
test "$(uname -m)" = aarch64
prefix=TB321FU-archlinuxarm-plasma-aarch64
new_prefix=$prefix-boe
mkdir "$work/raw" "$work/kernel" "$work/root"
(cd "$kernel" && sha256sum -c SHA256SUMS.txt --ignore-missing)
tar -xzf "$kernel/kernel-artifacts.tar.gz" -C "$work/kernel"
release=$(cat "$work/kernel/kernel-release.txt")
test "$release" = '7.1.1-tb321fu-boe1'
find_archive() {
  local name=$1
  mapfile -t matches < <(find "$base" -type f -name "$name")
  test "${#matches[@]}" = 1 || { echo "Expected one $name" >&2; return 1; }
  printf '%s\n' "${matches[0]}"
}
boot=$(find_archive boot.img.7z)
grub=$(find_archive "$prefix-grub-fat.img.7z")
rootfs=$(find_archive "$prefix-rootfs.img.7z")
printf '%s  %s\n' \
  a9c2e176b34d3205f8f71b5819c58d215dcb993395191d8d44f37d922f592b02 "$boot" \
  9a5655212da2ed1874a7704b32bfe0c00658947337604569d5ee4b8910e2e37a "$grub" \
  8cd17f39668e2c3fe27d399713b326735416ce7e91f54feb04acdfc2b4e16020 "$rootfs" | sha256sum -c -
for archive in "$boot" "$grub" "$rootfs"; do
  7z e -y -bsp0 "-o$work/raw" "$archive"
done
test "$(stat -c %s "$work/raw/$prefix-rootfs.img")" = 21474836480
test "$(stat -c %s "$work/raw/$prefix-grub-fat.img")" = 268435456
test "$(stat -c %s "$work/raw/boot.img")" = 100663296
mount -o loop "$work/raw/$prefix-rootfs.img" "$work/root"
mounted=1
# The source image's filesystem root may belong to its desktop user. Keep
# Android storage ancestors protected without changing ownership recursively.
chown 0:0 "$work/root"
test "$(stat -c %u:%g "$work/root")" = 0:0
test "$((8#$(stat -c %a "$work/root") & 0022))" -eq 0
tar -xzf "$kernel/modules-overlay.tar.gz" -C "$work/root"
depmod -b "$work/root" "$release"
test -f "$work/root/usr/lib/modules/$release/extra/aw86937-haptics.ko"
test "$(modinfo -F vermagic "$work/root/usr/lib/modules/$release/extra/aw86937-haptics.ko" | cut -d' ' -f1)" = "$release"
firmware=usr/lib/firmware/qcom/sm8650/lenovo/tb321fu/novatek_ts_boe_fw.bin
if [ ! -s "$work/root/$firmware" ]; then
  curl -fL --retry 3 'https://github.com/enij90/firmware-lenovo-tb321fu/releases/download/v2026.10.15/firmware-lenovo-tb321fu-2026.10.15.tar.gz' -o "$work/firmware.tar.gz"
  echo "951b797a2372abbccb8c5b930de6d34f7e79ad17f893ab2a1975459613c4ea7f  $work/firmware.tar.gz" | sha256sum -c -
  mapfile -t entries < <(tar -tzf "$work/firmware.tar.gz" | grep -E '(^|/)usr/lib/firmware/qcom/sm8650/lenovo/tb321fu/novatek_ts_boe_fw.bin$')
  test "${#entries[@]}" = 1
  mkdir -p "$(dirname "$work/root/$firmware")"
  tar -xOzf "$work/firmware.tar.gz" "${entries[0]}" > "$work/root/$firmware"
  test -s "$work/root/$firmware"
fi
boe_firmware_hash=$(sha256sum "$work/root/$firmware" | cut -d' ' -f1)
test -f "$work/root/usr/lib/modules/$release/modules.dep"
echo "9397719683cf6acd6cf4c16888f516ed0209e3d6866baeff9e3151deb9caa61d  $work/root/$firmware" | sha256sum -c -
sync
umount "$work/root"
mounted=0
# e2fsck returns 1 for corrections; anything larger needs investigation.
set +e
e2fsck -f -p "$work/raw/$prefix-rootfs.img"
fsck_status=$?
set -e
test "$fsck_status" -le 1
mkdir "$work/grub"
env OUTPUT_DIR="$work/grub" OUTPUT_PREFIX="$new_prefix" \
  BOOT_TEMPLATE_IMAGE="$work/raw/$prefix-grub-fat.img" \
  KERNEL_ARTIFACT_ARCHIVE="$kernel/kernel-artifacts.tar.gz" \
  DTB_NAME=sm8650-lenovo-tb321fu.dtb ROOT_SELECTOR=partlabel \
  ROOT_PARTLABEL=userdata STABLEARGS=drm_client_lib.active=none \
  BOOT_COMPRESS=none KEEP_BOOT_IMAGE=1 \
  bash "$repo/scripts/ci/build-grub-image.sh"
cp "$work/raw/boot.img" "$out/boot.img"
mv "$work/raw/$prefix-rootfs.img" "$out/$new_prefix-rootfs.img"
cp "$work/grub/$new_prefix-grub-fat.img" "$out/$new_prefix-grub-fat.img"
cat > "$out/BUILD-INFO.txt" <<INFO
source_run=40177430328
source_rootfs_sha256=35a22cb30fe49882dbbc7c9033b299af3bada4f9b9f871bf8eb6efa6b4d98cb7
kernel=$release
panel=BOE
boe_touch_firmware_sha256=$boe_firmware_hash
rootfs_accounts_and_passwords=preserved_from_source_image
hardware_tested=no
INFO
cd "$out"
sha256sum boot.img "$new_prefix-grub-fat.img" "$new_prefix-rootfs.img" > RAW-SHA256SUMS.txt
for image in boot.img "$new_prefix-grub-fat.img" "$new_prefix-rootfs.img"; do
  7z a -t7z -mx=3 -mmt=on "$image.7z" "$image"
done
sha256sum *.7z RAW-SHA256SUMS.txt BUILD-INFO.txt > SHA256SUMS.txt
# Artifacts contain only compressed images and metadata.
rm boot.img "$new_prefix-grub-fat.img" "$new_prefix-rootfs.img"
