#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""R46 三向一致专项 + 静态语法闸 v0
1) ROADMAP 空勾条目 -> 反查 INDEX_REGISTRY -> A/B/C 分类，A 类直接补勾
2) DL_Motion 抽 5 件做静态语法检查（非真实编译）
"""
import json, re, os, difflib, io, sys
from datetime import datetime

ROOT = r"C:\Library"
ROADMAP = os.path.join(ROOT, "ROADMAP.md")
REG = os.path.join(ROOT, "INDEX_REGISTRY.json")
OUTDIR = os.path.join(ROOT, "_Staging_Raw", "2026-11-19")
OUT = os.path.join(OUTDIR, "CONSISTENCY_R46.md")
MOTION = os.path.join(ROOT, "DL_Motion")


def norm(s):
    """归一化：去下划线/大小写/非字母数字"""
    return re.sub(r"[^a-z0-9]", "", s.lower())


NAME_RE = re.compile(r"\b(?:FB|FC|I|ST|E|UDT)_DL_[A-Za-z0-9_]+")


def load_registry():
    with io.open(REG, encoding="utf-8") as f:
        d = json.load(f)
    names = [c["name"] for c in d["components"]]
    cats = {c["name"]: c.get("category", "") for c in d["components"]}
    return names, cats, d.get("total_components"), d.get("version")


def parse_roadmap():
    with io.open(ROADMAP, encoding="utf-8") as f:
        lines = f.read().split("\n")
    items = []  # (idx, raw, name, desc)
    for i, l in enumerate(lines):
        if re.match(r"^\s*- \[ \]", l):
            m = NAME_RE.search(l)
            if m:
                desc = l[m.end():].strip(" `：:｜|→*-")
                items.append((i, l, m.group(0), desc))
            else:
                items.append((i, l, None, l.strip()))
    return lines, items


def classify(items, regnames, regcats):
    regmap = {}
    for n in regnames:
        regmap.setdefault(norm(n), n)
    A, B, C = [], [], []
    for idx, raw, name, desc in items:
        if name is None:
            C.append((idx, raw, "(无可解析名)", desc, "非组件条目/占位文字"))
            continue
        k = norm(name)
        if k in regmap:
            A.append((idx, raw, name, desc, regmap[k]))
            continue
        # 模糊邻件判定
        best, ratio = None, 0.0
        for rn in regnames:
            r = difflib.SequenceMatcher(None, k, norm(rn)).ratio()
            if r > ratio:
                best, ratio = rn, r
        dead = any(w in raw for w in ("弃做", "不做", "暂缓", "已废弃", "删除", "不立项"))
        if ratio >= 0.80:
            C.append((idx, raw, name, desc, "同义邻件：%s (相似度 %.2f)" % (best, ratio)))
        elif dead:
            C.append((idx, raw, name, desc, "条目显式标注弃做/暂缓"))
        else:
            B.append((idx, raw, name, desc, "最近似 %s (%.2f)" % (best, ratio)))
    return A, B, C


def fix_checks(lines, A):
    """A 类补勾：仅把 - [ ] 改 - [x]，不动其他字符"""
    n = 0
    for idx, raw, name, desc, matched in A:
        if lines[idx].startswith("- [ ]") or re.match(r"^\s*- \[ \]", lines[idx]):
            lines[idx] = re.sub(r"^(\s*)- \[ \]", r"\1- [x]", lines[idx], count=1)
            n += 1
    return n


# ---------------- 静态语法闸 v0（引用独立模块） ----------------
from compile_gate_v0 import gate_file, pick_samples


def main():
    regnames, regcats, total, ver = load_registry()
    lines, items = parse_roadmap()
    A, B, C = classify(items, regnames, regcats)
    nfixed = fix_checks(lines, A)
    with io.open(ROADMAP, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))

    # Motion 抽样：最近新增 2 件 + 核心 3 件
    sample = pick_samples(MOTION, 5)
    gates = []
    for p in sample:
        _src, _iss = gate_file(p)
        gates.append({"file": os.path.basename(p),
                      "lines": len(_src.splitlines()), "issues": _iss})

    md = []
    md.append("# R46 三向一致专项 + 静态语法闸 v0 报告\n")
    md.append("生成时间：%s ｜ registry %s ／ total_components=%s\n" % (
        datetime.now().strftime("%Y-%m-%d %H:%M:%S"), ver, total))
    md.append("ROADMAP 空勾条目：**%d** 条（含可解析组件名 %d 条）\n" % (
        len(items), len([i for i in items if i[2]])))
    md.append("## 一、分类汇总\n")
    md.append("| 类 | 含义 | 条数 |")
    md.append("|---|---|---|")
    md.append("| A | 已注册，需补勾（已自动补勾 %d 条） | %d |" % (nfixed, len(A)))
    md.append("| B | 真缺口（未注册，可派单） | %d |" % len(B))
    md.append("| C | 判定弃做 / 伪缺口 / 非组件条目 | %d |" % len(C))
    md.append("\n### A 类明细（补勾清单）\n")
    md.append("| # | ROADMAP 名称 | registry 命中 | 行号 |")
    md.append("|---|---|---|---|")
    for i, (idx, raw, name, desc, matched) in enumerate(A, 1):
        md.append("| %d | `%s` | `%s` | %d |" % (i, name, matched, idx + 1))
    md.append("\n### B 类明细（真缺口，可入选题池）\n")
    md.append("| # | 名称 | 描述 | 最近似邻件 | 行号 |")
    md.append("|---|---|---|---|---|")
    for i, (idx, raw, name, desc, note) in enumerate(B, 1):
        md.append("| %d | `%s` | %s | %s | %d |" % (i, name, desc[:60], note, idx + 1))
    md.append("\n### C 类明细（弃做 / 伪缺口）\n")
    md.append("| # | 名称 | 判定理由 | 行号 |")
    md.append("|---|---|---|---|")
    for i, (idx, raw, name, desc, note) in enumerate(C, 1):
        md.append("| %d | `%s` | %s | %d |" % (i, name, note, idx + 1))

    md.append("\n## 二、静态语法闸 v0（**非真实编译**，仅括号/关键字配对正则检查）\n")
    md.append("| 文件 | 行数 | G1 VAR | G2 结构 | G3 括号 | G4 分号 | G5 注释 | G6 红线 | 结论 |")
    md.append("|---|---|---|---|---|---|---|---|---|")
    npass = 0
    for g in gates:
        ok = not g["issues"]
        npass += 1 if ok else 0
        cells = []
        for tag in ("G1", "G2", "G3", "G4", "G5", "G6"):
            hit = [x for x in g["issues"] if x.startswith(tag)]
            cells.append("通过" if not hit else "**%d 项**" % len(hit))
        md.append("| `%s` | %d | %s | %s |" % (
            g["file"], g["lines"], " | ".join(cells), "通过" if ok else "不通过"))
    md.append("\n**抽样 %d 件，零问题 %d 件。**\n" % (len(gates), npass))
    for g in gates:
        if g["issues"]:
            md.append("- `%s`" % g["file"])
            for x in g["issues"]:
                md.append("    - %s" % x)
    md.append("\n> 声明：本闸为静态正则/配平检查，**不等价于 CODESYS 真实编译**，"
              "仅拦截结构性语法断裂；类型检查、隐式转换、库引用未覆盖。\n")
    with io.open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(md))

    # 控制台摘要
    print("A=%d B=%d C=%d fixed=%d" % (len(A), len(B), len(C), nfixed))
    print("GATE pass=%d/%d issues=%d" % (npass, len(gates), sum(len(g["issues"]) for g in gates)))
    print("---B names---")
    for _, _, name, desc, note in B:
        print("%s\t%s" % (name, desc[:40]))
    json.dump({"A": [a[2] for a in A], "B": [b[2] for b in B], "C": [c[2] for c in C],
               "gate": [(g["file"], g["issues"]) for g in gates]},
              io.open(os.path.join(OUTDIR, "_check_r46_result.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
