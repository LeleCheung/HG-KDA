# XSAI-emu 最小 workload

这些 bare-metal 程序用于复现 Linux 验证，不包含在 runtime 归档中。

前提：

- nexus-am checkout：`925e69ddc3ee6e986cf52954d50819f555024d33`
- 推荐 XSAI LLVM release：`20260528`
- 也可用 Ubuntu 的 `riscv64-linux-gnu-*` 做基础兼容性验证，但不能替代 LLVM/Matrix 路径验证

GNU 构建示例：

```bash
export AM_HOME=/absolute/path/to/nexus-am
make -C code/profiling/XSAI-emu/workloads/hello \
  ARCH=riscv64-xs TOOLCHAIN=GNU LINUX_GNU_TOOLCHAIN=1
make -C code/profiling/XSAI-emu/workloads/gemm-ijk \
  ARCH=riscv64-xs TOOLCHAIN=GNU LINUX_GNU_TOOLCHAIN=1
make -C code/profiling/XSAI-emu/workloads/gemm-ikj \
  ARCH=riscv64-xs TOOLCHAIN=GNU LINUX_GNU_TOOLCHAIN=1
```

LLVM 构建时设置 `LLVM_HOME`，并将 `TOOLCHAIN=GNU LINUX_GNU_TOOLCHAIN=1` 改为 `TOOLCHAIN=LLVM`。

GEMM 使用固定 N=8 整数输入。程序输出整个 kernel 循环前后的 `mcycle`、`minstret` 差值和 checksum；CSR 差值包括两次 CSR 读取及其邻近指令的固定测量开销，但不包含初始化、checksum 遍历和 printf。

`gemm-family/` 是证据到动作最小验证用的同语义变体集。它固定 N=16、重复 4 次，当前包含：

- `ijk`：标量累加基线；
- `ikj`：循环换序，连续访问 B/C；
- `jki`：跨行访问 A/C 的局部性负例；
- `reg2x2`：2x2 寄存器分块，增加独立累加链并复用载入值。
- `reg4x4`：4x4 寄存器分块，用于寻找更大 tile 的资源压力和收益边界。

四个变体都必须得到 checksum 295。批量构建并各运行一次：

```bash
export AM_HOME=/absolute/path/to/nexus-am
code/profiling/XSAI-emu/run_gemm_family.sh 1
```

XSAI-emu 在固定配置下是确定性执行；额外重复次数主要用于检查可重复性，可作为脚本参数增加。原始结果和均值分别写入 `code/profiling/XSAI-emu/results/gemm-family/runs.csv` 和 `summary.csv`。这些变体用于提出和排除瓶颈假设；循环换序会同时影响访存、依赖和指令数，不能只根据周期变化将其直接标记为单一瓶颈。

严格 RTL counter 窗口需要先有完整运行 CSV，并绑定当前源码校准值：

```bash
export AM_HOME=/absolute/path/to/nexus-am
code/profiling/XSAI-emu/run_gemm_profile_windows.sh
```

脚本用 `-W` 在测量窗口开始时清零 counter，用 `-I` 在结束 CSR 附近停止，将结果写入 `results/gemm-family-windows/evidence.csv`。窗口运行用于 profiling，不经过最终 checksum；必须和完整运行的 correctness 结果配对使用。程序打印的绝对 `minstret` 带平台高位偏移，只使用差值，不能直接作为 `-W/-I`。

若已有运行日志，可不重跑 emu，直接重建 CSV：

```bash
code/profiling/XSAI-emu/summarize_gemm_family.sh
```

运行脚本：

```bash
code/profiling/XSAI-emu/run_workload.sh \
  code/profiling/XSAI-emu/workloads/gemm-ijk/build/xsai-gemm-ijk-riscv64-xs.bin \
  gemm-ijk
```

脚本要求已解包的 `code/profiling/XSAI-emu/runtime/xsai-emu/`，输出写入其 `results/` 忽略目录。
