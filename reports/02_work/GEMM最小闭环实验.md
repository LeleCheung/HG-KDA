# GEMM 证据—瓶颈—动作最小闭环实验

日期：2026-09-16。平台：预编译 XSAI-emu，checkout `6690985ce4`，`DefaultMatrixConfig` 单核；workload 使用 nexus-am `925e69ddc3ee6e986cf52954d50819f555024d33` 和系统 RISC-V GNU 工具链构建。

## 1. 实验问题

本轮以整数 GEMM 为一个算子族，验证两条最小映射是否能形成可检查的证据链：

| 待检验语义瓶颈 | 证据 | 候选动作 | 预期变化 |
| --- | --- | --- | --- |
| cache/data-array replay 压力 | 周期、`MemNotReadyStall`、`load_replay`、data-array access；结合静态访问步长 | 将连续维放入内层循环 | replay、额外 data-array access 和周期下降 |
| 冗余 load/指令开销 | kernel 动态指令、PC 级 committed load 次数、周期 | 2x2 寄存器分块，复用 A/B | load 与总指令下降，周期下降 |

它们目前是待检验假设。`memory_wait` 只有在等待/replay 证据和干预结果共同成立时才能使用；单看耗时不能判定瓶颈。

## 2. 受控变体

固定 N=16、整数输入、4 次重复和 checksum=295。计时窗口包含每次计算前相同的 C 清零，不包含输入初始化、最终 checksum 和 printf。

| 变体 | 单一设计意图 |
| --- | --- |
| `ijk` | 标量累加基线 |
| `ikj` | j 为连续内层，连续访问 B/C |
| `jki` | i 为内层，跨行访问 A/C，作为局部性负例 |
| `reg2x2` | 四条独立累加链，同时复用两项 A 和两项 B |
| `reg4x4` | 十六条累加链，观察更大 tile 的 ILP 收益和资源压力 |

代码与复跑入口位于 `code/profiling/XSAI-emu/workloads/gemm-family/` 和 `code/profiling/XSAI-emu/run_gemm_family.sh`。

## 3. 第二轮确定性结果

所有版本均独立运行两次，每次都得到 checksum=295 和 `HIT GOOD TRAP`；每个版本两次运行的周期和指令数逐项完全一致。

| 变体 | kernel cycles | kernel instructions | 相对 `ijk` 周期 |
| --- | ---: | ---: | ---: |
| `ijk` | 28,805 | 125,663 | 1.000 |
| `ikj` | 28,365 | 141,023 | 0.985 |
| `jki` | 46,457 | 140,957 | 1.613 |
| `reg2x2` | 24,084 | 94,883 | 0.836 |
| `reg4x4` | 21,148 | 98,415 | 0.734 |

新增 `reg4x4` 和窗口输出后，二进制布局相对第一轮发生变化，因此第二轮数值与第一轮有小幅差异；排序与证据方向保持一致。下表是严格 guest-instruction 窗口的 RTL counter：先用 ChiselDB 校准测量开始前有 3,308 条 committed instruction，再用 `-W 3308` 清零，在 end `minstret` 附近用 `-I` 结束。窗口运行只采 profile，正确性由完整运行单独检查。

| 变体 | MemNotReadyStall | data-array access | load replay | load miss |
| --- | ---: | ---: | ---: | ---: |
| `ijk` | 973 | 37,546 | 4,390 | 15 |
| `ikj` | 220 | 35,166 | 5,060 | 5 |
| `jki` | 64,032 | 104,192 | 78,708 | 57 |
| `reg2x2` | 1,854 | 18,240 | 1,631 | 5 |
| `reg4x4` | 354 | 34,031 | 2,777 | 24 |

### 映射 A：replay 压力 → 循环换序

`jki` 和 `ikj` 的动态指令几乎相同，分别为 140,957 和 141,023；`jki` 的周期却高 63.8%。严格窗口中，`jki` 的 load replay 为 78,708，约为 `ikj` 的 15.6 倍，data-array access 约为 2.96 倍。这组证据支持瓶颈落在访问冲突/replay 压力，而不是单纯多执行指令；把连续的 j 维放进内层是匹配动作。

