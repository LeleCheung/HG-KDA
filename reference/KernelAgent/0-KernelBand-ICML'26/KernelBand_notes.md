# KernelBand 方法与实验笔记

## 1. 问题本质：Kernel 优化是大规模搜索问题

> Kernel optimization is intrinsically a search problem over a vast optimization space.

目标是在正确实现集合中找到延迟最低的 kernel：

$$
k^* = \arg\min_{k \in \mathcal{K}_{\mathrm{valid}}} L(k, H)
$$

可以将搜索过程看成一张图：

- 节点：正确的 kernel；
- 边：对 kernel 应用一种优化策略；
- LLM：根据所选策略生成新节点。

搜索空间会随新 kernel 的生成不断扩大。

## 2. 核心矛盾：LLM 擅长生成代码，但不擅长规划搜索路径

LLM 倾向于生成统计上常见且功能正确的代码，但 kernel 优化需要在不连续、硬件相关的性能空间中选择有效路径。无指导的迭代近似随机游走，容易浪费预算或陷入局部最优。

每轮需要决定：

$$
a_t = (k_t, s_t) \in A_t = P_t \times S
$$

其中：

- $P_t$：当前候选 kernel 集合；
- $S$：优化策略集合；
- $A_t$：当前所有“kernel + 策略”组合。

## 3. 解决思路：将搜索决策建模为 contextual bandit

> Our goal is to replace this undirected exploration with a principled decision policy that leverages both program semantics and hardware behavior.

> We formulate this as a contextual bandit problem.

LLM 负责执行代码改写，bandit 负责决定“改哪个 kernel、使用什么策略”。

奖励是单次改写带来的归一化延迟下降：

