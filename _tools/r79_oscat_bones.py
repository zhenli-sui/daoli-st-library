# -*- coding: utf-8 -*-
"""r79_oscat_bones.py - 从 oscatBasic.fun 声明块抽取「骨」（接口签名+参数域），零实现代码

黄区合规：本脚本只读 .fun（纯接口声明，无任何实现语句），产出仅含 name/返回类型/VAR_INPUT 参数域/
OSCAT 官方分类注释。不读取、不落盘任何函数体语句。
"""
import io, json, os, re, tarfile

HERE = os.path.dirname(os.path.abspath(__file__))
TAR = os.path.join(HERE, "_tmp_r79", "tkucic__brOscatLib.tar.gz")
DECL = "brOscatLib-main/oscatBasic/oscatBasic.fun"
OUT = os.path.join(HERE, "_tmp_r79", "out", "oscat_bones.json")

FAM = {
    "cal": ["DAY_OF_WEEK", "DAY_OF_YEAR", "DAYS_IN_MONTH", "DAYS_IN_YEAR", "LEAP_YEAR", "LEAP_DAY",
            "LEAP_OF_DATE", "MONTH_END", "MONTH_BEGIN", "WORK_WEEK", "CALENDAR_CALC", "DAYS_DELTA",
            "DATE_ADD", "EASTER", "YEAR_BEGIN", "YEAR_END", "JD2000"],
    "num": ["GCD", "FACT", "BIT_COUNT", "SQRTN", "POLYNOM_INT", "INT_TO_BCDC", "BCDC_TO_INT",
            "DEC_TO_DWORD", "RANGE_TO_WORD"],
    "geo": ["R2_ADD", "R2_ABS", "R2_MUL", "R2_SET", "CIRCLE_A", "CIRCLE_C", "CIRCLE_SEG",
            "ELLIPSE_A", "ELLIPSE_C", "TRIANGLE_A", "HYPOT"],
    "stat": ["ARRAY_VAR", "ARRAY_SDV", "ARRAY_MEDIAN", "ARRAY_AVG", "ARRAY_GAV", "ARRAY_HAV",
             "ARRAY_SPR", "ARRAY_TREND", "TREND", "IS_SORTED", "_ARRAY_SORT", "METER_STAT"],
    "cksum": ["CRC_GEN", "CHECK_PARITY", "PARITY", "BYTE_TO_GRAY", "CLEAN"],
}

# 按参数形态推导的「待验证缺口」（只依赖声明可见事实，不猜测实现）
HAZ = [
    (r"REFERENCE TO ARRAY\[0\.\.(\d+)\]", "数组入参上界 %s 由调用方保证，需加 SIZE<=上界 的边界闸"),
    (r"(?i)\bDIV\w*|\bD\b", "含除数入参，需除零闸"),
    (r"(?i)DATE\b|DT\b|TOD\b", "日期/时间入参无合法性校验，需校验月日范围与闰年"),
    (r"(?i):\s*(INT|UINT|WORD|SINT)\b", "返回窄整型，需校验中间量溢出与窄化钳位"),
    (r"(?i)SIZE\s*:\s*UINT", "SIZE 无 0 值处理，空数组需早退兜底"),
]


def parse(txt):
    """按 FUNCTION/FB 块切分，只保留声明区（到 END_FUNCTION 前的 VAR_INPUT/VAR/VAR CONSTANT 已足够）。"""
    blocks = {}
    for m in re.finditer(r"^(FUNCTION_BLOCK|FUNCTION)\s+([A-Za-z_]\w*)\s*(?::\s*([A-Za-z_][\w.\[\]]*))?([^\n]*)$",
                         txt, re.M):
        kind, name, ret, tail = m.group(1), m.group(2), m.group(3), m.group(4)
        end = txt.find("END_FUNCTION", m.end())
        body = txt[m.end(): end if end > 0 else m.end() + 3000]
        vi = re.search(r"VAR_INPUT(.*?)END_VAR", body, re.S)
        params = []
        if vi:
            for line in vi.group(1).split("\n"):
                mm = re.match(r"\s*([A-Za-z_]\w*)\s*(?:,\s*\w+\s*)*:\s*(.+?)\s*;", line)
                if mm:
                    ty = re.sub(r"\s+", " ", mm.group(2)).strip()
                    params.append("%s:%s" % (mm.group(1), ty))
        cat = re.search(r"\(\*([^*]+?)\*\)", tail or "")
        blocks[name.upper()] = {"kind": "FB" if kind == "FUNCTION_BLOCK" else "FC",
                                "ret": ret, "params": params,
                                "cat": (cat.group(1).strip() if cat else "")}
    return blocks


def gaps_for(params, ret):
    g = []
    joined = ", ".join(params) + (" : " + str(ret) if ret else "")
    for pat, msg in HAZ:
        mm = re.search(pat, joined)
        if mm:
            g.append(msg % mm.group(1) if "%s" in msg else msg)
    if not g:
        g.append("参数域无显式钳位，需人工判定边界向量")
    if not params:
        g.append("无 VAR_INPUT 声明（依赖 REFERENCE/全局），clean-room 时需重定义调用契约")
    return g[:4]


def main():
    t = tarfile.open(TAR, "r:gz")
    txt = t.extractfile(DECL).read().decode("utf-8", "replace")
    blocks = parse(txt)
    out = []
    for fam, names in FAM.items():
        for n in names:
            b = blocks.get(n.upper())
            if not b:
                print("  MISS", fam, n); continue
            out.append({"name": n, "family": fam, "kind": b["kind"], "ret": b["ret"],
                        "params": b["params"], "oscat_cat": b["cat"],
                        "defense_gaps": gaps_for(b["params"], b["ret"])})
    json.dump(out, io.open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("parsed blocks:", len(blocks), "| emitted:", len(out), "->", OUT)
    for r in out:
        print("  [%s] %-18s %-3s ret=%-8s %s" % (r["family"], r["name"], r["kind"], r["ret"],
                                                 " | ".join(r["params"])[:90]))


if __name__ == "__main__":
    main()
