#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
workload_dir="$script_dir/workloads/gemm-heldout"
results_dir="$script_dir/results/gemm-heldout"
variants=(kji ikj reg8x8 reg4x4)

: "${AM_HOME:?set AM_HOME to the nexus-am checkout}"
mkdir -p "$results_dir"
csv="$results_dir/runs.csv"
echo "variant,checksum,kernel_cycles,kernel_instr,binary_sha256" > "$csv"

for variant in "${variants[@]}"; do
  make -s -C "$workload_dir" clean >/dev/null
  make -s -C "$workload_dir" \
    ARCH=riscv64-xs TOOLCHAIN=GNU LINUX_GNU_TOOLCHAIN=1 \
    VARIANT="$variant" >/dev/null
  payload="$workload_dir/build/xsai-gemm-heldout-$variant-riscv64-xs.bin"
  log="$results_dir/$variant.log"
  XSAI_MAX_INSTR=500000 "$script_dir/run_workload.sh" "$payload" "gemm-heldout-$variant" >"$log" 2>&1
  line=$(rg '^HELDOUT variant=' "$log")
  line=${line%$'\r'}
  pattern='^HELDOUT variant=([^ ]+) n=([0-9]+) repeats=([0-9]+) checksum=(-?[0-9]+) kernel_cycles=([0-9]+) kernel_instr=([0-9]+)$'
  if [[ ! "$line" =~ $pattern ]] || [[ "${BASH_REMATCH[1]}" != "$variant" ]] || ! rg -q 'HIT GOOD TRAP' "$log"; then
    echo "invalid held-out run: $log" >&2
    exit 1
  fi
  checksum=${BASH_REMATCH[4]}
  cycles=${BASH_REMATCH[5]}
  instr=${BASH_REMATCH[6]}
  hash=$(sha256sum "$payload" | awk '{print $1}')
  printf '%s,%s,%s,%s,%s\n' "$variant" "$checksum" "$cycles" "$instr" "$hash" >> "$csv"
done

printf 'held-out results: %s\n' "$csv"