$$
r_t = \operatorname{Clip}\left(
\frac{L(k_t) - L(k'_t)}{L(k_t)}, 0, 1
\right)
$$

策略 $s$ 对 kernel $k$ 的期望收益为：

$$
\mu(k, s) = \mathbb{E}[r_t \mid k, s]
$$

### 3.1 Behavioral feature vector $\phi(k)$

$$
\phi(k) = [\tilde{T}(k), n_{\mathrm{reg}}, n_{\mathrm{smem}},
d_{\mathrm{block}}, \eta_{\mathrm{occ}}]
$$

用于衡量 kernel 相似性并进行聚类：

- $\tilde{T}(k)$：归一化执行时间；
- $n_{\mathrm{reg}}$：每线程寄存器数；
- $n_{\mathrm{smem}}$：每 block 共享内存；
- $d_{\mathrm{block}}$：block 维度；
- $\eta_{\mathrm{occ}}$：理论 occupancy。

核心假设是：

$$
|\mu(k_1, s) - \mu(k_2, s)|
\le L\|\phi(k_1) - \phi(k_2)\|_2
$$

即特征相近的 kernel，对同一策略的期望响应也相近。

严格来说，$\phi(k)$ 混合了运行时间、静态资源属性和 launch 配置，不能完全称为 program semantics 或 runtime behavior。

### 3.2 Hardware signature $h(k)$

$$
h(k) = [\text{SM throughput}, \text{DRAM throughput}, \text{L2 throughput}]
$$

通过 Nsight Compute 获得，用于判断资源是否接近饱和，并筛选优化策略；它不参与 K-Means 聚类。

## 4. 完整流程

### 4.1 候选特征提取与聚类

每隔 $\tau$ 轮，用当前候选集合中所有 kernel 的 $\phi(k)$ 进行 K-Means：

$$
C_t = \operatorname{KMeans}\left(\{\phi(k): k \in P_t\}, K\right)
$$

聚类让相似 kernel 共享策略收益统计，避免为每个 kernel 单独维护 bandit。

### 4.2 代表 kernel profiling

每个 cluster 选择一个代表 kernel $k_c^{(i)}$，只对代表进行昂贵的硬件 profiling：

$$
h_c^{(i)} = \operatorname{NCU}(k_c^{(i)})
$$

再用它近似整个 cluster 的硬件状态。

### 4.3 硬件剪枝

$$
M_{i,s} = \mathbb{I}\left[
h(k_c^{(i)})[\operatorname{Target}(s)] < \theta_{\mathrm{sat}}
\right]
$$

- $M_{i,s}=1$：策略可以参与选择；
- $M_{i,s}=0$：目标资源已超过阈值，策略被屏蔽。

这是启发式剪枝：资源饱和并不严格等于相关策略没有优化价值。

### 4.4 Masked UCB 选择 cluster 和策略

$$
(I_t, S_t) =
\arg\max_{\substack{i \in [K],\ s \in S \\ M_{i,s}=1}}
\left(
\hat{\mu}_{i,s} + c\sqrt{\frac{\ln t}{N_{i,s}}}
\right)
$$

其中：

- $\hat{\mu}_{i,s}$：该 cluster-strategy 组合的历史平均奖励；
- $N_{i,s}$：该组合被尝试的次数；
- 第一项偏向利用历史上有效的组合；
- 第二项鼓励探索尝试较少的组合。

### 4.5 选择具体 kernel

在选中的 cluster $C_{I_t}$ 内，根据硬件剩余空间选择 kernel：

$$
V_{\mathrm{hw}}(k, S_t) =
\theta_{\mathrm{sat}} - h(k)[\operatorname{Target}(S_t)]
$$

再通过 softmax 抽样具体的 $k_t$。

这里存在描述缺口：论文只 profile 代表 kernel，却又使用每个 kernel 的 $h(k)$ 进行簇内选择。

### 4.6 生成、验证和更新

$$
k'_t \sim P_{\mathrm{LLM}}(\cdot \mid k_t, S_t, H)
$$

对新 kernel 进行：

```text
LLM 生成 → 编译与正确性验证 → 测量延迟
→ 加入候选池 → 更新对应 cluster-strategy 的 UCB 统计
```

理论上，平均奖励差距满足：

$$
\text{Average Regret}
\le O\left(
\sqrt{\frac{K|S_{\mathrm{valid}}|\ln T}{T}}
\right)
+ L\max_i \operatorname{diam}(C_i)
$$

第一项是 bandit 学习误差，第二项是聚类近似误差。该结论约束的是平均即时奖励，并非最终 kernel 与全局最优 kernel 的延迟差距。

## 5. 实验章节 takeaway：我们的实验应如何设计

### 5.1 基准与测评协议

论文使用 corrected TritonBench-G，覆盖多种算子、难度、输入 shape 和 GPU。我们的实验也应明确：

- 修复或排除了哪些 benchmark；
- 正确性如何验证；
- 输入 shape 是否充分；
- 失败和性能退化如何计分；
- 比较是否使用相同迭代、时间和费用预算。

### 5.2 跨硬件适应性

需要证明 agent 会根据 GPU 改变策略分配，而非使用固定搜索模式：

> KernelBand adapts its optimization choices across devices rather than applying a fixed, hardware-agnostic search policy.

除报告不同 GPU 上的最终性能，还应比较：

- 策略选择频率；
- 各策略成功率；
- profiling 指标和策略选择的关系；
- 同一 kernel 在不同 GPU 上的搜索轨迹。

### 5.3 聚类粒度与搜索预算

测试不同 $K$ 和迭代预算 $T$：

- 小预算下，较少 cluster 有利于集中学习；
- 大预算下，适度细分有利于区分不同 kernel；
- cluster 过多会使反馈过度分散。

不能只报告默认 $K$，还要展示 $K$ 与预算的交互关系。

### 5.4 系统成本与并行效率

分别报告串行成本和实际并行后的 wall-clock time：

- LLM 推理；
- profiling；
- 编译；
- kernel 执行；
- 聚类与特征提取。

> Batched inference shifts the bottleneck.

批量调用 LLM 后，瓶颈可能从推理转移到编译和执行，因此系统优化不能只关注模型调用时间。

### 5.5 两级消融实验

**Single-component ablation**：每次删除一个模块，例如：

- 去掉 profiling；
- 去掉聚类；
- 去掉 hardware mask；
- 用随机选择替代 UCB。

**Framework-level ablation**：改变整个搜索范式，例如：

- LLM 自己选择策略；
- 去掉显式策略集合；
- 将原始 profiling 数据直接放入 prompt；
- 使用 Best-of-$N$ 独立采样。

实验需要回答两类问题：**每个组件是否有效，以及结构化搜索是否优于自由生成。**
