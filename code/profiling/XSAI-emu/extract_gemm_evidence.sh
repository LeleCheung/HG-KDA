#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
results_dir="$script_dir/results/gemm-family"
variants=(ijk ikj jki reg2x2 reg4x4)

echo "variant,mem_not_ready_stall,l1_miss_stall,data_array_access,demand_miss,load_replay,load_miss"
for variant in "${variants[@]}"; do
  log="$results_dir/gemm-family-$variant-1.log"
  if [[ ! -f "$log" ]]; then
    echo "missing log: $log" >&2
    exit 1
  fi
  awk -F, -v variant="$variant" '
    /: MemNotReadyStall,/ { memready += $2 }
    /: mem_stall_l1miss,/ { l1stall += $2 }
    /: data_array_access_total,/ { access += $2 }
    /: demand_miss_en,/ { demand += $2 }
    /: load_replay,/ { replay += $2 }
    /: load_miss,/ { miss += $2 }
    END {
      printf "%s,%d,%d,%d,%d,%d,%d\n", variant, memready, l1stall,
             access, demand, replay, miss;
    }
  ' "$log"
done
