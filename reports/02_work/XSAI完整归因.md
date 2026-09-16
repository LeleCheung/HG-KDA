SHAP/XGBoost 不是直接把 counter 喂给 Agent，而是先用历史数据学习“哪些 profiling 字段能解释某个诊断或动作结果”，再把结果用于证据选择。

假设每条样本包含：

```text
算子、shape、dtype、硬件、编译配置
profiling 字段
动作
修改前后 latency
修改前后 profiling
```

可以定义不同的预测目标：

```text
y1 = 当前瓶颈类别
y2 = 某个动作是否成功
y3 = 某个动作带来的 speedup
y4 = 动作失败或回退的概率
```

同一批 counter，针对不同目标训练出来的特征重要性可能完全不同。

## 1. 筛选候选字段

例如训练模型预测“是否应该增加 double buffering”：

```text
输入：
memory_stall
dma_overlap
compute_utilization
dram_bandwidth
occupancy
register_count
bank_conflict
...

输出：
动作成功概率，或者动作带来的 speedup
```

XGBoost 学习这些字段与目标之间的非线性关系。SHAP 对每个样本解释：

```text
当前样本预测 speedup = 1.18×

memory_stall 较高       → +0.10
dma_overlap 较低        → +0.07
compute_utilization 较高 → -0.03
register_count 较高     → -0.02
```

在整个验证集上统计 `mean(abs(SHAP))`，可以得到全局候选字段排序：

```text
memory_stall       0.21
dma_overlap        0.17
occupancy           0.09
register_count      0.05
bank_conflict       0.01
```

这可以帮助你：

- 从几百个原始 counter 中筛出较小的候选集合；
- 找到可能重复、无信息量或只与特定平台相关的字段；
- 设计统一 profiler schema 时确定优先保留哪些字段。

但这里的结论是“对预测模型有用”，不是“该字段具有因果作用”。例如 `memory_stall` 可能只是很多其他现象的结果。

## 2. 发现非线性交互

硬件性能通常不是“一个 counter 高，就一定应该执行某个动作”。

例如：

- `memory_stall` 高，但带宽已经接近上限时，增加并行度可能没有效果；
- `memory_stall` 高且 `dma_overlap` 低时，double buffering 可能有效；
- `register_count` 高且 occupancy 低时，缩小 tile 可能有效；
- `register_count` 高但没有 spill 时，减少寄存器未必带来收益。

XGBoost 能表示这类条件关系，SHAP interaction values 可以进一步查看字段之间的交互：

```text
memory_stall × dma_overlap
register_count × occupancy
tile_size × arithmetic_intensity
```

例如得到：

```text
memory_stall 单独贡献：+0.04
dma_overlap 单独贡献：+0.02
两者交互贡献：+0.11
```

这说明“高 memory stall + 低 DMA overlap”比单独看任一字段更能预测 double buffering 的收益。

项目中可以把这种交互转成动作触发条件：

```text
if memory_stall 高
and dma_overlap 低
and register_pressure 不高:
    候选动作 = 增加 double buffering
```

## 3. 预测动作收益

这里不能只训练一个“总体性能模型”，而应以动作结果为目标。

例如针对每个动作建立模型：

```text
M_tile：预测调整 tile 后的 speedup
M_pipeline：预测调整 pipeline stage 后的 speedup
M_layout：预测 layout 调整后的 speedup
M_fusion：预测 fusion 后的 speedup
```

对于当前算子，模型输出：

```text
调整 tile       预测 speedup 1.04，成功概率 0.82
增加 pipeline   预测 speedup 1.17，成功概率 0.71
修改 layout     预测 speedup 1.08，成功概率 0.64
fusion           预测 speedup 0.99，成功概率 0.40
```

Agent 可以据此决定：

1. 先尝试哪些动作；
2. 哪些动作不值得编译和测量；
3. 哪些动作需要更多 profiling；
4. 失败后选择什么回退方案。

更稳妥的做法是同时预测：

```text
期望收益 = 成功概率 × speedup收益 - 失败成本
```

这样就不会只追求预测 speedup，而忽略编译失败、正确性风险或测量成本。

## 4. 构造问题条件化的 Top-K

固定一个全局 Top-K，例如永远把：

```text
memory_stall、occupancy、bandwidth、register_count、IPC
```

交给 Agent，意义有限。不同动作需要不同证据。

应该先确定当前诊断问题，再动态选字段。

| 当前问题 | 优先证据 |
|---|---|
| 是否需要 double buffering | memory stall、DMA overlap、片上存储余量、compute 利用率 |
| 是否需要缩小 register tile | register count、spill 流量、occupancy、local memory traffic |
| 是否需要改 layout | stride、transaction/sectors、bank conflict、地址分布 |
| 是否需要 fusion | launch gap、DRAM bytes、中间结果读写、端到端调用时间 |
| 是否需要提高并行度 | occupancy、active warps、dispatch 利用率、依赖 stall |

具体流程可以是：

```text
1. 根据端到端指标和粗粒度 counter 判断当前问题属于哪一类；
2. 为该问题加载对应的候选动作；
3. 使用该动作对应的 XGBoost 模型计算当前样本的 SHAP；
4. 按当前样本的 SHAP 贡献排序；
5. 选择能够区分候选动作的最小证据集合；
6. 将语义化结果和证据来源交给 Agent。
```

例如当前观察到：

```text
device execution 时间高
compute_utilization 中等
memory_stall 高
```

系统先判断问题偏向 memory movement，然后只在相关字段中计算排序：

```text
memory_stall       SHAP +0.18
dma_overlap        SHAP +0.14
dram_bandwidth     SHAP +0.05
occupancy          SHAP +0.03
register_count     SHAP +0.01
```

最终给 Agent 的内容可以是：

```text
语义判断：数据搬运等待，DMA 与计算重叠不足
关键证据：
- memory_stall = 42%
- dma_overlap = 18%
- compute_utilization = 51%

候选动作：
1. 增加 double buffering
2. 调整 pipeline stage
3. 检查 tile 是否受片上存储限制
```

而不是直接发送几百个原始字段。

## 需要特别区分的三种“重要性”

SHAP 结果至少有三种用途，但不能混为一谈：

1. **预测重要性**
   哪些字段有助于预测 speedup 或动作成功率。

2. **诊断重要性**
   哪些字段有助于区分 `memory_wait`、`low_occupancy` 等瓶颈。

3. **因果证据**
   改变某个硬件因素后，性能和相关 counter 是否按预期变化。

前两种可以用 XGBoost+SHAP 辅助，第三种必须用 XSAI 或国产卡上的受控干预实验验证。

因此最终研究流程应是：

```text
XGBoost + SHAP
→ 发现候选字段和交互
→ 形成问题条件化证据集合
→ XSAI 干预实验验证因果关系
→ 固化为可解释的瓶颈规则和动作映射
```

SHAP 负责从大量字段中发现线索，不能单独证明“这个 counter 高，所以应该执行某个优化动作”。
