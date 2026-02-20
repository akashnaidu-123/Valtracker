#!/bin/bash

echo "takes few seconds to run."
summary_dir="/root/Valtracker/summary/summary_report"
output_base="/root/Valtracker/test_logs"
collateral_dir="/root/Valtracker/collateral"
csv_file="/root/Valtracker/commands.csv"
model_file="/root/Valtracker/cmd_model.pkl"
train_py="/root/Valtracker/train_predictor.py"
predict_py="/root/Valtracker/predict_cmd.py"

mkdir -p "$summary_dir" "$collateral_dir"

ts=$(date "+%d_%b_%Y_%H:%M")
svosinfo_file="$collateral_dir/svosinfo_${ts}.txt"
svosdimminfo_file="$collateral_dir/svosdimminfo_${ts}.txt"
svosinfo > "$svosinfo_file"
svosdimminfo > "$svosdimminfo_file"
echo "Collateral generated:"
echo "  $svosinfo_file"
echo "  $svosdimminfo_file"

summary_log="$summary_dir/${ts}_run_summary.log"
session_start="$(date '+%a %b %e %H:%M:%S %Z %Y')"
echo "Session started at: $session_start" > "$summary_log"
echo "Logging of cmd_is started"
echo "Press ctrl+c to exit"
echo "Enter the Command or to exit"

cmd_num=1

extract_data_to_csv() {
    awk '
        /^Command:/ {cmd=$0; sub(/^Command: /, "", cmd)}
        /^Timespan:/ {ts=$0; sub(/^Timespan: /, "", ts); sub(/ seconds/, "", ts)}
        /^Result:/ {res=$0; sub(/^Result: /, "", res); print cmd "|" ts "|" res}
    ' "$summary_dir"/*.log > "$csv_file"
}

train_model() {
    extract_data_to_csv
    if [ -s "$csv_file" ]; then
        python3 "$train_py"
    else
        echo "No training data available, skipping ML training."
    fi
}

predict_command_success() {
    cmd="$1"
    timespan="$2"
    prediction=$(python3 "$predict_py" "$cmd" "$timespan")
    echo "$prediction"
}

parse_strong_result() {
    local scan_this="$1"
    local result=""
    if grep -Eiq '(FAIL|FAILED)' "$scan_this"; then
        result="FAIL"
    fi
    if grep -iq "Segmentation fault" "$scan_this"; then
        result="FAIL"
    fi
    if grep -Eiq '(not found|No such file|ERROR|CRITICAL|invalid|Unknown command|unrecognized option|unrecognized arguments)' "$scan_this"; then
        result="FAIL"
    fi
    if grep -Eiq '(PASS|PASSED)' "$scan_this"; then
        result="PASS"
    fi
    if grep -Eiq '(Usage:| --help|usage:|^help$)' "$scan_this"; then
        if [ -z "$result" ]; then
            result="NA"
        fi
    fi
    echo "$result"
}

if ls "$summary_dir"/*.log &>/dev/null; then
    train_model
fi

while true; do
    read -p '' full_cmd_line
    [[ "$full_cmd_line" == "exit" ]] && break
    [[ -z "$full_cmd_line" ]] && continue

    # Split multi-command lines into separate subcommands for robust tracking
    # Support &, ;, &&, ||  as delimiters
    IFS=$'\n' read -rd '' -a split_cmds < <(
        perl -wle '
            use Text::ParseWords;
            my $in = shift;
            my @pieces;
            my $wstart = 0;
            my $qon = 0;
            for my $i (0..length($in)-1) {
                my $c = substr($in,$i,1); $qon ^= 1 if $c eq "\"";
                if (!$qon && ($c eq ";" || $c eq "&" || $c eq "|")) {
                    my $sep = $c;
                    if($c eq "&" && substr($in,$i+1,1) eq "&") { $sep="&&"; $i++; }
                    elsif($c eq "|" && substr($in,$i+1,1) eq "|") { $sep="||"; $i++; }
                    push @pieces, substr($in,$wstart,$i-$wstart);
                    $wstart = $i+1;
                }
            }
            push @pieces, substr($in,$wstart) if $wstart < length($in);
            print join("\n", grep { $_ !~ /^\s*$/ } map { s/^\s+//; s/\s+$//; $_ } @pieces);
        ' "$full_cmd_line"
    )

    for cmd_cmd in "${split_cmds[@]}"; do
        [[ -z "$cmd_cmd" ]] && continue

        if [ -f "$model_file" ]; then
            echo "AI Prediction:"
            predict_command_success "$cmd_cmd" "1"
            echo "Pausing 3 seconds to review prediction..."
            sleep 3
        fi

        start_date=$(date '+%d_%b_%Y_%H:%M')
        start_time=$(date +%s)

        # Only create output dir and save logs if not NA
        # Run command in a temp dir first
        tmp_outdir=$(mktemp -d)
        (
            cd "$tmp_outdir"
            eval "$cmd_cmd" 2>&1 | tee cmd_output.log
        )
        exit_code=$?
        end_time=$(date +%s)
        timespan=$((end_time - start_time))

        test_result=$(parse_strong_result "$tmp_outdir/cmd_output.log")
        if [ -z "$test_result" ]; then
            if [ $exit_code -eq 0 ]; then
                test_result="NA"
            else
                test_result="FAIL"
            fi
        fi

        {
            echo "======================================"
            echo "Command: $cmd_cmd"
            echo "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "Timespan: $timespan seconds"
            echo "Result: $test_result"
            echo ""
        } >> "$summary_log"

        if [ "$test_result" != "NA" ]; then
            # Save logs in output_base
            cmd_outdir="${output_base}/cmd${cmd_num}_${start_date}"
            mkdir -p "$cmd_outdir"
            mv "$tmp_outdir/cmd_output.log" "$cmd_outdir/"
            echo "Command/log files directory: $cmd_outdir"
        else
            echo "Command result is NA, logs not saved."
        fi
        # Remove temp dir
        rm -rf "$tmp_outdir"

        echo "Summary report: $summary_log"
        echo

        cmd_num=$((cmd_num + 1))
        train_model
    done
    echo "Enter the Command or to exit press ctrl+c"
done

session_end="$(date '+%a %b %e %H:%M:%S %Z %Y')"
echo "Session ended at: $session_end" >> "$summary_log"
