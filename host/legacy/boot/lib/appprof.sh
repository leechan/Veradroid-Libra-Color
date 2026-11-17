# 每个应用的显示设置（per-app display profiles）。host/pw6、host/k49、host/legacy 三份完全相同（tests/run-static.sh 核对），
# 机型差别只在各自 settings.sh 里有没有那些键 / 显示桥认不认那些命令：认不了的键写进去也只是没人用。
#
# 前台信号：VeraHome 的 TaskStackListener（任务栈一变系统就通知，不轮询、不跑 dumpsys）发命令 "fg <包名>"；
#   桌面自己点开应用时在 startActivity 之前先发一次（应用画第一帧前就换好）。桌面 / 设置 = "fg home"。
#   同一个包重复发、或者换了应用但结果参数一样：什么都不做（不发 SET，显示桥不重画）。
# 文件：
#   $VD/boot/appprofiles.conf  内置推荐（随版本更新，只读）："<包名>[*] KEY=v;KEY=v  # 注释"，末尾 * = 前缀匹配
#   $SYS/settings.apps         用户自己的（和 settings.conf 放在一起，升级不动）："<包名> KEY=v;KEY=v"；"<包名> -" = 全跟随全局
#                              （有内置推荐的应用，用户选“全部跟随”时就是这一行）。用户的一行整体代替内置的那一行。
#   $X/appprof                 合并后的表，给桌面看（容器里 /dev/kfb/appprof）："<包名> b|u|ub <spec>"（b 内置、u 用户、ub 用户的盖住了内置的；spec 空 = -）
#   $SYS/settings.app          当前前台应用实际生效的参数（settings_load 最后读；以前 cmd.sh appdisp 写的就是它）
# 命令（cmd.sh）：
#   fg <pkg>|home              前台变了
#   appset <pkg>|<spec>        存用户的设置（spec 空 = 删掉这一行，回到内置推荐 / 全局；"-" = 全跟随）；"appset *|" 全部清掉
APPPROF_RE='^KFB_(CONTRAST|DITHER|FLASH|INVERT|LIGHTF|DARKEN|MODE|SETTLE|HOLD|SMOOTH|PACE|CLEAN|REAGL_MIN|SETTLE2|SCROLLDU|IMG|ANIM_MODE|ANIM_DIR|ANIM_STEPS|ANIM_MIN)=[0-9.]{1,6}$'

