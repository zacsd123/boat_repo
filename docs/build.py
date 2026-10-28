#!/usr/bin/env python3
"""계획서 맞추기.

규칙(01-rules.md)이나 수치(02-config.md)를 고친 뒤 이 스크립트를 돌리면
  - 단계 파일의 "지킬 규칙", "쓰는 수치" 표를 새 내용으로 다시 채우고
  - 04-traceability.md(규칙 추적표)와 README의 단계 목록을 다시 만들고
  - 없는 규칙 번호, 없는 수치 키, 어느 단계에도 걸리지 않은 규칙을 찾아 알려 준다.

쓰는 법:  python3 build.py            (이 폴더의 파일을 제자리에서 고친다)
         python3 build.py 원본폴더 결과폴더
"""
import re, sys, pathlib

SRC = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parent
OUT = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else SRC
OUT.mkdir(exist_ok=True)

RULE_ROW = re.compile(r"^\| ([A-Z]{2}-\d+) \| (.+?) \|\s*$")
KEY_ROW = re.compile(r"^\| `([A-Z][A-Z0-9_]+)` \| (.+?) \| (.+?) \|")
NOT_START = r"(?:(?!<!--(?:RULES|CONFIG|STAGE_INDEX|KEY_USAGE)).)*?"
GROUP_NAMES = {"KR": "핵심", "FL": "흐름", "SC": "점수", "BT": "배와 한계", "BL": "종과 출항", "CR": "상자",
               "GD": "황금 상자", "IN": "버튼", "HG": "끌어안기", "RC": "되찾기", "WT": "물과 캐릭터",
               "JN": "출입과 인원", "UI": "화면", "PL": "봇", "VR": "배 크기 변주", "PR": "지켜야 할 성질",
               "GP": "계획에서 정한 것"}
errors = []

def read(name): return (SRC / name).read_text(encoding="utf-8")
def unescape(s): return s.replace("\\~", "~")

rules = {}
for line in read("01-rules.md").splitlines():
    m = RULE_ROW.match(line)
    if m:
        if m.group(1) in rules: errors.append(f"규칙 번호가 겹친다: {m.group(1)}")
        rules[m.group(1)] = unescape(m.group(2))
keys = {}
for line in read("02-config.md").splitlines():
    m = KEY_ROW.match(line)
    if m: keys[m.group(1)] = (unescape(m.group(2)), unescape(m.group(3)))

group_order = list(dict.fromkeys(r.split("-")[0] for r in rules))
def rule_sort(r):
    g, n = r.split("-"); return (group_order.index(g), int(n))

stage_files = sorted(p.name for p in SRC.glob("S[0-9][0-9]-*.md"))
stages = []
rule_to_stages = {r: [] for r in rules}
key_to_stages = {k: [] for k in keys}

def fill_tables(text, sid):
    def rules_table(m):
        ids = m.group(1).split()
        rows = ["| 번호 | 규칙 |", "| --- | --- |"]
        for r in ids:
            if r not in rules: errors.append(f"{sid}: 없는 규칙 {r}"); continue
            rows.append(f"| {r} | {rules[r]} |")
            if sid in [s for s, *_ in stages] or sid.startswith("S"):
                if sid not in rule_to_stages[r]: rule_to_stages[r].append(sid)
        body = "\n".join(rows) if ids else "이 단계는 규칙을 새로 구현하지 않는다."
        return f"<!--RULES: {' '.join(ids)}-->\n\n{body}\n\n<!--/RULES-->"
    def config_table(m):
        ks = m.group(1).split()
        rows = ["| 키 | 값 | 뜻 |", "| --- | --- | --- |"]
        for k in ks:
            if k not in keys: errors.append(f"{sid}: 없는 수치 키 {k}"); continue
            rows.append(f"| `{k}` | {keys[k][0]} | {keys[k][1]} |")
            if sid.startswith("S") and sid not in key_to_stages[k]: key_to_stages[k].append(sid)
        body = "\n".join(rows) if ks else "이 단계에서 새로 쓰는 수치는 없다."
        return f"<!--CONFIG: {' '.join(ks)}-->\n\n{body}\n\n<!--/CONFIG-->"
    text = re.sub(r"<!--RULES:(.*?)-->(" + NOT_START + r"<!--/RULES-->)?", rules_table, text, flags=re.S)
    text = re.sub(r"<!--CONFIG:(.*?)-->(" + NOT_START + r"<!--/CONFIG-->)?", config_table, text, flags=re.S)
    return text

def check_refs(name, text):
    plain = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    for r in set(re.findall(r"(?<![A-Za-z0-9])([A-Z]{2}-\d+)(?!\d)", plain)):
        if r not in rules: errors.append(f"{name}: 본문에 없는 규칙 번호 {r}")
    for k in set(re.findall(r"`([A-Z][A-Z0-9_]{3,})`", plain)):
        if k not in keys: errors.append(f"{name}: 본문에 없는 수치 키 {k}")
    for s in set(re.findall(r"(?<![A-Za-z0-9])S(\d\d)(?!\d)", plain)):
        if not any(f.startswith(f"S{s}-") for f in stage_files): errors.append(f"{name}: 없는 단계 S{s}")
    for f in set(re.findall(r"`((?:0\d|S\d\d)-[a-z0-9-]+\.md)`", plain)):
        if not (SRC / f).exists() and f != "04-traceability.md": errors.append(f"{name}: 없는 파일 {f}")

