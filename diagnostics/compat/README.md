# VeraDroid compatibility scripts

Read-only probe and preflight guard for PW6 firmware variants.

## probe

```sh
sh veradroid_probe.sh --out /mnt/us/veradroid-probe.txt
```

Does not write to the device except the optional output file. Collects firmware,
kernel, framebuffer, `/proc/bus/input/devices`, touch capabilities, I2C drivers and
container dependencies.

## preflight

```sh
sh veradroid_preflight.sh --report
echo $?
```

Exit codes:

- `0` VERIFIED: 1272-wide framebuffer, exactly one MT touchscreen with tracking ID,
  firmware 5.19.5 + `pt_mt`, binder/uinput present.
- `2` EXPERIMENTAL: firmware 5.17.1–5.20.1 but not the tested combination, or
  `fts_ts`/unknown driver. Requires `--force-experimental`.
- `1` REFUSE: resolution mismatch, firmware outside 5.17.1–5.20.1, no/ambiguous MT
  touchscreen, no tracking ID, or missing binder/uinput.

This guard is **not wired into the installer yet**.

## touchcap

```sh
sh veradroid_touchcap.sh /dev/input/event1 tap 15
```

Releases `veradroid-input` while capturing, then grabs it again. Use only on a
debug device. Prints a summary and leaves the raw `.bin` in `/mnt/us`.

## Verified locally

- `sh -n` and `busybox sh -n`: all three scripts.
- `dash tests/bitmask-test.sh`: exit 0.
- `busybox sh tests/bitmask-test.sh`: exit 0.
- `ABS=2e18000 0`, BPL=32: bits 47,48,53,54,55,57 set; no BTN_TOUCH in `KEY=0`.
- Probe/preflight touch selection tested against a 5.19.5-shaped sample.

Not yet run on a physical Kindle; `busybox ash` arithmetic is verified, but the
Kindle's exact `/proc` and `prettyversion` formats still need one real run.
