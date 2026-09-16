#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
output_dir="$script_dir/results"
conditions=(latency_only raw_counters semantic_mapping)
mkdir -p "$output_dir"

for condition in "${conditions[@]}"; do
  prompt=$(mktemp)
  trap 'rm -f "$prompt"' EXIT
  {
    sed -n '1,$p' "$script_dir/common.md"
    printf '\n'
    sed -n '1,$p' "$script_dir/$condition.md"
  } > "$prompt"
  codex exec \
    --ephemeral --ignore-user-config --skip-git-repo-check \
    --sandbox read-only -C /tmp \
    --output-schema "$script_dir/action_selection_schema.json" \
    --output-last-message "$output_dir/$condition.json" \
    - < "$prompt" >"$output_dir/$condition.events.log" 2>&1
  rm -f "$prompt"
  trap - EXIT
done

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
    decisions: [.decisions[] | . + {gold_action_id: $answers[.case_id], correct: (.action_id == $answers[.case_id])}]
  })' > "$output_dir/score.json"

jq -r '.[] | [.condition, .correct, .total] | @tsv' "$output_dir/score.json"