appprof_valid_pkg() { case "$1" in ''|*[!A-Za-z0-9._]*) return 1 ;; esac; [ ${#1} -le 200 ]; }

# 把 "K=v;K=v" 过滤成 settings.app 的行（只留白名单里的键和数字值）
appprof_lines() { printf '%s\n' "$1" | tr ';' '\n' | grep -E "$APPPROF_RE"; }

# 合并表：用户的一行盖掉内置的同名一行；内置的前缀行（com.foo.*）照原样列出，桌面自己按前缀匹配
appprof_publish() {
    set --; for ap_f in "$VD/boot/appprofiles.conf" "$SYS/settings.apps"; do [ -f "$ap_f" ] && set -- "$@" "$ap_f"; done
    [ $# -gt 0 ] || set -- /dev/null
    awk 'FNR == 1 { src = (FILENAME ~ /settings\.apps$/) ? "u" : "b" }
         /^[ \t]*(#|$)/ { next }
         { sub(/[ \t]*#.*/, ""); p = $1; s = $2; if (s == "") s = "-"
           if (src == "u") { u[p] = s; if (!(p in seen)) { seen[p] = 1; ord[++n] = p } }
           else { b[p] = s; if (!(p in seen)) { seen[p] = 1; ord[++n] = p } } }
         END { for (i = 1; i <= n; i++) { p = ord[i]; if (p in u) print p, (p in b ? "ub" : "u"), u[p]; else print p, "b", b[p] } }' \
        "$@" 2>/dev/null > $X/appprof.tmp
    chmod 644 $X/appprof.tmp 2>/dev/null; mv -f $X/appprof.tmp $X/appprof
}

# 这个包现在该用的 spec（没有 = 空）：用户的精确匹配 > 内置精确匹配 > 内置前缀匹配（最长的前缀）
appprof_spec() {
    [ -s $X/appprof ] || appprof_publish
    awk -v p="$1" '
        $1 == p { s = $3; exit }
        $1 ~ /\*$/ { pre = substr($1, 1, length($1) - 1); if (index(p, pre) == 1 && length(pre) > best) { best = length(pre); s = $3 } }
        END { if (s != "-") print s }' $X/appprof 2>/dev/null
}

# 这个包生效的那一行来自哪里：b 内置 / u、ub 用户的 / 空 = 没有（前缀行都是内置的）
appprof_src() {
    awk -v p="$1" '
        $1 == p { s = $2; exit }
        $1 ~ /\*$/ { pre = substr($1, 1, length($1) - 1); if (index(p, pre) == 1 && length(pre) > best) { best = length(pre); s = $2 } }
        END { print s }' $X/appprof 2>/dev/null
}

appprof_fg() {
    ap_pkg=$1
    [ "$ap_pkg" = com.veradroid.home ] && ap_pkg=home
    [ "$ap_pkg" = home ] || appprof_valid_pkg "$ap_pkg" || return 0
    [ "$ap_pkg" = "$(cat $W/appprof.pkg 2>/dev/null)" ] && return 0
    echo "$ap_pkg" > $W/appprof.pkg
    ap_spec=; [ "$ap_pkg" = home ] || ap_spec=$(appprof_spec "$ap_pkg")
    ap_new=$(appprof_lines "$ap_spec")
    # 用户在全局里明确选了“不全刷”（settings.conf 里 KFB_FLASH=0）：内置推荐不能替他打开按页数全刷（0.96 用户反馈“更新后会黑屏全刷”）。
    # 用户自己给这个应用存的设置（u / ub）照旧生效。
    if [ -n "$ap_new" ] && grep -qx 'KFB_FLASH=0' "$SYS/settings.conf" 2>/dev/null && [ "$(appprof_src "$ap_pkg")" = b ]; then
        ap_new=$(printf '%s\n' "$ap_new" | grep -v '^KFB_FLASH=')
    fi
    ap_old=$(cat $SYS/settings.app 2>/dev/null)
    if [ "$ap_new" = "$ap_old" ]; then t "app display $ap_pkg: same as before (${ap_spec:-global})"; return 0; fi
    if [ -n "$ap_new" ]; then printf '%s\n' "$ap_new" > $SYS/settings.app.tmp && mv -f $SYS/settings.app.tmp $SYS/settings.app; else rm -f $SYS/settings.app; fi
    appprof_send
    t "app display $ap_pkg: ${ap_spec:-global}"
}

# 把 settings.app（已经写好）发给显示桥
# 一次写进 FIFO（一次 open，一批命令；以前每条 epd_send 都要 fork 一次查进程，切换应用时多出约 100 ms）
appprof_send() {
    settings_load 2>/dev/null || true
    [ -p $X/epd.fifo ] && alive $W/epd.pid || return 0
    ap_msg=$({ echo "SET $KFB_CONTRAST $KFB_DITHER $KFB_FLASH $KFB_INVERT $KFB_MODE $KFB_SETTLE ${KFB_LIGHTF:-0} ${KFB_DARKEN:-0}"
      echo "ANIM $KFB_ANIM_MODE $KFB_ANIM_DIR $KFB_ANIM_STEPS $KFB_ANIM_MIN"
      echo "HOLD ${KFB_HOLD:-70}"
      # legacy 的显示桥没有 PACE/CLEAN/REAGL/SETTLE2/SCROLLDU/IMG：那里的 settings.sh 不定义 epd_send_smooth，这几条就不发
      if type epd_send_smooth >/dev/null 2>&1; then
          echo "PACE ${KFB_PACE:-0}"; echo "CLEAN ${KFB_CLEAN:-0}"; echo "REAGL ${KFB_REAGL_MIN:-35}"
          echo "SETTLE2 ${KFB_SETTLE2:-40}"; echo "SCROLLDU ${KFB_SCROLLDU:-0}"; echo "IMG ${KFB_IMG:-0}"
      fi; })
    # 显示桥在上面的检查和这次写之间退出时，打开 FIFO 写会一直等读者：和 epd_send 一样限 3 秒（vd_timeout，common.sh），
    # 不让命令监听（fg / appset）卡死。没有 vd_timeout 的老宿主照旧直接写。
    if type vd_timeout >/dev/null 2>&1; then vd_timeout 3 sh -c 'printf "%s\n" "$1" > "$2"' sh "$ap_msg" $X/epd.fifo
    else printf '%s\n' "$ap_msg" > $X/epd.fifo; fi
}

appprof_set() {
    ap_p=${1%%|*}; ap_s=${1#*|}; [ "$ap_s" = "$1" ] && ap_s=
    touch $SYS/settings.apps
    if [ "$ap_p" = '*' ]; then : > $SYS/settings.apps.tmp
    else
        appprof_valid_pkg "$ap_p" || return 0
        awk -v p="$ap_p" '$1 != p' $SYS/settings.apps > $SYS/settings.apps.tmp 2>/dev/null
        if [ "$ap_s" = - ]; then echo "$ap_p -" >> $SYS/settings.apps.tmp
        elif [ -n "$ap_s" ]; then
            ap_c=$(appprof_lines "$ap_s" | tr '\n' ';'); ap_c=${ap_c%;}
            echo "$ap_p ${ap_c:--}" >> $SYS/settings.apps.tmp
        fi
    fi
    mv -f $SYS/settings.apps.tmp $SYS/settings.apps
    appprof_publish
    # 正在前台的就是它：马上换上（不用等下次切换）
    ap_cur=$(cat $W/appprof.pkg 2>/dev/null); rm -f $W/appprof.pkg
    [ -n "$ap_cur" ] && appprof_fg "$ap_cur"
    t "app display saved: $ap_p ${ap_s:-(default)}"
}

# 启动时：合并表发布出来；上次停在某个应用时留下的 settings.app 不带进新的一次（开机时前台是桌面）
appprof_init() { rm -f $SYS/settings.app $W/appprof.pkg; appprof_publish; }
