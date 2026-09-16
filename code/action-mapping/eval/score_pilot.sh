#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
output_dir="$script_dir/pilot_outputs"

jq -n \
  --slurpfile gold "$script_dir/gold.json" \
  --slurpfile latency "$output_dir/latency_only.json" \
  --slurpfile raw "$output_dir/raw_counters.json" \
  --slurpfile semantic "$output_dir/semantic_mapping.json" '
  ($gold[0].cases | map({key: .case_id, value: .gold_action_id}) | from_entries) as $answers |
  [$latency[0], $raw[0], $semantic[0]] |
  map({
    condition,
    correct: ([.decisions[] | select(.action_id == $answers[.case_id])] | length),
    total: (.decisions | length),
    decisions: [.decisions[] | . + {
      gold_action_id: $answers[.case_id],
      correct: (.action_id == $answers[.case_id])
    }]
  })' > "$output_dir/score.json"

jq -r '.[] | [.condition, .correct, .total] | @tsv' "$output_dir/score.json"

