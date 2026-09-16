#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
results_dir="$script_dir/results/gemm-family"
csv="$results_dir/runs.csv"
variants=(ijk ikj jki reg2x2 reg4x4)

mkdir -p "$results_dir"
echo "variant,run,n,repeats,checksum,kernel_cycles,kernel_instr,raw_minstret_start,raw_minstret_end" > "$csv"

for variant in "${variants[@]}"; do
  run=0
  while IFS= read -r log; do
    ((run += 1))
    line=$(rg '^GEMM variant=' "$log")
    line=${line%$'\r'}
    pattern='^GEMM variant=([^ ]+) n=([0-9]+) repeats=([0-9]+) checksum=(-?[0-9]+) kernel_cycles=([0-9]+) kernel_instr=([0-9]+)$'
    if [[ ! "$line" =~ $pattern ]] || [[ "${BASH_REMATCH[1]}" != "$variant" ]]; then
      echo "cannot parse result: $log" >&2
      exit 1
    fi
    n=${BASH_REMATCH[2]}
    workload_repeats=${BASH_REMATCH[3]}
    checksum=${BASH_REMATCH[4]}
    kernel_cycles=${BASH_REMATCH[5]}
    kernel_instr=${BASH_REMATCH[6]}
    window=$(rg '^PROFILE_WINDOW ' "$log")
    window=${window%$'\r'}
    window_pattern='^PROFILE_WINDOW start_instr=([0-9]+) end_instr=([0-9]+)$'
    if [[ ! "$window" =~ $window_pattern ]]; then
      echo "cannot parse profile window: $log" >&2
      exit 1
    fi
    printf '%s,%d,%s,%s,%s,%s,%s,%s,%s\n' \
      "$variant" "$run" "$n" "$workload_repeats" \
      "$checksum" "$kernel_cycles" "$kernel_instr" \
      "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" >> "$csv"
  done < <(find "$results_dir" -maxdepth 1 -type f -name "gemm-family-$variant-*.log" | sort)
done

awk -F, '
  NR > 1 {
    if (!($1 in count)) order[++n] = $1;
    count[$1]++;
    cycles[$1] += $6;
    instr[$1] += $7;
  }
  END {
    print "variant,runs,mean_kernel_cycles,mean_kernel_instr";
    for (i = 1; i <= n; i++) {
      variant = order[i];
      printf "%s,%d,%.2f,%.2f\n", variant, count[variant], cycles[variant] / count[variant], instr[variant] / count[variant];
    }
  }
' "$csv" > "$results_dir/summary.csv"

printf 'raw: %s\nsummary: %s\n' "$csv" "$results_dir/summary.csv"
