# Linux 端接手：本次汇报的三项工作

首次：`git clone https://github.com/LeleCheung/HG-KDA.git`；已有 checkout：确认本地修改后 `git pull --ff-only`。在仓库根目录开展以下任务。

## 1. 动作映射：先展示，再补实验

```bash
python3 code/action-mapping/export_actions.py
python3 code/action-mapping/export_actions.py --method memory.coalesced_access
```

打开 [3 张案例卡](../../code/action-mapping/generated/demo_cards.html)，选择本机能验证的 2–3 个讲解，其中至少一个争取有真实修改前后结果。卡片当前展示的是计划，不包含已测得加速。

现有卡片的[截图预览](assets/action-cards.png)可直接查看；修改案例后重新导出 HTML，并更新用于汇报的截图。

核对 [动作库](../../code/action-mapping/README.md)和[构建方案](../../docs/映射构建与FlagGems数据方案.md)。阈值、典型加速比和 NVIDIA 的 `min_sm` 不能直接当成跨平台事实。只有 AMX 主机时，保留 CUDA 案例用于讲解；验证需要改写为 CPU 适用的动作并单独建立记录。

向智源提出历史版本数据需求：先取少量可复跑的父子版本对，带输入、环境、代码差异、前后 profile 和失败记录。原始合作数据放 `data/private/`，实验产物放 `results/`，均已忽略。

## 2. XSAI-emu：先确认能跑，再研究优化

阅读 [能力与 Linux 验证](../../docs/XSAI-emu能力与Linux验证.md)，按“环境 → 解包哈希 → Hello → 小 GEMM 两版本 → 正确性 → guest 周期 → 热点解释”执行。详细命令见 [原 guide](../../code/profiling/XSAI-emu/XSAI-emu-guide.md)。

当前包是预编译 emu，不含完整 RTL 源码/工具链/workload。AMX 是宿主能力，不会自动使 guest 使用 AMX。未取得内核测量范围时，周期结果注明整个 workload，不报告 kernel speedup。

首轮只做现有 counters 的语义解释与变体实验；Top-K 建模需要同语义、可比较的多版本数据。全量/固定 Top-K/层次证据的对照应保留相同任务和算法工作量。

## 3. 国产芯片：预研已有入口，拿卡后验证

阅读 [官方工具预研](../../docs/国产芯片Profiler预研.md)。先确认卡型号，按目标 SDK 补能力矩阵，复现一个厂商 profiler 示例，再走一个算子闭环。把厂商已有专家建议/Agent 纳入对照。

## 本次汇报产物

- 动作卡：来源、待核验条件、两三个可讲案例；有实验时再补数值。
- XSAI：实际跑通步骤、版本/命令、正确性、明确口径的 guest 数据、待解决问题。
- 国产卡：官方工具入口、能力矩阵、首个实机案例或尚待获取的信息。

优先在本目录新增 `实验进展.md`，逐项记录“已验证 / 仅文档支持 / 未执行”。复用实现进入 `code/`，附 commit、命令和结果位置。下一次周汇报再建新轮次目录。