def escape_tildes(text):
    out, in_fence = [], False
    for line in text.split("\n"):
        if line.lstrip().startswith("```"):
            in_fence = not in_fence; out.append(line); continue
        if in_fence: out.append(line); continue
        parts = re.split(r"(`[^`]*`)", line)
        out.append("".join(p if p.startswith("`") else re.sub(r"(?<!\\)~", r"\\~", p) for p in parts))
    return "\n".join(out)

built = {}
for f in stage_files:
    raw = unescape(read(f))
    sid = f[:3]
    title = re.search(r"^# (S\d\d)\. (.+)$", raw, flags=re.M)
    if not title or title.group(1) != sid:
        errors.append(f"{f}: 첫 줄 제목이 '# {sid}. 이름' 꼴이 아니다"); continue
    fields = dict(re.findall(r"^- \*\*(.+?)\*\*: (.+)$", raw, flags=re.M))
    for need in ("묶음", "앞 단계", "크기(어림)", "끝나면"):
        if need not in fields: errors.append(f"{f}: 머리말에 '{need}'가 없다")
    if "## 지킬 규칙" not in raw: errors.append(f"{f}: '지킬 규칙' 절이 없다")
    if "## 완료 확인" not in raw and "## 넘어가는 조건" not in raw:
        errors.append(f"{f}: '완료 확인'이나 '넘어가는 조건' 절이 없다")
    stages.append((sid, f, title.group(2), fields))
    text = fill_tables(raw, sid)
    check_refs(f, text)
    built[f] = text

# 규칙 추적표
lines = ["# 규칙 추적표", "",
         "모든 규칙이 어느 단계에서 구현되거나 확인되는지를 모은 표다. `build.py`가 단계 파일의 \"지킬 규칙\" 절에서 뽑아 만든다. 손으로 고치지 않는다. 고치려면 단계 파일의 규칙 목록을 고치고 `build.py`를 돌린다.", "",
         "쓰는 때는 둘이다. 단계를 끝낼 때 그 단계에 걸린 규칙을 다시 읽는다. 공개 전(S30)에 이 표를 위에서부터 한 줄씩 다시 확인한다.", ""]
groups = {}
for r in rules: groups.setdefault(r.split("-")[0], []).append(r)
for g, rs in groups.items():
    lines += [f"## {GROUP_NAMES.get(g, g)} ({g})", "", "| 번호 | 규칙 | 단계 |", "| --- | --- | --- |"]
    for r in rs:
        st = rule_to_stages[r]
        if not st: errors.append(f"어느 단계에도 걸리지 않은 규칙: {r}")
        lines.append(f"| {r} | {rules[r]} | {', '.join(st)} |")
    lines.append("")
lines += ["## 단계별로 본 규칙", "", "| 단계 | 이름 | 걸린 규칙 |", "| --- | --- | --- |"]
for sid, f, title, fields in stages:
    rs = sorted([r for r in rules if sid in rule_to_stages[r]], key=rule_sort)
    lines.append(f"| {sid} | {title} | {', '.join(rs) if rs else '없음'} |")
lines.append("")
built["04-traceability.md"] = "\n".join(lines)

def stage_index(_):
    rows = ["| 단계 | 파일 | 이름 | 크기(어림) | 끝나면 |", "| --- | --- | --- | --- | --- |"]
    cur = None
    for sid, f, title, fields in stages:
        b = fields.get("묶음", "")
        if b != cur:
            cur = b; rows.append(f"| **{b}** | | | | |")
        rows.append(f"| {sid} | `{f}` | {title} | {fields.get('크기(어림)', '')} | {fields.get('끝나면', '')} |")
    return "<!--STAGE_INDEX-->\n\n" + "\n".join(rows) + "\n\n<!--/STAGE_INDEX-->"
def key_usage(_):
    rows = ["| 키 | 쓰는 단계 |", "| --- | --- |"]
    for k in keys:
        rows.append(f"| `{k}` | {', '.join(key_to_stages[k]) if key_to_stages[k] else '없음'} |")
    return "<!--KEY_USAGE-->\n\n" + "\n".join(rows) + "\n\n<!--/KEY_USAGE-->"

for f in ("README.md", "01-rules.md", "02-config.md", "03-architecture.md"):
    if not (SRC / f).exists(): errors.append(f"파일이 없다: {f}"); continue
    text = unescape(read(f))
    text = re.sub(r"<!--STAGE_INDEX-->(" + NOT_START + r"<!--/STAGE_INDEX-->)?", stage_index, text, flags=re.S)
    text = re.sub(r"<!--KEY_USAGE-->(" + NOT_START + r"<!--/KEY_USAGE-->)?", key_usage, text, flags=re.S)
    text = fill_tables(text, f)
    check_refs(f, text)
    built[f] = text

for k, st in key_to_stages.items():
    if not st and not k.startswith("DEBUG_"): errors.append(f"어느 단계에서도 쓰지 않는 수치 키: {k}")

for f, text in built.items():
    (OUT / f).write_text(escape_tildes(text).rstrip() + "\n", encoding="utf-8")

print(f"규칙 {len(rules)}개, 수치 키 {len(keys)}개, 단계 {len(stages)}개, 파일 {len(built)}개를 맞췄다 → {OUT}")
if errors:
    print(f"\n고칠 곳 {len(errors)}건:")
    for e in dict.fromkeys(errors): print(" -", e)
    sys.exit(1)
print("교차 검사 통과: 없는 번호나 키가 없고, 모든 규칙이 한 단계 이상에 걸려 있다.")
