#!/usr/bin/env bash
# Build a complete matching BOE kernel/module set. Never touches USB devices.
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
work=${BOE_WORK_DIR:-"$repo/out/boe-work"}
out=${BOE_OUTPUT_DIR:-"$repo/out/boe-kernel"}
base=5df8e852ea722929f5359a5ef28ebcec0c4443fd
haptics=f25d3a29d83a3c8a2f63bcc56306818e5973f994
profile=${BOE_KERNEL_PROFILE:-boe1}
case "$profile" in
  boe1) localversion=-tb321fu-boe1 ;;
  mobile) localversion=-tb321fu-boe2 ;;
  *) echo "Unsupported BOE kernel profile: $profile" >&2; exit 1 ;;
esac
mkdir -p "$work" "$out"
work=$(cd "$work" && pwd -P)
out=$(cd "$out" && pwd -P)
test "$(uname -m)" = aarch64 || { echo 'Use an ARM64 Linux runner.' >&2; exit 1; }
test ! -e "$work/linux" || { echo 'Use a fresh build directory.' >&2; exit 1; }
curl -fL --retry 3 "https://codeload.github.com/GUF296/linux/tar.gz/$base" -o "$work/linux.tar.gz"
mkdir "$work/linux"
tar -xzf "$work/linux.tar.gz" --strip-components=1 -C "$work/linux"
curl -fL --retry 3 'https://github.com/GUF296/ubuntu-y700-build-ci/releases/download/bootstrap-y700-20260625/y700-kernel-artifacts-7.1.1-g5df8e852ea72.tar.gz' -o "$work/base.tar.gz"
echo "86ea0190e3a073a8ce94e1d6f74dcc3482457a0b9161c2ff968aaeb0f1147188  $work/base.tar.gz" | sha256sum -c -
mkdir "$work/base" "$work/build"
tar -xzf "$work/base.tar.gz" -C "$work/base"
cd "$work/linux"
echo '9a0b46716f3afc3e7e8379a433010ad5d4f4280a5dd78d80b78ab8ec48a00906  drivers/gpu/drm/panel/panel-novatek-nt36523.c' | sha256sum -c -
# The vendor DTS has mixed line endings; normalize before applying a unified diff.
python3 - <<'PY'
from pathlib import Path
p = Path('arch/arm64/boot/dts/qcom/sm8650-lenovo-tb321fu.dts')
p.write_text(p.read_text())
PY
patch --dry-run -p1 < "$repo/source/boe/0001-tb321fu-add-boe-panel.patch"
patch -p1 < "$repo/source/boe/0001-tb321fu-add-boe-panel.patch"
cp "$work/base/kernel.config" "$work/build/.config"
export LOCALVERSION=
scripts/config --file "$work/build/.config" --set-str LOCALVERSION "$localversion" --disable LOCALVERSION_AUTO --disable DEBUG_INFO --enable DEBUG_INFO_NONE
if [ "$profile" = mobile ]; then
  KCONFIG_CONFIG="$work/build/.config" scripts/kconfig/merge_config.sh -m \
    "$work/build/.config" "$repo/source/boe/mobile-runtime.config"
fi
make O="$work/build" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
if [ "$profile" = mobile ]; then
  python3 "$repo/scripts/ci/check-kernel-fragment.py" \
    "$work/build/.config" "$repo/source/boe/mobile-runtime.config"
fi
release=$(make -s O="$work/build" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- kernelrelease)
test "$release" = "7.1.1$localversion"
make -j"$(nproc)" O="$work/build" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- Image modules qcom/sm8650-lenovo-tb321fu.dtb
stage="$work/modules"
make O="$work/build" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH="$stage" INSTALL_MOD_STRIP=1 modules_install
mkdir -p "$work/extra"
curl -fL --retry 3 "https://raw.githubusercontent.com/GUF296/tb321fu-haptics-debs/$haptics/haptics/daily-current/linux/drivers/input/misc/aw86937-y700.c" -o "$work/extra/aw86937-haptics.c"
python3 - "$work/extra/aw86937-haptics.c" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
old = '.name = "aw86937-y700"'
assert s.count(old) == 1
s = s.replace(old, '.name = "aw86937-haptics"')
old = '\t{ "aw86937_y700" },'
assert s.count(old) == 1
s = s.replace(old, '\t{ "aw86937_haptics" },\n' + old)
p.write_text(s)
PY
printf 'obj-m := aw86937-haptics.o\n' > "$work/extra/Makefile"
make O="$work/build" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- M="$work/extra" modules
aarch64-linux-gnu-strip --strip-debug "$work/extra/aw86937-haptics.ko"
install -Dm644 "$work/extra/aw86937-haptics.ko" "$stage/lib/modules/$release/extra/aw86937-haptics.ko"
test "$(modinfo -F vermagic "$work/extra/aw86937-haptics.ko" | cut -d' ' -f1)" = "$release"
# Arch uses /usr/lib/modules; omit SDK symlinks from the runtime overlay.
rm -f "$stage/lib/modules/$release/build" "$stage/lib/modules/$release/source"
mkdir -p "$out/overlay/usr/lib"
mv "$stage/lib/modules" "$out/overlay/usr/lib/"
depmod -b "$out/overlay/usr" "$release"
install -m644 "$work/build/arch/arm64/boot/Image" "$out/Image"
install -m644 "$work/build/arch/arm64/boot/dts/qcom/sm8650-lenovo-tb321fu.dtb" "$out/sm8650-lenovo-tb321fu.dtb"
install -m644 "$work/build/.config" "$out/kernel.config"
printf '%s\n' "$release" > "$out/kernel-release.txt"
strings "$out/Image" | grep -F 'lenovo,tb321fu-kirby-nt36523-boe-dsc-vid' > "$out/boe-driver-match.txt"
dtc -I dtb -O dts "$out/sm8650-lenovo-tb321fu.dtb" -o "$out/compiled-device-tree.dts" 2> "$out/dtc-warnings.txt"
grep -F 'lenovo,tb321fu-kirby-nt36523-boe-dsc-vid' "$out/compiled-device-tree.dts" > "$out/boe-panel-compatible.txt"
grep -F 'nt36523-boe-dsc' "$out/boe-panel-compatible.txt"
grep -F 'novatek_ts_boe_fw.bin' "$out/compiled-device-tree.dts"
tar -czf "$out/kernel-artifacts.tar.gz" -C "$out" Image sm8650-lenovo-tb321fu.dtb kernel.config kernel-release.txt
tar -czf "$out/modules-overlay.tar.gz" -C "$out/overlay" .
printf 'base_commit=%s\nhaptics_commit=%s\npanel=BOE\nkernel=%s\nhardware_tested=no\n' "$base" "$haptics" "$release" > "$out/BUILD-INFO.txt"
printf 'kernel_profile=%s\n' "$profile" >> "$out/BUILD-INFO.txt"
(cd "$out" && sha256sum Image sm8650-lenovo-tb321fu.dtb kernel.config kernel-artifacts.tar.gz modules-overlay.tar.gz BUILD-INFO.txt > SHA256SUMS.txt)
