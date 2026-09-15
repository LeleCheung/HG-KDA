# 研究内容与任务分解：转写及研究价值评估

> 说明：本文件依据 `任务要求.jpg` 转写，并结合公开论文、开源系统和硬件生态进行高层次研究评估。任务原图中的“KernelGen（众智 FlagOS）”等名称按图片原文保留。

## 一、任务要求转写

### 总体目标

本项目探索**白盒 AI 硬件特征制导的算子自动优化技术**，具体包括以下任务：

1. **边界探索**：基于 Nvidia GPU、Intel AMX AICPU、迭进时空 K3 AICPU，研究 Agent 辅助算子生成、正确性验证、性能剖析与迭代优化的方法，探索黑盒/灰盒硬件的算子优化能力边界。
2. **关键特征识别**：从开源 RISC-V AICPU 切入，梳理 AICPU 微架构细节，并基于瓶颈分析（机理分析）或数值模拟的方法，识别影响算子优化的关键硬件特征。
3. **Profiling 工具与 Agent 工作流**：对算子参考实现进行 Profiling 分析，将 Profiling 结果、编译反馈、优化记录等组织成结构化上下文，使 Agent 能够在可验证闭环中提出代码修改、调度策略和数据布局优化建议。
4. **方法验证与推广**：将该方法推广到更多闭源硬件（Intel、先进时空、Nvidia 等），并在关键算子上进行验证。

### 任务 1：边界探索

基于 Nvidia GPU、Intel AMX AICPU、迭进时空 K3 AICPU，研究 Agent 辅助的算子生成、正确性验证、性能剖析和迭代优化方法，探索黑盒/灰盒硬件的算子优化能力边界。

原图意图是研究：随着可获得 Profiling 信息增加，Agent 的优化加速比如何变化，以及黑盒、灰盒硬件的能力边界在哪里。

### 任务 2：关键特征识别

从开源 RISC-V AICPU 入手，梳理开源 AICPU 的微架构细节；基于瓶颈分析（机理分析）或数值模拟方法，识别影响算子优化的关键硬件特征。

原图给出 Roofline 模型示意，用于区分计算受限、访存受限和带宽/性能 Ceiling，并通过硬件特征制导 Kernel 优化。图中还给出如下形式的特征筛选表达式（符号以原图为准）：

```text
IMP_v = { e_l | φ_l >= Thresh }
```

其中可将 `e_l` 理解为候选硬件特征，将 `φ_l` 理解为该特征的重要性或影响度量，`Thresh` 为筛选阈值；正式论文中需要重新定义符号和估计方法。

### 任务 3：Profiling 工具与 Agent 流程

总体链路为：

```text
AI 算子
   ↓
Profiling 工具
   ↓
关键硬件特征（运行时）
   ↓
KernelGen（众智 FlagOS）中的 evidence-driven kernel agent
```

图中将 Agent 工作流拆为三部分：

- **Agent**：负责 prompt、plan、branch；
- **Harness**：负责 benchmark、verifier、profile；
- **Evidence**：记录 lineage、failure record。

目标是形成“Agent + Harness + Evidence”的可验证闭环，使 Agent 不仅生成代码，还能够根据运行证据提出代码修改、调度策略和数据布局优化建议。

### 任务 4：方法验证与推广

将方法推广到更多异构或闭源硬件（图中举例包括 Nvidia、华为昇腾、Intel、先进时空等），并在关键算子上进行验证。原图还展示了多类国产 AI 加速硬件/厂商生态，包括昇腾、天数智芯、海光、沐曦、摩尔线程、燧原等。

## 二、SOTA 对照

