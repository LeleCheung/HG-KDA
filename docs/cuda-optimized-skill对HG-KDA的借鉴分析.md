# cuda-optimized-skill 对 HG-KDA 的借鉴分析

## 1. 分析结论

`cuda-optimized-skill`（下文简称 c-o-s）最值得 HG-KDA 借鉴的，不是某一条 CUDA 优化方法，而是它将 Agent 优化过程拆成了两类职责：

- Agent 负责理解 profiling 证据、选择优化方向、组合方法并生成候选 kernel；
- 确定性脚本负责环境检查、profiling、编译、正确性验证、稳定测速、候选选拔、实现验证、消融归因和状态更新。

因此，c-o-s 可以视为一个“受约束的优化闭环执行器”。它已经固化了观察格式、搜索边界和实验裁决，但没有完全固化细粒度瓶颈诊断、动作决策和代码变换。

HG-KDA 可以借用其闭环工程结构，继续把以下问题作为研究重点：

1. 如何将不同芯片的原始 counter 转换为统一、可解释的语义证据；
2. 如何由语义证据诊断细粒度瓶颈；
3. 如何把瓶颈可靠地映射为带适用条件、风险和验证方法的动作；
4. 如何在白盒 XSAI 与灰盒国产芯片之间迁移最小必要特征和动作规则。

## 2. c-o-s 的整体优化流程

c-o-s 的主流程可以概括为：

```text
硬件与工具门禁
  → baseline 编译、正确性、稳定测速和 NCU profiling
  → 原始 NCU 指标归入 compute / memory / latency 三轴
  → 计算三个轴的瓶颈 gap
  → 按 gap 分配本轮方法预算
  → Agent 从对应轴的方法库选择一个方法组合
  → Agent 为同一方法组合生成 K 个实现或参数变体
  → 脚本编译、验证、测速并选出 champion
  → 对 champion 做 NCU profiling、SASS 验证和逐方法消融
  → 更新 best、方法状态、frontier 和历史记录
  → 下一轮重新 profiling 当前 best
```

这里的“迭代次数”是上限。硬件、正确性、稳定计时或 profiling 门禁失败时，系统会写入停止状态，不继续生成后续候选。

## 3. 从原始 counter 到三轴预算

### 3.1 Counter 采集与归类

c-o-s 使用 NCU 采集预定义指标，并通过指标注册表维护字段别名、单位和缺失值语义。已知指标被组织到三个粗粒度轴：

- `compute`：计算管线利用率、Tensor Core、指令吞吐等；
- `memory`：显存带宽、cache、访存效率等；
- `latency`：warp stall、等待和延迟隐藏等。

这一步主要由注册表和脚本完成，不需要 Agent 每轮自由决定 counter 属于哪个类别。未知或缺失指标被视为 `unknown`，不会自动当成 0。

需要注意，这种分类是开发者预先编写的 NVIDIA 指标映射，不是从数据中自动学习出的跨平台分类。

### 3.2 三轴 gap 与预算分配

`roofline.py` 根据 profiler 结果计算：

```text
Δcompute
Δmemory
Δlatency
```

然后按 gap 大小为三个轴分配本轮方法名额。默认总预算通常为 3，单轴上限为 2。例如：

```json
{
  "delta_compute": 0.72,
  "delta_memory": 0.21,
  "delta_latency": 0.48,
  "axis_budget": {
    "compute": 2,
    "memory": 0,
    "latency": 1
  }
}
```

这表示本轮应从 compute 轴选择最多两个方法，从 latency 轴选择最多一个方法。预算只确定“从哪个类别选择几个方法”，还没有确定具体动作。

没有显式 workload model 时，这三个量只是 bottleneck-gap heuristic，不能被严格宣称为真实 Roofline，也不能据此认定已经达到性能上限。c-o-s 的较新实现已经对此作了约束。

## 4. 方法库、触发条件与 Agent 的职责

### 4.1 方法库中固化的信息

c-o-s 的方法注册表按 compute、memory、latency 三轴组织。每个方法可包含：

