# -*- coding: utf-8 -*-
"""R12 码位占用台账生成器
输入：C:\\Library\\INDEX_REGISTRY.json（168 条） + 各组件 .st 实测码位字面量
输出：CODE_SEGMENT_LEDGER_R12.md / code_segment_ledger_r12.json

口径（与 R11 码位地图一致）：
1. 码位段优先取注册表 code_segment；注册表未登记（104 条老组件）时回落到 .st 内
   `16#XXXX_YYYY` 字面量，标注「实测」，仅作占用参考。
2. 公共区不计按件占用：`0000_xxxx`（无故障基准）、各码族 `xxxx_0000~00FF`
   （公共/预留区）、`FFFF_xxxx`（占位填充）。
3. 极大值按号段带统计：`01xx`（信息级）/ `02xx`（故障级）/ `0Xxx`（特殊带）/
   `1x00`（DL_Algo 按件算法带），并给出下一可用起号。
"""
import json, os, re, io, sys, collections

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

LIB = r"C:\Library"
OUT_DIR = os.path.join(LIB, "_Staging_Raw", "2026-11-15")
CATS = ["DL_Base", "DL_MathData", "DL_Algo", "DL_Device", "DL_Motion", "DL_Process"]
FAMILY = {"DL_Base": {"0001", "0002"}, "DL_MathData": {"0001", "0002"},
          "DL_Algo": {"0002"}, "DL_Device": {"0003"},
          "DL_Motion": {"0004"}, "DL_Process": {"0005"}}
COMMON_LOW = {"0000_0000", "0000_0001", "0000_00FF", "FFFF_FFFE", "FFFF_FFFF"} | \
             {f"0001_{v:04X}" for v in range(0x0001, 0x000A)} | \
             {f"0002_{v:04X}" for v in range(0x0000, 0x0006)}
SHARED_NOTE = {
    "DL_Base": "`0001` / `0002` 两族与 DL_MathData（及 DL_Algo 的 `0002`）共用，取码须查末节合计表",
    "DL_MathData": "`0001` / `0002` 两族与 DL_Base（及 DL_Algo 的 `0002`）共用，取码须查末节合计表",
    "DL_Algo": "`0002` 族与 DL_Base / DL_MathData 共用 `01xx~03xx`；算法自有 `1x00` 带逐件独占",
    "DL_Device": "`0003` 族本库独占",
    "DL_Motion": "`0004` 族本库独占",
    "DL_Process": "`0005` 族本库独占",
}

SEG_RE = re.compile(r"16#([0-9A-Fa-f]{4})_([0-9A-Fa-f]{4})(?:~([0-9A-Fa-f]{4}))?")


def parse_registry_segment(seg, cat):
    """注册表码位串 → [(base, start_int, end_int, kind)]
    支持 `0305~0306,0308` / `1B10、1B11` 这类同前缀多段写法。"""
    out = []
    if not seg or seg.startswith("无"):
        return out
    for part in re.split(r"\s*/\s*", seg):
        m = re.search(r"16#([0-9A-Fa-f]{4})_", part)
        if not m:
            continue
        base = m.group(1).upper()
        if base not in FAMILY[cat]:
            continue
        kind = "fault" if "故障" in part else ("info" if ("信息" in part or "入参" in part
                                                         or "降级" in part or "钳位" in part) else "aux")
        rest = part[m.end():]
        # 逐个取 4 位十六进制项与 a~b 区间
        for tok in re.finditer(r"([0-9A-Fa-f]{4})(?:~([0-9A-Fa-f]{4}))?", rest):
            s = int(tok.group(1), 16)
            e = int(tok.group(2), 16) if tok.group(2) else s
            out.append((base, s, e, kind))
    return out


def compress(codes):
    if not codes:
        return ""
    pairs = sorted((c.split("_")[0], int(c.split("_")[1], 16)) for c in codes)
    out, i = [], 0
    while i < len(pairs):
        base, s = pairs[i]
        e = s
        while i + 1 < len(pairs) and pairs[i + 1][0] == base and pairs[i + 1][1] == e + 1:
            i += 1
            e = pairs[i][1]
        out.append(f"16#{base}_{s:04X}" + ("" if e == s else f"~{e:04X}"))
        i += 1
    return " / ".join(out)


