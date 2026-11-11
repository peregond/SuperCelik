#!/usr/bin/env bash
set -x
mkdir -p shots
adb install -r android/app/build/outputs/apk/debug/app-debug.apk
A=com.peregond.supercelik/.MainActivity
cap() {
  rm -rf "/tmp/emu-$1"; mkdir -p "/tmp/emu-$1"
  # headless emulator: ask the emulator itself for the frame (console command)
  adb emu screenrecord screenshot "/tmp/emu-$1"; sleep 2
  f=$(ls "/tmp/emu-$1"/*.png 2>/dev/null | head -1)
  [ -n "$f" ] && cp "$f" "shots/$1.png"
}
adb shell cmd uimode night no
adb shell am start -n $A
sleep 8; cap android-start-light
adb shell am force-stop com.peregond.supercelik
adb shell am start -n $A --ez demo true
sleep 6; cap android-result-light
adb shell am force-stop com.peregond.supercelik
adb shell am start -n $A --ez demo true --es tab token
sleep 6; cap android-token-light
adb shell am force-stop com.peregond.supercelik
adb shell am start -n $A --ez demo true --es tab settings
sleep 6; cap android-settings-light
adb shell am force-stop com.peregond.supercelik
adb shell am start -n $A --ez demo true --ez pdf true
sleep 8; cap android-pdf-light
adb shell cmd uimode night yes
adb shell am force-stop com.peregond.supercelik
adb shell am start -n $A --ez demo true
sleep 6; cap android-result-dark
adb logcat -d -s AndroidRuntime:E | tail -30
ls -la shots