| 研究方向 | 代表性工作/系统 | 已解决的问题 | 对本任务的启示 |
|---|---|---|---|
| LLM GPU Kernel 生成与执行反馈 | KernelBench（2025） | 建立 250 个 PyTorch 工作负载，使用编译、运行和 speedup 评价 LLM 生成 kernel | “生成—验证—测量—迭代”是必要基线，但单轮生成仍不足 |
| 鲁棒评测与反奖励投机 | KernelBench-Verified（2026） | TF32 现实基线、多分布隐藏测试、显存指标，揭示 hardcode 和 reward hacking | 必须把正确性、隐藏分布、显存和现实基线纳入评测 |
| 大规模 Agent/RL | CUDA Agent（2026） | 可扩展数据合成、带验证/Profiling 的 CUDA 环境、execution-grounded reward 和 RL | Harness 与可靠奖励信号本身是研究对象，不只是工程脚本 |
| 进化式、多样性搜索 | KernelFoundry（2026） | MAP-Elites、元提示进化、模板参数优化和分布式多硬件评测 | 需要保持不同优化策略的多样性，不能只追逐当前最快候选 |
| 编译器自动调度 | Ansor/AutoTVM、MetaSchedule、Triton/CUTLASS 生态 | 对 tile、线程、layout、pipeline 等结构化参数进行系统搜索 | LLM 适合提出结构和变异，自动调优器适合参数级搜索 |
| 机器学习性能建模 | TVM cost model、学习型 autotuning、硬件感知调度 | 用历史测量结果预测候选性能并减少真实试验次数 | Profiling 预算应采用多保真、成本感知和不确定性驱动分配 |
| 低层硬件性能分析 | Roofline、Nsight Compute/CUPTI、硬件计数器 | 将算子映射到算力、带宽、occupancy、stall、cache 等瓶颈 | 原始 counter 需要转换为可解释、可执行的优化建议 |
| 执行可验证代码搜索 | Best-of-N、execution-grounded test-time search | 通过多样采样和执行结果选择候选 | 正确但低置信度的尾部候选可能包含最优 kernel，应保留探索性 |

## 三、研究动机是否成立

### 结论

**动机成立，而且具有明显工程价值；但按当前表述，它更像一个范围很大的系统研究计划，尚未自动构成清晰的学术创新点。**

动机主要来自四个事实：

1. **算子性能高度依赖硬件细节**。相同数学算子在不同 GPU、AICPU、NPU 上可能受不同的带宽、矩阵指令、片上缓存、DMA、同步和布局约束支配。
2. **现有 LLM kernel 工作大多集中在 CUDA/GPU**。KernelBench、CUDA Agent 等证明了执行反馈的有效性，但对非 CUDA、闭源、指标受限的硬件覆盖有限。
3. **Profiling 信息是稀缺且有成本的**。完整硬件计数器、编译器中间信息和微架构文档在商业硬件上可能不可得，Agent 必须在有限、噪声大、跨设备不一致的证据下决策。
4. **从“发现瓶颈”到“修改代码”仍缺少可靠中间层**。很多系统把 profiler 输出作为文本提示或标量奖励，尚未充分解决硬件特征的因果归因、可迁移表示和可追溯优化闭环。

因此，“硬件特征制导的 Agent 算子优化”是有现实需求的，尤其适用于国产/专用/闭源加速器生态；但论文需要把“需求很大”转化为一个可检验的科学问题。

## 四、是否填补 research gap

### 当前表述能够主张的 gap

#### Gap 1：跨 ISA、跨可观测性级别的统一 Agent 优化框架不足

SOTA 主要在 Nvidia CUDA 上验证，或在单一 DSL/编译器生态中工作。对于 Nvidia GPU、Intel AMX AICPU、RISC-V AICPU、昇腾及其他闭源加速器，编程模型、计数器、编译反馈和可用库不同，目前缺少统一的“证据接口”和 Agent 工作流。

本项目若能定义与后端无关的 evidence schema，并证明同一 Agent 控制逻辑可在不同后端适配，就有明确 gap。但“支持很多硬件”本身不是创新，关键在于统一抽象和跨后端迁移效果。

#### Gap 2：硬件特征重要性识别与优化动作之间缺少可验证映射

现有工作通常直接使用 profiler feedback、cost model 或 LLM 经验，较少系统回答：

```text
哪些硬件特征真正影响某类算子？
影响强度多大？
该特征应触发哪一种代码/调度/layout 变换？
这种映射能否迁移到新 Shape、新算子和新硬件？
```

