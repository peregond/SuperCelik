#!/usr/bin/env bash
set -x
mkdir -p shots
adb install -r android/app/build/outputs/apk/debug/app-debug.apk
A=com.peregond.supercelik/.MainActivity
cap() {
  adb shell screencap -p /sdcard/s.png; echo "screencap rc=$?"
  adb shell ls -l /sdcard/s.png
  # screencap can fail on a display it cannot pick on its own: try each display id the system reports
  if ! adb shell test -s /sdcard/s.png; then
    for d in $(adb shell dumpsys SurfaceFlinger --display-id | grep -oE 'Display [0-9]+' | grep -oE '[0-9]+'); do
      adb shell screencap -p -d "$d" /sdcard/s.png; echo "screencap -d $d rc=$?"
      adb shell test -s /sdcard/s.png && break
    done
  fi
  adb pull /sdcard/s.png "shots/$1.png"
}
adb shell cmd uimode night no
adb shell am start -n $A
sleep 8; cap android-start-light
adb shell am start -n $A --ez demo true
sleep 5; cap android-result-light
adb shell cmd uimode night yes
sleep 5; cap android-result-dark
ls -la shots
