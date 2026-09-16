#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
workload_dir="$script_dir/workloads/gemm-family"
runtime_dir="$script_dir/runtime/xsai-emu"
results_dir="$script_dir/results/gemm-family-windows"
full_runs="$script_dir/results/gemm-family/runs.csv"
variants=(ijk ikj jki reg2x2 reg4x4)
expected_source_hash=2d476fbf0d2f9d7861b3c0f4cba7518bbd55a91fa692ea4a35b19162e3760797
warmup_instr=3308
end_offset=3282

: "${AM_HOME:?set AM_HOME to the nexus-am checkout}"
if [[ ! -x "$runtime_dir/bin/emu" ]] || [[ ! -f "$full_runs" ]]; then
  echo "missing emu or full-run CSV" >&2
  exit 1
fi

actual_source_hash=$(sha256sum "$workload_dir/main.c" | awk '{print $1}')
if [[ "$actual_source_hash" != "$expected_source_hash" ]]; then
  echo "window calibration is stale for main.c: $actual_source_hash" >&2
  exit 1
fi

mkdir -p "$results_dir"
csv="$results_dir/evidence.csv"
echo "variant,warmup_instr,max_instr,mem_not_ready_stall,l1_miss_stall,data_array_access,demand_miss,load_replay,load_miss" > "$csv"

for variant in "${variants[@]}"; do
  kernel_instr=$(awk -F, -v variant="$variant" '$1 == variant && $2 == 1 { print $7 }' "$full_runs")
  if [[ -z "$kernel_instr" ]]; then
    echo "missing full-run measurement for $variant" >&2
    exit 1
  fi
  max_instr=$((end_offset + kernel_instr))

  make -s -C "$workload_dir" clean >/dev/null
  make -s -C "$workload_dir" \
    ARCH=riscv64-xs TOOLCHAIN=GNU LINUX_GNU_TOOLCHAIN=1 \
    VARIANT="$variant" >/dev/null

  payload=$(realpath "$workload_dir/build/xsai-gemm-family-$variant-riscv64-xs.bin")
  run_dir="$runtime_dir/results/window-gemm-family-$variant"
  dram_dir="$runtime_dir/results/dramsim3/window-gemm-family-$variant"
  mkdir -p "$run_dir" "$dram_dir"
  (
    cd "$runtime_dir"
    NOOP_HOME="$runtime_dir" ./bin/emu \
      -i "$payload" --no-diff -W "$warmup_instr" -I "$max_instr" \
      --force-dump-result \
      --dramsim3-ini "$runtime_dir/config/XiangShan.ini" \
      --dramsim3-outdir "$dram_dir" \
      >"$run_dir/run.log" 2>"$run_dir/run.err"
  )

  values=$(awk -F, '
    /: MemNotReadyStall,/ { memready += $2 }
    /: mem_stall_l1miss,/ { l1stall += $2 }
    /: data_array_access_total,/ { access += $2 }
    /: demand_miss_en,/ { demand += $2 }
    /: load_replay,/ { replay += $2 }
    /: load_miss,/ { miss += $2 }
    END { printf "%d,%d,%d,%d,%d,%d", memready, l1stall, access, demand, replay, miss }
  ' "$run_dir/run.err")
  printf '%s,%d,%d,%s\n' "$variant" "$warmup_instr" "$max_instr" "$values" >> "$csv"
done

printf 'window evidence: %s\n' "$csv"

