#!/usr/bin/env bash
set -x
mkdir -p shots
adb install -r android/app/build/outputs/apk/debug/app-debug.apk
A=com.peregond.supercelik/.MainActivity
cap() { adb shell screencap -p /sdcard/s.png && adb pull /sdcard/s.png "shots/$1.png"; }
adb shell cmd uimode night no
adb shell am start -n $A
sleep 8; cap android-start-light
adb shell am start -n $A --ez demo true
sleep 5; cap android-result-light
adb shell cmd uimode night yes
sleep 5; cap android-result-dark
ls -la shots
