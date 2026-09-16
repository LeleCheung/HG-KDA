Condition name: `semantic_mapping`.

In addition to the common description, a hardware-grounded mapper supplies these diagnoses and constraints.

```text
case=loop-heldout
hypothesis=memory_access_replay_pressure
confidence=high
support: instruction count is ordinary for this GEMM family; replay and memory-not-ready evidence are extreme; row-major inner-i traversal is strided for C.
preferred_action_constraint: first test an action that makes the row-major j dimension contiguous in the inner loop.
expected_validation: replay, memory-not-ready stalls and cycles should fall without relying on fewer arithmetic operations.

case=tile-boundary
hypothesis=register_tile_resource_tradeoff
confidence=medium
support: a 4x4 tile already reuses data but has stack-resident accumulators; resource pressure exists, while the performance regression point has not been established.
preferred_action_constraint: profile one adjacent tile size; do not infer that stack traffic alone requires shrinking. Increasing may still win if added ILP/reuse outweighs the pressure.
expected_validation: accept an increase only if final cycles fall; track instructions, data-array activity and stack traffic as risks.
```

Return the required JSON. Select the best next action, including a measurement-oriented action when the diagnosis explicitly has uncertainty.