任务 2 若能提出硬件特征重要性模型、干预实验或数值模拟，并验证“识别出的特征确实改善搜索效率/最终性能”，可形成较强方法学贡献。

#### Gap 3：有限 Profiling 预算下的证据驱动搜索

完整 profiling 很昂贵，闭源硬件还可能只能获得 kernel 时间、编译日志或少量 counters。现有 LLM 迭代工作常采用固定轮数反馈，自动调优器则通常假设较稳定的测量 API；二者对“何时采集什么证据、把预算给哪个候选、何时停止”研究不足。

若本项目提出多保真 profiling、主动特征采样、成本感知候选选择或不确定性驱动搜索，并证明在相同 profiling 预算下达到更高 speedup，就具备清晰 gap。

#### Gap 4：可追溯、可复现的 Agent 优化证据链

“Agent + Harness + Evidence”是一个有潜力的系统研究切入点。应保存：源码 lineage、编译配置、输入 Shape、随机种子、正确性结果、counter、失败原因、修改 diff 和性能变化。

现有工作普遍强调最终 speedup，但对优化决策为何有效、失败如何复用、跨设备结果为何变化，记录和分析还不充分。若能将证据链用于诊断、检索和迁移，而不是只做日志，会更有学术价值。

#### Gap 5：多目标和真实部署约束下的跨硬件泛化

许多 benchmark 只优化单 kernel latency。实际部署还关心：端到端延迟、峰值显存、能耗、编译时间、稳定性、Shape 分布和 fallback。跨硬件推广若能同时报告这些目标，并建立 runtime dispatch 或 Pareto 选择，将比单一 speedup 更接近真实问题。

### 不能直接声称的 gap

以下说法容易被现有工作反驳：

- “首次使用 Agent 生成并优化 GPU kernel”：KernelBench、CUDA Agent 等已经覆盖。
- “首次将 Profiling 反馈用于 kernel 优化”：大量 autotuning、编译器和 LLM 工作已有执行/Profiling 闭环。
- “首次采用进化搜索优化 kernel”：Ansor、MetaSchedule、KernelFoundry 等已有系统性搜索。
- “首次跨硬件验证”：跨后端编译器、自动调度和厂商工具链已有相关实践。

更稳妥的主张应是：**在异构、部分可观测硬件上，提出一种硬件特征重要性驱动、成本感知、证据可追溯的 Agent kernel 优化方法，并验证其跨后端泛化能力。**

## 五、建议收窄为可发表的核心研究问题

建议从“大系统”收敛到以下主问题：

> 在只能获得异构硬件部分运行时证据的条件下，如何学习一个可迁移的硬件特征—优化动作映射，并以最少 Profiling 次数指导 Agent 找到满足正确性和资源约束的高性能算子实现？

可以拆成三个可验证假设：

1. **特征假设**：少量可观测硬件特征能够解释大部分算子性能差异，并比原始 profiler 文本更适合指导优化。
2. **搜索假设**：特征制导的候选选择/变异在相同真实测量预算下优于无诊断的 Best-of-N 或固定轮数迭代。
3. **迁移假设**：将硬件特征表示为后端无关的语义类别（计算、带宽、缓存、并行、同步、布局等），可提高跨 Shape、跨算子或跨硬件迁移效果。

## 六、建议的实验设计

### 硬件与可观测性分级

设置三种信息条件，而不是简单区分“黑盒/白盒”：

| 条件 | 可见信息 | 目的 |
|---|---|---|
| 黑盒 | 仅输入输出、编译是否成功、端到端时间 | 测试最弱可观测性 |
| 灰盒 | 编译日志、kernel 时间、少量运行时 counters、资源使用 | 模拟商业硬件常见接口 |
| 白盒 | 微架构文档、完整 counters、指令/IR 和调度信息 | 测试上限与机制解释 |

### 对照方法

- 厂商库和官方编译器；
- Triton/CUDA/CUTLASS 或对应后端 DSL；
- Ansor/MetaSchedule/AutoTVM 等自动调度；
- LLM Best-of-N；
- LLM + 固定执行反馈；
- LLM + Profiling 诊断；
- 所提方法去掉特征识别、去掉 evidence、去掉主动预算分配的消融版本。

