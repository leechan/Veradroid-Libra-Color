# switch.sh <rounds> [wait_s] : warm app switching Home -> WeRead -> 多看 -> Moon+ (am start, no -W);
# "shown" = ms from am start to the last bridge refresh covering >= 30 % of the screen within wait_s; plus refault / pgpgin / direct reclaim
A="sh /mnt/base-us/veradroid/boot/ashell.sh"; E=/dev/shm/veradroid/epd.log; WS=${2:-8}
v() { for k in workingset_refault_file pgpgin pgsteal_direct; do awk -v k=$k '$1==k{printf "%s ", $2}' /proc/vmstat; done; }
r=0; while [ $r -lt $1 ]; do
 for c in com.veradroid.home/.HomeActivity com.tencent.weread.eink/com.tencent.weread.LauncherActivity com.duokan.einkreader/com.duokan.home.DkHomeActivity com.flyersoft.moonreaderp/com.flyersoft.moonreaderp.ActivityMain; do
  a=$(v); l1=$(wc -l < $E); t0=$(awk '{printf "%d", $1*1000}' /proc/uptime)
  $A "am start -n $c" >/dev/null 2>&1; sleep $WS; b=$(v)
  last=$(tail -n +$((l1+1)) $E | awk -v t0=$t0 '/epd: [0-9]+x[0-9]+\+/{t=substr($1,2)+0; split($3,g,/[x+]/); if (g[1]*g[2] >= 1272*1696*0.3) L=t-t0} END{print (L?L:"-")}')
  echo "$a|$b" | awk -F'|' -v t="$last" -v c="${c%%/*}" '{split($1,x," ");split($2,y," "); printf "SW %s shown=%s refault=%d pgpgin_kb=%d direct=%d\n", c, t, y[1]-x[1], y[2]-x[2], y[3]-x[3]}'
 done; r=$((r+1)); done
