#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 1 ]]; then
  echo "usage: $0 [repetitions]" >&2
  exit 2
fi

repetitions=${1:-1}
if [[ ! "$repetitions" =~ ^[1-9][0-9]*$ ]]; then
  echo "repetitions must be a positive integer" >&2
  exit 2
fi

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
workload_dir="$script_dir/workloads/gemm-family"
results_dir="$script_dir/results/gemm-family"
variants=(ijk ikj jki reg2x2 reg4x4)

: "${AM_HOME:?set AM_HOME to the nexus-am checkout}"
mkdir -p "$results_dir"
csv="$results_dir/runs.csv"
echo "variant,run,n,repeats,checksum,kernel_cycles,kernel_instr,raw_minstret_start,raw_minstret_end" > "$csv"

for variant in "${variants[@]}"; do
  make -s -C "$workload_dir" clean >/dev/null
  make -s -C "$workload_dir" \
    ARCH=riscv64-xs TOOLCHAIN=GNU LINUX_GNU_TOOLCHAIN=1 \
    VARIANT="$variant"

  payload="$workload_dir/build/xsai-gemm-family-$variant-riscv64-xs.bin"
  for ((run = 1; run <= repetitions; run++)); do
    run_name="gemm-family-$variant-$run"
    log="$results_dir/$run_name.log"
    XSAI_MAX_INSTR=500000 \
      "$script_dir/run_workload.sh" "$payload" "$run_name" >"$log" 2>&1
    line=$(rg '^GEMM variant=' "$log")
    line=${line%$'\r'}
    if [[ -z "$line" ]] || ! rg -q 'HIT GOOD TRAP' "$log"; then
      echo "invalid run: $log" >&2
      exit 1
    fi
    pattern='^GEMM variant=([^ ]+) n=([0-9]+) repeats=([0-9]+) checksum=(-?[0-9]+) kernel_cycles=([0-9]+) kernel_instr=([0-9]+)$'
    if [[ ! "$line" =~ $pattern ]] || [[ "${BASH_REMATCH[1]}" != "$variant" ]]; then
      echo "cannot parse result: $line" >&2
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
      echo "cannot parse profile window: $window" >&2
      exit 1
    fi
    printf '%s,%d,%s,%s,%s,%s,%s,%s,%s\n' \
      "$variant" "$run" "$n" "$workload_repeats" \
      "$checksum" "$kernel_cycles" "$kernel_instr" \
      "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" >> "$csv"
  done
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