### 评价指标

- correctness pass rate；
- 几何平均 speedup，而非只报告最佳样例；
- 达到目标 speedup 所需的 profiling 次数和 GPU 时间；
- 跨 Shape、跨算子、跨硬件的迁移性能；
- 峰值显存、能耗、编译时间和方差；
- 失败类型分布和恢复成功率；
- profiling 特征重要性识别的准确性/稳定性。

### 关键消融

至少比较：

1. 只给 latency vs. 给结构化 counters；
2. 原始 counters vs. bottleneck 诊断；
3. 随机搜索 vs. 特征制导搜索；
4. 固定 profiling 频率 vs. 主动/多保真 profiling；
5. 无 evidence lineage vs. 有 lineage/failure retrieval；
6. 单硬件训练/调优 vs. 跨硬件迁移。

## 七、主要风险与需要补充的定义

1. **范围过大**：Nvidia、Intel AMX、RISC-V、昇腾和多家国产芯片同时覆盖，可能导致每个平台都只做浅层适配。建议先选一个白盒平台和一个灰/黑盒平台。
2. **“关键特征”定义不清**：需明确是硬件 counter、静态微架构参数、编译资源，还是它们的组合，并规定重要性算法和阈值。
3. **“黑盒/灰盒”定义不清**：应按可观测字段列出接口矩阵，而非按厂商笼统分类。
4. **Profiling 噪声**：时钟、并发任务、热状态和驱动版本都会影响结果，必须报告重复次数、置信区间和环境控制。
5. **正确性与反作弊**：需要隐藏 Shape/输入分布、非连续布局、数值误差和非确定性检测。
6. **闭源硬件可复现性**：若无法公开驱动、计数器或编译器版本，应发布可公开平台上的完整复现实验，并把闭源平台定位为外部验证。
7. **学术贡献与产品流程混淆**：KernelGen、Harness 和厂商工具是系统载体；论文需要单独明确算法、表示、搜索策略或可验证结论。

## 八、最终判断

### Motivation

**强。** 异构 AI 硬件快速增加，算子优化严重依赖微架构和编译器；LLM/Agent 生成代码在 CUDA 之外的泛化、部分可观测条件下的决策和 Profiling 成本控制都存在现实痛点。

### Research gap

**有，但不是“Agent + Profiling + 自动优化”这一宽泛组合本身。** 这些组件分别已有大量先例。更有说服力的 gap 是三者的交叉处：

> 面向跨 ISA、部分可观测硬件，学习可迁移的硬件特征—优化动作映射，并在有限真实 Profiling 预算下实现可追溯、多目标的 Agent kernel 搜索。

### 可发表性判断

- 若只完成多硬件接入、Profiling 接口和若干算子 speedup：更像系统集成/工程报告，创新性偏弱。
- 若能提出新的特征表示、重要性识别/因果干预方法、成本感知搜索策略，并在严格跨硬件消融中证明收益：具有较明确的 research contribution。
- 若再公开统一 benchmark、evidence schema 和可复现评测协议：有机会形成基础设施与方法结合的工作。

## 参考工作（公开资料）

1. Ouyang et al., *KernelBench: Can LLMs Write Efficient GPU Kernels?*, arXiv:2502.10517, 2025。
2. Zhang et al., *KernelBench-Verified: Do LLM-Generated Kernels Actually Beat PyTorch?*, arXiv preprint, 2026。
3. Dai et al., *CUDA Agent: Large-Scale Agentic RL for High-Performance CUDA Kernel Generation*, arXiv preprint, 2026。
4. Wiedemann et al., *KernelFoundry: Hardware-aware evolutionary GPU kernel optimization*, arXiv preprint, 2026。
5. TVM/Ansor、AutoTVM、MetaSchedule 相关自动调度工作。
6. Roofline model、NVIDIA Nsight Compute/CUPTI 以及各类 GPU 性能计数器分析工具。