- 稳定的方法 ID 和所属轴；
- 优先级；
- 触发指标；
- good/bad 阈值和指标方向；
- GPU 架构与硬件能力要求；
- CUDA、CUTLASS、Triton 后端支持情况；
- 数值语义影响；
- 方法间的冲突、互补和共同预算关系；
- 所需证据、缺失证据处理规则和验证方法；
- 参考实现、经验加速声明和测试矩阵。

例如，一个方法可以声明：当某个计算利用率指标较低、目标 GPU 满足最低 SM 架构且存在 Tensor Core 能力时，该方法成为候选。

因此，“哪些 counter 可能触发哪些方法”已经在数据结构层面部分固化。

### 4.2 Trigger 判断并非完全自动

方法选择仍不是一个纯确定性规则引擎。实际模式是：

```text
registry 提供规则和约束
  → Agent 阅读当前 counter、源码和历史状态
  → Agent 判断 trigger、适用条件和组合关系
  → Agent 输出 methods.json
  → validator 检查结构性和安全性约束
```

Skill 要求 Agent按优先级扫描方法，并依次检查：

1. 方法是否已经尝试；
2. 架构、后端、工具链和硬件能力是否兼容；
3. skip condition 是否成立；
4. 当前 profiler 证据是否满足 trigger；
5. 是否与已选方法冲突；
6. 是否符合当前数值精度策略；
7. 以前的失败是否允许在新瓶颈下重新尝试。

脚本能够拒绝超预算、方法 ID 不存在、轴不匹配、明显冲突或能力不兼容的输出。但是，复合证据、源码结构、workload 类型以及 trigger 是否真正有意义，仍主要由 Agent 判断。

部分方法还没有完整的触发指标或阈值，因此不能把整个方法库理解为已经实现的自动专家系统。

### 4.3 方法到代码修改由 Agent 完成

即使选中了 `thread coarsening`、`register tiling` 或 `multi-stage pipeline`，方法库也不会自动生成确定性的代码变换。Agent 仍需结合当前 kernel 决定：

- 修改哪一层循环；
- tile 的具体形状；
- warp、stage、线程块等参数；
- 如何处理边界和不规则 shape；
- 如何平衡复用、并行度、寄存器压力和 spill；
- 在 CUDA、CUTLASS 或 Triton 中如何实现；
- 如何生成多个可比较的实现变体。

所以方法库描述的是优化方向和约束，而不是能够直接执行的 compiler pass。

## 5. 哪些步骤已固化，哪些仍由 Agent 完成

| 环节 | 主要执行者 | 固化程度 | 说明 |
|---|---|---:|---|
| 环境和工具检查 | 脚本 | 高 | 检查 GPU、运行时、编译器、NCU、cuobjdump 等 |
| Counter 采集 | 脚本 | 高 | 调用 NCU，处理权限、超时、空结果和降级情况 |
| Counter 字段归一化 | registry + 脚本 | 中高 | 维护字段别名、单位和缺失值语义 |
| Counter 三轴归类 | registry + 脚本 | 高 | 使用预定义的 compute/memory/latency 分类 |
| 三轴 gap 计算 | 脚本 | 高 | 生成 bottleneck gap 或带 workload model 的 Roofline 信息 |
| 轴预算分配 | 脚本 | 高 | 按 gap 比例分配方法名额 |
| 候选方法检索 | Agent 按 Skill 规程执行 | 中 | 方法库和优先级已定义，但扫描主体仍是 Agent |
| Trigger 与适用性判断 | Agent 为主，validator 辅助 | 中低 | 简单阈值可检查，复合语义和源码上下文仍需 Agent |
| 方法组合 | Agent + validator | 中 | Agent 选择，validator 检查预算、冲突和能力条件 |
| 具体代码修改 | Agent | 低 | 需要理解代码并生成实现 |
| K 个参数/实现分支 | Agent 生成，脚本执行 | 中 | 分支结构固化，具体变体由 Agent 设计 |
| 编译和 correctness | 脚本 | 高 | 未通过者不能参与性能排序 |
| 稳定测速和 champion 选择 | 脚本 | 高 | 从有效分支中选择最快版本 |
| Champion profiling | 脚本 | 高 | 使用可比较的指标集合重新采集 |
| SASS 实现验证 | 脚本 | 中高 | 自动匹配指令签名，但只能提供启发式证据 |
| Leave-one-out 消融 | 脚本执行，Agent需准备消融版本 | 中高 | 计算各方法的局部贡献 |
| 方法状态分类 | 脚本 | 高 | effective、ineffective、failed、unverified |
| 历史、best 和 frontier 更新 | 脚本 | 高 | 状态持久化并作为下一轮输入 |

