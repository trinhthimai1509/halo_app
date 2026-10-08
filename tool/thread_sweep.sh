#!/bin/sh
# Development tool. Set ANDROID_SERIAL (and ADB if adb is not on PATH) before use.
# Controlled 2/3/4-thread sweep on the connected phone.
ADB="${ADB:-adb} -s ${ANDROID_SERIAL:?set ANDROID_SERIAL to the device serial}"
export MSYS_NO_PATHCONV=1
DEV=$ANDROID_SERIAL; PKG=dev.offlineai.offline_ai_chat; L=${SWEEP_DIR:-./sweep}
mkdir -p $L
ap() { $ADB shell dumpsys thermalservice | grep -m1 "mName=AP" | sed -E 's/.*mValue=([0-9.]+).*/\1/'; }
caps() { $ADB shell "for c in 0 4 6; do printf 'cpu%s cap=%s ' \$c \$(( \$(cat /sys/devices/system/cpu/cpu\$c/cpufreq/scaling_max_freq)/1000 )); done"; }
monitor() {  # $1 = log file; sampled every 3 s until $L/stop exists
  n=0
  while [ ! -f $L/stop ]; do
    PID=$($ADB shell pidof $PKG | tr -d '\r')
    { echo "=== $(date +%T) pid=$PID AP=$(ap)"
      $ADB shell "for c in 0 1 2 3 4 5 6 7; do printf '%s/%s ' \$(( \$(cat /sys/devices/system/cpu/cpu\$c/cpufreq/scaling_cur_freq)/1000 )) \$(( \$(cat /sys/devices/system/cpu/cpu\$c/cpufreq/scaling_max_freq)/1000 )); done; echo cur/cap_MHz"
      [ -n "$PID" ] && $ADB shell "top -H -b -n 1 -p $PID -o TID,CPU,%CPU,S -s 3 | sed -n '6,11p'"
    } >> $1 2>&1
    n=$((n+1)); [ $((n % 20)) -eq 0 ] && $ADB shell input keyevent 59
    sleep 2
  done
}
MODEL_DIR=/sdcard/Android/data/$PKG/files/models
for N in ${SWEEP_THREADS:-2 3 4}; do
  # Harness only: an uninstall deletes Android/data/<pkg> (and the model).
  $ADB shell pm path $PKG > /dev/null 2>&1 || $ADB install -r build/app/outputs/flutter-apk/app-debug.apk > /dev/null
  if ! $ADB shell ls $MODEL_DIR/Qwen3.5-2B-Q4_K_M.gguf > /dev/null 2>&1; then
    $ADB shell mkdir -p $MODEL_DIR && $ADB push "${MODEL_FILE:?set MODEL_FILE to the local GGUF path}" $MODEL_DIR/ > /dev/null
    echo "[HOST] model pushed $(date +%T)" >> $L/summary.txt
  fi
  $ADB shell am force-stop $PKG
  t=0; while [ "$(ap | cut -d. -f1)" -gt 45 ] && [ $t -lt 240 ]; do sleep 10; t=$((t+10)); [ $((t % 60)) -eq 0 ] && $ADB shell input keyevent 59; done
  echo "[HOST] threads=$N cooldown_s=$t start_AP=$(ap) $(caps) $(date +%T)" | tee -a $L/summary.txt
  rm -f $L/stop; : > $L/monitor_t$N$SUFFIX.log
  monitor $L/monitor_t$N$SUFFIX.log &
  MON=$!
  ${FLUTTER:-flutter} test integration_test/thread_sweep_test.dart -d $DEV --no-uninstall \
     --dart-define=LLM_THREADS=$N --dart-define=LLM_SEED=42 ${SWEEP_CASE:+--plain-name "$SWEEP_CASE"} > $L/sweep_t$N$SUFFIX.log 2>&1
  echo "[HOST] threads=$N flutter_exit=$? end_AP=$(ap) $(caps) $(date +%T)" | tee -a $L/summary.txt
  touch $L/stop; wait $MON
done
echo SWEEP_DONE >> $L/summary.txt