第一轮源码修订上采集的 PC 级 lifetime 也支持该解释：`ikj` 内层 load `0x800001c2` 的平均 issue-queue-to-commit 为 21.16 cycles，`jki` 对应 load `0x80000226` 为 60.82 cycles；相邻内层指令也整体从约 21 cycles 上升到约 60 cycles。加入 `reg4x4` 前后这两个 kernel 的地址和指令体没有变化，但该 PC 级结果仍按旧 binary provenance 保存，不混入第二轮机器可读数值。

当前结论等级：`intervention_supported`。严格窗口和确定性复测均已完成；`LoadLifeTimeCommitTrace` 仍为空，不能把 replay 进一步归因到具体地址或硬件机制，也暂不固化通用阈值。

### 映射 B：冗余 load/指令 → 2x2 寄存器分块

`reg2x2` 相对 `ijk` 减少 24.5% 动态指令、16.4% 周期。ChiselDB 的 committed PC 计数显示，`ijk` 内层有两条 load，各执行 16,384 次，共 32,768 次；`reg2x2` 内层四条 load 各执行 4,096 次，共 16,384 次，在乘法工作量相同的情况下将 load 指令减半。严格窗口中的 data-array access 从 37,546 降至 18,240，load replay 从 4,390 降至 1,631。

这支持“数据复用不足/冗余 load”语义以及寄存器分块动作。平均 issue-queue-to-commit 延迟没有下降：过滤未提交记录后，`ijk` 为 32.74 cycles，`reg2x2` 为 33.36 cycles；因此目前不应把收益解释成单指令 latency 改善。

当前结论等级：`intervention_supported`。动作规则必须保留寄存器压力风险。

### 边界观察：2x2 → 4x4

`reg4x4` 比 `reg2x2` 再快 13.9%，但动态指令从 94,883 回升到 98,415，data-array access 从 18,240 回升到 34,031，L1 miss stall 从 27 上升到 164。反汇编显示 `reg2x2` 的 kernel text 为 244 字节、栈帧 80 字节；`reg4x4` 增长到 676 字节、栈帧 272 字节，热循环内已经出现大量栈 load/store。

这说明 4x4 在本例中仍靠更多独立累加链获得净收益，同时资源压力已经出现。它是动作适用边界的预警样本，尚不是性能回退样本；真正的停止阈值还需要更大 tile 或其他 shape 才能确定。

## 4. ChiselDB 数据质量发现

代表版本已生成 lifetime DB；当前第二轮 `ijk` DB 有 445,504 条 lifetime 记录。已检查的 DB 中 `LoadLifeTimeCommitTrace` 均为 0 行，因此不能从该表获得地址或 replay 归因。

`LifeTimeCommitTrace` 包含阶段时间为 0 的未提交/取消记录。延迟统计必须至少使用 `AtCommit > 0`，计算 issue 延迟时还要满足 `AtIssueQue > 0 AND AtCommit >= AtIssueQue`。未过滤时会出现负延迟，属于无效统计。

## 5. 下一轮实验

已完成 PC 级 lifetime 对照、五个变体的两次确定性运行、严格 RTL counter 窗口、bin 哈希和两条机器可读观测。接下来按以下顺序推进：

1. 构造一个隐藏循环顺序变体和一个隐藏分块变体，冻结正确答案后再给 Agent 不同层级的证据。
2. 比较 latency-only、raw-counter 和结构化映射三种输入的动作选择、解释和测量次数。
3. 增加其他 shape，检验当前映射是否保持方向，并寻找寄存器分块的实际回退点。
4. 获得 LLVM/Matrix 工具链后，把同样方法迁移到专用矩阵指令路径。

前两项的 pilot 已完成，见 [Agent 动作选择 Pilot](Agent动作选择Pilot.md)。当前只有两个 case，用于验证 harness，不作为统计性结论。

第一轮已经走通了“正确性 → 动态证据 → 语义假设 → 动作干预 → 性能及证据复测”。当前证据只覆盖这个 N=16 整数 GEMM 微案例，不能外推为真实矩阵扩展或国产 AI 芯片上的通用收益。

两条机器可读观测已写入 `code/action-mapping/gemm_xsai_observations.json`，状态为 `intervention_supported`，并显式保留反例解释、风险和未解决项。
