#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 /absolute/or/relative/payload.bin run-name" >&2
  exit 2
fi

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
runtime_dir="$script_dir/runtime/xsai-emu"
payload=$(realpath "$1")
run_name=$2
max_instr=${XSAI_MAX_INSTR:-200000}

if [[ ! "$max_instr" =~ ^[1-9][0-9]*$ ]]; then
  echo "XSAI_MAX_INSTR must be a positive integer" >&2
  exit 2
fi

if [[ ! -x "$runtime_dir/bin/emu" ]]; then
  echo "missing executable: $runtime_dir/bin/emu" >&2
  exit 1
fi

mkdir -p "$runtime_dir/build" "$runtime_dir/results/$run_name" \
  "$runtime_dir/results/dramsim3/$run_name"

cd "$runtime_dir"
export NOOP_HOME="$runtime_dir"
exec ./bin/emu \
  -i "$payload" \
  --no-diff \
  --max-instr="$max_instr" \
  --force-dump-result \
  --dramsim3-ini "$runtime_dir/config/XiangShan.ini" \
  --dramsim3-outdir "$runtime_dir/results/dramsim3/$run_name"
