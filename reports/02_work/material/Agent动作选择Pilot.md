# Agent 动作选择 Pilot

日期：2026-09-16。本实验检查动作选择评测链路是否可用，不提供统计性结论。

## 设计

从独立的 `gemm-heldout` workload 构造两道题，gold action 由实际 emu 干预结果决定：

| case | baseline | gold action | intervention | 实测变化 |
| --- | --- | --- | --- | ---: |
| `loop-heldout` | `kji`，49,644 cycles | 改为连续 j 内层的 `ikj` | 28,488 cycles | 1.7426x |
| `tile-boundary` | `reg4x4`，33,855 cycles | 测试更大的 `reg8x8` | 32,550 cycles | 1.0401x |

三组 Agent 收到相同的算子、代码结构、候选动作、正确性、周期和指令数。额外反馈分别为：

1. `latency_only`：没有 profiler counter；准确说是 latency + 静态程序上下文。
2. `raw_counters`：增加未经解释的 RTL counter。
3. `semantic_mapping`：增加瓶颈假设、置信度、动作约束、风险和预期验证信号。

每组使用独立、无历史上下文、禁止读仓库和运行工具的 Agent。输出使用相同 JSON 结构。gold 在决策完成后才用于评分。

## 结果

| condition | loop case | tile boundary | 合计 |
| --- | --- | --- | ---: |
| latency-only | 正确 | 错误：选择缩小 2x2 | 1/2 |
| raw counters | 正确 | 错误：选择缩小 2x2 | 1/2 |
| semantic mapping | 正确 | 正确：测试增大 8x8 | 2/2 |

三组都能从 row-major 访问结构选出循环换序。差异出现在边界题：前两组看到 stack-resident accumulator 后，将“存在资源压力”直接解释为“应缩小 tile”；但实际测量中 8x8 仍比 4x4 快 4.0%。语义映射显式表达“压力存在，但回退点未知，必须测试相邻 tile，不能仅凭 stack traffic 判定方向”，因此选中实测有效动作。

## 调用方式与限制

最初使用本机 `codex exec` 建立临时只读会话，通过 stdin 传入固定 prompt，并用 JSON Schema 约束输出。该调用在本机连接 OpenAI Responses API 时收到 HTTP 403 `Country, region, or territory not supported`，没有产生模型答案。

本轮实际结果来自当前环境的三个独立子 Agent；它们使用 `fork_turns=none`，只接收对应盲化题面。prompt、schema、gold、原始回复和评分脚本均保存在 `code/action-mapping/eval/`。

本 pilot 只有两个 case、每个条件只有一次模型决策；`semantic_mapping` 还直接包含动作约束。因此 2/2 对 1/2 只能说明评测链路可工作，并给出一个符合研究假设的案例，不能声称方法总体优于 raw counters。下一步至少需要扩展到多个 shape、更多循环排列、多个 tile 回退点和重复模型采样，并在相同 token/测量预算下报告准确率、回退率和校准误差。

