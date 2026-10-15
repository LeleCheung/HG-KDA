# 传统 Kernel Agent 与 HG-KDA：Profiling 到优化动作的区别

> 图的核心：两类系统共享“生成/修改代码—编译—运行—测量—验证”的基本闭环。HG-KDA 的研究重点是在这个闭环中显式加入“标准化证据事实 → 语义瓶颈诊断 → 结构化候选动作”，并用白盒与灰盒硬件实验验证这条通路。

## 配色含义

- <span style="color:#2563EB">**蓝色：共有环节**</span>——现有 Kernel Agent/KDA 和 HG-KDA 都具备的执行闭环。
- <span style="color:#D97706">**橙色：HG-KDA 的核心研究接口**</span>——本项目需要设计、实现并通过消融实验证明价值的部分。
- <span style="color:#15803D">**绿色：硬件制导基础**</span>——XSAI、国产卡和静态硬件知识为核心接口提供证据与约束。
- <span style="color:#B91C1C">**红色：传统流程中的未显式化部分**</span>——功能可能存在于 Agent 推理中，但没有稳定、可检查的接口。

## 图一：传统 Kernel Agent

```mermaid
flowchart LR
    T1["Kernel 代码"] --> T2["编译与运行"]
    T2 --> T3["运行与编译反馈<br/>Latency · Profiler 报告 · 错误"]
    T3 --> T4["Agent / LLM<br/>在上下文中理解瓶颈<br/>依靠模型经验选择动作"]
    T4 --> T5["修改 Kernel"]
    T5 --> T2
    T2 --> T8["结果验证<br/>正确性 · Speedup"]
    T8 --> T4

    T6["证据 → 瓶颈 → 动作<br/>隐含在模型知识和上下文中"] -.-> T4
    T7["中间判断难以检查、复用、<br/>迁移和单独评价"] -.-> T6

    classDef shared fill:#DBEAFE,stroke:#2563EB,stroke-width:2px,color:#172554;
    classDef implicit fill:#FEE2E2,stroke:#B91C1C,stroke-width:2px,color:#450A0A,stroke-dasharray:5 4;

    class T1,T2,T3,T4,T5,T8 shared;
    class T6,T7 implicit;
```

## 图二：HG-KDA

```mermaid
flowchart LR
    H1["Kernel 代码"] --> H2["编译与运行"]

    X["XSAI 白盒<br/>完整观测、受控干预"] --> H3
    D["国产卡灰盒<br/>真实 Profiler、真实工具链"] --> H3

    H2 --> H3["运行与编译反馈<br/>counter · trace · latency · 错误"]
    H3 --> H4["标准化证据事实<br/>字段定义 · 单位 · 分母 · 作用域<br/>来源 · 缺失状态 · 置信信息"]

    K["静态硬件知识<br/>资源上限、微架构约束<br/>Profiler 字段语义"] --> H4
    K --> H5

    H4 --> H5["语义瓶颈诊断<br/>瓶颈类别 · 原因子类<br/>严重度 · 诊断置信度<br/>支持/反对证据"]

    H5 --> H6["结构化候选动作<br/>触发条件 · 适用前提<br/>预期影响 · 风险 · 回退条件"]
    H6 --> H7["Agent<br/>选择、组合并生成修改"]
    H7 --> H8["修改 Kernel / IR / Pass<br/>编译器检查与 lowering"]
    H8 --> H2

    H2 --> H9["结果验证<br/>正确性 · Speedup · 证据变化"]
    H9 --> H10["结构化经验更新<br/>保留、修正或否定诊断与映射"]
    H10 --> H5
    H10 --> H6

    classDef shared fill:#DBEAFE,stroke:#2563EB,stroke-width:2px,color:#172554;
    classDef contribution fill:#FFEDD5,stroke:#D97706,stroke-width:3px,color:#431407;
    classDef grounding fill:#DCFCE7,stroke:#15803D,stroke-width:2px,color:#052E16;

    class H1,H2,H3,H7,H8,H9 shared;
    class H4,H5,H6,H10 contribution;
    class X,D,K grounding;
```

这里的橙色不表示这些概念从未出现在任何已有工作中。它表示 HG-KDA 将这些环节作为显式系统接口和主要研究变量，并需要验证它们相对于 raw-counter prompt、latency-only Agent 等基线带来的增益。

## 两个中间层的输出示例

标准化证据层输出的是带有明确测量语义的事实，而不是瓶颈结论：

```yaml
metric: compute.vector_active
value: 0.20
unit: ratio
denominator: kernel_elapsed_cycles
scope: kernel
aggregation: mean
source:
  platform: vendor_A
  raw_metric: vec_pipe_active_cycles
availability: measured
```

语义瓶颈层把多条证据与硬件知识组合成诊断假设：

```yaml
bottleneck: compute_underutilization
subtype: insufficient_parallelism
severity: high
confidence: 0.78
supporting_evidence:
  - compute.vector_active = 0.20
  - execution.occupancy = 0.18
  - scheduler.eligible_work = low
contradicting_evidence:
  - memory.bandwidth_utilization = 0.35
alternative_hypothesis:
  - memory_latency_starvation
```

## 读图时需要区分的三个数值

1. **测量比例**：例如 `vector_active = 20%`。这是带明确分母的观测事实。
2. **瓶颈严重度**：例如 `severity = high` 或归一化分数 `0.8`。这是诊断系统定义的程度，不能解释为 80% 的运行时间。
3. **诊断置信度**：例如 `confidence = 0.78`。这是对诊断可靠性的校准概率或分数，也不是硬件利用率。

由于计算、访存和同步可以重叠，不同瓶颈的严重度通常不能相加为 100%。

## 一句话表述

```text
传统流程：Profiler 输出 → Agent 内部推理 → 代码修改

HG-KDA：平台原始字段
        → 有来源和测量语义的标准化证据
        → 可检查的瓶颈诊断
        → 带适用条件和验证方法的候选动作
        → Agent/编译器执行
        → 用性能与证据变化验证诊断
```