def bucket(code):
    """码位 → 号段带标识"""
    v = int(code.split("_")[1], 16)
    if v < 0x0100:
        return "00"
    if v < 0x0200:
        return "01"
    if v < 0x0300:
        return "02"
    if v < 0x1000:
        return f"{v >> 8:02X}"
    return "1x"


def main():
    reg = json.load(open(os.path.join(LIB, "INDEX_REGISTRY.json"), encoding="utf-8"))
    comps = reg["components"]
    rows = collections.defaultdict(list)
    codes_by_cat = collections.defaultdict(set)     # 全部实测/登记码（含低带）
    kinds_by_code = {}                              # code -> 标注集合（来自注册表）
    lowband = collections.defaultdict(set)

    for c in comps:
        cat, name = c["category"], c["name"]
        seg = (c.get("code_segment") or "").strip()
        parsed = parse_registry_segment(seg, cat)
        codes = set()
        for base, s, e, kind in parsed:
            for v in range(s, e + 1):
                k = f"{base}_{v:04X}"
                codes.add(k)
                kinds_by_code.setdefault(k, set()).add(kind)
        if parsed:
            disp = re.sub(r"\s*/\s*", " / ", seg)
        else:
            # 回落：读 .st 实测字面量
            p = c.get("file_path", "")
            if os.path.exists(p):
                txt = open(p, encoding="utf-8").read()
                for a, b in re.findall(r"16#([0-9A-Fa-f]{4})_([0-9A-Fa-f]{4})", txt):
                    k = f"{a.upper()}_{b.upper()}"
                    if a.upper() in FAMILY[cat]:
                        codes.add(k)
            hi = {k for k in codes if int(k.split("_")[1], 16) >= 0x0100}
            lo = {k for k in codes - hi if k not in COMMON_LOW}
            lowband[cat] |= lo
            codes = hi
            if codes:
                disp = "实测 " + compress(codes) + "（注册表未登记）"
            elif lo:
                disp = "无按件码位（低带实测 " + compress(lo) + "）"
            else:
                disp = "无（仅用公共码）"
            if seg.startswith("无"):
                disp = seg
        codes_by_cat[cat] |= codes
        rows[cat].append({"name": name, "segment": disp,
                          "tags": ", ".join(c.get("function_tags") or []),
                          "type": c.get("type", "")})

    # 各带极大值（本目录）
    summary = {}
    for cat in CATS:
        bands = collections.defaultdict(set)
        for k in codes_by_cat[cat]:
            bands[bucket(k)].add(k)
        summary[cat] = {b: max(v, key=lambda x: int(x.split("_")[1], 16)) for b, v in bands.items()}

    # 码族合计（跨目录共用）
    fam_codes = {}
    for base in ("0001", "0002", "0003", "0004", "0005"):
        fam_codes[base] = set()
        for cat in CATS:
            if base in FAMILY[cat]:
                fam_codes[base] |= {c for c in codes_by_cat[cat] if c.startswith(base + "_")}

    def mv(codes, lo, hi):
        cand = [c for c in codes if lo <= int(c.split("_")[1], 16) < hi]
        return max(cand, key=lambda x: int(x.split("_")[1], 16)) if cand else None

    def inc(code):
        b, v = code.split("_")
        return f"`16#{b}_{int(v, 16) + 1:04X}`"

    def nxt(cat):
        """返回 (信息级下一可用, 故障级下一可用, 建议说明)"""
        if cat == "DL_Algo":
            band = summary[cat].get("1x")
            if band:
                b = int(band.split("_")[1], 16) >> 8
                base = band.split("_")[0]
                return (f"`16#{base}_{(b + 1) * 0x100 + 0x01:04X}`",
                        f"`16#{base}_{(b + 1) * 0x100 + 0x10:04X}`",
                        "（新带首码，故障子码沿用 +0x0F 约定）")
            return "—", "—", "无按件带"
        base = ("0001" if cat in ("DL_Base", "DL_MathData") else
                "0003" if cat == "DL_Device" else "0004" if cat == "DL_Motion" else "0005")
        fc = fam_codes[base]
        info = mv(fc, 0x0100, 0x0200)
        fault = mv(fc, 0x0200, 0x1000)
        tag = "（同族合计）" if base == "0001" else ""
        return (inc(info) if info else "—", inc(fault) if fault else "—", tag)

    # ---------- JSON ----------
    js = {cat: [{"name": r["name"], "segment": r["segment"], "tags": r["tags"]} for r in rows[cat]]
          for cat in CATS}
    os.makedirs(OUT_DIR, exist_ok=True)
    with open(os.path.join(OUT_DIR, "code_segment_ledger_r12.json"), "w", encoding="utf-8") as f:
        json.dump(js, f, ensure_ascii=False, indent=1)

    # ---------- MD ----------
    L = []
    A = L.append
    A("# R12 码位占用台账 / CODE SEGMENT LEDGER (R12)")
    A("")
    A("> **用途**：下一环节新组件落码前先查本表，按各节末尾「极大值摘要」顺延取号，杜绝多轮撞号返工。")
    A(f"> **生成日期**：2026-11-15 ｜ **数据基准**：`INDEX_REGISTRY.json`（{len(comps)} 条）+ 全库 `.st` 实测码位字面量 ｜ **生成脚本**：`_Staging_Raw/2026-11-15/gen_ledger_r12.py`（只读，不改库）")
    A("")
    A("**口径说明**")
    A("")
    A("- 码位段优先取注册表 `code_segment` 原文；注册表未登记的组件回落到 `.st` 内 `uErrorId` 字面量，前缀 `实测`，仅作占用参考、不代表已发布契约。")
    A("- 公共区不参与按件分配：`0000_xxxx`（无故障基准）、各码族 `xxxx_0000~00FF`（公共 / 预留区）、`FFFF_xxxx`（占位填充）。低带实测值单列在节末，不计入极大值。")
    A("- 号段带：`01xx` 信息级 / `02xx` 故障级 / `0Xxx` 特殊带 / `1x00` DL_Algo 按件算法带。")
    A("")
    A("## 0. 结论速览 / Next Available Slots")
    A("")
    A("| 目录 | 信息级已用至（本目录） | 故障级已用至（本目录） | 建议起号（信息 ／ 故障） | 码族 |")
    A("|---|---|---|---|---|")
    for cat in CATS:
        s = summary[cat]
        info = s.get("01")
        infos = f"`16#{info}`" if info else "—"
        cands = [s[b] for b in ("02", "03", "04", "05", "06", "07", "08", "09") if b in s]
        fault = max(cands, key=lambda x: int(x.split("_")[1], 16)) if cands else None
        if cat == "DL_Algo" and "1x" in s:
            fault = s["1x"]
        faults = f"`16#{fault}`" if fault else "—"
        n_info, n_fault, _ = nxt(cat)
        A(f"| `{cat}` | {infos} | {faults} | {n_info} ／ {n_fault} | {'+'.join(sorted(FAMILY[cat]))} |")
    A("")
    A("> 速览表左侧两列只给「本目录自身」极大值；右侧起号已按**码族合计**计算（`0001` / `0002` 跨目录共用），故 DL_Base 与 DL_MathData 的起号相同——取号时任选其一占位，另一方不得重复使用。")
    A(">")
    A("> DL_Algo 例外：算法件按「一件一带」独占 `Nx00` 带，带内 `01~06` 为信息级、`10` 起为故障级；共享区 `0002_01xx/02xx` 的历史占号（`0101`、`0102`、`0201`、`0301`…）实为早期算法件带码，不构成共享区耗尽。")
    A("")

    for cat in CATS:
        rs = rows[cat]
        A(f"## {cat}（{len(rs)} 件）")
        A("")
        A("| # | 组件名 | 码位段 | 标签 |")
        A("|---|---|---|---|")
        for i, r in enumerate(rs, 1):
            A(f"| {i} | `{r['name']}` | {r['segment']} | {r['tags']} |")
        A("")
        A(f"**{cat} 已占用号段极大值摘要**")
        A("")
        A("| 号段带 | 已用极大值 | 占用码数 | 标注构成 |")
        A("|---|---|---|---|")
        bands = collections.defaultdict(set)
        for k in codes_by_cat[cat]:
            bands[bucket(k)].add(k)
        label = {"00": "公共/预留带 `00xx`", "01": "信息级带 `01xx`", "02": "故障级带 `02xx`",
                 "1x": "算法按件带 `1x00`"}
        for b in sorted(bands):
            mx = max(bands[b], key=lambda x: int(x.split("_")[1], 16))
            kc = collections.Counter()
            for c2 in bands[b]:
                for kd in kinds_by_code.get(c2, {"实测"}):
                    kc[kd] += 1
            NAME = {"info": "信息级", "fault": "故障级", "aux": "兜底/其他", "实测": "实测无标注"}
            kd_txt = " / ".join(f"{NAME[k]}×{v}" for k, v in kc.items())
            A(f"| {label.get(b, '特殊带 `' + b + 'xx`')} | `16#{mx}` | {len(bands[b])} | {kd_txt} |")
        n_info, n_fault, tip = nxt(cat)
        A("")
        A(f"- **下一可用**：信息级 {n_info} 起；故障级 {n_fault} 起{tip}。")
        A(f"- 本目录合计按件占用 **{len(codes_by_cat[cat])}** 码（不含公共区）；{SHARED_NOTE[cat]}。")
        if lowband[cat]:
            A(f"- 低带 `0000~00FF` 公共/预留区实测占用 {len(lowband[cat])} 码：{compress(lowband[cat])}（历史件，不参与后续分配）。")
        A("")

    A("## 附：共享码族合计极大值（跨目录取码必查）")
    A("")
    A("| 码族 | 参与目录 | 信息带 `01xx` 极大值 | 故障带 `02xx` 极大值 | 特殊带极大值 |")
    A("|---|---|---|---|---|")
    for base, cats in [("0001", ["DL_Base", "DL_MathData"]), ("0002", ["DL_Base", "DL_MathData", "DL_Algo"])]:
        codes = set()
        for cat in cats:
            codes |= {c for c in codes_by_cat[cat] if c.startswith(base + "_")}
        b01 = [c for c in codes if int(c.split("_")[1], 16) < 0x0200]
        b02 = [c for c in codes if 0x0200 <= int(c.split("_")[1], 16) < 0x0300]
        bxx = [c for c in codes if int(c.split("_")[1], 16) >= 0x0300]
        f = lambda arr: ("`16#%s`" % max(arr, key=lambda x: int(x.split("_")[1], 16))) if arr else "—"
        A(f"| `16#{base}_xxxx` | {' + '.join(cats)} | {f(b01)} | {f(b02)} | {f(bxx)} |")
    A("")
    A("> `0002` 族的算法按件带（`1x00`）计入「特殊带」列；带内故障子码沿用 `+0x0F` 约定（如 `1F03` → 故障 `1F10`）。")
    A("")
    open(os.path.join(OUT_DIR, "CODE_SEGMENT_LEDGER_R12.md"), "w", encoding="utf-8").write("\n".join(L))

    print("已生成 CODE_SEGMENT_LEDGER_R12.md / code_segment_ledger_r12.json")
    for cat in CATS:
        print(f"{cat}: n={len(rows[cat])} bands={ {b: max(v, key=lambda x: int(x.split('_')[1],16)) for b,v in collections.defaultdict(set, {b: {k for k in codes_by_cat[cat] if bucket(k)==b} for b in {bucket(k) for k in codes_by_cat[cat]}}).items()} } codes={len(codes_by_cat[cat])}")


if __name__ == "__main__":
    main()
