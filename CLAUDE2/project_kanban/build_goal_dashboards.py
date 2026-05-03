from __future__ import annotations

import html
import json
import re
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict
from pathlib import Path
from zipfile import ZipFile


WORKBOOK_PATTERN = "*工作目标*.xlsx"
CURRENT_MONTH = 5
MONTHS = range(1, CURRENT_MONTH + 1)

NS = {"a": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
REL_NS = {"rel": "http://schemas.openxmlformats.org/package/2006/relationships"}
RID = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id"


NEGATIVE_WORDS = (
    "延期",
    "延时",
    "未完成",
    "未按要求",
    "扣分",
    "质量问题",
    "存在问题",
    "暂停",
    "终止",
)

RISK_WORDS = (
    "暂缓",
    "暂停",
    "待确认",
    "未开始",
    "暂未启动",
    "暂无进度",
    "跟进",
    "正在",
    "待",
    "风险",
)

DONE_WORDS = (
    "已完成",
    "完成",
    "已上线",
    "已部署",
    "已发起",
    "已提交",
    "已输出",
)


def col_to_idx(cell_ref: str) -> int:
    match = re.match(r"([A-Z]+)", cell_ref)
    if not match:
        return 0
    value = 0
    for char in match.group(1):
        value = value * 26 + ord(char) - 64
    return value - 1


def read_shared_strings(zip_file: ZipFile) -> list[str]:
    if "xl/sharedStrings.xml" not in zip_file.namelist():
        return []
    root = ET.fromstring(zip_file.read("xl/sharedStrings.xml"))
    strings: list[str] = []
    for item in root.findall("a:si", NS):
        strings.append("".join(text.text or "" for text in item.findall(".//a:t", NS)))
    return strings


def cell_value(cell: ET.Element, shared_strings: list[str]) -> str:
    cell_type = cell.attrib.get("t")
    if cell_type == "s":
        value = cell.find("a:v", NS)
        if value is None or value.text is None:
            return ""
        return shared_strings[int(value.text)]
    if cell_type == "inlineStr":
        return "".join(text.text or "" for text in cell.findall(".//a:t", NS))
    value = cell.find("a:v", NS)
    return value.text if value is not None and value.text is not None else ""


def read_sheet_rows(zip_file: ZipFile, sheet_path: str) -> list[list[str]]:
    shared_strings = read_shared_strings(zip_file)
    root = ET.fromstring(zip_file.read(sheet_path))
    rows: list[list[str]] = []
    for row in root.findall(".//a:sheetData/a:row", NS):
        values: list[str] = []
        for cell in row.findall("a:c", NS):
            idx = col_to_idx(cell.attrib["r"])
            while len(values) <= idx:
                values.append("")
            values[idx] = clean_text(cell_value(cell, shared_strings))
        rows.append(values)
    return rows


def clean_text(value: object) -> str:
    text = "" if value is None else str(value)
    return re.sub(r"[ \t]+", " ", text.replace("\r\n", "\n").replace("\r", "\n")).strip()


def workbook_sheet_paths(zip_file: ZipFile) -> dict[str, str]:
    workbook = ET.fromstring(zip_file.read("xl/workbook.xml"))
    rels = ET.fromstring(zip_file.read("xl/_rels/workbook.xml.rels"))
    rel_map = {rel.attrib["Id"]: rel.attrib["Target"] for rel in rels.findall("rel:Relationship", REL_NS)}
    sheet_map: dict[str, str] = {}
    for sheet in workbook.findall("a:sheets/a:sheet", NS):
        name = sheet.attrib["name"]
        target = rel_map[sheet.attrib[RID]]
        sheet_map[name] = "xl/" + target if not target.startswith("xl/") else target
    return sheet_map


def safe_int(value: str) -> int | None:
    match = re.search(r"-?\d+", clean_text(value))
    return int(match.group(0)) if match else None


def normalize_row(row: list[str], width: int) -> list[str]:
    return row + [""] * max(0, width - len(row))


def parse_sheet(zip_file: ZipFile, sheet_name: str, sheet_path: str) -> list[dict]:
    rows = read_sheet_rows(zip_file, sheet_path)
    header_idx = next(
        idx for idx, row in enumerate(rows) if len(row) > 6 and row[0] == "序号" and "项目" in row[3]
    )
    header = rows[header_idx]
    width = max(len(header), max((len(row) for row in rows), default=0))
    tasks: list[dict] = []

    for row in rows[header_idx + 1 :]:
        row = normalize_row(row, width)
        seq = safe_int(row[0] if row else "")
        project = clean_text(row[3] if len(row) > 3 else "")
        center = clean_text(row[1] if len(row) > 1 else "")
        if seq is None or not project or not center:
            continue

        monthly: list[dict] = []
        for month in MONTHS:
            base = 10 + (month - 1) * 4
            plan = clean_text(row[base] if base < len(row) else "")
            actual = clean_text(row[base + 1] if base + 1 < len(row) else "")
            score = clean_text(row[base + 2] if base + 2 < len(row) else "")
            note = clean_text(row[base + 3] if base + 3 < len(row) else "")
            monthly.append({"month": month, "plan": plan, "actual": actual, "score": score, "note": note})

        task = {
            "seq": seq,
            "sheet": sheet_name,
            "center": center,
            "keyTask": clean_text(row[2] if len(row) > 2 else ""),
            "project": project,
            "target": clean_text(row[4] if len(row) > 4 else ""),
            "stagePlan": clean_text(row[5] if len(row) > 5 else ""),
            "owner": clean_text(row[6] if len(row) > 6 else ""),
            "rawStatus": clean_text(row[7] if len(row) > 7 else ""),
            "selfDeveloped": clean_text(row[8] if len(row) > 8 else ""),
            "assessor": clean_text(row[9] if len(row) > 9 else ""),
            "monthly": monthly,
        }
        task.update(classify_task(task))
        tasks.append(task)
    return tasks


def text_has(text: str, words: tuple[str, ...]) -> bool:
    return any(word in text for word in words)


def classify_task(task: dict) -> dict:
    monthly = task["monthly"]
    current = monthly[-1]
    current_text = "\n".join([current["plan"], current["actual"], current["score"], current["note"]])
    negative_score = safe_int(current["score"]) is not None and safe_int(current["score"]) < 0

    if negative_score or text_has(current_text, ("扣分", "未按要求", "质量问题")):
        status = "red"
        reason = "扣分/质量问题"
    elif text_has(current_text, ("延期", "延时", "未完成")):
        status = "red"
        reason = "当月延期或未完成"
    elif current["plan"] and not current["actual"]:
        status = "yellow"
        reason = "当月有计划但未填实际"
    elif text_has(current_text, RISK_WORDS):
        status = "yellow"
        reason = "暂停/待确认/外部依赖"
    elif text_has(current["actual"], DONE_WORDS):
        status = "green"
        reason = "已完成或按计划推进"
    else:
        status = "yellow"
        reason = "进展待补充"

    stage_plan = task.get("stagePlan", "")
    has_may_plan = bool(current["plan"]) or bool(re.search(r"5\s*月|五月", stage_plan))
    closed = status == "green" or text_has(current["actual"], DONE_WORDS)
    key_task = "重点任务" in task.get("keyTask", "")
    needs_decision = status == "red" or ("协调" in current_text and status != "green")

    return {
        "status": status,
        "statusText": {"green": "正常", "yellow": "风险", "red": "异常"}[status],
        "reason": reason,
        "latestPlan": current["plan"] or stage_plan,
        "latestActual": current["actual"],
        "latestScore": current["score"],
        "latestNote": current["note"],
        "hasMayPlan": has_may_plan,
        "closed": closed,
        "isKeyTask": key_task,
        "needsDecision": needs_decision,
    }


def summarize(tasks: list[dict]) -> dict:
    total = len(tasks)
    status_counts = Counter(task["status"] for task in tasks)
    center_counts = Counter(task["center"] for task in tasks)
    key_total = sum(task["isKeyTask"] for task in tasks)
    may_total = sum(task["hasMayPlan"] for task in tasks)
    decision_total = sum(task["needsDecision"] for task in tasks)
    closed_total = sum(text_has(task.get("latestActual", ""), DONE_WORDS) for task in tasks)
    self_dev_total = sum("是" in task["selfDeveloped"] for task in tasks)
    paused_total = sum(text_has(task["latestActual"], ("暂停", "暂缓")) for task in tasks)
    ontime = status_counts["green"]

    center_summary = []
    for center, count in center_counts.most_common():
        center_tasks = [task for task in tasks if task["center"] == center]
        center_summary.append(
            {
                "center": center,
                "total": count,
                "green": sum(task["status"] == "green" for task in center_tasks),
                "yellow": sum(task["status"] == "yellow" for task in center_tasks),
                "red": sum(task["status"] == "red" for task in center_tasks),
                "key": sum(task["isKeyTask"] for task in center_tasks),
            }
        )

    return {
        "total": total,
        "green": status_counts["green"],
        "yellow": status_counts["yellow"],
        "red": status_counts["red"],
        "keyTotal": key_total,
        "mayTotal": may_total,
        "decisionTotal": decision_total,
        "closedRate": round(closed_total / total * 100) if total else 0,
        "ontimeRate": round(ontime / total * 100) if total else 0,
        "selfDevTotal": self_dev_total,
        "closedTotal": closed_total,
        "pausedTotal": paused_total,
        "centerSummary": center_summary,
        "redTasks": [task for task in tasks if task["status"] == "red"],
        "yellowTasks": [task for task in tasks if task["status"] == "yellow"],
        "mayTasks": [task for task in tasks if task["hasMayPlan"]],
    }


def compact(text: str, length: int = 90) -> str:
    text = clean_text(text).replace("\n", "；")
    return text if len(text) <= length else text[: length - 1] + "…"


def build_dashboard(title: str, subtitle: str, tasks: list[dict], output_path: Path, source_name: str, sheet_indicator: str = "") -> None:
    summary = summarize(tasks)
    data_json = json.dumps({"tasks": tasks, "currentMonth": CURRENT_MONTH}, ensure_ascii=False)

    month_buttons = "".join(
        f'<button class="mbtn" data-m="{m}">{m}月</button>'
        for m in MONTHS
    )

    page = f"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(title)}</title>
  <style>
    :root{{--ink:#172033;--muted:#68758b;--line:#dbe4f0;--panel:#fff;--green:#18a058;--green-soft:#e9f8ef;--yellow:#d99a00;--yellow-soft:#fff6dd;--red:#d92d20;--red-soft:#fff0ee;--blue:#2158d0;--blue-soft:#eef4ff;--shadow:0 18px 44px rgba(31,48,83,.11);--radius:8px}}
    *{{box-sizing:border-box}}
    body{{margin:0;background:linear-gradient(180deg,#eaf1fb 0,#f7f9fc 35%,#eef3f8 100%);font-family:"Microsoft YaHei","PingFang SC",Arial,sans-serif;color:var(--ink)}}
    .page{{width:min(1680px,calc(100vw - 32px));margin:0 auto;padding:14px 0 20px}}
    .top{{display:flex;justify-content:space-between;gap:18px;align-items:center;margin-bottom:10px}}
    h1{{margin:0;font-size:30px;line-height:1.15}} .sub{{margin:5px 0 0;color:var(--muted);font-size:14px}}
    .actions{{display:flex;gap:8px;align-items:center;flex-wrap:wrap;justify-content:flex-end}}
    .btn,.stamp{{height:36px;border:1px solid var(--line);background:#fff;border-radius:6px;padding:0 12px;display:inline-flex;align-items:center;color:var(--ink);font-weight:700;cursor:pointer}}
    .stamp{{cursor:default;font-weight:400;color:var(--muted)}}
    .mbar{{display:flex;gap:6px;align-items:center;margin-bottom:10px;background:#fff;border:1px solid var(--line);border-radius:var(--radius);padding:8px 14px;box-shadow:0 8px 20px rgba(31,48,83,.06)}}
    .mbar label{{font-weight:700;font-size:14px;margin-right:6px;white-space:nowrap}}
    .mbtn{{height:32px;min-width:52px;border:1px solid var(--line);background:#fff;border-radius:6px;padding:0 12px;cursor:pointer;font-weight:700;font-size:13px;color:var(--ink);transition:all .15s}}
    .mbtn:hover{{background:var(--blue-soft);border-color:#a8bfea}}
    .mbtn.on{{background:var(--blue);color:#fff;border-color:var(--blue)}}
    .mbtn-go{{height:32px;border:1px solid var(--blue);background:var(--blue);color:#fff;border-radius:6px;padding:0 16px;cursor:pointer;font-weight:700;font-size:13px;margin-left:8px}}
    .hero{{border:1px solid #bfccdf;border-radius:var(--radius);box-shadow:var(--shadow);background:#fff;padding:10px;margin-bottom:10px}}
    .kpis{{display:grid;grid-template-columns:1.3fr repeat(7,1fr);gap:8px}}
    .conclusion,.kpi{{border-radius:var(--radius);min-height:94px;padding:11px 13px;cursor:pointer}}
    .conclusion{{background:#17233d;color:#fff;display:flex;flex-direction:column;justify-content:space-between;overflow:hidden;position:relative}}
    .conclusion b{{font-size:28px;line-height:1.05}} .conclusion span,.conclusion p{{position:relative;margin:0;color:rgba(255,255,255,.76);font-size:12px}}
    .kpi{{border:1px solid var(--line);background:#fff;display:flex;flex-direction:column;justify-content:space-between}}
    .kpi.green{{background:var(--green-soft);border-color:#bce8ce}}.kpi.yellow{{background:var(--yellow-soft);border-color:#f3d894}}.kpi.red{{background:var(--red-soft);border-color:#ffc8c2}}
    .kpi span{{font-size:12px;color:var(--muted)}}.kpi b{{font-size:32px}}.kpi small{{font-size:12px;color:var(--muted)}}
    .bar{{height:8px;background:#ecf1f7;border-radius:999px;overflow:hidden}}.bar i{{display:block;height:100%;background:linear-gradient(90deg,var(--green),#65c98f)}}
    .decision{{display:grid;grid-template-columns:1.2fr repeat(5,1fr);gap:8px;margin-bottom:10px}}
    .decision article{{background:#fff;border:1px solid var(--line);border-radius:var(--radius);min-height:64px;padding:10px 14px;box-shadow:0 10px 28px rgba(31,48,83,.07)}}
    .decision article:first-child{{background:linear-gradient(90deg,var(--red-soft),#fff);border-color:#ffc8c2;box-shadow:inset 5px 0 0 var(--red),0 10px 28px rgba(31,48,83,.07);display:flex;justify-content:space-between;align-items:center}}
    .decision b{{font-size:22px}}.decision strong{{font-size:34px;color:var(--red)}}.decision span{{display:block;color:var(--muted);font-size:12px;margin-bottom:3px}}
    .grid{{display:grid;grid-template-columns:1.02fr .98fr;gap:10px;margin-bottom:10px}}
    .lower{{display:grid;grid-template-columns:1.15fr .85fr;gap:10px}}
    .lower-left{{display:flex;flex-direction:column;gap:10px}}
    .panel{{background:#fff;border:1px solid rgba(210,220,233,.94);border-radius:var(--radius);box-shadow:0 12px 34px rgba(31,48,83,.08);overflow:hidden}}
    .head{{height:44px;display:flex;align-items:center;justify-content:space-between;padding:0 12px;border-bottom:1px solid var(--line);background:linear-gradient(180deg,#fff,#f7f9fc)}}
    .head b{{font-size:16px}}.head span{{color:var(--muted);font-size:12px;margin-left:8px}}
    table{{width:100%;border-collapse:collapse;table-layout:fixed}}th,td{{padding:10px 12px;border-bottom:1px solid #edf1f6;text-align:left;font-size:12px;vertical-align:middle}}th{{color:var(--muted);background:#fbfcfe}}tr[data-d]{{cursor:pointer}}tr[data-d]:hover,.icard:hover,.ms:hover,.kpi:hover{{filter:brightness(.985);box-shadow:0 12px 26px rgba(31,48,83,.12)}}
    .st,.tag{{display:inline-flex;align-items:center;justify-content:center;min-width:44px;height:24px;border-radius:999px;color:#fff;font-size:12px;font-weight:800;padding:0 8px;white-space:nowrap}}
    .green{{background:var(--green)}}.yellow{{background:var(--yellow)}}.red{{background:var(--red)}}
    .iwrap{{display:grid;grid-template-columns:1fr 1fr;min-height:100%}}.iwrap section{{max-height:320px;overflow-y:auto}}.iwrap section+section{{border-left:1px solid var(--line)}}
    .btitle{{height:36px;display:flex;align-items:center;justify-content:space-between;padding:0 12px;font-weight:800;border-bottom:1px solid var(--line)}}.btitle.red{{color:var(--red);background:var(--red-soft)}}.btitle.yellow{{color:#9a6500;background:var(--yellow-soft)}}
    .icard{{margin:8px;padding:10px;border:1px solid var(--line);border-radius:var(--radius);cursor:pointer;background:#fff}}.icard.red{{border-color:#ffc8c2;box-shadow:inset 4px 0 0 var(--red)}}.icard.yellow{{border-color:#f3d894;box-shadow:inset 4px 0 0 var(--yellow)}}
    .ititle{{display:flex;gap:8px;align-items:center;justify-content:space-between;margin-bottom:6px}}.ititle b{{font-size:14px}}
    dl{{display:grid;grid-template-columns:56px 1fr;margin:0;gap:3px 8px;font-size:12px}}dt{{color:var(--muted)}}dd{{margin:0;font-weight:700;color:var(--ink);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}}
    .mswrap{{display:grid;grid-template-columns:repeat(5,1fr);gap:8px;padding:10px 12px 12px;max-height:400px;overflow-y:auto}}.ms{{border:1px solid var(--line);border-top:4px solid var(--blue);border-radius:var(--radius);padding:9px;min-height:126px;cursor:pointer;display:flex;flex-direction:column;gap:5px}}.ms.green{{background:var(--green-soft);border-color:#bce8ce;border-top-color:var(--green)}}.ms.yellow{{background:var(--yellow-soft);border-color:#f3d894;border-top-color:var(--yellow)}}.ms.red{{background:var(--red-soft);border-color:#ffc8c2;border-top-color:var(--red)}}.ms b{{font-size:13px}}.ms span,.ms p{{font-size:12px;color:var(--muted);margin:0}}.ms strong{{font-size:22px;margin-top:auto}}.ms em{{font-style:normal;font-weight:800;color:var(--ink)}}
    .empty{{padding:20px;text-align:center;color:var(--muted);font-size:13px;margin:0}}
    .drawer-mask{{position:fixed;inset:0;background:rgba(15,23,42,.34);backdrop-filter:blur(2px);display:none;z-index:20}}.drawer-mask.open{{display:block}}.drawer{{position:fixed;top:0;right:0;width:min(820px,95vw);height:100vh;background:#fff;z-index:21;box-shadow:-24px 0 52px rgba(20,33,58,.22);transform:translateX(104%);transition:.22s;display:flex;flex-direction:column}}.drawer.open{{transform:translateX(0)}}.drawer-head{{display:grid;grid-template-columns:1fr auto;gap:12px;padding:16px 18px 12px;border-bottom:1px solid var(--line);background:linear-gradient(180deg,#f9fbff,#fff)}}.drawer h2{{margin:0;font-size:20px}}.drawer p{{margin:6px 0 0;color:var(--muted);font-size:13px}}.close{{width:34px;height:34px;border:1px solid var(--line);border-radius:6px;background:#fff;font-size:22px;cursor:pointer}}.drawer-summary{{display:grid;grid-template-columns:repeat(4,1fr);gap:8px;padding:12px 18px;border-bottom:1px solid var(--line);background:#f7f9fc}}.drawer-summary div{{background:#fff;border:1px solid var(--line);border-radius:6px;padding:8px 10px}}.drawer-summary span{{display:block;font-size:12px;color:var(--muted)}}.drawer-summary b{{font-size:20px}}.drawer-body{{padding:12px 18px 18px;overflow:auto}}
    .tcard{{border:1px solid var(--line);border-radius:var(--radius);padding:12px;margin-bottom:10px;background:#fff}}.tcard.red{{background:var(--red-soft);border-color:#ffc8c2}}.tcard.yellow{{background:var(--yellow-soft);border-color:#f3d894}}.tcard.green{{background:var(--green-soft);border-color:#bce8ce}}.ttop{{display:flex;justify-content:space-between;gap:12px;margin-bottom:8px}}.ttop b{{font-size:15px}}.tmeta{{display:grid;grid-template-columns:repeat(4,1fr);gap:8px;margin:8px 0}}.tmeta span,.desc span{{display:block;color:var(--muted);font-size:12px;margin-bottom:2px}}.tmeta strong,.desc p{{margin:0;color:var(--ink);font-size:13px;line-height:1.45}}.desc{{display:grid;grid-template-columns:1fr 1fr;gap:10px;border-top:1px dashed rgba(105,117,139,.28);padding-top:8px}}
    .modal{{position:fixed;inset:0;display:none;align-items:center;justify-content:center;background:rgba(15,23,42,.36);backdrop-filter:blur(2px);z-index:30;padding:22px}}.modal.open{{display:flex}}.rule{{width:min(720px,94vw);background:#fff;border-radius:var(--radius);border:1px solid var(--line);box-shadow:0 28px 70px rgba(20,33,58,.28);overflow:hidden}}.rule-head{{display:flex;justify-content:space-between;padding:16px 18px;border-bottom:1px solid var(--line)}}.rule-head h2{{margin:0;font-size:20px}}.rule-body{{display:grid;gap:10px;padding:16px 18px;max-height:calc(90vh - 80px);overflow-y:auto}}.rule-item{{display:grid;grid-template-columns:82px 1fr;gap:10px;border:1px solid var(--line);border-radius:var(--radius);padding:12px}}.rule-item.red{{background:var(--red-soft);border-color:#ffc8c2}}.rule-item.green{{background:var(--green-soft);border-color:#bce8ce}}.rule-item.yellow{{background:var(--yellow-soft);border-color:#f3d894}}.badge{{height:28px;border-radius:999px;color:#fff;display:flex;align-items:center;justify-content:center;font-weight:800;font-size:12px}}.rule-item.red .badge{{background:var(--red)}}.rule-item.green .badge{{background:var(--green)}}.rule-item.yellow .badge{{background:var(--yellow)}}.badge.blue{{background:var(--blue)}}.rule-item b{{display:block;margin-bottom:4px}}.rule-item span{{font-size:13px;line-height:1.55}}
    @media(max-width:1180px){{.kpis,.grid,.lower,.decision,.mswrap{{grid-template-columns:1fr 1fr}}.conclusion{{grid-column:1/-1}}}}@media(max-width:760px){{.page{{width:calc(100vw - 20px)}}.top,.kpis,.grid,.lower,.decision,.mswrap,.iwrap,.drawer-summary,.tmeta,.desc{{display:grid;grid-template-columns:1fr}}.iwrap section+section{{border-left:0;border-top:1px solid var(--line)}}}}
    .ai-btn{{height:36px;border:1px solid var(--blue);background:var(--blue);color:#fff;border-radius:6px;padding:0 14px;font-weight:700;font-size:13px;cursor:pointer;display:inline-flex;align-items:center;gap:4px}}
    .ai-btn:hover{{background:#1a4bb8}}
    .ai-modal{{position:fixed;inset:0;display:none;align-items:center;justify-content:center;background:rgba(15,23,42,.36);backdrop-filter:blur(2px);z-index:30;padding:22px}}.ai-modal.open{{display:flex}}
    .ai-panel{{width:min(780px,94vw);height:min(85vh,700px);background:#fff;border-radius:12px;border:1px solid var(--line);box-shadow:0 28px 70px rgba(20,33,58,.28);display:flex;flex-direction:column;overflow:hidden}}
    .ai-head{{display:flex;justify-content:space-between;align-items:center;padding:14px 18px;border-bottom:1px solid var(--line);background:linear-gradient(180deg,#f9fbff,#fff)}}.ai-head h2{{margin:0;font-size:18px}}
    .ai-presets{{display:flex;gap:8px;padding:12px 18px;border-bottom:1px solid var(--line);flex-wrap:wrap}}
    .ai-pbtn{{height:30px;border:1px solid var(--line);background:#fff;border-radius:6px;padding:0 12px;font-size:12px;font-weight:700;cursor:pointer;color:var(--ink)}}.ai-pbtn:hover{{background:var(--blue-soft);border-color:#a8bfea}}
    .ai-body{{flex:1;overflow:auto;padding:16px 18px}}
    .ai-msg{{margin-bottom:14px}}.ai-msg.user{{text-align:right}}.ai-msg span{{display:inline-block;max-width:85%;padding:10px 14px;border-radius:10px;font-size:14px;line-height:1.6;text-align:left}}
    .ai-msg.user span{{background:var(--blue);color:#fff;border-bottom-right-radius:2px}}
    .ai-msg.assistant span{{background:#f7f9fc;border:1px solid var(--line);border-bottom-left-radius:2px;white-space:pre-wrap}}
    .ai-msg.assistant span p{{margin:0 0 8px}}.ai-msg.assistant span p:last-child{{margin-bottom:0}}
    .ai-loading{{display:inline-flex;gap:4px;padding:10px 14px;background:#f7f9fc;border:1px solid var(--line);border-radius:10px;border-bottom-left-radius:2px}}
    .ai-loading i{{width:6px;height:6px;background:var(--muted);border-radius:50%;animation:aiblink .8s infinite}}.ai-loading i:nth-child(2){{animation-delay:.15s}}.ai-loading i:nth-child(3){{animation-delay:.3s}}
    @keyframes aiblink{{0%,80%{{opacity:.3}}40%{{opacity:1}}}}
    .ai-input{{display:flex;gap:8px;padding:12px 18px;border-top:1px solid var(--line);background:#f7f9fc}}
    .ai-input input{{flex:1;height:38px;border:1px solid var(--line);border-radius:6px;padding:0 12px;font-size:14px}}
    .ai-input button{{height:38px;background:var(--blue);color:#fff;border:none;border-radius:6px;padding:0 18px;font-weight:700;font-size:14px;cursor:pointer}}
    .rectify-tabs{{display:flex;gap:6px;padding:8px 12px;border-bottom:1px solid var(--line);background:#f7f9fc}}
    .rtab{{height:30px;border:1px solid var(--line);background:#fff;border-radius:6px;padding:0 14px;font-size:13px;font-weight:700;cursor:pointer;color:var(--ink)}}.rtab:hover{{background:var(--blue-soft)}}.rtab.on{{background:var(--blue);color:#fff;border-color:var(--blue)}}
    .rectify-cards{{display:grid;grid-template-columns:1fr 1fr;gap:10px;padding:12px;overflow-y:auto}}
    .rcard{{border:1px solid var(--line);border-radius:var(--radius);padding:12px;border-left:4px solid var(--yellow);background:#fff}}.rcard.adopted{{border-left-color:var(--blue)}}.rcard.resolved{{border-left-color:var(--green);opacity:.7}}
    .rcard-head{{display:flex;justify-content:space-between;align-items:center;margin-bottom:8px}}.rcard-head b{{font-size:14px}}
    .rcard-body{{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:8px}}.rcard-body span{{display:block;font-size:12px;color:var(--muted);margin-bottom:2px}}.rcard-body p{{margin:0;font-size:13px;line-height:1.45;color:var(--ink)}}
    .rcard-meta{{display:flex;gap:16px;font-size:12px;color:var(--muted);margin-bottom:8px}}
    .rcard-actions{{display:flex;gap:8px;border-top:1px dashed rgba(105,117,139,.28);padding-top:8px}}
    .rbtn{{height:28px;border:1px solid var(--line);background:#fff;border-radius:6px;padding:0 12px;font-size:12px;font-weight:700;cursor:pointer}}.rbtn:hover{{background:var(--blue-soft)}}.rbtn.adopt{{border-color:var(--blue);color:var(--blue)}}.rbtn.ignore{{border-color:var(--red);color:var(--red)}}.rbtn.resolve{{border-color:var(--green);color:var(--green)}}
    @media(max-width:760px){{.rectify-cards,.rcard-body{{grid-template-columns:1fr}}}}
  </style>
</head>
<body>
  <main class="page">
    <header class="top">
      <div><h1>{html.escape(title)}</h1><p class="sub">{html.escape(subtitle)}｜数据来源：{html.escape(source_name)}</p></div>
      <div class="actions"><button class="ai-btn" id="aiBtn">&#9733; AI 分析</button><button class="btn" id="ruleBtn">扣分规则</button><a class="btn" href="dashboard_index.html">看板首页</a><span class="stamp">更新：2026-05-03</span></div>
    </header>
    <nav class="mbar"><label>分析月份：</label><span id="monthBtns"></span><button class="mbtn-go" id="goBtn">确定</button></nav>
    <div id="root"></div>
  </main>
  <div class="ai-modal" id="aiModal">
    <div class="ai-panel">
      <div class="ai-head"><h2>AI 智能分析</h2><button class="close" id="aiClose">&times;</button></div>
      <div class="ai-presets">
        <button class="ai-pbtn" data-p="summary">月度分析总结</button>
        <button class="ai-pbtn" data-p="risk">异常任务识别</button>
        <button class="ai-pbtn" data-p="reason">异常原因推测</button>
      </div>
      <div class="ai-body" id="aiBody"></div>
      <div class="ai-input"><input id="aiInput" placeholder="输入问题，或点击上方预设分析..." /><button id="aiSend">发送</button></div>
    </div>
  </div>
  <div class="drawer-mask" id="dmask"></div>
  <aside class="drawer" id="drawer">
    <header class="drawer-head"><div><h2 id="dtitle">任务明细</h2><p id="dsub"></p></div><button class="close" id="dclose">×</button></header>
    <section class="drawer-summary"><div><span>合计</span><b id="sTotal">0</b></div><div><span>正常</span><b id="sGreen">0</b></div><div><span>风险</span><b id="sYellow">0</b></div><div><span>异常</span><b id="sRed">0</b></div></section>
    <section class="drawer-body" id="dbody"></section>
  </aside>
  <section class="modal" id="ruleModal">
    <div class="rule">
      <header class="rule-head"><div><h2>重点任务扣分规则</h2><p class="sub">来源于目标台账表头</p></div><button class="close" id="ruleClose">×</button></header>
      <div class="rule-body">
        <article class="rule-item red"><div class="badge">D档</div><div><b>月度计划未完成</b><span>重点任务当月未完成月度计划，负责人当月考核直接为D。</span></div></article>
        <article class="rule-item red"><div class="badge">年度D</div><div><b>年度计划未完成</b><span>重点任务当年未完成年度计划，负责人当年考核为D。</span></div></article>
        <article class="rule-item green"><div class="badge">保底C</div><div><b>全部按时完成</b><span>重点任务全部按时完成，则任务负责人考核保底为C。</span></div></article>
        <article class="rule-item yellow"><div class="badge">看板口径</div><div><b>红黄绿判定</b><span>红色：扣分/延期/未完成/质量问题；黄色：暂停/暂缓/待确认/有计划无实际；绿色：已完成或按计划推进。</span></div></article>
        <article class="rule-item"><div class="badge blue">统计①</div><div><b>总体结论栏（各月合并）</b><span>以下统计基于全部月份合并分析，不随月份切换变化：</span><br><span>• 任务总数：工作表中所有有效任务的数量</span><br><span>• 正常：任一月份曾判定为绿色（实际进展含"已完成/完成/已上线/已部署/已发起/已提交/已输出"等关键词）</span><br><span>• 风险：从未判定为红色，也从未判定为绿色的任务</span><br><span>• 异常：任一月份曾判定为红色（扣分/延期/未完成/质量问题）</span><br><span>• 按期完成率 = 曾为绿色的任务数 ÷ 任务总数 × 100%</span><br><span>• 问题闭环率 = 任一月份曾闭环的任务数 ÷ 任务总数 × 100%（闭环 = 状态绿色 或 实际含完成关键词）</span><br><span>• 需盯办：任一月份曾为红色 或 需要协调的事项</span><br><span>• 完成：任一月份的实际进展中包含"已完成/完成/已上线/已部署/已发起/已提交/已输出"等关键词的任务数</span><br><span>• 暂停：任一月份的实际进展中包含"暂停/暂缓"关键词的任务数</span></div></article>
        <article class="rule-item"><div class="badge blue">统计②</div><div><b>决策区（按选中月份）</b><span>以下统计随月份切换动态变化：</span><br><span>• 需领导盯办：选中月份判定为红色 或 含"协调"关键词且非绿色的任务</span><br><span>• 重点任务：keyTask 列包含"重点任务"的任务</span><br><span>• N月有计划：选中月份计划列有内容，或阶段性成果计划中提到该月份</span><br><span>• 自研任务：是否自研列包含"是"的任务</span><br><span>• 完成任务：选中月份的实际进展中包含完成关键词的任务</span><br><span>• 暂停任务：选中月份的实际进展中包含"暂停/暂缓"的任务</span></div></article>
        <article class="rule-item"><div class="badge blue">统计③</div><div><b>分类判定规则</b><span>按选中月份的数据逐一判定，优先级从高到低：</span><br><span>① 红色：得分 &lt; 0 或 含"扣分/未按要求/质量问题" → 扣分/质量问题</span><br><span>② 红色：含"延期/延时/未完成" → 当月延期或未完成</span><br><span>③ 黄色：有计划但未填实际 → 当月有计划但未填实际</span><br><span>④ 黄色：含"暂缓/暂停/待确认/未开始/暂未启动/暂无进度/跟进/正在/待/风险" → 暂停/待确认/外部依赖</span><br><span>⑤ 绿色：实际含"已完成/完成/已上线/已部署/已发起/已提交/已输出" → 已完成或按计划推进</span><br><span>⑥ 黄色：以上均不匹配 → 进展待补充</span></div></article>
      </div>
    </div>
  </section>
  <script>
  (function(){{
    let DD={data_json};
    const defaultCM=DD.currentMonth||1;
    const ulKey='kanban_uploaded_{sheet_indicator}';
    const uploaded=localStorage.getItem(ulKey);
    if(uploaded){{
      try{{
        const ud=JSON.parse(uploaded);
        if(ud.tasks&&ud.tasks.length>0)DD=ud;
        localStorage.removeItem(ulKey);
      }}catch(e){{localStorage.removeItem(ulKey)}}
    }}
    const raw=DD.tasks;
    /* 月份=MAX(Python默认值, 上传值, 数据实际检测) */
    let CM=Math.max(defaultCM, DD.currentMonth||1);
    raw.forEach(t=>(t.monthly||[]).forEach(m=>{{if((m.plan||m.actual)&&m.month>CM)CM=m.month}}));
    DD.currentMonth=CM;
    let curM=CM;
    /* 动态生成月份按钮 */
    (function(){{
      const mb=document.getElementById('monthBtns');if(!mb)return;
      let html='';
      for(let m=1;m<=CM;m++)html+='<button class="mbtn" data-m="'+m+'">'+m+'月</button>';
      mb.innerHTML=html;
    }})();

    const NEG=["扣分","未按要求","质量问题"],RISK=["暂缓","暂停","待确认","未开始","暂未启动","暂无进度","跟进","正在","待","风险"],DONE=["已完成","完成","已上线","已部署","已发起","已提交","已输出"],MN=["一","二","三","四","五","六","七","八","九","十","十一","十二"];
    function has(t,ws){{return ws.some(w=>t.includes(w))}}
    function esc(v){{return String(v||"").replace(/[&<>"']/g,m=>({{"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}}[m])).replace(/\\n/g,"<br>")}}
    function cpt(s,n){{s=String(s||"").replace(/\\n/g,"；");return s.length>n?s.slice(0,n-1)+"…":s}}

    function classify(task,month){{
      const ml=task.monthly.slice(0,month), cur=ml[ml.length-1];
      const ct=[cur.plan,cur.actual,cur.score,cur.note].join("\\n");
      const negSc=cur.score&&parseInt(cur.score)<0;
      let st,rs;
      if(negSc||has(ct,NEG)){{st="red";rs="扣分/质量问题"}}
      else if(has(ct,["延期","延时","未完成"])){{st="red";rs="当月延期或未完成"}}
      else if(cur.plan&&!cur.actual){{st="yellow";rs="当月有计划但未填实际"}}
      else if(has(ct,RISK)){{st="yellow";rs="暂停/待确认/外部依赖"}}
      else if(has(cur.actual,DONE)){{st="green";rs="已完成或按计划推进"}}
      else{{st="yellow";rs="进展待补充"}}
      const sp=task.stagePlan||"";
      const re=new RegExp(month+"\\\\s*月|"+MN[month-1]+"月");
      const hmp=!!cur.plan||re.test(sp);
      const closed=st==="green"||has(cur.actual,DONE);
      const isKey=(task.keyTask||"").includes("重点任务");
      const nd=st==="red"||(ct.includes("协调")&&st!=="green");
      return{{status:st,statusText:{{green:"正常",yellow:"风险",red:"异常"}}[st],reason:rs,latestPlan:cur.plan||sp,latestActual:cur.actual,latestScore:cur.score,latestNote:cur.note,hasMonthPlan:hmp,closed,isKeyTask:isKey,needsDecision:nd}};
    }}

    function calcAll(month){{
      const items=raw.map(t=>({{...t,...classify(t,month)}}));
      const sc={{green:0,yellow:0,red:0}};
      items.forEach(t=>sc[t.status]++);
      const cs={{}};
      items.forEach(t=>{{if(!cs[t.center])cs[t.center]={{center:t.center,total:0,green:0,yellow:0,red:0,key:0}};const c=cs[t.center];c.total++;c[t.status]++;if(t.isKeyTask)c.key++;}});
      const csl=Object.values(cs).sort((a,b)=>b.total-a.total);
      const total=items.length;
      const closed=items.filter(t=>t.closed).length;
      const selfD=items.filter(t=>String(t.selfDeveloped).includes("是")).length;
      const closedT=items.filter(t=>DONE.some(w=>(t.latestActual||"").includes(w))).length;
      const pausedT=items.filter(t=>["暂停","暂缓"].some(w=>(t.latestActual||"").includes(w))).length;
      return{{total,green:sc.green,yellow:sc.yellow,red:sc.red,
        keyTotal:items.filter(t=>t.isKeyTask).length,
        monthTotal:items.filter(t=>t.hasMonthPlan).length,
        decisionTotal:items.filter(t=>t.needsDecision).length,
        closedRate:total?Math.round(closed/total*100):0,
        ontimeRate:total?Math.round(sc.green/total*100):0,
        selfDevTotal:selfD,closedTotal:closedT,pausedTotal:pausedT,
        rawClosedTotal:items.filter(t=>(t.rawStatus||"")==="已完成").length,
        rawPausedTotal:items.filter(t=>(t.rawStatus||"")==="暂停").length,
        centers:csl,
        reds:items.filter(t=>t.status==="red"),
        yellows:items.filter(t=>t.status==="yellow"),
        mTasks:items.filter(t=>t.hasMonthPlan),
        items}};
    }}

    /* 合并所有月份：每个任务取各月最差状态 */
    function calcMerged(){{
      const cm=DD.currentMonth||5;
      const W={{red:3,yellow:2,green:1}};
      /* 为每个任务计算合并状态，直接写入 item 属性，下钻过滤可匹配 */
      const items=raw.map(t=>{{
        let ws="green",everGreen=false,everClosed=false,everDec=false;
        let everDone=false,everPause=false;
        const greenM=[],redM=[],doneM=[],pauseM=[];
        for(let m=1;m<=cm;m++){{
          const cl=classify(t,m);
          if(cl.status==="green"){{everGreen=true;greenM.push(m);}}
          if(cl.closed)everClosed=true;
          if(cl.status==="red"){{redM.push(m);}}
          if(W[cl.status]>W[ws])ws=cl.status;
          if(cl.needsDecision)everDec=true;
          const act=t.monthly[Math.min(m,t.monthly.length)-1].actual||"";
          if(DONE.some(w=>act.includes(w))){{everDone=true;doneM.push(m);}}
          if(["暂停","暂缓"].some(w=>act.includes(w))){{everPause=true;pauseM.push(m);}}
        }}
        const mst=ws==="red"?"red":everGreen?"green":"yellow";
        const srcMonths=[];
        if(mst==="green")greenM.forEach(m=>{{if(!srcMonths.includes(m))srcMonths.push(m)}});
        if(mst==="red")redM.forEach(m=>{{if(!srcMonths.includes(m))srcMonths.push(m)}});
        if(everDone)doneM.forEach(m=>{{if(!srcMonths.includes(m))srcMonths.push(m)}});
        if(everPause)pauseM.forEach(m=>{{if(!srcMonths.includes(m))srcMonths.push(m)}});
        return{{...t,...classify(t,cm),
          status:mst,statusText:ST[mst],
          closed:everClosed,needsDecision:ws==="red"||everDec,
          everDone,everPause,
          greenM,redM,doneM,pauseM,
          srcMonths:srcMonths.length?srcMonths:[cm]
        }};
      }});
      const sc={{green:0,yellow:0,red:0}};
      items.forEach(t=>sc[t.status]++);
      const total=items.length;
      const closed=items.filter(t=>t.closed).length;
      return{{total,green:sc.green,yellow:sc.yellow,red:sc.red,
        decisionTotal:items.filter(t=>t.needsDecision).length,
        closedRate:total?Math.round(closed/total*100):0,
        ontimeRate:total?Math.round(sc.green/total*100):0,
        rawClosedTotal:items.filter(t=>t.everDone).length,
        rawPausedTotal:items.filter(t=>t.everPause).length,
        items}};
    }}

    const ST={{green:"正常",yellow:"风险",red:"异常"}};

    function render(month){{
      const s=calcAll(month), m=calcMerged(), ml=month+"月";
      document.querySelectorAll(".mbtn").forEach(b=>{{b.classList.toggle("on",Number(b.dataset.m)===month)}});

      document.getElementById("root").innerHTML=`
      <section class="hero"><div class="kpis">
        <article class="conclusion" data-d="all"><span>总体结论（各月合并）</span><b>${{m.total}}项任务，${{m.red}}项异常</b><p>重点盯办红榜、计划未闭环和需要协调事项。</p></article>
        <article class="kpi" data-d="all"><span>任务总数</span><b>${{m.total}}<small>项</small></b><small>纳入本表统计</small></article>
        <article class="kpi green" data-d="ms::green"><span>正常</span><b>${{m.green}}<small>项</small></b><small>已完成或推进中</small></article>
        <article class="kpi yellow" data-d="ms::yellow"><span>风险</span><b>${{m.yellow}}<small>项</small></b><small>待确认/暂缓/临近</small></article>
        <article class="kpi red" data-d="ms::red"><span>异常</span><b>${{m.red}}<small>项</small></b><small>扣分/延期/未完成</small></article>
        <article class="kpi"><span>按期完成率</span><b>${{m.ontimeRate}}<small>%</small></b><div class="bar"><i style="width:${{m.ontimeRate}}%"></i></div></article>
        <article class="kpi red" data-d="mdec"><span>需盯办</span><b>${{m.decisionTotal}}<small>项</small></b><small>红榜或需协调</small></article>
        <article class="kpi green"><span>问题闭环率</span><b>${{m.closedRate}}<small>%</small></b><div class="bar"><i style="width:${{m.closedRate}}%"></i></div></article>
        <article class="kpi green" data-d="rawClosed"><span>完成</span><b>${{m.rawClosedTotal}}<small>项</small></b><small>状态为已完成</small></article>
        <article class="kpi yellow" data-d="rawPaused"><span>暂停</span><b>${{m.rawPausedTotal}}<small>项</small></b><small>状态为暂停</small></article>
      </div></section>
      <section class="decision">
        <article data-d="dec"><div><span>${{ml}}需领导盯办</span><b>红榜及协调事项</b></div><strong>${{s.decisionTotal}}项</strong></article>
        <article data-d="key"><span>重点任务</span><b>${{s.keyTotal}}项</b></article>
        <article data-d="mp"><span>${{ml}}有计划</span><b>${{s.monthTotal}}项</b></article>
        <article data-d="self"><span>自研任务</span><b>${{s.selfDevTotal}}项</b></article>
        <article data-d="cl"><span>完成任务</span><b>${{s.closedTotal}}项</b></article>
        <article data-d="paused"><span>暂停任务</span><b>${{s.pausedTotal}}项</b></article>
      </section>
      <section class="grid">
        <article class="panel"><div class="head"><div><b>中心统计</b><span>点击数值查看对应明细</span></div></div>
          <table><thead><tr><th style="width:58px">排名</th><th>归属中心</th><th>任务数</th><th>正常</th><th>风险</th><th>异常</th><th>重点</th></tr></thead><tbody>
          ${{s.centers.map((r,i)=>{{
            const c=esc(r.center);
            return `<tr><td><b>${{i+1}}</b></td><td>${{c}}</td><td data-d="c::${{c}}" style="cursor:pointer">${{r.total}}</td><td data-d="cs::${{c}}::green" style="cursor:pointer"><span class="st green">${{r.green}}</span></td><td data-d="cs::${{c}}::yellow" style="cursor:pointer"><span class="st yellow">${{r.yellow}}</span></td><td data-d="cs::${{c}}::red" style="cursor:pointer"><span class="st red">${{r.red}}</span></td><td data-d="ck::${{c}}" style="cursor:pointer">${{r.key}}</td></tr>`;
          }}).join("")}}
          </tbody></table></article>
        <article class="panel"><div class="head"><div><b>红黄榜</b><span>扣分、延期、暂停、待确认事项</span></div></div>
          <div class="iwrap"><section><div class="btitle red">红榜重点 <span data-d="s::red" style="cursor:pointer">${{s.red}}项</span></div>${{s.reds.map(t=>`<article class="icard red" data-d="t::${{t.seq}}"><div class="ititle"><b>${{esc(cpt(t.project,22))}}</b><span class="tag red">${{esc(t.reason)}}</span></div><dl><dt>中心</dt><dd>${{esc(t.center)}}</dd><dt>负责人</dt><dd>${{esc(t.owner||"未填")}}</dd><dt>实际</dt><dd>${{esc(cpt(t.latestActual||t.latestNote||"未填实际",56))}}</dd></dl></article>`).join("")||'<p class="empty">暂无红榜任务</p>'}}</section>
          <section><div class="btitle yellow">黄榜预警 <span data-d="s::yellow" style="cursor:pointer">${{s.yellow}}项</span></div>${{s.yellows.map(t=>`<article class="icard yellow" data-d="t::${{t.seq}}"><div class="ititle"><b>${{esc(cpt(t.project,22))}}</b><span class="tag yellow">${{esc(t.reason)}}</span></div><dl><dt>中心</dt><dd>${{esc(t.center)}}</dd><dt>负责人</dt><dd>${{esc(t.owner||"未填")}}</dd><dt>实际</dt><dd>${{esc(cpt(t.latestActual||t.latestNote||"未填实际",56))}}</dd></dl></article>`).join("")||'<p class="empty">暂无黄榜任务</p>'}}</section></div></article>
      </section>
      <section class="lower">
        <div class="lower-left">
          <article class="panel"><div class="head"><div><b>${{ml}}关键里程碑</b><span>有${{ml}}计划的节点</span></div></div>
          <div class="mswrap">${{s.mTasks.slice(0,10).map(t=>`<article class="ms ${{t.status}}" data-d="t::${{t.seq}}"><b>${{esc(cpt(t.project,18))}}</b><span>负责人：${{esc(t.owner||"未填")}}</span><p>${{esc(cpt(t.latestPlan,54))}}</p><strong>${{ml}}</strong><em>${{ST[t.status]}}</em></article>`).join("")||'<p class="empty">暂无该月计划任务</p>'}}</div></article>
          <article class="panel">
          <div class="head"><div><b>整改任务清单</b><span>AI分析生成整改措施，持续跟踪</span></div><button class="ai-btn" id="rectifyBtn">AI分析生成整改任务</button></div>
          <div class="rectify-tabs">
          <button class="rtab on" data-tab="pending">待选 (0)</button>
          <button class="rtab" data-tab="adopted">整改中 (0)</button>
          <button class="rtab" data-tab="resolved">已整改 (0)</button>
          </div>
          <div class="rectify-cards" id="rectifyCards"></div>
          </article>
        </div>
        <article class="panel"><div class="head"><div><b>负责人问题统计</b><span>按负责人汇总异常/风险任务数量，点击行可下钻</span></div></div>
        <table><thead><tr><th>负责人</th><th>任务数</th><th>异常</th><th>风险</th><th>正常</th><th style="max-width:260px">异常/风险项目</th></tr></thead><tbody>
        ${{(() => {{
        const om={{}};
        s.items.forEach(t=>{{
        const o=t.owner||"未填";
        if(!om[o])om[o]={{name:o,total:0,green:0,yellow:0,red:0,issues:[]}};
        om[o].total++;om[o][t.status]++;
        if(t.status==="red"||t.status==="yellow")om[o].issues.push(t.seq+"."+t.project);
        }});
        return Object.values(om).sort((a,b)=>(b.red*3+b.yellow)-(a.red*3+a.yellow)).map(o=>`<tr style="cursor:pointer"><td><b>${{esc(o.name)}}</b></td><td data-d="o::${{esc(o.name)}}" style="cursor:pointer">${{o.total}}</td><td data-d="os::${{esc(o.name)}}::red" style="cursor:pointer">${{o.red?`<span class="st red">${{o.red}}</span>`:0}}</td><td data-d="os::${{esc(o.name)}}::yellow" style="cursor:pointer">${{o.yellow?`<span class="st yellow">${{o.yellow}}</span>`:0}}</td><td data-d="os::${{esc(o.name)}}::green" style="cursor:pointer">${{o.green?`<span class="st green">${{o.green}}</span>`:0}}</td><td style="font-size:12px;color:var(--muted);max-width:260px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${{esc(o.issues.slice(0,3).join("；"))}}</td></tr>`).join("");
        }})()}}
        </tbody></table></article>
      </section>`;
      bindDrill();
      bindRectify();
      renderRectify();
    }}

    function pick(key,m){{
      const s=calcAll(m),items=s.items,ml=m+"月";
      const mg=calcMerged(),mi=mg.items;
      if(key==="all")return[mi,"全部任务（各月合并）",""];
      if(key.startsWith("ms::")){{const v=key.split("::")[1];return[mi.filter(t=>t.status===v),ST[v]+"任务（合并）",""]}}
      if(key==="mdec")return[mi.filter(t=>t.needsDecision),"需盯办任务（合并）",""];
      if(key.startsWith("s::")){{const v=key.split("::")[1];return[items.filter(t=>t.status===v),ST[v]+"任务（"+ml+"）",""]}}
      if(key.startsWith("o::")){{const o=key.split("::")[1];return[items.filter(t=>(t.owner||"未填")===o),o+" 负责的全部任务",""]}}
      if(key.startsWith("os::")){{const p=key.split("::"),o=p[1],v=p[2];return[items.filter(t=>(t.owner||"未填")===o&&t.status===v),o+" "+ST[v]+"任务",""]}}
      if(key.startsWith("c::")){{const c=key.split("::")[1];return[items.filter(t=>t.center===c),c+" 全部任务",""]}}
      if(key.startsWith("cs::")){{const p=key.split("::"),c=p[1],v=p[2];return[items.filter(t=>t.center===c&&t.status===v),c+" "+ST[v]+"任务",""]}}
      if(key.startsWith("ck::")){{const c=key.split("::")[1];return[items.filter(t=>t.center===c&&t.isKeyTask),c+" 重点任务",""]}}
      if(key.startsWith("t::")){{const id=+key.split("::")[1],t=items.find(x=>x.seq===id);return[[t].filter(Boolean),t?t.project:"",""]}}
      const M={{mp:[items.filter(t=>t.hasMonthPlan),ml+"有计划任务",""],key:[items.filter(t=>t.isKeyTask),"重点任务",""],self:[items.filter(t=>String(t.selfDeveloped).includes("是")),"自研任务",""],dec:[items.filter(t=>t.needsDecision),"需领导盯办任务",""],cl:[items.filter(t=>DONE.some(w=>(t.latestActual||"").includes(w))),"完成任务",""],paused:[items.filter(t=>["暂停","暂缓"].some(w=>(t.latestActual||"").includes(w))),"暂停任务",""],rawClosed:[mi.filter(t=>t.everDone),"已完成任务",""],rawPaused:[mi.filter(t=>t.everPause),"暂停任务",""]}};
      return M[key]||M.all;
    }}

    function openDrill(key){{
      const[list,title]=pick(key,curM);
      const isMerged=key==="all"||key.startsWith("ms::")||key==="mdec"||key==="rawClosed"||key==="rawPaused";
      document.getElementById("dtitle").textContent=title;
      document.getElementById("dsub").textContent="共"+list.length+"项";
      document.getElementById("sTotal").textContent=list.length;
      document.getElementById("sGreen").textContent=list.filter(t=>t.status==="green").length;
      document.getElementById("sYellow").textContent=list.filter(t=>t.status==="yellow").length;
      document.getElementById("sRed").textContent=list.filter(t=>t.status==="red").length;
      const MN=["","1月","2月","3月","4月","5月","6月","7月","8月","9月","10月","11月","12月"];
      document.getElementById("dbody").innerHTML=list.map(t=>{{
        const src=isMerged&&t.srcMonths?"（数据来源："+t.srcMonths.map(m=>MN[m]).join("、")+"）":"";
        const tags=[];
        if(t.greenM&&t.greenM.length)tags.push('<span class="st green" style="margin-right:4px">正常:'+t.greenM.map(m=>MN[m]).join(",")+'</span>');
        if(t.redM&&t.redM.length)tags.push('<span class="st red" style="margin-right:4px">异常:'+t.redM.map(m=>MN[m]).join(",")+'</span>');
        if(t.doneM&&t.doneM.length)tags.push('<span class="st green" style="margin-right:4px">完成:'+t.doneM.map(m=>MN[m]).join(",")+'</span>');
        if(t.pauseM&&t.pauseM.length)tags.push('<span class="st yellow" style="margin-right:4px">暂停:'+t.pauseM.map(m=>MN[m]).join(",")+'</span>');
        const tagHtml=tags.length?'<div style="margin:6px 0 0;font-size:12px">'+tags.join("")+'</div>':"";
        return `<article class="tcard ${{t.status}}"><div class="ttop"><b>${{t.seq}}. ${{esc(t.project)}}</b><span class="st ${{t.status}}">${{t.statusText}}</span></div><div class="tmeta"><div><span>归属中心</span><strong>${{esc(t.center)}}</strong></div><div><span>负责人</span><strong>${{esc(t.owner||"未填")}}</strong></div><div><span>是否自研</span><strong>${{esc(t.selfDeveloped||"未填")}}</strong></div><div><span>判定原因</span><strong>${{esc(t.reason)}}${{src}}</strong></div></div>${{tagHtml}}<div class="desc"><div><span>阶段计划 / 当月计划</span><p>${{esc(t.stagePlan||t.latestPlan||"未填")}}</p></div><div><span>实际进展 / 备注</span><p>${{esc(t.latestActual||t.latestNote||"未填")}}</p></div></div></article>`;
      }}).join("")||'<p class="empty">暂无明细。</p>';
      document.getElementById("dmask").classList.add("open");
      document.getElementById("drawer").classList.add("open");
    }}

    function bindDrill(){{document.querySelectorAll("[data-d]").forEach(el=>el.addEventListener("click",()=>openDrill(el.dataset.d)))}}

    function closeD(){{document.getElementById("dmask").classList.remove("open");document.getElementById("drawer").classList.remove("open")}}
    document.getElementById("dclose").addEventListener("click",closeD);
    document.getElementById("dmask").addEventListener("click",closeD);
    document.getElementById("ruleBtn").addEventListener("click",()=>document.getElementById("ruleModal").classList.add("open"));
    document.getElementById("ruleClose").addEventListener("click",()=>document.getElementById("ruleModal").classList.remove("open"));
    document.getElementById("ruleModal").addEventListener("click",e=>{{if(e.target.id==="ruleModal")document.getElementById("ruleModal").classList.remove("open")}});
    document.addEventListener("keydown",e=>{{if(e.key==="Escape"){{closeD();document.getElementById("ruleModal").classList.remove("open")}}}});

    document.querySelectorAll(".mbtn").forEach(b=>b.addEventListener("click",()=>{{
      document.querySelectorAll(".mbtn").forEach(x=>x.classList.remove("on"));
      b.classList.add("on");
    }}));
    document.getElementById("goBtn").addEventListener("click",()=>{{
      const sel=document.querySelector(".mbtn.on");
      if(!sel)return;
      curM=Number(sel.dataset.m);
      render(curM);
    }});

    const PRESETS={{
      summary:"请对当前月份数据进行月度分析总结，包括：\\n1. 整体态势评估（稳/需关注/失控）\\n2. 各中心任务完成情况对比\\n3. 风险趋势（与前期相比的变化）\\n4. 重点关注建议（需领导盯办的事项）",
      risk:"请分析以下数据，智能识别可能存在风险但尚未被标记的任务：\\n1. 有计划但长期未更新实际进展的任务\\n2. 多次出现'暂缓'、'待确认'的任务\\n3. 负责人空缺或未填写的任务\\n4. 进展描述模糊不清的任务\\n请列出具体任务序号和名称，说明判断依据。",
      reason:"请对以下异常/风险任务进行原因推测和建议：\\n1. 分析每个异常任务可能的风险原因\\n2. 给出具体的解决建议和措施\\n3. 建议是否需要领导协调或介入\\n4. 按紧急程度排序"
    }};
    let aiHistory=[];

    function buildContext(){{
      const MN=["","1月","2月","3月","4月","5月","6月","7月","8月","9月","10月","11月","12月"];
      const maxM=DD.currentMonth;
      let ctx=`以下是全部月份（1-${{maxM}}月）的工作目标数据：\\n\\n`;
      for(let m=1;m<=maxM;m++){{
        const s=calcAll(m);
        ctx+=`=== ${{MN[m]}} ===\\n任务总数：${{s.total}}，正常：${{s.green}}，风险：${{s.yellow}}，异常：${{s.red}}\\n按期完成率：${{s.ontimeRate}}%，问题闭环率：${{s.closedRate}}%\\n`;
        s.centers.forEach((c,i)=>ctx+=`  中心${{i+1}}.${{c.center}}：总数${{c.total}}，正常${{c.green}}，风险${{c.yellow}}，异常${{c.red}}，重点${{c.key}}\\n`);
        const reds=s.items.filter(t=>t.status==="red");
        if(reds.length){{ctx+=`  异常任务：`;reds.forEach(t=>ctx+=`[${{t.seq}}]${{t.project}}(${{t.reason}}) `);ctx+="\\n"}}
        const noplan=s.items.filter(t=>t.hasMonthPlan&&!t.latestActual);
        if(noplan.length){{ctx+=`  有计划未填实际（${{noplan.length}}项）：`;noplan.slice(0,10).forEach(t=>ctx+=`[${{t.seq}}]${{t.project}} `);ctx+="\\n"}}
        ctx+=`  任务明细：\\n`;
        s.items.slice(0,40).forEach(t=>ctx+=`  [${{t.seq}}] ${{t.project}} | ${{t.center}} | ${{t.owner||"未填"}} | ${{t.statusText}} | ${{t.reason}} | 计划：${{(t.latestPlan||"").slice(0,50)}} | 实际：${{(t.latestActual||"").slice(0,50)}}\\n`);
        ctx+="\\n";
      }}
      ctx+=`当前选中的分析月份是：${{MN[curM]}}\\n`;
      return ctx;
    }}

    async function callAI(userMsg){{
      const cfg=localStorage.getItem('ai_config');
      if(!cfg){{addMsg('assistant','请先在看板首页配置 AI 模型（API 地址、Key、模型名称）。');return}}
      let c;try{{c=JSON.parse(cfg)}}catch(e){{addMsg('assistant','AI 配置格式错误，请重新配置。');return}}
      if(!c.apiUrl||!c.apiKey||!c.model){{addMsg('assistant','AI 配置不完整，请检查 API 地址、Key 和模型名称。');return}}
      const sysPrompt="你是项目管理分析助手。根据提供的项目数据回答问题。回答使用中文，结构清晰，用编号和要点组织内容。";
      const ctx=buildContext();
      const messages=[{{role:"system",content:sysPrompt+"\\n\\n"+ctx}},...aiHistory,{{role:"user",content:userMsg}}];
      addMsg('assistant','');
      const lastMsg=document.querySelector('.ai-msg.assistant:last-child span');
      lastMsg.innerHTML='<div class="ai-loading"><i></i><i></i><i></i></div>';
      let url=c.apiUrl.replace(/\\/$/,'');
      if(!url.endsWith('/chat/completions'))url+=(url.endsWith('/v1')||url.endsWith('/v4')?'':'/v1')+'/chat/completions';
      try{{
        const resp=await fetch(url,{{method:'POST',headers:{{'Content-Type':'application/json','Authorization':'Bearer '+c.apiKey}},body:JSON.stringify({{model:c.model,messages,stream:true}})}});
        if(!resp.ok){{const err=await resp.text();throw new Error('API错误('+resp.status+'): '+err)}}
        const reader=resp.body.getReader();const decoder=new TextDecoder();let result='';let buffer='';
        while(true){{
          const{{done,value}}=await reader.read();if(done)break;
          buffer+=decoder.decode(value,{{stream:true}});const lines=buffer.split('\\n');buffer=lines.pop()||'';
          for(const line of lines){{
            const trimmed=line.trim();if(!trimmed.startsWith('data: '))continue;
            const data=trimmed.slice(6);if(data==='[DONE]')continue;
            try{{const json=JSON.parse(data);const delta=json.choices?.[0]?.delta?.content;if(delta){{result+=delta;lastMsg.textContent=result}}}}catch(e){{}}
          }}
        }}
        aiHistory.push({{role:"user",content:userMsg}},{{role:"assistant",content:result}});
        if(aiHistory.length>10)aiHistory=aiHistory.slice(-8);
      }}catch(e){{lastMsg.textContent='调用失败：'+e.message}}
    }}

    function addMsg(role,text){{
      const d=document.createElement('div');d.className='ai-msg '+role;
      d.innerHTML='<span>'+esc(text)+'</span>';document.getElementById('aiBody').appendChild(d);
      document.getElementById('aiBody').scrollTop=999999;
    }}

    document.getElementById("aiBtn").addEventListener("click",()=>{{
      document.getElementById("aiBody").innerHTML='';aiHistory=[];
      document.getElementById("aiModal").classList.add("open");
    }});
    document.getElementById("aiClose").addEventListener("click",()=>document.getElementById("aiModal").classList.remove("open"));
    document.getElementById("aiModal").addEventListener("click",e=>{{if(e.target.id==="aiModal")document.getElementById("aiModal").classList.remove("open")}});
    document.querySelectorAll(".ai-pbtn").forEach(b=>b.addEventListener("click",()=>callAI(PRESETS[b.dataset.p])));
    document.getElementById("aiSend").addEventListener("click",()=>{{
      const v=document.getElementById("aiInput").value.trim();if(!v)return;
      addMsg('user',v);document.getElementById("aiInput").value='';callAI(v);
    }});
    document.getElementById("aiInput").addEventListener("keydown",e=>{{if(e.key==='Enter')document.getElementById("aiSend").click()}});

    /* 整改任务清单 */
    const RK='rectify_{sheet_indicator}';
    let rectifyTab='pending';
    function loadRectify(){{const d=localStorage.getItem(RK);if(d)try{{return JSON.parse(d)}}catch(e){{}}return[]}}
    function saveRectify(list){{localStorage.setItem(RK,JSON.stringify(list))}}
    function renderRectify(){{
      const list=loadRectify();
      const pn=list.filter(r=>r.status==='pending'),ad=list.filter(r=>r.status==='adopted'),rs=list.filter(r=>r.status==='resolved');
      document.querySelectorAll('.rtab').forEach(b=>{{
        const t=b.dataset.tab,n=t==='pending'?pn.length:t==='adopted'?ad.length:rs.length;
        b.textContent=(t==='pending'?'待选':t==='adopted'?'整改中':'已整改')+' ('+n+')';
        b.classList.toggle('on',t===rectifyTab);
      }});
      const fl=rectifyTab==='pending'?pn:rectifyTab==='adopted'?ad:rs;
      const ct=document.getElementById('rectifyCards');
      if(!ct)return;
      if(!fl.length){{ct.innerHTML='<p class="empty">暂无整改任务</p>';return}}
      ct.innerHTML=fl.map(r=>{{
        let act='';
        if(r.status==='pending')act='<button class="rbtn adopt" data-id="'+r.id+'">采纳</button><button class="rbtn ignore" data-id="'+r.id+'">忽略</button>';
        else if(r.status==='adopted')act='<button class="rbtn resolve" data-id="'+r.id+'">标记已整改</button>';
        return '<article class="rcard '+r.status+'"><div class="rcard-head"><b>'+r.seq+'. '+esc(r.project)+'</b>'+(r.status==='resolved'?'<span class="st green">已整改</span>':'')+'</div><div class="rcard-body"><div><span>问题</span><p>'+esc(r.issue)+'</p></div><div><span>整改措施</span><p>'+esc(r.measure)+'</p></div></div><div class="rcard-meta"><span>负责人：'+esc(r.owner||'未填')+'</span><span>'+r.month+'月分析</span></div>'+(act?'<div class="rcard-actions">'+act+'</div>':'')+'</article>';
      }}).join('');
      ct.querySelectorAll('.rbtn.adopt').forEach(b=>b.addEventListener('click',function(){{
        const list=loadRectify(),item=list.find(r=>r.id===this.dataset.id);
        if(item){{item.status='adopted';saveRectify(list);renderRectify()}}
      }}));
      ct.querySelectorAll('.rbtn.ignore').forEach(b=>b.addEventListener('click',function(){{
        let list=loadRectify();list=list.filter(r=>r.id!==this.dataset.id);
        saveRectify(list);renderRectify();
      }}));
      ct.querySelectorAll('.rbtn.resolve').forEach(b=>b.addEventListener('click',function(){{
        const list=loadRectify(),item=list.find(r=>r.id===this.dataset.id);
        if(item){{item.status='resolved';saveRectify(list);renderRectify()}}
      }}));
    }}
    function bindRectify(){{
      document.querySelectorAll('.rtab').forEach(b=>b.addEventListener('click',function(){{
        rectifyTab=this.dataset.tab;renderRectify();
      }}));
      const rb=document.getElementById('rectifyBtn');
      if(rb)rb.addEventListener('click',generateRectify);
    }}
    async function generateRectify(){{
      const cfg=localStorage.getItem('ai_config');
      if(!cfg){{alert('请先在看板首页配置 AI 模型');return}}
      let c;try{{c=JSON.parse(cfg)}}catch(e){{alert('AI 配置格式错误');return}}
      if(!c.apiUrl||!c.apiKey||!c.model){{alert('AI 配置不完整');return}}
      const s=calcAll(curM);
      const problems=s.items.filter(t=>t.status==='red'||t.status==='yellow');
      if(!problems.length){{alert('当前'+curM+'月无异常/风险任务');return}}
      const taskList=problems.map(t=>'序号:'+t.seq+' | 项目:'+t.project+' | 负责人:'+(t.owner||'未填')+' | 中心:'+t.center+' | 状态:'+t.statusText+' | 原因:'+t.reason+' | 计划:'+cpt(t.latestPlan||'未填',40)+' | 实际:'+cpt(t.latestActual||'未填',60)+' | 得分:'+(t.latestScore||'无')).join('\\n');
      const prompt='你是项目管理整改顾问。以下是'+curM+'月的异常/风险任务数据，请根据每个任务的实际进展和异常原因推测根本原因，生成针对性的整改措施。\\n\\n要求：\\n1. 根据任务的实际进展和异常原因，推测根本原因，给出简明问题摘要（不超过30字）\\n2. 针对根本原因给出具体可执行的整改措施，包括责任人、时间节点、关键动作（不超过80字）\\n3. 严格按JSON数组格式返回，不要返回其他内容\\n\\n问题任务列表：\\n'+taskList+'\\n\\n返回格式示例：\\n[{{"seq":1,"issue":"问题摘要含原因分析","measure":"整改措施含责任人、时间、动作"}}]'
      const btn=document.getElementById('rectifyBtn');
      btn.disabled=true;btn.textContent='AI 分析中('+curM+'月)...';
      let url=c.apiUrl.replace(/\\/$/,'');
      if(!url.endsWith('/chat/completions'))url+=(url.endsWith('/v1')||url.endsWith('/v4')?'':'/v1')+'/chat/completions';
      try{{
        const resp=await fetch(url,{{method:'POST',headers:{{'Content-Type':'application/json','Authorization':'Bearer '+c.apiKey}},body:JSON.stringify({{model:c.model,messages:[{{role:'user',content:prompt}}],stream:true}})}});
        if(!resp.ok){{const err=await resp.text();throw new Error('API错误('+resp.status+'): '+err)}}
        const reader=resp.body.getReader();const decoder=new TextDecoder();let result='';let buffer='';
        while(true){{
          const{{done,value}}=await reader.read();if(done)break;
          buffer+=decoder.decode(value,{{stream:true}});const lines=buffer.split('\\n');buffer=lines.pop()||'';
          for(const line of lines){{
            const trimmed=line.trim();if(!trimmed.startsWith('data: '))continue;
            const data=trimmed.slice(6);if(data==='[DONE]')continue;
            try{{const json=JSON.parse(data);const delta=json.choices?.[0]?.delta?.content;if(delta)result+=delta}}catch(e){{}}
          }}
        }}
        if(!result){{alert('AI 未返回数据');return}}
        const jsonMatch=result.match(/\\[[\\s\\S]*\\]/);
        if(!jsonMatch){{alert('AI 返回格式异常，请重试\\n'+result.slice(0,200));return}}
        let items;try{{items=JSON.parse(jsonMatch[0])}}catch(e){{alert('AI 返回 JSON 解析失败\\n'+result.slice(0,200));return}}
        const probMap={{}};problems.forEach(t=>{{probMap[t.seq]=t}});
        const list=loadRectify();
        const now=new Date().toISOString().slice(0,10);
        let added=0;
        items.forEach(item=>{{
          const task=probMap[item.seq];if(!task)return;
          if(list.some(r=>r.seq===item.seq&&r.month===curM))return;
          list.push({{id:'r_'+Date.now()+'_'+item.seq,seq:item.seq,project:task.project,owner:task.owner||'',issue:item.issue||'',measure:item.measure||'',status:'pending',month:curM,created:now}});
          added++;
        }});
        saveRectify(list);rectifyTab='pending';renderRectify();
        alert('生成成功！新增 '+added+' 项整改任务');
      }}catch(e){{alert('AI 调用失败：'+e.message)
      }}finally{{btn.disabled=false;btn.textContent='AI分析生成整改任务'}}
    }}

    render(CM);
  }})();
  </script>
</body>
</html>"""
    output_path.write_text(page, encoding="utf-8")


def build_index(business_summary: dict, support_summary: dict) -> None:
    bt = str(business_summary['total'])
    bg = str(business_summary['green'])
    by = str(business_summary['yellow'])
    br = str(business_summary['red'])
    st = str(support_summary['total'])
    sg = str(support_summary['green'])
    sy = str(support_summary['yellow'])
    sr = str(support_summary['red'])

    page = f"""<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>2026年工作目标看板首页</title>
<script src="https://cdn.jsdelivr.net/npm/jszip@3.10.1/dist/jszip.min.js"></script>
<style>
body{{margin:0;font-family:"Microsoft YaHei",Arial,sans-serif;background:linear-gradient(180deg,#eaf1fb,#f7f9fc);color:#172033}}
main{{width:min(1120px,calc(100vw - 32px));margin:0 auto;padding:40px 0}}
h1{{font-size:34px;margin:0 0 8px}}p{{color:#68758b}}
.cards{{display:grid;grid-template-columns:1fr 1fr;gap:16px;margin-top:24px}}
a.card{{display:block;text-decoration:none;color:inherit;background:#fff;border:1px solid #dbe4f0;border-radius:8px;padding:22px;box-shadow:0 18px 44px rgba(31,48,83,.11)}}
h2{{margin:0 0 16px;font-size:22px}}
.kpis{{display:grid;grid-template-columns:repeat(4,1fr);gap:10px}}
.kpis div{{background:#f7f9fc;border:1px solid #dbe4f0;border-radius:6px;padding:10px}}
.kpis span{{display:block;color:#68758b;font-size:12px}}.kpis b{{font-size:24px}}
.top-bar{{display:flex;justify-content:space-between;align-items:center}}
.btns{{display:flex;gap:8px}}
.btn{{height:38px;border:1px solid #dbe4f0;background:#fff;border-radius:6px;padding:0 16px;font-weight:700;font-size:14px;cursor:pointer;color:#172033;display:inline-flex;align-items:center;gap:6px}}
.btn:hover{{background:#f0f4fa}}.btn.active{{background:#2158d0;color:#fff;border-color:#2158d0}}
.btn.primary{{background:#2158d0;color:#fff;border-color:#2158d0}}.btn.primary:hover{{background:#1a4bb8}}
.modal{{position:fixed;inset:0;display:none;align-items:center;justify-content:center;background:rgba(15,23,42,.36);backdrop-filter:blur(2px);z-index:30;padding:22px}}
.modal.open{{display:flex}}
.cfg{{width:min(560px,94vw);background:#fff;border-radius:12px;border:1px solid #dbe4f0;box-shadow:0 28px 70px rgba(20,33,58,.28);overflow:hidden}}
.cfg-head{{display:flex;justify-content:space-between;align-items:center;padding:18px 22px;border-bottom:1px solid #dbe4f0;background:linear-gradient(180deg,#f9fbff,#fff)}}
.cfg-head h2{{margin:0;font-size:20px}}
.close{{width:34px;height:34px;border:1px solid #dbe4f0;border-radius:6px;background:#fff;font-size:22px;cursor:pointer}}
.cfg-body{{padding:22px}}
.fg{{margin-bottom:16px}}
.fg label{{display:block;font-weight:700;font-size:14px;margin-bottom:6px}}
.fg input{{width:100%;height:38px;border:1px solid #dbe4f0;border-radius:6px;padding:0 12px;font-size:14px;box-sizing:border-box}}
.fg small{{display:block;color:#68758b;font-size:12px;margin-top:4px}}
.fg .hint{{background:#f7f9fc;border:1px solid #e3eaf4;border-radius:6px;padding:10px 12px;font-size:12px;color:#68758b;margin-top:8px;line-height:1.6}}
.fg .hint b{{color:#172033}}
.save-btn{{width:100%;height:42px;background:#2158d0;color:#fff;border:none;border-radius:6px;font-size:16px;font-weight:700;cursor:pointer;margin-top:8px}}
.save-btn:hover{{background:#1a4bb8}}
.status{{display:inline-flex;align-items:center;gap:6px;font-size:13px;margin-left:12px}}
.status.ok{{color:#18a058}}.status.no{{color:#d99a00}}
.toast{{position:fixed;top:20px;left:50%;transform:translateX(-50%);padding:12px 24px;border-radius:8px;font-size:14px;font-weight:700;z-index:100;animation:fadein .3s;pointer-events:none}}
.toast.err{{background:#d92d20;color:#fff}}.toast.ok{{background:#18a058;color:#fff}}
@keyframes fadein{{from{{opacity:0;transform:translateX(-50%) translateY(-10px)}}to{{opacity:1;transform:translateX(-50%) translateY(0)}}}}
.loading-mask{{position:fixed;inset:0;background:rgba(255,255,255,.8);display:none;align-items:center;justify-content:center;z-index:50;flex-direction:column;gap:12px}}
.loading-mask.open{{display:flex}}
.spinner{{width:40px;height:40px;border:4px solid #dbe4f0;border-top-color:#2158d0;border-radius:50%;animation:spin .8s linear infinite}}
@keyframes spin{{to{{transform:rotate(360deg)}}}}
@media(max-width:760px){{.cards{{grid-template-columns:1fr}}}}
</style></head>
<body><main>
<div class="top-bar"><div><h1>2026年工作目标看板</h1><p>由"2026年工作目标o.xlsx"自动解析生成</p></div>
<div class="btns">
<button class="btn primary" id="uploadBtn">&#128194; 重新读取文件</button>
<button class="btn" id="cfgBtn">&#9881; AI 模型配置</button>
</div></div>
<input type="file" id="fileInput" accept=".xlsx" style="display:none">
<section class="cards">
<a class="card" href="business_goal_dashboard.html"><h2>业务目标看板</h2><div class="kpis"><div><span>任务</span><b>{bt}</b></div><div><span>正常</span><b>{bg}</b></div><div><span>风险</span><b>{by}</b></div><div><span>异常</span><b>{br}</b></div></div></a>
<a class="card" href="support_center_goal_dashboard.html"><h2>支撑中心目标看板</h2><div class="kpis"><div><span>任务</span><b>{st}</b></div><div><span>正常</span><b>{sg}</b></div><div><span>风险</span><b>{sy}</b></div><div><span>异常</span><b>{sr}</b></div></div></a>
</section></main>
<div class="loading-mask" id="loadMask"><div class="spinner"></div><p>正在解析文件...</p></div>
<div class="modal" id="cfgModal">
<div class="cfg"><div class="cfg-head"><h2>AI 模型配置</h2><button class="close" id="cfgClose">&times;</button></div>
<div class="cfg-body">
  <div class="fg"><label>API 地址（Base URL）</label><input id="apiUrl" placeholder="https://api.openai.com"><small>不含 /v1/chat/completions，系统自动拼接</small></div>
  <div class="fg"><label>API Key</label><input id="apiKey" type="password" placeholder="sk-..."></div>
  <div class="fg"><label>模型名称</label><input id="modelName" placeholder="gpt-4o-mini"></div>
  <div class="fg"><div class="hint"><b>常见服务商 API 地址：</b><br>OpenAI: https://api.openai.com<br>通义千问: https://dashscope.aliyuncs.com/compatible-mode/v1<br>智谱AI: https://open.bigmodel.cn/api/paas/v4<br>DeepSeek: https://api.deepseek.com<br>Kimi: https://api.moonshot.cn/v1<br><br><b>注意：</b>通义千问/智谱只需填到 .../v1 即可，系统会自动拼接 /chat/completions</div></div>
  <button class="save-btn" id="saveBtn">保存配置</button>
</div></div></div>
<script>
(function(){{
  const K='ai_config',MONTHS=12;
  function load(){{const d=localStorage.getItem(K);if(d)try{{return JSON.parse(d)}}catch(e){{}}return null}}
  function save(){{const c={{apiUrl:document.getElementById('apiUrl').value.trim(),apiKey:document.getElementById('apiKey').value.trim(),model:document.getElementById('modelName').value.trim()}};if(!c.apiUrl||!c.apiKey||!c.model){{alert('请填写完整配置');return}}localStorage.setItem(K,JSON.stringify(c));alert('配置已保存');document.getElementById('cfgModal').classList.remove('open')}}
  function openCfg(){{const c=load();if(c){{document.getElementById('apiUrl').value=c.apiUrl||'';document.getElementById('apiKey').value=c.apiKey||'';document.getElementById('modelName').value=c.model||''}}document.getElementById('cfgModal').classList.add('open')}}
  document.getElementById('cfgBtn').addEventListener('click',openCfg);
  document.getElementById('saveBtn').addEventListener('click',save);
  document.getElementById('cfgClose').addEventListener('click',()=>document.getElementById('cfgModal').classList.remove('open'));
  document.getElementById('cfgModal').addEventListener('click',e=>{{if(e.target.id==='cfgModal')document.getElementById('cfgModal').classList.remove('open')}});
  document.addEventListener('keydown',e=>{{if(e.key==='Escape')document.getElementById('cfgModal').classList.remove('open')}});

  function toast(msg,type){{
    const d=document.createElement('div');d.className='toast '+(type||'err');d.textContent=msg;
    document.body.appendChild(d);setTimeout(()=>d.remove(),3500);
  }}

  const NS='http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  const REL_NS='http://schemas.openxmlformats.org/package/2006/relationships';
  function colIdx(ref){{
    const m=ref.match(/^([A-Z]+)/);if(!m)return 0;let v=0;for(const c of m[1])v=v*26+c.charCodeAt(0)-64;return v-1;
  }}
  function getText(el,ns){{
    const ts=el.getElementsByTagNameNS(ns,'t');let s='';for(let i=0;i<ts.length;i++)s+=ts[i].textContent||'';return s.trim();
  }}
  function cellVal(cell,ss,ns){{
    const t=cell.getAttribute('t');
    if(t==='s'){{const v=cell.getElementsByTagNameNS(ns,'v')[0];if(!v||!v.textContent)return '';return ss[parseInt(v.textContent)]||'';}}
    if(t==='inlineStr')return getText(cell,ns);
    const v=cell.getElementsByTagNameNS(ns,'v')[0];
    return v&&v.textContent?v.textContent:'';
  }}
  async function readSharedStrings(zip){{
    const f=zip.file('xl/sharedStrings.xml');if(!f)return [];
    const doc=new DOMParser().parseFromString(await f.async('text'),'text/xml');
    const sis=doc.getElementsByTagNameNS(NS,'si');
    const arr=[];for(let i=0;i<sis.length;i++)arr.push(getText(sis[i],NS));
    return arr;
  }}
  async function readSheetRows(zip,path,ss){{
    const f=zip.file(path);if(!f)return [];
    const doc=new DOMParser().parseFromString(await f.async('text'),'text/xml');
    const rows=doc.getElementsByTagNameNS(NS,'row');
    const result=[];
    for(let r=0;r<rows.length;r++){{
      const cells=rows[r].getElementsByTagNameNS(NS,'c');
      const vals=[];
      for(let c=0;c<cells.length;c++){{
        const idx=colIdx(cells[c].getAttribute('r'));
        while(vals.length<=idx)vals.push('');
        vals[idx]=cellVal(cells[c],ss,NS).replace(/[\\r\\n]+/g,' ').replace(/[ \\t]+/g,' ').trim();
      }}
      result.push(vals);
    }}
    return result;
  }}
  async function sheetPaths(zip){{
    const wbDoc=new DOMParser().parseFromString(await zip.file('xl/workbook.xml').async('text'),'text/xml');
    const relsDoc=new DOMParser().parseFromString(await zip.file('xl/_rels/workbook.xml.rels').async('text'),'text/xml');
    const rmap={{}};const rels=relsDoc.getElementsByTagNameNS(REL_NS,'Relationship');
    for(let i=0;i<rels.length;i++)rmap[rels[i].getAttribute('Id')]=rels[i].getAttribute('Target');
    const map={{}};const sheets=wbDoc.getElementsByTagNameNS(NS,'sheet');
    for(let i=0;i<sheets.length;i++){{
      const name=sheets[i].getAttribute('name');
      const rid=sheets[i].getAttributeNS('http://schemas.openxmlformats.org/officeDocument/2006/relationships','id');
      let tgt=rmap[rid]||'';if(!tgt.startsWith('xl/'))tgt='xl/'+tgt;
      map[name]=tgt;
    }}
    return map;
  }}
  function safeInt(v){{const m=String(v||'').match(/-?\\d+/);return m?parseInt(m[0]):null;}}

  async function parseSheet(zip,name,path,ss){{
    const rows=await readSheetRows(zip,path,ss);
    let headerIdx=-1;
    for(let i=0;i<rows.length;i++){{
      if(rows[i].length>6&&rows[i][0]==='序号'&&rows[i][3]&&rows[i][3].includes('项目')){{headerIdx=i;break;}}
    }}
    if(headerIdx<0)return null;
    const tasks=[];
    for(let i=headerIdx+1;i<rows.length;i++){{
      const row=rows[i];
      const seq=safeInt(row[0]||'');
      const project=(row[3]||'').trim();
      const center=(row[1]||'').trim();
      if(seq===null||!project||!center)continue;
      const monthly=[];
      for(let m=1;m<=MONTHS;m++){{
        const base=10+(m-1)*4;
        monthly.push({{month:m,plan:row[base]||'',actual:row[base+1]||'',score:row[base+2]||'',note:row[base+3]||''}});
      }}
      tasks.push({{
        seq,sheet:name,center,keyTask:row[2]||'',project,target:row[4]||'',
        stagePlan:row[5]||'',owner:row[6]||'',rawStatus:row[7]||'',
        selfDeveloped:row[8]||'',assessor:row[9]||'',monthly
      }});
    }}
    return tasks;
  }}

  document.getElementById('uploadBtn').addEventListener('click',()=>document.getElementById('fileInput').click());
  document.getElementById('fileInput').addEventListener('change',async function(e){{
    const file=e.target.files[0];if(!file)return;
    this.value='';
    if(!file.name.endsWith('.xlsx')){{toast('请选择 .xlsx 格式的 Excel 文件','err');return;}}
    document.getElementById('loadMask').classList.add('open');
    try{{
      const buf=await file.arrayBuffer();
      const zip=await JSZip.loadAsync(buf);
      const ss=await readSharedStrings(zip);
      const sp=await sheetPaths(zip);

      let bizName='',supName='';
      for(const n in sp){{if(n.startsWith('业务目标'))bizName=n;if(n==='支撑中心目标')supName=n;}}
      if(!bizName||!supName){{
        document.getElementById('loadMask').classList.remove('open');
        toast('文件格式不对，请更换文件（缺少「业务目标」或「支撑中心目标」工作表）','err');
        return;
      }}

      const bizTasks=await parseSheet(zip,bizName,sp[bizName],ss);
      const supTasks=await parseSheet(zip,supName,sp[supName],ss);
      if(bizTasks===null||supTasks===null){{
        document.getElementById('loadMask').classList.remove('open');
        toast('文件格式不对，请更换文件（未找到「序号」和「项目」表头行）','err');
        return;
      }}
      if(bizTasks.length===0&&supTasks.length===0){{
        document.getElementById('loadMask').classList.remove('open');
        toast('文件格式不对，请更换文件（未读取到有效任务数据）','err');
        return;
      }}

      let maxMonth=1;
      [bizTasks,supTasks].forEach(tasks=>tasks.forEach(t=>t.monthly.forEach(m=>{{
        if(m.plan||m.actual){{
          const found=Math.min(m.month,MONTHS);
          if(found>maxMonth)maxMonth=found;
        }}
      }})));

      localStorage.setItem('kanban_uploaded_business',JSON.stringify({{tasks:bizTasks,currentMonth:maxMonth,sheet:'business'}}));
      localStorage.setItem('kanban_uploaded_support',JSON.stringify({{tasks:supTasks,currentMonth:maxMonth,sheet:'support'}}));

      document.getElementById('loadMask').classList.remove('open');
      toast('文件解析成功！业务 '+bizTasks.length+' 项，支撑 '+supTasks.length+' 项','ok');
      setTimeout(()=>{{window.location.href='business_goal_dashboard.html';}},1200);
    }}catch(err){{
      document.getElementById('loadMask').classList.remove('open');
      toast('文件读取失败：'+err.message,'err');
    }}
  }});
}})();
</script></body></html>"""

    Path("dashboard_index.html").write_text(page, encoding="utf-8")


def main() -> None:
    workbook_files = sorted(Path(".").glob(WORKBOOK_PATTERN))
    if not workbook_files:
        raise FileNotFoundError(f"未找到 {WORKBOOK_PATTERN}")
    workbook_path = workbook_files[0]
    with ZipFile(workbook_path) as zip_file:
        sheets = workbook_sheet_paths(zip_file)
        business_name = next(name for name in sheets if name.startswith("业务目标"))
        support_name = next(name for name in sheets if name == "支撑中心目标")
        business_tasks = parse_sheet(zip_file, business_name, sheets[business_name])
        support_tasks = parse_sheet(zip_file, support_name, sheets[support_name])

    business_summary = summarize(business_tasks)
    support_summary = summarize(support_tasks)

    build_dashboard(
        "业务目标驾驶舱看板",
        f"子表：{business_name}",
        business_tasks,
        Path("business_goal_dashboard.html"),
        workbook_path.name,
        sheet_indicator="business",
    )
    build_dashboard(
        "支撑中心目标驾驶舱看板",
        f"子表：{support_name}",
        support_tasks,
        Path("support_center_goal_dashboard.html"),
        workbook_path.name,
        sheet_indicator="support",
    )
    build_index(business_summary, support_summary)

    compact_report = {
        "workbook": str(workbook_path),
        "business": {k: business_summary[k] for k in ("total", "green", "yellow", "red", "keyTotal", "mayTotal", "decisionTotal", "closedRate", "ontimeRate")},
        "support": {k: support_summary[k] for k in ("total", "green", "yellow", "red", "keyTotal", "mayTotal", "decisionTotal", "closedRate", "ontimeRate")},
        "outputs": [
            "dashboard_index.html",
            "business_goal_dashboard.html",
            "support_center_goal_dashboard.html",
        ],
    }
    print(json.dumps(compact_report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
