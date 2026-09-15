# Hardware-Grounded Kernel/Compiler Agent

本仓库服务于《基于白盒硬件特征制导的算子自动优化技术》课题。课题由中国科学院计算技术研究所承担，智源研究院提供合作支持，任务书和协议位于 `key/secret/`，不纳入公开 Git 仓库。

课题的工程验收包括：Profiling 工具、两款国产 AI 芯片适配、至少五个 Triton-TLE 算子优化，以及相对 FlagGems 基线平均 1.2 倍加速。研究工作需要把这些工程交付组织成一个可验证的问题：

> 如何把静态硬件知识和动态运行证据，转换成 Agent 可以执行、验证和复用的算子优化动作？

## 研究结构

```text
静态硬件知识库
        +
动态 profiler
        ↓
证据 → 语义瓶颈 → 优化动作
        ↓
Agent 编译、验证、测量和经验沉淀
```

三个核心模块：

1. **静态硬件知识库**：记录计算单元、存储层次、带宽、ISA/矩阵扩展、DMA、同步、编译器约束和 profiler 字段定义。
2. **动态 profiler**：采集算子实际运行行为、编译资源和性能计数器，并将厂商字段统一到项目 schema。
3. **证据到动作映射**：把原始 counter 组织成 `memory_wait`、`compute_underuse`、`spill`、`sync_imbalance` 等语义瓶颈，再匹配 Triton、IR、pass 或调度动作。

Top-K Index 属于动态 profiler 和映射模块之间的接口。它的核心职责是：针对算子、shape、dtype、硬件和当前诊断问题，选择相关证据并压缩语义。预算只影响在线阶段是否追加更昂贵的 counter、重复测量几次和何时停止。把几百个原始 counter 全部交给 Agent，无法替代归一化、诊断和动作匹配。

## 目录

```text
00_workplace/
├── README.md
├── code/
│   ├── action-mapping/
│   │   └── kernel-optimize-优化方法清单.xlsx
│   └── profiling/
│       └── XSAI-emu/
│           ├── XSAI-emu-guide.md
│           └── xsai-emu.zip
├── docs/                       # 持续更新的研究定位和技术文档
│   └── 研究定位与创新点_精简保留版.md
├── reports/                    # 按智源汇报轮次归档
│   ├── README.md               # 汇报索引与归档约定
│   ├── 01_work/                # 第一次汇报及会前分析
│   │   ├── 面向学术paper的分析.md
│   │   └── 面向学术与工程落地的研究院汇报.pptx
│   └── 02_work/                # 第二次汇报，准备中
│       ├── 汇报准备与材料分析.md
│       └── profiling信息到优化方法的映射机制.pptx
├── key/
│   └── secret/                 # 任务书和协议，禁止公开推送
└── reference/
    ├── KernelAgent/            # CAKE、AVO、KernelBench 等论文
    └── Profiling/              # Top-down 等性能分析资料
```

`code/action-mapping/` 是本科生动作库原型，目前包含 compute、memory、latency 三类优化方法。下一步应为每条方法补充触发证据、单位、适用算子/shape、实现入口、风险和验证结果。

`code/profiling/XSAI-emu/` 是预编译 XSAI RTL emu 和使用说明。它能运行 `riscv64-xs` bare-metal image，采集 RTL counter、ChiselDB，并用 PerfCCT 分析指令/uop 的流水级时间戳。运行要求、LLVM/AM、emu 参数和 DB 查询方式见 `XSAI-emu-guide.md`。

每周汇报在 `reports/` 下按轮次新增 `03_work/`、`04_work/` 等目录，保存当次 PPT、准备材料和会后纪要。第一次汇报前的学术分析保留在 `01_work/`；长期研究定位在 `docs/` 持续更新；复用代码仍在 `code/` 维护。具体材料见[汇报索引](reports/README.md)。

## 三个平台的关系

### XSAI

XSAI 是高可观测、可干预的白盒研究平台。用于：

- 观察完整或接近完整的 counter、流水线、uop、访存和编译信息；
- 构造 tile、layout、pipeline、线程组织等不同 kernel 变体；
- 研究证据与瓶颈的关系，并用干预实验验证动作是否有效；
- 校准语义瓶颈和动作规则。

XSAI-emu 的 RTL/仿真结果应与真实芯片结果分开报告。它提供机制解释和实验控制，不自动等同于最终硬件性能。

### 国产 AI 芯片

国产卡是真实环境中的灰盒验证平台。重点不是重复跑五个算子，而是确认：

- 厂商 profiler 实际能够提供哪些字段；
- 字段定义、单位、导出格式和版本是否稳定；
- 缺失哪些硬件信息后，瓶颈诊断仍然有效；
- 规则能否迁移到厂商编译器和真实运行环境。

拿到服务器后的第一份交付物应是每个平台的 profiler 能力矩阵，至少覆盖时间、计算资源、内存系统、调度/同步、编译资源、导出接口和可干预参数。随后选择一个算子走通“采集 -> 诊断 -> 动作 -> 编译 -> correctness -> 性能”的闭环。

### Intel AMX

AMX 可以作为独立的第三个平台，也可以作为运行 XSAI-emu 的宿主机，二者要分开标记：

- **AMX 实验**测的是 Intel CPU 上的真实 tile matrix 指令和内存系统；
- **XSAI-emu 实验**测的是 XSAI/RISC-V 模型，AMX 只是宿主机。

