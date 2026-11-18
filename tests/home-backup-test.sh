#!/bin/sh
# Static checks for VeraHome's "更新前备份" setting and "已备份的数据" page (feat/backup-opt). No device access.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(dirname "$HERE")
S=$REPO/android/packages/VeraHome/src/com/veradroid/home
M=$REPO/android/packages/VeraHome/AndroidManifest.xml
fail=0
need()   { grep -qE "$2" "$1" || { echo "FAIL $(basename "$1"): $3"; fail=1; }; }
forbid() { grep -qE "$2" "$1" && { echo "FAIL $(basename "$1"): $3"; fail=1; } || true; }
need "$M" 'android:name="\.BackupActivity"' 'BackupActivity declared'
need "$S/HomeActivity.java" '"更新前备份", BackupActivity\.desc\(\)' 'setting row in 设备与更新'
need "$S/HomeActivity.java" 'new Intent\(HomeActivity\.this, BackupActivity\.class\)' 'backups page reachable from 设备与更新'
# host requests only through HostReq (the FIFO / settings.new are writable by every app)
need   "$S/BackupActivity.java" 'HostReq\.run\(a, "updatebackup"' 'mode set through HostReq'
need   "$S/BackupActivity.java" 'HostReq\.run\(BackupActivity\.this, "backups"' 'list through HostReq'
need   "$S/BackupActivity.java" 'ask\("backupdel", it\.where \+ " " \+ it\.name\)' 'delete one by host-listed where + name'
need   "$S/BackupActivity.java" 'ask\("backupdel", "all"\)' 'delete all'
forbid "$S/BackupActivity.java" 'HostLink\.(cmd|settings)\(' 'no FIFO command / settings.new for backups'
forbid "$S/BackupActivity.java" '/mnt/(base-)?us' 'no Kindle paths in the UI'
# confirmations say what goes and that it cannot be undone; locked items cannot be deleted
need "$S/BackupActivity.java" '"删除这份备份？"' 'confirm one'
need "$S/BackupActivity.java" '"全部删除？"' 'confirm all'
[ "$(grep -c '删除后不能恢复' "$S/BackupActivity.java")" -ge 2 ] || { echo "FAIL BackupActivity.java: both confirmations say it cannot be undone"; fail=1; }
need "$S/BackupActivity.java" '正在使用\\n暂不能删' 'locked items show 正在使用，暂不能删'
need "$S/BackupActivity.java" 'if \(it\.locked\(\)\) \{' 'locked items have no delete button'
# off warns in the setting, in the off confirmation and in the update dialog
need "$S/BackupActivity.java" 'OFF_WARN = "不备份时，更新出问题无法恢复' 'off warning text'
need "$S/BackupActivity.java" '"关闭更新前备份？"' 'choosing off asks first'
need "$S/SysUpdate.java" 'BackupActivity\.off\(\)' 'update confirmation warns when backups are off'
[ $fail = 0 ] && echo "home-backup: ok"
exit $fail
