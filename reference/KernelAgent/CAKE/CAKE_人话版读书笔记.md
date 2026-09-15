# CAKE：把编译器变成 Kernel Agent 的搭档

论文：*CAKE: Compiler-Agent Co-Design for Frontier Kernel Evolution*  
版本：arXiv:2608.12629v1，2026-08-12

## 先说论文在做什么

CAKE 关注一个很具体的事实：当 Kernel Agent 已经会写 CUDA 以后，继续提升性能会越来越困难。困难通常不在语法，而在于 Agent 不知道硬件真正需要什么，也不知道编译失败、同步错误和性能回退分别对应哪个调度决策。

普通流程是 Agent 写 CUDA/Triton，编译，运行 correctness，测时间，再修改代码。编译器在这个流程里基本是黑盒，只返回成功或失败。CAKE 同时改两边：给 Agent 一个能表达硬件调度的中间表示 Cake IR，并让编译器把错误和性能信息整理成 Agent 能使用的反馈。

论文的贡献可以概括为三件事：

1. 设计一个面向 Agent 的、带类型的硬件显式 IR；
2. 用 verifier、cost model 和局部诊断帮助 Agent 过滤和修改候选；
3. 让 kernel 的反复失败反过来推动 IR、lowering、验证规则和成本模型改进。

CAKE 不是证明 Agent 已经能自动写出所有 GPU kernel。它更像是在证明：程序表示和编译器反馈本身，会决定 Agent 搜索能走多远。

## Cake IR 为什么有用

高层 DSL 往往把 warp 分工、barrier、流水线和不同层次的内存隐藏起来。低层 CUDA/PTX 可以表达这些细节，但 Agent 很容易写错，错误也很难定位。Cake IR 处在两者之间：重要的调度意图写出来，机械细节交给编译器推导。

Agent 需要表达哪些 warp 或 warp group 负责什么、buffer 如何在不同 memory tier 间流动、producer 和 consumer 怎样通过 barrier 交接、pipeline 有几级、使用什么 tensor-core 操作。编译器负责推导 barrier 地址、phase bit、TMEM offset、descriptor encoding 等细节，减少 Agent 手写底层细节的面积。

Cake program 显式包含 operation、resource、warp role、grid 和 pipeline 配置。buffer 的 shape、dtype、owner 和 lifetime 也进入检查，因此编译器可以把问题指回某个 schedule 决策，而不是返回模糊的编译错误。

CAKE 没有把 layout 做成类似 CuTe 的完整代数系统。Agent 写具体的存储和访问承诺，verifier 检查这些承诺是否沿数据流一致、是否满足硬件约束。代价是 layout 的复杂性更多落在 verifier 和 lowering 中，而且这种 IR 明显带有 NVIDIA/Blackwell 色彩，不能直接当成通用跨架构 IR。

## Compiler harness 做什么

Compiler harness 是一组让 Agent 能持续工作的接口：编译前检查同步、内存、资源、指令和 schedule contract；运行时检查数值正确性；用 cost model 做候选排序；把性能分析变成修改提示；保存源码、配置、失败原因、修改 diff 和测量结果。

静态 verifier 不是完整的 GPU 正确性证明，cost model 也不能取代真机测量。它们的作用是减少无效试验，并尽量解释失败原因。最终正确性和性能仍由真实执行裁决。

## “共同演化”是什么意思

kernel evolution 负责生成 Cake IR、静态检查、cost-model 排序、真实 correctness/benchmark/profiling 和下一轮修改。compiler-harness evolution 则把重复出现的问题沉淀下来：同步错误变成 verifier rule，系统性误判变成 calibration target，反复需要的硬件操作变成 IR primitive 或 lowering 支持。

这不是完全无人监督地修改编译器。IR 设计带有专家的 Blackwell 知识，编译器改动需要 kernel corpus 测试和人工 merge gate。Agent 发现问题、提出修改，人类控制最终合入。

## 关键实验和边界

最能说明问题的是 Flash-KMeans `assign` 的 clean-start 对照。任务固定为 B=32、N=65536、K=1024、D=128，BF16 输入、FP32 累加，FlashML Triton 作为 baseline。相同 Agent、预算和 correctness/benchmark harness，分别编辑 Cake IR 或 CUDA/PTX。

三次运行中，Cake IR 的性能中位数是 FlashML 的 1.144 倍，CUDA/PTX 是 0.928 倍；Cake IR 三次都在预算内达到 plateau，CUDA/PTX 三次都没有达到。这个结果说明程序表示可能影响搜索效率，但它仍只有一个 kernel、一个 shape、每组 3 次运行，不能证明 Cake IR 在所有任务上都更好。

论文还报告 Kimi Delta Attention、TinyGEMM、Alpha-MoE、known-kernel reproduction 和 KNN/KMeans portfolio 结果。它们使用不同硬件、shape、baseline 和指标，不能混在一起比较；API 层收益也不能直接当作核心 kernel 吞吐提升。

## 阅读结论

CAKE 最有价值的地方，是把程序表示、静态检查、真实执行、局部诊断、失败沉淀和生产交付连成一个闭环。它提醒我们，单 shape 最优 kernel 还需要 dispatcher、guard、fallback 和 held-out shape 验证。

论文的边界也很清楚：主要证据来自 NVIDIA，尤其是 B200；搜索成本高；模型、token、GPU-hours 和完整复现条件披露不足；IR 设计依赖硬件专家。因此 CAKE 适合作为“编译器和 Agent 应共同设计”的强基线，而不是跨国产卡通用方案的证明。

## 对我们项目的启发

我们不需要复制 Cake IR。可以借鉴它的思路，把系统拆成静态硬件知识库、动态 profiler、profiling 证据到 IR/pass/调度动作的映射。XSAI 用来完整观察和验证这条映射，国产卡用来检验信息不完整时它是否仍然有效。

