#!/bin/bash

echo "System Checking takes few seconds"
summary_dir="/root/Valtracker/summary/summary_report"
reborn_base="/root/Valtracker/reborn/reborn_logs"
summary_out_dir="/root/Valtracker/reborn/reborn_summary"
collateral_dir="/root/Valtracker/collateral"
reborn_collateral_dir="/root/Valtracker/reborn/reborn_collateral"

mkdir -p "$reborn_base" "$summary_out_dir" "$reborn_collateral_dir"

trap 'echo -e "\nScript terminated by user (Ctrl+C).";' SIGINT

# --- ADD THIS FUNCTION ---
filter_datetime() {
    grep -Ev '(^Date:|^Time:|current.*date.*=|^[A-Za-z]{3} [A-Za-z]{3} [ 0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} [A-Z]{3} [0-9]{4})'
}

parse_strong_result() {
    local scan_this="$1"
    local result=""
    if [[ ! -s "$scan_this" ]]; then result="NA"; echo "$result"; return; fi
    if grep -Eiq '(FAIL|FAILED)' "$scan_this"; then result="FAIL"; fi
    if grep -iq "Segmentation fault" "$scan_this"; then result="FAIL"; fi
    if grep -Eiq '(not found|No such file|ERROR|CRITICAL|invalid|Unknown command|unrecognized option|unrecognized arguments)' "$scan_this"; then result="FAIL"; fi
    if grep -Eiq '(PASS|PASSED)' "$scan_this"; then result="PASS"; fi
    if grep -Eiq '(Usage:| --help|usage:|^help$)' "$scan_this"; then
        if [ -z "$result" ]; then result="NA"; fi
    fi
    echo "$result"
}

extract_commands_from_log() {
    local log="$1"
    awk '/^Command:/ {sub(/^Command: /,""); print}' "$log"
}

# Collateral collection
ts=$(date "+%d_%b_%Y_%H:%M")
reborn_svosinfo_file="$reborn_collateral_dir/svosinfo_${ts}.txt"
reborn_svosdimminfo_file="$reborn_collateral_dir/svosdimminfo_${ts}.txt"
svosinfo > "$reborn_svosinfo_file"
svosdimminfo > "$reborn_svosdimminfo_file"

echo "Reborn collateral generated:"
echo "  $reborn_svosinfo_file"
echo "  $reborn_svosdimminfo_file"

# Collateral comparison (now this works!)
latest_main_svosinfo=$(ls -t "$collateral_dir"/svosinfo_*.txt | head -1)
latest_main_svosdimminfo=$(ls -t "$collateral_dir"/svosdimminfo_*.txt | head -1)

svosinfo_diff=$(diff <(filter_datetime < "$latest_main_svosinfo") <(filter_datetime < "$reborn_svosinfo_file"))
if [ -z "$svosinfo_diff" ]; then
    echo "svosinfo collateral: SAME "
else
    echo "svosinfo collateral: MISMATCH "
    echo "Mismatch details:"
    echo "$svosinfo_diff"
fi

svosdimminfo_diff=$(diff <(filter_datetime < "$latest_main_svosdimminfo") <(filter_datetime < "$reborn_svosdimminfo_file"))
if [ -z "$svosdimminfo_diff" ]; then
    echo "svosdimminfo collateral: SAME "
else
    echo "svosdimminfo collateral: MISMATCH "
    echo "Mismatch details:"
    echo "$svosdimminfo_diff"
fi

echo "Reborn Menu:"
echo "1) Rerun all commands from the last summary_report"
echo "2) Rerun the last 3 commands from last summary report"
echo "3) Rerun All commands from all summary report"
echo "To exit press ctrl + c"
read -p "Select an option (1-3): " choice

case "$choice" in
1)
    last_log=$(ls -t "$summary_dir"/*.log | head -1)
    [ -z "$last_log" ] && { echo "No summary_report log files found."; exit 1; }
    ts=$(date '+%d_%b_%Y_%H:%M:%S')
    summary_name=$(basename "$last_log" .log)
    session_folder="$reborn_base/${summary_name}_${ts}"
    mkdir -p "$session_folder"
    summary_log="$summary_out_dir/${summary_name}_${ts}_reborn.log"
    mapfile -t commands < <(extract_commands_from_log "$last_log")
    ;;
2)
    last_log=$(ls -t "$summary_dir"/*.log | head -1)
    [ -z "$last_log" ] && { echo "No summary_report log files found."; exit 1; }
    ts=$(date '+%d_%b_%Y_%H:%M:%S')
    summary_name=$(basename "$last_log" .log)
    session_folder="$reborn_base/${summary_name}_${ts}"
    mkdir -p "$session_folder"
    summary_log="$summary_out_dir/${summary_name}_${ts}_reborn.log"
    mapfile -t all_cmds < <(extract_commands_from_log "$last_log")
    total=${#all_cmds[@]}
    start=$((total-3>0?total-3:0))
    commands=("${all_cmds[@]:$start:3}")
    ;;
3)
    summary_log="$summary_out_dir/fullsession_$(date '+%Y_%m_%d_%H_%M_%S')_reborn.log"
    commands=()
    for logfile in "$summary_dir"/*.log; do
        while read -r cmd; do
            [ -n "$cmd" ] && commands+=("$cmd")
        done < <(extract_commands_from_log "$logfile")
    done
    session_folder="$reborn_base/fullsession_$(date '+%Y_%m_%d_%H_%M_%S')"
    mkdir -p "$session_folder"
    ;;
*)
    echo "Exiting."
    exit 0
    ;;
esac

cmd_num=1
for cmd_cmd in "${commands[@]}"; do
    [ -z "$cmd_cmd" ] && continue
    start_time=$(date +%s)
    start_date=$(date '+%d_%b_%Y_%H:%M')
    tmp_outdir=$(mktemp -d)
    (
        cd "$tmp_outdir"
        eval "$cmd_cmd" 2>&1 | tee cmd_output.log
    )
    exit_code=$?
    end_time=$(date +%s)
    timespan=$((end_time - start_time))
    test_result=$(parse_strong_result "$tmp_outdir/cmd_output.log")
    {
        echo "======================================"
        echo "Command: $cmd_cmd"
        if [ "$test_result" != "NA" ]; then
            cmd_outdir="${session_folder}/cmd${cmd_num}_${start_date}"
            mkdir -p "$cmd_outdir"
            mv "$tmp_outdir/cmd_output.log" "$cmd_outdir/"
            echo "Directory: $cmd_outdir"
        else
            echo "Directory: "
        fi
        echo "Started at: $(date -d @$start_time '+%Y-%m-%d %H:%M:%S')"
        echo "Ended at: $(date -d @$end_time '+%Y-%m-%d %H:%M:%S')"
        echo "Timespan: $timespan seconds"
        echo "Result: $test_result"
        echo ""
    } >> "$summary_log"
    if [ "$test_result" != "NA" ]; then
        echo "Command/log files directory: $cmd_outdir"
    else
        echo "Command result is NA, logs not saved."
    fi
    rm -rf "$tmp_outdir"
    cmd_num=$((cmd_num + 1))
done

echo "Reborn logs have been saved in $reborn_base/"
echo "Reborn summary saved in $summary_log"
