#!/bin/sh
# Development tool. Set ANDROID_SERIAL (and ADB if adb is not on PATH) before use.
# Samples the S10 every 3 s during a regression run and aborts on unsafe heat.
ADB="${ADB:-adb} -s ${ANDROID_SERIAL:?set ANDROID_SERIAL to the device serial}"
export MSYS_NO_PATHCONV=1
PKG=dev.offlineai.offline_ai_chat; OUT=$1; STOP=$2; LIMIT=75
: > $OUT; n=0
while [ ! -f $STOP ]; do
  PID=$($ADB shell pidof $PKG | tr -d '\r')
  AP=$($ADB shell dumpsys thermalservice | grep -m1 "mName=AP" | sed -E 's/.*mValue=([0-9.]+).*/\1/')
  { echo "=== $(date +%T) pid=$PID AP=$AP"
    $ADB shell "for c in 0 4 6 7; do printf 'cpu%s %s/%s ' \$c \$(( \$(cat /sys/devices/system/cpu/cpu\$c/cpufreq/scaling_cur_freq)/1000 )) \$(( \$(cat /sys/devices/system/cpu/cpu\$c/cpufreq/scaling_max_freq)/1000 )); done; echo cur/cap_MHz"
    [ -n "$PID" ] && $ADB shell "top -H -b -n 1 -p $PID -o TID,CPU,%CPU,S -s 3 | sed -n '6,9p'"
  } >> $OUT 2>&1
  if [ "${AP%%.*}" -ge $LIMIT ] 2>/dev/null; then
    echo "UNSAFE AP=$AP >= $LIMIT: force-stopping app" >> $OUT; $ADB shell am force-stop $PKG
  fi
  n=$((n+1)); [ $((n % 20)) -eq 0 ] && $ADB shell input keyevent 59
  sleep 3
done
