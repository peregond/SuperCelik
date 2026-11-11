#!/usr/bin/env bash
set -ex
mkdir -p shots
adb install -r android/app/build/outputs/apk/debug/app-debug.apk
A=com.peregond.supercelik/.MainActivity
adb shell cmd uimode night no
adb shell am start -n $A
sleep 6; adb exec-out screencap -p > shots/android-start-light.png
adb shell am start -n $A --ez demo true
sleep 4; adb exec-out screencap -p > shots/android-result-light.png
adb shell cmd uimode night yes
sleep 4; adb exec-out screencap -p > shots/android-result-dark.png