AMX 适合做算子优化，尤其是 BF16/INT8 GEMM、batched GEMM、convolution、attention projection、layer normalization 等。优先使用 oneDNN、Intel Extension for PyTorch、LIBXSMM/BRGEMM 和 LLVM/MLIR 作为强基线，使用 Linux `perf`、Intel VTune/Advisor、编译器优化报告和反汇编观察 AMX 利用率、tile 配置、带宽、线程和 NUMA 行为。Triton 的 CPU/AMX 后端仍应先确认当前版本和目标支持，不能默认把 GPU Triton kernel 直接迁移到 AMX；若后端可用，可作为 DSL 实验对象，不能预设其达到 oneDNN 等成熟库的 SOTA。

AMX 的研究价值在于提供一个公开、可重复的灰/白盒 CPU 平台：用它验证 profiler 语义和动作映射的通用性，再将 XSAI-emu 的白盒机制和国产卡的灰盒接口接入同一 schema。

## 近期可行研究点

### 1. 证据到动作的结构化映射

把本科生动作表从经验目录变成规则：

```text
证据字段和阈值
  -> 语义瓶颈
  -> 候选动作
  -> 预期影响与风险
  -> correctness/性能验证
```

论文可检验：结构化映射是否比 latency-only、raw counter 或自由文本提示带来更高的有效修改率。

### 2. 白盒到灰盒的最小必要特征

在 XSAI 上使用完整证据和可控变体建立机制解释，再逐步屏蔽字段，得到可观测性退化曲线；在国产卡上验证最小特征集合。论文可检验：哪些语义特征能跨芯片迁移，哪些需要重新校准。

### 3. 面向诊断问题的 Top-K Index

Top-K 不采用固定的全局 counter 排名，而按当前问题选择证据。例如，double buffer、减小 tile、改变 layout 和 fusion 分别需要不同证据集合。预算感知采集作为在线附加策略。

Top-down 的层次化思想可以用于组织诊断顺序：

```text
端到端时间
 -> host/launch | device execution
 -> compute | memory movement | synchronization
 -> 具体资源约束
 -> 优化动作
```

国产芯片应重新定义层次和指标，不能直接复制 Intel 的 slot 百分比。XGBoost/SHAP 可用于候选特征筛选和性能预测，SHAP 结果需要通过 tile/layout/pipeline 等干预实验验证因果方向。

## 国产卡接入工作清单

### 当天完成

1. 记录型号、驱动、SDK、编译器、运行时和 profiler 版本。
2. 找到官方 profiler 的命令行入口、权限要求和 CSV/JSON/trace 导出方式。
3. 用一个已有算子跑通基线，记录 warmup、重复次数、时间方差和 correctness 方法。
4. 导出一份原始 profiler 报告，标注每个字段的定义、单位、采集范围和是否可重复。

### 一周内交付给老师

1. 一页 profiler 能力矩阵：可获得字段、不可获得字段、采集成本和导出格式。
2. 一个算子案例：原始 counter、语义瓶颈、候选动作、修改结果和性能变化。
3. 一份字段映射表：国产卡原始字段 -> 项目统一 schema -> 诊断类别。
4. 三个明确结论：当前工具能定位到哪一级、最缺哪类信息、下一步需要申请什么权限或资料。

交付先追求“一个算子闭环和一张能力矩阵”，再扩展到五个算子。这样能快速判断这张卡适合做真实灰盒验证，还是只能作为时间和编译反馈平台。

## 第二次智源汇报（准备中）

本次材料位于 [reports/02_work/](reports/02_work/)，后续汇报按轮次另建目录。

建议题目：**从 Profiling 证据到算子优化动作：XSAI 白盒研究与国产卡灰盒验证**。

静态知识库压缩为一页，主体放在两个近期进展：

1. **动作映射**：展示本科生动作库中的一条完整规则，说明证据、瓶颈、动作和验证结果；
2. **白盒 profiling**：展示 XSAI 的完整 counter/流水分析、Top-K 语义索引和屏蔽字段实验设计；
3. **国产卡计划**：展示 profiler 能力矩阵模板和即将完成的第一个真实算子闭环。

现场核心表述：

> XSAI 用来验证哪些硬件证据真正解释性能，国产卡用来验证部分证据条件下的诊断和动作能否迁移到真实芯片。

## 版本控制与公开边界

该目录适合 Git 化。提交前应检查：

- `key/secret/` 中的任务书和协议不推送到公开仓库；
- XSAI-emu 压缩包接近 GitHub 单文件限制，长期建议使用 Git LFS 或 release artifact；
- `build/`、`results/`、ChiselDB、波形和厂商 profiler 原始报告通常不进入 Git；
- 国产卡内部文档、驱动、计数器定义和结果按协议保密；
- 公开仓库优先放 schema、脚本、脱敏样例和可复现实验说明。

## 参考材料

- [第一次汇报前的学术分析](reports/01_work/面向学术paper的分析.md)：早期任务拆解和研究 gap；
- [第一次汇报 PPT](reports/01_work/面向学术与工程落地的研究院汇报.pptx)：首次研究院汇报原稿；
- [研究定位与创新点](docs/研究定位与创新点_精简保留版.md)：持续更新的研究定位和最小实验矩阵；
- [第二次汇报准备与材料分析](reports/02_work/汇报准备与材料分析.md)：本次汇报建议；
- [第二次汇报的动作映射进展](reports/02_work/profiling信息到优化方法的映射机制.pptx)：本科生阶段材料；
- `reference/KernelAgent/CAKE/CAKE_人话版读书笔记.md`；
- `reference/KernelAgent/AVO/AVO_人话版读书笔记.md`；
- `code/profiling/XSAI-emu/XSAI-emu-guide.md`：XSAI-emu 使用说明。
