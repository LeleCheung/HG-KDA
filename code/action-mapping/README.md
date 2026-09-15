# 动作库：从模型先验到验证规则

Excel 是本科生让大模型基于已有知识生成的初稿。JSON 转换只改变格式，所有条目保持 `llm_prior_unvalidated` 状态。原表的阈值、典型加速比、参考实现和架构条件均保留为待核验声明。

在仓库根目录运行（Python 3.9+，无第三方依赖）：

```bash
python3 code/action-mapping/export_actions.py
python3 code/action-mapping/export_actions.py --method memory.coalesced_access
```

- [generated/actions.json](generated/actions.json)：78 条可检索记录，保留 Excel 行号、文件 SHA-256 和全部原始字段。
- [generated/review_summary.md](generated/review_summary.md)：缺失证据、阈值等问题统计。
- [generated/demo_cards.html](generated/demo_cards.html)：浏览器直接打开，可截图或打印；3 个案例均标为待验证。
- [demo_cases.json](demo_cases.json)：案例解释及验证方案，供 Linux 端 Agent 筛选/补充。

Agent 先检索候选方法，再确认指标含义、后端能力和适用条件，提出局部修改并验证。当前记录没有执行器，不能直接把数值阈值当成自动改代码的规则；`null` 表示未知。修改数据源后重新导出，不手改 generated 文件。

汇报时可说：**已经把 78 条模型先验整理成可追溯的候选动作库，并找出了需要补证据的触发条件；下一步用 FlagGems 版本对和受控实验验证。**

构建方法与历史数据需求见 [映射构建与 FlagGems 数据方案](../../docs/映射构建与FlagGems数据方案.md)。
