Condition name: `raw_counters`.

In addition to the common description, the profiler exports these raw whole-workload counters. Names are emitted by the RTL and no semantic diagnosis is supplied.

```text
case=loop-heldout
MemNotReadyStall=100725
mem_stall_l1miss=218
data_array_access_total=128120
demand_miss_en=141
load_replay=93679
load_miss=184

case=tile-boundary
MemNotReadyStall=17767
mem_stall_l1miss=200
data_array_access_total=39944
demand_miss_en=161
load_replay=1989
load_miss=219
```

Return the required JSON. Do not assume undocumented counter thresholds.

