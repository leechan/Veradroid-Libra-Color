# models/*.conf for 0.73 / 0.81

Extracted from bootstrap.sh resolution/model cases and settings.sh defaults.
`settings_load` sources `$VD/models/$MODEL.conf` after built-in defaults and
before `$SYS/settings.conf`, so the user file still wins.

These files do not change install gating (that stays in bootstrap.sh).
