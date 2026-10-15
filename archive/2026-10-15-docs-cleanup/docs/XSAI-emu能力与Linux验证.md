# XSAI-emu：当前包能做什么，Linux 端先验证什么

## 已核对的交付包

`code/profiling/XSAI-emu/xsai-emu.zip` 包含预编译 `bin/emu`（406,120,792 字节）、NEMU reference、DRAMSim3 配置、`perfcct.py`、README 和 SHA256SUMS。四个文件的哈希均与包内清单一致。

包内没有完整 RTL/Chisel 源码、LLVM、nexus-am 和现成算子 workload。Linux 执行能力尚待实机验证；当前检查是在 Windows 上完成的归档与哈希检查。

## 执行路径

```text
C/C++ 算子 + AM 启动/链接代码
 → 配套 XSAI LLVM：RISC-V ELF、反汇编、bare-metal .bin
 → x86-64 Linux 上的 emu 模拟 XSAI RTL
 → guest 周期/指令、RTL counter、ChiselDB、可选波形
 → 定位代码/指令热点，修改算子，重新验证
```

- **emu** 模拟目标核；宿主机是否带 AMX 不改变 guest ISA。宿主机耗时只用于估算实验成本。
- **NEMU difftest** 比较指令执行状态；算子输出仍需单独与参考结果比较。
- **DRAMSim3** 提供当前配置下的内存时序模型。
- **ChiselDB / PerfCCT** 提供指令/uop 生命周期及部分 load 信息。issue-to-commit 包含等待和提交等影响，不能等同于执行单元延迟或各阶段可加和的瓶颈比例。

## 当前可以开展的算子优化

在工具链和运行验证通过后，可以做 bare-metal C/C++ kernel 的循环交换、分块、展开、布局和访存优化；AME/Matrix 路径需另核对 intrinsic/API、ISA feature 与 reference 的兼容性。包内没有已验证的 Triton→XSAI 路径。

固定二进制开放的 counters 可以立即研究；新增 RTL counter、修改核配置/微架构需要匹配的源码和重建环境。白盒可观测范围以实际编译进包的功能为准。

## Linux 端执行顺序

1. **环境**：确认 x86-64 Linux、glibc ≥ 2.33、libstdc++ 提供 GLIBCXX_3.4.29，按原 guide 检查依赖。
2. **解包与哈希**：在仓库根执行以下命令。若已有 runtime，先检查现有文件，不覆盖实验现场。

```bash
mkdir -p code/profiling/XSAI-emu/runtime
unzip -n code/profiling/XSAI-emu/xsai-emu.zip -d code/profiling/XSAI-emu/runtime
cd code/profiling/XSAI-emu/runtime/xsai-emu
sha256sum -c SHA256SUMS
chmod u+x bin/emu
ldd bin/emu
ldd lib/riscv64-nemu-interpreter-so
./bin/emu --help
```

3. **配套工具链**：按 [原 guide](../code/profiling/XSAI-emu/XSAI-emu-guide.md) 获取 LLVM release `20260528` 和 nexus-am commit `925e69ddc3ee6e986cf52954d50819f555024d33`。本轮在线确认二者存在；LLVM release 资产约 1.25 GB，当前未下载/执行。
4. **Hello**：使用原 guide 的最小 C 程序编译 `.bin`；确认 RISC-V ELF、入口地址及正常 guest 结束。记录命令、版本、产物哈希和完整日志。
5. **正确性**：构造小矩阵整数 GEMM（数值范围避免溢出）及可核验结果。分别编译 `ijk` 和 `ikj` 循环版本；检查不同 shape、边界和输出。两版本可能被编译为相同机器码，需反汇编/哈希确认。
6. **性能范围**：定位 kernel 区间后比较 guest cycles。初始化、校验与 printf 不应混入 kernel 性能；使用配套 AM 的测量/标记能力前先核对实现。尚未分离时明确标为整个 workload 周期，不能报作 kernel speedup。
7. **解释**：对热点 PC 采集短窗口 ChiselDB，检查访存及指令变化；保留变快、持平、变慢案例，再扩展分块/展开。

## 测量时必须区分

- `-W/-I` 是累计 guest 指令计数；`-D/-C` 和 waveform 窗口使用 guest 周期。不同变体的同一指令区间不一定对应相同算法工作量。
- `--no-diff` 降低宿主运行成本；不能以此证明算子正确。设置指令上限后退出也不等于程序正常完成，必须检查 guest trap/输出。
- ChiselDB 默认先写内存、结束时落盘；先用短 workload 验证，缺失/空 DB 单独报告。
- 对确定性的相同仿真运行反复执行，不能自动得到真实芯片上的统计置信度。

首轮交付：环境检查、Hello 日志、两个可重跑算子版本、正确性结果、guest 周期口径、一个热点解释。只对实际完成的步骤标记“通过”。
