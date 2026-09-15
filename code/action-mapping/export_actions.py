"""Export the local action workbook without treating its claims as verified rules.

Python 3.9+, standard library only. Run from any working directory.
"""
import argparse
from collections import Counter
import hashlib
import html
import json
from pathlib import Path
import posixpath
import xml.etree.ElementTree as ET
import zipfile

BASE = Path(__file__).resolve().parent
NS = {"s": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
REL = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"


def read_workbook(path):
    with zipfile.ZipFile(path) as archive:
        strings = []
        if "xl/sharedStrings.xml" in archive.namelist():
            root = ET.fromstring(archive.read("xl/sharedStrings.xml"))
            strings = ["".join(t.text or "" for t in si.findall(".//s:t", NS)) for si in root]
        relationships = ET.fromstring(archive.read("xl/_rels/workbook.xml.rels"))
        targets = {r.attrib["Id"]: r.attrib["Target"] for r in relationships}
        workbook = ET.fromstring(archive.read("xl/workbook.xml"))
        for sheet in workbook.findall("s:sheets/s:sheet", NS):
            target = targets[sheet.attrib[f"{{{REL}}}id"]]
            member = target.lstrip("/") if target.startswith("/") else posixpath.normpath("xl/" + target)
            root = ET.fromstring(archive.read(member))
            headers = None
            for row in root.findall("s:sheetData/s:row", NS):
                cells = {}
                for cell in row.findall("s:c", NS):
                    column = "".join(c for c in cell.attrib["r"] if c.isalpha())
                    if cell.find("s:f", NS) is not None:
                        raise ValueError(f"Formula requires review: {sheet.attrib['name']}!{cell.attrib['r']}")
                    value = cell.findtext("s:v", default="", namespaces=NS)
                    if cell.get("t") == "s":
                        value = strings[int(value)]
                    elif cell.get("t") == "inlineStr":
                        value = "".join(t.text or "" for t in cell.findall(".//s:t", NS))
                    cells[column] = value
                if not any(cells.values()):
                    continue
                if headers is None:
                    headers = {col: name for col, name in cells.items() if name}
                    if "method_id" not in headers.values():
                        raise ValueError(f"Missing method_id header in {sheet.attrib['name']}")
                    if len(set(headers.values())) != len(headers):
                        raise ValueError("Duplicate column names")
                    continue
                raw = {name: cells.get(col, "") for col, name in headers.items()}
                if not raw["method_id"]:
                    raise ValueError(f"Missing method_id at row {row.attrib['r']}")
                yield sheet.attrib["name"], int(row.attrib["r"]), raw


def fields(value):
    return [item.strip() for item in value.split(",") if item.strip()]


def export(path):
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    actions = []
    for sheet, row, raw in read_workbook(path):
        review = ["thresholds_unvalidated", "backend_capabilities_unverified", "speedup_claim_unverified"]
        if not raw["source_refs"]:
            review.append("missing_source_refs")
        if not raw["trigger_metric"]:
            review.append("missing_trigger_metric")
        elif not raw["trigger_good"] or not raw["trigger_bad"]:
            review.append("incomplete_thresholds")
        elif raw["trigger_good"] == raw["trigger_bad"]:
            review.append("equal_good_bad_thresholds")
        if raw["trigger_metric"] and raw["trigger_metric"] not in fields(raw["required_evidence"]):
            review.append("trigger_not_in_required_evidence")
        actions.append({
            "method_id": raw["method_id"], "name": raw["name"], "axis": raw["axis"],
            "status": "llm_prior_unvalidated",
            "source": {"workbook": path.name, "sha256": digest, "sheet": sheet, "row": row,
                       "origin": "LLM-generated initial catalog, as reported by project owner"},
            "required_evidence": fields(raw["required_evidence"]),
            "required_features": fields(raw["required_features"]),
            "trigger_proposal": {"metric_alias": raw["trigger_metric"] or None,
                                 "good": raw["trigger_good"] or None, "bad": raw["trigger_bad"] or None,
                                 "direction": raw["trigger_direction"] or None,
                                 "unit": None, "calibration": None},
            "applicability": {"scope": "NVIDIA-oriented source catalog; other backends require review",
                              "min_sm_claim": raw["min_sm"] or None,
                              "architectures_claim": fields(raw["architectures"]),
                              "shape_constraints_claim": raw["shape_constraints"] or None},
            "implementation_hint": raw["reference_impl"] or None,
            "speedup_claim": {"text": raw["typical_speedup"], "verified": False},
            "source_hints": raw["source_refs"] or None,
            "coupled_methods_claim": raw["coupled_methods"] or None,
            "evidence_records": [], "executor": None,
            "review_flags": review, "raw_fields": raw,
        })
    ids = [action["method_id"] for action in actions]
    if not actions or len(set(ids)) != len(ids):
        raise ValueError("Empty catalog or duplicate method IDs")
    return {"schema_version": "0.1", "record_count": len(actions),
            "usage": "Retrieve hypotheses only. Thresholds, speedups and platform claims need validation; null is unknown.",
            "actions": actions}


def render_cases(catalog, cases):
    lookup = {a["method_id"]: a for a in catalog["actions"]}
    sections = []
    for case in cases:
        action = lookup[case["method_id"]]
        items = "".join(f"<dt>{html.escape(label)}</dt><dd>{html.escape(case[key])}</dd>"
                        for key, label in [("original_gap", "原规则待补的证据"), ("evidence", "要观察什么"),
                                           ("hypothesis", "待检验的瓶颈假设"), ("action", "具体修改"),
                                           ("validation", "怎样验证"), ("limits", "适用范围与反例")])
        sections.append(f"<article><span class='tag'>规则初稿 · 待实验验证</span><h2>{html.escape(case['title'])}</h2>"
                        f"<p class='meta'>{html.escape(action['method_id'])} · Excel 第 {action['source']['row']} 行</p>"
                        f"<dl>{items}</dl><p class='status'>状态：没有附带实测加速比；本页展示待执行的验证方案。</p></article>")
    return """<!doctype html><html lang="zh-CN"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>HG-KDA · 证据到动作</title><style>
body{margin:0;background:#f1f4f8;color:#18283e;font:17px/1.6 system-ui,'Microsoft YaHei',sans-serif}
main{max-width:1020px;margin:auto;padding:28px}h1{font-size:30px;margin-bottom:4px}h2{font-size:25px;margin:12px 0}
article{background:white;border:1px solid #dbe3ed;border-radius:14px;padding:28px;margin:24px 0;break-inside:avoid}
.tag{color:#795700;background:#fff0bf;padding:4px 10px;border-radius:5px;font-size:14px}.meta{color:#596b82;font-size:14px}
dl{display:grid;grid-template-columns:170px 1fr;gap:12px 18px}dt{font-weight:600;color:#245279}dd{margin:0}
.status{border-top:1px solid #dbe3ed;padding-top:14px;font-size:14px;color:#596b82}
@media(max-width:640px){dl{grid-template-columns:1fr}main,article{padding:16px}}
@media print{body{background:white}article{break-after:page}}
</style><main><h1>HG-KDA · 从运行证据到优化动作</h1>
<p>3 个可讲解案例｜Excel 初稿 → 证据补充 → 单项修改 → 配对验证</p>""" + "".join(sections) + "</main></html>\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=BASE / "kernel-optimize-优化方法清单.xlsx")
    parser.add_argument("--output-dir", type=Path, default=BASE / "generated")
    parser.add_argument("--method", help="Print one action as JSON instead of writing artifacts")
    args = parser.parse_args()
    catalog = export(args.input)
    if args.method:
        matches = [a for a in catalog["actions"] if a["method_id"] == args.method]
        if not matches:
            parser.error(f"Unknown method: {args.method}")
        print(json.dumps(matches[0], ensure_ascii=False, indent=2))
        return
    cases = json.loads((BASE / "demo_cases.json").read_text(encoding="utf-8"))
    cards = render_cases(catalog, cases)
    axes = Counter(a["axis"] for a in catalog["actions"])
    flags = Counter(flag for a in catalog["actions"] for flag in a["review_flags"])
    summary = "# 动作库导出检查\n\n自动生成；修改 Excel 后重新运行 `export_actions.py`。\n\n"
    summary += f"条目：{catalog['record_count']}；类别：{dict(axes)}。\n\n"
    summary += "所有条目保留原始字段及来源行号。阈值、加速比、架构约束均待核验；未发现任何随表提交的实验记录。\n\n"
    summary += "| 待检查项 | 条目数 |\n| --- | ---: |\n"
    summary += "".join(f"| {flag} | {count} |\n" for flag, count in sorted(flags.items()))
    summary += "\n`min_sm=0` 不代表支持所有芯片；`metric_alias` 需映射到目标 profiler 的真实字段、单位和统计范围。\n"
    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / "actions.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (args.output_dir / "review_summary.md").write_text(summary, encoding="utf-8")
    (args.output_dir / "demo_cards.html").write_text(cards, encoding="utf-8")
    print(f"Exported {catalog['record_count']} actions and {len(cases)} demo cards to {args.output_dir}")


if __name__ == "__main__":
    main()
