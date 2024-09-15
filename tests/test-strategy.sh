#!/usr/bin/env bash
# Copyright (C) 2024 shmilee

# test the expiration strategy
# rm -rf TestSrc/ TestDest/ && bash test-strategy.sh 90 5 <to-future-or-not>
#  test-strategy.sh TotalDays BackupsPerDay <use-faketime-to-future>

CMD='atb.sh --strategy-noconfirm'
#CMD='../rsync_tmbackup.sh'

TestDIR="$(dirname $(realpath "$0"))"
TestSrc="$TestDIR/TestSrc"
TestDest="$TestDIR/TestDest"
TodayE=$(date -d "$(date +%F) 00:00:00" +%s)

## To Past
fn_make_past_day_backups() {
    local day="$1" N="$2" i=0 H=24  # like $1: 2024-09-10, $2: 15
    if [ "$(date -d "$1 00:00:00" +%s)" = "$TodayE" ]; then
        H=$(($(date +%H) + 1))
    fi
    while [ "$i" -lt "$N" ]; do
        local t="$(printf "%02d%02d%02d" $((RANDOM%H)) $((RANDOM%60)) $((RANDOM%60)))"
        mkdir -pv "$TestDest/$day-$t"
        ((i++))
    done
}
fn_run_a_past_test() {
    local TotalDays="$1"
    local BackupsPerDay="$2"
    mkdir -pv "$TestSrc"
    D=0
    while [ "$D" -le "$TotalDays" ]; do
        DayE=$((TodayE - 86400*D))
        day="$(date -d "@$DayE" +%F)"
        fn_make_past_day_backups "$day" "$BackupsPerDay"
        ((D++))
    done
    touch "$TestDest/backup.marker"
    ls "$TestDest" | sort > "$TestSrc/past-test-$$-before.txt"
    $CMD "$TestSrc" "$TestDest"
    ls "$TestDest" | sort > "$TestSrc/past-test-$$-after.txt"
}

## To Future
fn_make_future_day_backups() {
    local day="$1" N="$2" i=0 timestamps  # like $1: 2024-09-10, $2: 15
    while [ "$i" -lt "$N" ]; do
        local t="$(printf "%02d:%02d:%02d" $((RANDOM%24)) $((RANDOM%60)) $((RANDOM%60)))"
        timestamps+=($t)
        ((i++))
    done
    IFS=$'\n' timestamps=($(sort <<<"${timestamps[*]}")); unset IFS
    #echo ${timestamps[@]}
    for stamp in "${timestamps[@]}"; do
        local delta="@$day $stamp"
        faketime -f "$delta" $CMD "$TestSrc" "$TestDest"
        local latest="$(realpath "$TestDest/latest")"
        echo "$(basename $latest)" >>$TestSrc/future-test-$$-add.txt
    done
    echo "==> Now: $day $stamp"
}
fn_run_a_future_test() {
    local TotalDays="$1"
    local BackupsPerDay="$2"
    mkdir -pv "$TestSrc"
    $CMD --init "$TestDest" || (
        mkdir -pv  "$TestDest"
        touch  "$TestDest/backup.marker"
    )
    D=0
    while [ "$D" -le "$TotalDays" ]; do
        DayE=$((TodayE + 86400*D))
        day="$(date -d "@$DayE" +%F)"
        fn_make_future_day_backups "$day" "$BackupsPerDay"
        ((D++))
    done
    ls "$TestDest" | sort > "$TestSrc/future-test-$$-keep.txt"
}

TotalDays="${1:-1000}"   # 1000,  90,   3
BackupsPerDay="${2:-1}"  #    1,   5,  20
if [ -z "$3" ]; then
    fn_run_a_past_test "$TotalDays" "$BackupsPerDay"
else
    fn_run_a_future_test "$TotalDays" "$BackupsPerDay"
fi
