You are selecting exactly one next optimization action for each of two integer GEMM cases on the same XSAI/RISC-V emulator. The matrices are row-major, N=16, int32, and every measured baseline passed checksum. Select an action from the case's list. Do not invent another action. Optimize expected guest cycles while preserving correctness. Treat the supplied evidence as the complete observation; do not inspect files or run tools.

Case `loop-heldout`: the current kernel uses loop order k-j-i. The inner i loop updates C[i][j] and reads A[i][k]. Its measured window executes 140,839 instructions in 49,644 guest cycles.

Actions:

- `loop.contiguous_j_inner`: interchange loops to i-k-j so the row-major j dimension is inner.
- `tile.register_2x2`: keep the current loop order and compute a 2x2 register tile.
- `memory.software_prefetch`: keep the layout and insert software prefetches.
- `none`: retain the current kernel.

Case `tile-boundary`: the current kernel computes a 4x4 output tile using an accumulator array. Its measured window executes 168,166 instructions in 33,855 guest cycles. Static inspection shows stack-resident accumulator traffic.

Actions:

- `tile.increase_8x8`: increase the output tile to 8x8.
- `tile.decrease_2x2`: reduce the output tile to 2x2.
- `loop.contiguous_j_inner`: replace the tiled kernel with an i-k-j scalar update loop.
- `none`: retain the current kernel.

