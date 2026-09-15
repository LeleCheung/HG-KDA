# AVO：让 Agent 自己管理一段 Kernel 优化过程

论文：*AVO: Agentic Variation Operators for Autonomous Evolutionary Search*  
版本：arXiv:2603.24517v1，2026-03-25

## 论文想改变什么

传统演化搜索中，外部框架负责选 parent、管理 population 和安排评测，LLM 只负责把旧程序改成新程序。AVO 认为 kernel 优化不是一次代码补全，而是一项持续的软件工程工作，所以把 variation operator 交给完整的 coding agent。

这个 Agent 自己决定看哪个历史版本、查哪些资料、什么时候 profiling、如何解释编译或 correctness 失败、是否继续当前路线以及什么时候提交新版本。外部系统仍负责运行和评分，但不再规定每一步都按固定顺序执行。

## 实验对象和结果

AVO 在 NVIDIA B200 上优化 BF16 Attention forward-prefill kernel，主要是 MHA，也做了 GQA 迁移。系统连续运行 7 天，内部探索超过 500 个方向，提交 40 个递进版本。论文报告最高 1668 TFLOPS；在测试范围内，相对 cuDNN 最高提升 3.5%，相对 FlashAttention-4 最高提升 10.5%。MHA 到 GQA 的适配约用了 30 分钟。

这些结果应理解为“B200 Attention 上的强能力展示”。实验没有覆盖其他 GPU、其他算子、其他精度和完整 decode 场景，核心 campaign 也没有多随机种子的独立重复。

## 一轮 variation 中发生什么

Agent 阅读历史实现和 profiling，查询 CUDA/PTX/Blackwell 资料，判断瓶颈并修改 CUDA/inline PTX，然后编译、做 correctness 和 benchmark。如果失败或回退，就分析原因继续修改；只有新版本可靠且更快时才提交。

AVO 还设置 supervisor 处理停滞和循环。论文所谓“无人参与”，是运行期间没有人工逐步操作，不是没有 supervisor、初始 seed、知识库和固定评测 contract。

## 三个有代表性的优化

**Branchless accumulator rescaling。** 线性 softmax 需要根据 running maximum 是否变化决定是否重缩放 accumulator。AVO 改成始终计算 factor，再用 predicated select 选择 1.0，减少分支和同步开销；non-causal 约提升 8.1%，causal 约提升 1.6%。

**Correction 与 MMA 重叠。** 原实现等两个 Q-stage 的 PV GEMM 都完成后才启动 correction。后续版本在第一个 stage 完成后就启动 correction，使它和第二个 PV GEMM 重叠，non-causal 约提升 1.1%。

**Warp group 寄存器重平衡。** Profiler 显示 correction group spill，而 softmax group 还有寄存器余量。AVO 将分配从 192/80/48 调整为 184/88/56，减少关键路径上的 spill，non-causal 约提升 2.1%。

这些案例说明，后期优化往往来自控制流、同步、流水线、寄存器压力和 memory fence 的联合权衡，Agent 不只是替换代码模板。

## 阅读结论

AVO 的价值是把搜索变成长时间、可回溯的软件工程循环，强调历史版本、失败诊断、停滞检测和 supervisor。它使用了较强的 cuDNN/FA4 baseline、同机测量和 correctness gate。

它的不足也很明显：模型和推理成本不透明，缺少严格组件消融和多次独立运行；初始 seed 和知识库包含成熟实现，因此不是从数学定义开始的 clean-start synthesis；实验范围集中在 B200 Attention。

## 对我们项目的启发

AVO 可以作为“Agent 如何长期使用 profiling 和历史证据”的基线。我们的重点应放在信息受限时的三个问题：采集什么证据、如何判断证据够不够、如何把瓶颈映射成下一步 IR/pass/调度动作。AVO 研究 Agent 的自主演化，我们研究支撑这种演化的硬件证据接口和动作映射。

