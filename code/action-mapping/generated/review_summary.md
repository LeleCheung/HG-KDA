# 动作库导出检查

自动生成；修改 Excel 后重新运行 `export_actions.py`。

条目：78；类别：{'compute': 26, 'memory': 27, 'latency': 25}。

所有条目保留原始字段及来源行号。阈值、加速比、架构约束均待核验；未发现任何随表提交的实验记录。

| 待检查项 | 条目数 |
| --- | ---: |
| backend_capabilities_unverified | 78 |
| equal_good_bad_thresholds | 1 |
| incomplete_thresholds | 11 |
| missing_source_refs | 75 |
| missing_trigger_metric | 20 |
| speedup_claim_unverified | 78 |
| thresholds_unvalidated | 78 |
| trigger_not_in_required_evidence | 1 |

`min_sm=0` 不代表支持所有芯片；`metric_alias` 需映射到目标 profiler 的真实字段、单位和统计范围。