职责边界可简化为：

```text
                         固化脚本
                            │
NCU 采集 → 指标归类 → 三轴 gap → 轴预算
                                      │
                                      ▼
                              Agent 选择方法组合
                                      │
                              Agent 生成候选代码
                                      │
                                      ▼
编译 → correctness → 稳定测速 → NCU → SASS → 消融 → 状态更新
                            │
                         固化脚本
```

## 6. 预算后的方法如何进行变体尝试

这里需要区分“方法组合搜索”和“固定组合下的变体搜索”。

c-o-s 每轮通常先选择一个方法组合。假设预算得到两个 compute 名额和一个 latency 名额，Agent 可能选择：

```text
M = {
  compute.tensor_core,
  compute.launch_config,
  latency.multi_stage
}
```

接着生成的 K 个分支共享同一个方法组合 `M`，主要改变具体实现与超参数：

| 分支 | 方法组合 | Tile | Warps | Stages |
|---|---|---:|---:|---:|
| b1 | Tensor Core + launch config + multistage | 64×64×32 | 4 | 2 |
| b2 | 同上 | 128×64×32 | 4 | 3 |
| b3 | 同上 | 128×128×32 | 8 | 3 |
| b4 | 同上 | 64×128×64 | 8 | 4 |

脚本依次完成：

```text
K 个分支
  → 编译
  → 接口与静态 contract 检查
  → correctness
  → 稳定测速
  → 从有效分支中选择延迟最低者作为本轮 champion
```

其他正确但较慢的分支进入 `frontier`，默认不会成为下一轮主线。

它通常不会系统穷举：

```text
A
B
C
A+B
A+C
B+C
A+B+C
```

它主要尝试的是：

```text
同一方法组合 A+B+C
×
K 种参数和实现变体
```

因此，K 个分支主要评价某个既定优化方向的实现和参数，而不是充分评价不同动作组合。

## 7. Champion、历史 best 与下一轮

本轮 champion 是“本轮所有有效分支中最快的版本”。它不一定自动成为下一轮输入。

只有当 champion 相对历史 `best` 的提升超过噪声阈值，系统才更新 `best_file`。否则：

```text
本轮 champion 正确但没有显著超过历史 best
  → 记录本轮实验和方法归因
  → 历史 best 保持不变
  → 下一轮仍从历史 best 开始 profiling
```

下一轮会重新 profile 当前 best，重新计算三轴 gap 和预算，再选择尚未尝试或因瓶颈变化而值得重试的方法。

完整关系是：

```text
方法组合 A+B+C
       │
   ┌───┼────────┐
   ▼   ▼        ▼
  b1  b2  ...   bK
   │   │        │
   └─ correctness + 性能排序 ─┘
                 │
             champion
                 │
      显著优于历史 best？
          │             │
         是             否
          │             │
     更新 best      保留旧 best
          └──────┬──────┘
                 ▼
          下一轮重新 profiling
```

## 8. 消融归因的作用

Champion 选出后，c-o-s 会针对其中的方法做 leave-one-out 消融：

```text
champion A+B+C
champion 去掉 A
champion 去掉 B
champion 去掉 C
```

单个方法的归因定义为：

```text
attribution(A) = time(no_A) - time(champion)
```

若去掉 A 后性能显著变差，可以认为 A 对该 champion 有正贡献。结合实现验证后，方法会进入：

