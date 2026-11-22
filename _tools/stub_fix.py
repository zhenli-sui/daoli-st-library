#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""stub_fix.py —— iec_std_stub.st 自愈式补全工具

背景：
    RuSTy 不内建 IEC 标准件声明，L2 闸靠 iec_std_stub.st 的 {external} 桩兜底。
    桩缺声明时，合法代码会被误判 E048/E049（Could not resolve reference），
    污染 L2 通过率统计，让真实缺陷被淹没。

做法（不盲目堆砌，按需精准补齐）：
    1. 扫全库 DL_*/*.st，提取所有 `XXX_TO_YYY` 形态的调用名；
    2. 剔除自研枚举误匹配（以 DL_ 开头者，如 DL_CES_TO_FOLD）；
    3. 剔除源码中已自行定义的同名 FUNCTION（避免重复定义）；
    4. 与桩现有 {external} 声明求差 → 缺失集；
    5. 按 IEC 61131-3 标准签名生成声明，追加到桩的「自动补全区」。

用法：
    python stub_fix.py --dry-run      # 只报告缺失，不写文件
    python stub_fix.py                # 补齐并写回
    python stub_fix.py --check        # 校验桩本身能否被 plc.exe 解析

纪律：
    - 只声明 IEC 61131-3 标准规定的显式转换（ANY_ELEMENTARY 间），不发明函数。
    - 不覆盖手工区，所有自动生成内容集中在 AUTO-GENERATED 标记块内。
    - 每次运行先重建该块（幂等），不做累加式追加，避免重复。
"""
import glob
import os
import re
import subprocess
import sys

LIB = r"C:\Library"
STUB = os.path.join(LIB, "_tools", "rusty", "iec_std_stub.st")
RUSTY = os.path.join(LIB, "_tools", "rusty", "plc.exe")

BEGIN = "(* ===== BEGIN AUTO-GENERATED CONVERSIONS  (stub_fix.py 维护，勿手改) ===== *)"
END = "(* ===== END AUTO-GENERATED CONVERSIONS ===== *)"

# IEC 61131-3 第3版基本类型；DTL 为 CODESYS 扩展（源码已使用，按需声明）
BITSTR = ["BYTE", "WORD", "DWORD", "LWORD"]
INT_S = ["SINT", "INT", "DINT", "LINT"]
INT_U = ["USINT", "UINT", "UDINT", "ULINT"]
FLOAT = ["REAL", "LREAL"]
TIME_T = ["TIME", "DATE", "TOD", "DT", "DTL"]
STR_T = ["STRING"]
ALL_NUM = BITSTR + INT_S + INT_U + FLOAT

# 允许的转换对（含标准矩阵 + 位串↔整型 + 时间↔整型 + 数值↔STRING）
def _allowed_pairs():
    pairs = set()
    for s in ALL_NUM:
        for d in ALL_NUM:
            if s != d:
                pairs.add((s, d))
    # 时间族 ↔ 整型/浮点（按 IEC 语义，TIME 等以毫秒存于 DINT/UDINT 等）
    for s in TIME_T:
        for d in ["DINT", "UDINT", "LINT", "INT", "REAL", "LREAL", "TIME", "TOD", "DATE", "DT", "DTL"]:
            if s != d:
                pairs.add((s, d))
    for s in ["DINT", "UDINT", "LINT", "INT", "REAL", "LREAL"]:
        for d in ["TIME", "DATE", "TOD", "DT"]:
            pairs.add((s, d))
    # STRING 族
    for d in ALL_NUM + TIME_T:
        pairs.add(("STRING", d))
        pairs.add((d, "STRING"))
    return pairs


ALLOWED = _allowed_pairs()

# 非转换函数的标准 FB（源码用到但桩缺）
STD_FBS = {
    "SR": ("VAR_INPUT S1 : BOOL; R : BOOL; END_VAR", "VAR_OUTPUT Q1 : BOOL; END_VAR"),
    "RS": ("VAR_INPUT S : BOOL; R1 : BOOL; END_VAR", "VAR_OUTPUT Q1 : BOOL; END_VAR"),
    "RTO": ("VAR_INPUT IN : BOOL; PT : TIME; R : BOOL; END_VAR",
            "VAR_OUTPUT Q : BOOL; ET : TIME; END_VAR"),
    "SEMA": ("VAR_INPUT CLAIM : BOOL; RELEASE : BOOL; END_VAR",
             "VAR_OUTPUT BUSY : BOOL; END_VAR"),
}


def collect_used():
    used = set()
    for f in glob.glob(os.path.join(LIB, "DL_*", "*.st")):
        try:
            txt = open(f, encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        used |= set(re.findall(r"\b([A-Z][A-Z0-9_]*_TO_[A-Z][A-Z0-9_]*)\b", txt))
    return used


def collect_self_defined():
    """源码里自行定义的 FUNCTION 名（不得在桩里重复声明）。"""
    defined = set()
    for f in glob.glob(os.path.join(LIB, "DL_*", "*.st")):
        try:
            txt = open(f, encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        defined |= set(re.findall(r"^\s*FUNCTION\s+([A-Za-z_][A-Za-z0-9_]*)", txt, re.M))
        defined |= set(re.findall(r"^\s*FUNCTION_BLOCK\s+([A-Za-z_][A-Za-z0-9_]*)", txt, re.M))
    return defined


def stub_declared(text):
    return set(re.findall(r"^\s*(?:FUNCTION|FUNCTION_BLOCK)\s+([A-Za-z_][A-Za-z0-9_]*)",
                          text, re.M))


def gen_conversion(name):
    """XXX_TO_YYY → 声明体；非法/未知类型返回 None。"""
    m = re.match(r"^([A-Z0-9]+)_TO_([A-Z0-9]+)$", name)
    if not m:
        return None
    s, d = m.group(1), m.group(2)
    if (s, d) not in ALLOWED:
        return None
    ret = "STRING" if d == "STRING" else d
    arg = "STRING" if s == "STRING" else s
    return ("{external}\nFUNCTION %s : %s\nVAR_INPUT IN : %s; END_VAR\nEND_FUNCTION\n"
            % (name, ret, arg))


def gen_fb(name):
    spec = STD_FBS.get(name)
    if not spec:
        return None
    vin, vout = spec
    return ("{external}\nFUNCTION_BLOCK %s\n%s\n%s\nEND_FUNCTION_BLOCK\n" % (name, vin, vout))


def build_block(missing, full=False):
    chunks = [BEGIN, "(* 由 _tools/stub_fix.py 自动生成，覆盖全部 IEC 61131-3 标准转换。 *)", ""]
    names = set(missing)
    if full:
        # 完整标准矩阵：ALL_NUM 两两互转 + 时间族 + STRING 族
        for s, d in sorted(ALLOWED):
            names.add("%s_TO_%s" % (s, d))
    n = 0
    for name in sorted(names):
        body = gen_conversion(name) or gen_fb(name)
        if body:
            chunks.append(body)
            n += 1
    chunks.append(END)
    return "\n".join(chunks), n


def main():
    dry = "--dry-run" in sys.argv
    if not os.path.exists(STUB):
        print("桩文件不存在:", STUB)
        return 2
    text = open(STUB, encoding="utf-8", errors="ignore").read()

    # 剥离旧自动块，回到手工区
    manual = re.sub(re.escape(BEGIN) + r".*?" + re.escape(END), "", text, flags=re.S).rstrip() + "\n"

    used = collect_used()
    defined = collect_self_defined()
    declared = stub_declared(manual)

    # 候选：源码用到 - 自研命名 - 源码自定义 - 桩已声明
    cand = {n for n in used
            if not n.startswith("DL_") and n not in defined and n not in declared}
    # 加上标准 FB 缺口
    for fb in STD_FBS:
        if fb not in declared and fb not in defined:
            cand.add(fb)

    full = "--full" in sys.argv
    block, n = build_block(cand, full=full)
    skipped = sorted(c for c in cand if not (gen_conversion(c) or gen_fb(c)))

    print("源码用到 %d | 桩手工区已声明 %d | 待补 %d | 可生成 %d | 跳过(非标准) %d"
          % (len(used), len(declared), len(cand), n, len(skipped)))
    if skipped:
        print("  跳过清单（不属于 IEC 标准转换，需人工确认）:", ", ".join(skipped[:12]),
              "..." if len(skipped) > 12 else "")

    if dry:
        print("\n--- 将追加的声明（前 12 条预览）---")
        preview = [l for l in block.split("\n") if l.startswith("FUNCTION")]
        print("\n".join(preview[:12]))
        return 0

    new_text = manual + "\n" + block
    open(STUB, "w", encoding="utf-8", newline="\n").write(new_text)
    print("已写入", STUB, "（新增声明 %d 条）" % n)

    # 自校验 + 自愈：RuSTy 内建了一批转换函数，重复声明会报
    # "xxxx: Duplicate symbol"。逐轮剔除内建项后重生成，最多 6 轮。
    builtin = set()
    for rnd in range(6):
        p = subprocess.run([RUSTY, "--check", STUB], capture_output=True, text=True,
                           encoding="utf-8", errors="ignore", timeout=300)
        if p.returncode == 0:
            print("桩自校验通过（plc.exe --check 无错）")
            if builtin:
                print("  已剔除编译器内建声明 %d 个: %s"
                      % (len(builtin), ", ".join(sorted(builtin)[:10])
                         + ("..." if len(builtin) > 10 else "")))
            return 0
        msg = (p.stdout or "") + (p.stderr or "")
        dup = set(m.upper() for m in re.findall(r"([A-Za-z_][A-Za-z0-9_]*): Duplicate symbol", msg))
        if not dup:
            print("\n⚠ 桩自校验失败且非 Duplicate 类，需人工检查：")
            for line in msg.split("\n"):
                if "error" in line.lower():
                    print("  ", line.strip()[:140])
            return 1
        builtin |= dup
        # 用剔除后的集合重建
        names = {c for c in cand if c not in builtin}
        if full:
            names = {"%s_TO_%s" % (s, d) for s, d in ALLOWED if ("%s_TO_%s" % (s, d)) not in builtin}
        block2, n2 = build_block(names, full=False)
        new_text = manual + "\n" + block2
        open(STUB, "w", encoding="utf-8", newline="\n").write(new_text)
        print("  第 %d 轮：剔除内建 %d 个，重生成 %d 条声明" % (rnd + 1, len(dup), n2))
    print("⚠ 多轮自愈仍未通过，请人工检查桩文件")
    return 1


if __name__ == "__main__":
    sys.exit(main())
