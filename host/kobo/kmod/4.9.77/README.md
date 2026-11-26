# Kobo Libra Colour (N428) kernel modules — Linux 4.9.77

Verified on device firmware **4.42.23303** (kernel `4.9.77 SMP preempt mod_unload modversions ARMv7 p2v8`).

| File | Purpose |
|---|---|
| `binder_linux.ko` | Protocol-7 (32-bit) binder. The stock 4.9.77 kernel has a built-in protocol-8 (64-bit) binder, which Android 7 ARM cannot use. This module registers a *separate* char device named `binder32` (its own major, 511, not a misc device); `host/kobo/boot/lib/kmod.sh` creates `/dev/binder` from its real major:minor (`/sys/class/binder32/binder32/dev`). |
| `kobo_madvise.ko` | `/dev/kobo_madvise` helper used by the Bionic preload shim (`libkobo_madvise.so`). 4.9.77 has `CONFIG_ADVISE_SYSCALLS`, but keeping the module means the ART and page-reclaim path is identical to the Libra 2. |
| `kobo_pagecache.ko` | Optional page-cache drop helper (not loaded by the default boot path). |

Source and build recipe:

- Kernel source: <https://github.com/kobolabs/Kobo-Reader/tree/master/hw/mt8113-libraC_vision7>
  (pinned by the builder at commit `f5d86fdab03d7206773933fe985a6b1d63616b52`).
- These binaries were built from that source with the device's `/proc/config.gz`,
  `CONFIG_MODVERSIONS=y` and the module CRCs taken from the same build
  (`module_layout` must equal `0xa81081b3`, the CRC used by Kobo's own Wi-Fi modules).
- The build recipe and the CVE-2019-2215-hardened protocol-7 binder source are in
  [lyoe/Koboweread-Colour · `src/kmod-mtk/`](https://github.com/lyoe/Koboweread-Colour/tree/main/src/kmod-mtk)
  (GPL-2.0). `tools/kobo/fetch-libra-colour-kmod.sh` re-downloads the pinned
  binaries and verifies `SHA256SUMS`.

License: GPL-2.0 (Linux kernel modules). The rest of this repository is GPL-3.0-or-later.

> These modules only match kernel `4.9.77`. After a Kobo firmware update that
> changes the kernel, rebuild them from the matching Kobo source tree; do not
> force-load a mismatched module.