- `effective_methods`：贡献超过噪声阈值，且实现验证通过；
- `ineffective_methods`：实现存在，但贡献未超过噪声；
- `implementation_failed_methods`：有较强证据表明目标实现没有生成；
- `unverified_methods`：消融或实现证据不足，不能下结论。

消融是在同一 champion 附近进行局部归因，不等价于完整的方法组合搜索。它也难以识别强交互：例如 A 或 B 单独无效，但 A+B 才有效；或者去除 A 会改变 B 的实现方式。

## 9. c-o-s 的局限

### 9.1 瓶颈语义较粗

三轴分类无法充分表达 HG-KDA 关心的：

- spill 或寄存器压力；
- memory replay；
- cache bank conflict；
- synchronization imbalance；
- DMA、NoC 和片上 SRAM 行为；
- 负载不均衡；
- 编译器 lowering 失败；
- host、launch 与 device execution 的层次关系。

### 9.2 固定方法组合限制了搜索

如果 Agent 选择了错误的方法组合，K 个分支仍共享这个方向。参数搜索很难纠正方法层面的错误。

### 9.3 方法库仍包含大量经验先验

方法注册表中的许多阈值、优先级和典型加速比并未覆盖充分的测试矩阵。部分方法缺少可执行 verifier。因此它更接近结构化工程先验，不是经过大规模实验验证的诊断模型。

### 9.4 SASS 检查只是启发式证据

匹配到某类机器指令，只能证明该指令存在，不能证明：

- 它一定由目标动作导致；
- 它处于目标热点函数和正确路径；
- 使用方式高效；
- 整个优化语义已经正确实现。

### 9.5 测试与文档仍有工程缺口

项目 README 仍主要描述 V2，而实际 `SKILL.md` 已是 v3，存在版本漂移。仓库包含 pytest 风格测试，但没有开箱即跑的测试依赖和统一入口；在本次检查环境中没有安装 pytest，`unittest discover` 发现 0 个测试。注册表 lint 和 Python 语法检查可以通过，但这不等于端到端 GPU 路径已经获得充分回归测试。

### 9.6 单案例加速不能证明普遍有效

项目展示的 Tensara 加速结果可以说明某次优化成功，但不能单独证明三轴诊断、方法选择或消融机制在不同算子、shape 和硬件上普遍有效。

## 10. 对 HG-KDA 的直接借鉴

### 10.1 借鉴执行与验证底座

HG-KDA 可以抽象以下平台接口：

```text
PlatformAdapter
ProfilerAdapter
MetricNormalizer
BottleneckDiagnoser
ActionRegistry
CandidateExecutor
ImplementationVerifier
ExperimentState
```

核心 orchestrator 保持平台无关；CUDA、XSAI、国产卡和 AMX 分别实现 adapter。

### 10.2 扩展 transition schema

HG-KDA 已有 `transition_template.json`，可以继续增加：

- run、iteration、candidate 和 parent ID；
- 方法组合及具体超参数；
- 原始 counter、统一字段和语义瓶颈；
- observation mask，即哪些证据可见、缺失或被主动屏蔽；
- 编译、contract、correctness、race、稳定性和实现验证的独立状态；
- 性能样本、置信区间和噪声阈值；
- attribution 与动作交互；
- champion、frontier、历史 best 和停止原因；
- 源码、IR、二进制、工具链和 profiler 版本哈希。

### 10.3 将方法有效性绑定到上下文

HG-KDA 不应维护一个全局的 `effective_methods` 列表。方法结论至少应绑定：

```text
平台 + 芯片/仿真版本 + 算子 + shape + dtype
+ 编译器和编译参数 + 动作参数 + correctness contract
+ 可见证据集合 + 测量协议
```

同一个动作在不同 shape、layout、编译器或硬件上可能产生相反结果。

建议把当前 78 条动作逐步划分为：

- `prior`：只有知识或大模型先验；
- `eligible`：当前平台、算子和证据满足前提；
- `observed`：已经执行并记录完整 transition；
- `context_effective`：在特定上下文中有显著正贡献；
- `context_ineffective`：在特定上下文中未发现显著贡献；
- `implementation_failed`：目标变换没有真正实现；
- `unverified`：证据不足。

