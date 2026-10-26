# TB321FU BOE build preparation

## Mobile runtime kernel candidate

The separately triggered **Build TB321FU BOE mobile kernel candidate** workflow
builds `7.1.1-tb321fu-boe2` with `BOE_KERNEL_PROFILE=mobile`. It adds Landlock,
private Binderfs, uinput, nftables/NAT, EROFS compression and pressure-stall
information while retaining the BOE1 device configuration. A guard rejects
Kconfig results that drop required settings. The external haptics module and
all kernel modules are rebuilt for the new release.

This workflow produces only a kernel/module artifact for installation and
hardware testing. It does not replace a running kernel or rebuild a rootfs.
The existing BOE image workflow still uses the BOE1 profile. Keep BOE1 available
until the candidate has passed tablet testing. The original BOE1 kernel has
booted Plasma on the owner's TB321FU with working touch, Wi-Fi, sound and
charging; BOE2 has not yet been tested.

The older preparation notes below describe the original BOE1 backport.

This is an uncompiled, untested BOE backport, prepared after the actual tablet's
Android bugreport reported:

```text
msm_drm.dsi_display0=qcom,mdss_dsi_kirby_nt36523_boe_dsc_vid
```

The original `7.1.1-g5df8e852ea72` kernel and DTB match this device's CSOT panel
only. Changing the DTB name alone does not add BOE driver support.

The patch takes the BOE init sequence, 120 Hz baseline modes, descriptor and
compatible strings from enij90's GPL panel patch, retaining the 7.1.1 APIs:

- Kernel base: https://github.com/GUF296/linux/tree/5df8e852ea722929f5359a5ef28ebcec0c4443fd
- BOE implementation: https://github.com/enij90/armada-tb321fu/blob/27fa5c0052d888cae2d4bdd4a3b0cd60d39adacf/packages/kernel/patches/0803-drm-panel-nt36523-add-lenovo-kirby-csot-boe.patch
- Haptics: https://github.com/GUF296/tb321fu-haptics-debs/tree/f25d3a29d83a3c8a2f63bcc56306818e5973f994
- BOE firmware input: https://github.com/enij90/firmware-lenovo-tb321fu/releases/tag/v2026.10.15

The workflow builds a distinct `7.1.1-tb321fu-boe1` kernel, all its modules, and
the external haptics module. It then modifies copies of the already-built Arch
images from run `40177430328`. Existing accounts and passwords are preserved
without reading them. The new DTB selects BOE and BOE touch firmware. Existing
firmware is retained, with just the missing BOE touch binary added if needed.
No tablet is accessed or flashed by these scripts.

Local checks passed: shell syntax; workflow YAML parsing; forward and reverse
patch applicability against the two files at the pinned source commit. The
firmware archive was downloaded and its hash and actual BOE file path checked;
the 196608-byte BOE firmware SHA-256 is
`9397719683cf6acd6cf4c16888f516ed0209e3d6866baeff9e3151deb9caa61d`.
A Linux
compile and real hardware validation are still required. This is not a ready
to flash image or a claim that every peripheral works with this backport.

## 在你的 fork 上运行

1. 合并到 `main` 后，打开 Actions → **Build TB321FU BOE compatible images** →
   **Run workflow**，选择 `main`，再次点击 **Run workflow**。
   没有输入项，不需要重新填写密码。
2. Mac / Linux 命令行也可以触发：

   ```sh
   gh workflow run build-boe-compatible-images.yml --repo YoisakiKnd/arch-y700-build-ci --ref main
   ```

3. `kernel` 作业先构建成套设备层；`images` 作业再下载原 Arch 附件、
   校验、更新副本并压缩。
4. 成功后保存 `tb321fu-boe-kernel` 和
   `TB321FU-archlinuxarm-plasma-aarch64-BOE-images` 两个附件。

`codex/tb321fu-boe` 分支对本方案文件的推送也会自动构建。
本流程只上传 Actions 附件，不发布 Release；原有 CSOT 构建 workflow 仍保留。
目前固定复用此 fork 的原构建 `40177430328`，需要其附件尚未过期。

如果编译或镜像检查失败，请保留日志并修复后再继续。新产物仍需校验和
实机测试；请勿将原 CSOT 镜像和新 BOE 镜像混用。
