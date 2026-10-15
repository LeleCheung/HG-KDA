# 国产芯片 Profiler 预研

检索日期：2026-09-15。下列内容来自实际访问的官方文档或源码；尚未在国产卡上运行。公开文档支持的功能不代表目标服务器的已装版本全部可用。

## 已核实的入口

| 平台 | 官方入口与已读内容 | 拿卡后优先验证 |
| --- | --- | --- |
| 昇腾 | [msProf](https://github.com/Ascend/msprof)：采集/解析 CANN 与 NPU 数据；[msprof-analyze](https://github.com/Ascend/msprof-analyze)：比对和专家建议；[Advisor 指南](https://github.com/Ascend/msprof-analyze/blob/master/docs/zh/user_guide/advisor_instruct.md)列出计算、调度等分析 | 同一算子的 trace、时间、可用 AI Core 指标；版本/数据格式；Advisor 建议对应哪些原始证据 |
| 摩尔线程 | [Moore Perf Compute 性能分析](https://docs.mthreads.com/mooreperf/mooreperf-doc-online/moore_perf_compute/profiling)：LaunchStats、MemoryWorkloadAnalysis、SpeedOfLight，含内存事务/带宽/命中/Bank Conflict 分析；[muPTI](https://docs.mthreads.com/musa-sdk/version-5.2.0/toolkits/mupti)：性能工具接口 | 当前型号支持的 sections、`mcu` 版本与导出方式；重放次数；局部内存/共享存储统计如何归属到 kernel |
| 寒武纪 | [torch_mlu 官方仓库](https://github.com/Cambricon/torch_mlu)；[Profiler 测试](https://github.com/Cambricon/torch_mlu/blob/r1.22_pt2.1.0/test/profiler/test_profiler.py)含 MLU activity 和 Chrome trace 导出；[PMU 测试](https://github.com/Cambricon/torch_mlu/blob/r1.22_pt2.1.0/test/profiler/test_profiler_pmu.py)及 CNPAPI 实现可查 | SDK/PyTorch 扩展与该分支是否匹配；实际 PMU 名称、采集权限、统计口径；不要直接将测试中的开关复制为生产设置 |
| 海光 | [光合开发者社区](https://developer.sourcefind.cn/)已访问；当前只确认到门户入口 | 申请当前 DTK/性能工具手册；核实 profiler 命令、计数器和导出能力，本轮不做字段能力承诺 |
| 沐曦 | [开发者平台](https://developer.metax-tech.com/)已访问；当前只确认到门户入口 | 获取当前 MACA/性能工具文档和样例，核实时间线与 kernel 计数器能力 |

昇腾额外需对照 [MindStudio Agent](https://mindstudio-profiler-docs.readthedocs.io/zh-cn/latest/msagent/)：官方文档已列出 Profiler、Operator 等 Agent 及算子调优能力。其实际效果与开放接口仍需实测。此前笼统地把国产卡描述为缺少工具，依据不足。

## 对研究定位的影响

厂商已经提供分层分析、优化建议，部分提供 Agent。我们应复用这些接口，并检验：**版本历史支持的动作适用条件、对反例的处理和跨后端证据解释，能否进一步提高有效优化率。**

Top-down 思想可以组织提问顺序：热点在哪 → 哪个资源/依赖限制 → 还缺什么证据 → 哪个动作可验证。GPU/NPU 的计算、搬运、同步会重叠，不能未经定义把它们变成相加等于 100% 的时间分区。

## 到机器后的最小操作

先保存型号、SDK、编译器、profiler 版本和 `--help`。以下仅为上述文档中的调用示意，必须匹配现场工具版本：

```bash
# 昇腾 msProf：只针对已能独立运行的本地算子程序
msprof --output=./results/profile --application="python3 bench_one_op.py"
# Advisor 要求相容的 *_ascend_pt / *_ascend_ms 等目录；不能假定上面的输出直接兼容
msprof-analyze advisor all -d /path/to/compatible_profile -o ./results/advisor

# 摩尔线程：先确认这些 sections 在本机支持
mcu --sections LaunchStats,MemoryWorkloadAnalysis,SpeedOfLight ./bench_one_op
```

`bench_one_op.py` / `bench_one_op` 是现场需要提供的算子程序，仓库当前没有这些文件。寒武纪优先用与已安装扩展版本匹配的官方 profiler 最小示例。

对一个算子分别做无 profiler 计时和 profiler 采集。Profiler 的重放、串行化可能改变时序；若算子启动多个 kernel，要逐个关联并报告算子边界，不能简单平均百分比或把重叠 kernel 时间之和当作端到端时间。

## 给老师的交付物

1. **能力矩阵**：原始字段、定义/单位/分母、kernel 或范围、可用性、支持版本、导出命令；保留缺失项。
2. **一个案例**：原始报告 → 厂商诊断 → 我们的候选动作 → 编译/正确性/前后性能；未执行的环节明确待做。
3. **信息缺口**：为了区分两个候选瓶颈，还需要哪项指标、指令信息或厂商说明。

首次汇报可以展示工具文档与能力矩阵；收到卡后用真实样例替换空白。不要把门户可访问、文档有示例或生成了建议，写成已跑通算子优化。