### 10.4 建立多级实现验证

HG-KDA 可以将 c-o-s 的 SASS 验证扩展为：

```text
源码动作是否出现
  → IR 属性、schedule 或 pass 是否出现
  → lowering 后的汇编/指令模式是否出现
  → profiler 指标是否按预期方向变化
  → correctness 和最终性能是否显著改善
```

不同平台可以提供不同 verifier：

- CUDA：PTX/SASS、NCU；
- Triton：TTIR/TTGIR、后端汇编；
- XSAI：RISC-V 汇编、RTL counter、ChiselDB、PerfCCT；
- 国产芯片：厂商 IR、编译报告、反汇编和 profiler 字段。

### 10.5 从单层变体搜索升级为两层搜索

HG-KDA 可以设计：

```text
上层：不同动作或方法组合
下层：每个组合的参数和实现变体
```

例如同一预算下比较：

```text
组合 1：A
组合 2：B
组合 3：A+B
组合 4：A+C
```

每个组合内部再搜索 tile、layout、pipeline、线程映射等参数。这能更直接地测量“profiling → 瓶颈 → 动作映射”是否正确，减少参数调优掩盖动作选择错误的风险。

组合数较多时不必穷举，可以使用：

- 单动作基线；
- 根据冲突和互补关系剪枝；
- 分阶段加入动作；
- factorial/fractional-factorial 设计；
- bandit 或贝叶斯优化；
- 对高交互风险动作增加成对消融。

### 10.6 保持 HG-KDA 的论文差异

c-o-s 适合作为闭环执行参考，但 HG-KDA 的论文重点仍应是：

1. 跨平台统一证据 schema；
2. 原始 counter 到细粒度语义瓶颈的可靠诊断；
3. 白盒到灰盒的最小必要特征迁移；
4. 问题条件化的 Top-K 证据索引；
5. 结构化动作映射相对 latency-only、raw counter 和自由文本提示的收益；
6. 在不同观测缺失程度下，动作选择质量如何退化。

## 11. 建议的近期实施顺序

1. 以现有 XSAI GEMM 为最小闭环，先实现统一 runner 和状态 schema；
2. 将已有 `ijk`、`ikj`、`reg2x2`、`reg4x4`、`reg8x8` 作为候选与 frontier；
3. 固化 baseline、正确性、稳定 guest cycle、RTL counter 和反汇编验证；
4. 将 loop interchange 和 register tiling 两类动作接入正式 action registry；
5. 对不同 loop order、tile size 和动作组合做两层搜索与消融；
6. 扩展 shape、dtype 和 held-out case，形成足够规模的 transition 数据；
7. 运行 latency-only、raw counter、Top-K、语义瓶颈、语义瓶颈+动作映射对照实验；
8. 在 XSAI 上逐步屏蔽字段，测量动作选择与最终 speedup 的退化曲线；
9. 将同一个 runner 接入国产卡，仅替换 profiler、compiler 和 verifier adapter；
10. 用统一指标报告 correctness、有效修改率、几何平均加速、真实测量次数、失败类型和跨平台迁移效果。

当前 HG-KDA 的两题 pilot 中，语义映射条件得到 2/2，而 latency-only 和 raw counter 均为 1/2。这只能说明实验管线和研究假设值得继续验证，样本量不足以支持普遍性结论。下一步应将其扩展为多算子、多 shape、多动作边界和多平台的正式评测集。

## 12. 最终定位

对 c-o-s 最准确的概括是：

> 它固化了 profiling 采集、粗粒度轴归类、搜索预算、候选验证和实验裁决；方法触发与适用性判断仍由 Agent 在规则约束下完成，具体代码变换也主要由 Agent 生成。

对 HG-KDA 的借鉴定位是：

> 使用 c-o-s 的执行和验证结构作为工程底座参考，重点研究它尚未解决的细粒度语义诊断、动作映射、组合搜索和跨芯片证据迁移。
