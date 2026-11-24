#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""reorder_methods.py —— 把 METHOD 块重排到声明区之后（IEC 61131-3 正确位序）

问题（2026-11-23 最小实验判定）:
    本库 45 个 FB 把 METHOD ... END_METHOD 写在**实现体之后**：

        FUNCTION_BLOCK FB_X
        VAR ... END_VAR
        x := x + 1;            ← 实现体
        METHOD Foo : INT       ← 位置错误
        ...
        END_METHOD
        END_FUNCTION_BLOCK

    IEC 61131-3 第3版 function_block_type_declaration 的位序为
    「变量声明 → 方法声明 → 代码体」，CODESYS 亦以此为准。
    RuSTy 严格校验：T1 形态报 E007 Unexpected token expected expression
    but found METHOD；T2 形态（方法在声明区之后）直接通过。

    本工具把每个 METHOD 块整体搬到「最后一个顶层声明的 END_VAR 之后」，
    属于纯位置调整，不改任何一行语义内容。

安全设计:
    - 只在 FUNCTION_BLOCK 作用域内、嵌套深度 0 处收集 METHOD 块；
      METHOD 内部的 VAR 块与嵌套 METHOD 不会被误判。
    - 顶层声明区 = 紧随 FB 头部的 VAR/VAR_INPUT/VAR_OUTPUT/VAR_IN_OUT/VAR_STAT 块；
      METHOD 内部的 VAR 不算。
    - 自动备份到 _archive/reorder_methods_<ts>/。
    - --dry-run 只报告不写盘。

用法:
    python reorder_methods.py --dry-run
    python reorder_methods.py
    python reorder_methods.py --files a.st b.st
"""
import glob
import os
import re
import shutil
import sys
import datetime

LIB = r"C:\Library"

FB_START = re.compile(r"^\s*FUNCTION_BLOCK\b", re.I)
FB_END = re.compile(r"^\s*END_FUNCTION_BLOCK\b", re.I)
VAR_START = re.compile(r"^\s*(VAR(?:_INPUT|_OUTPUT|_IN_OUT|_STAT|_TEMP)?)\s*$", re.I)
VAR_END = re.compile(r"^\s*END_VAR\b", re.I)
METHOD_START = re.compile(r"^\s*METHOD\s+[A-Za-z_]", re.I)
METHOD_END = re.compile(r"^\s*END_METHOD\b", re.I)


def reorder(lines):
    """返回 (新行列表, 是否改动, 搬移的 METHOD 数)。"""
    out = list(lines)
    n_moved = 0

    # 定位所有 FB 段（本库单文件单 FB，仍按通用处理）
    i = 0
    while i < len(out):
        if not FB_START.match(out[i]):
            i += 1
            continue
        fb_start = i
        # 找 FB 结束
        j = i + 1
        while j < len(out) and not FB_END.match(out[j]):
            j += 1
        if j >= len(out):
            break
        fb_end = j

        body = out[fb_start + 1:fb_end]
        methods = []          # [(块行列表)]
        kept = []
        k = 0
        last_top_decl_end = -1   # kept 中的索引
        in_method = False
        cur = []
        in_var = 0
        while k < len(body):
            ln = body[k]
            if in_method:
                cur.append(ln)
                if METHOD_END.match(ln):
                    methods.append(cur)
                    cur = []
                    in_method = False
                k += 1
                continue
            if METHOD_START.match(ln):
                in_method = True
                cur = [ln]
                k += 1
                continue
            if VAR_START.match(ln):
                in_var += 1
                kept.append(ln)
                k += 1
                continue
            if VAR_END.match(ln):
                in_var = max(0, in_var - 1)
                kept.append(ln)
                if in_var == 0:
                    last_top_decl_end = len(kept) - 1
                k += 1
                continue
            kept.append(ln)
            k += 1
        if cur:  # 未闭合的 METHOD 原样保留在尾部，交由其他工具处理
            kept.extend(cur)

        if not methods:
            i = fb_end + 1
            continue

        # 插到最后一个顶层声明的 END_VAR 之后；若没有声明区，插到 FB 头部之后
        insert_at = (last_top_decl_end + 1) if last_top_decl_end >= 0 else 0
        block = []
        for blk in methods:
            block.append("")
            block.extend(blk)
        new_body = kept[:insert_at] + block + kept[insert_at:]

        # 仅当顺序真的变化才计为改动
        if new_body != body:
            n_moved += sum(1 for _ in methods)
            out = out[:fb_start + 1] + new_body + out[fb_end:]
            fb_end = fb_start + 1 + len(new_body)
        i = fb_end + 1

    return out, n_moved > 0, n_moved


def main():
    dry = "--dry-run" in sys.argv
    args = sys.argv[1:]
    explicit = []
    if "--files" in args:
        k = args.index("--files")
        explicit = [a for a in args[k + 1:] if not a.startswith("--")]

    files = explicit or [f for f in sorted(glob.glob(os.path.join(LIB, "DL_*", "*.st")))
                         if not f.endswith((".bak", ".bak_gate"))]
    ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    bak = os.path.join(LIB, "_archive", "reorder_methods_" + ts)

    changed, total = [], 0
    for fp in files:
        try:
            text = open(fp, encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        if "METHOD" not in text:
            continue
        lines = text.split("\n")
        new_lines, did, n = reorder(lines)
        if did:
            changed.append((fp, n))
            total += n
            if not dry:
                os.makedirs(bak, exist_ok=True)
                shutil.copy2(fp, os.path.join(bak, os.path.basename(fp)))
                open(fp, "w", encoding="utf-8", newline="\n").write("\n".join(new_lines))

    print(("【预览】" if dry else "【已执行】") +
          " 重排文件 %d 个，搬移 METHOD 块 %d 个" % (len(changed), total))
    for fp, n in changed[:15]:
        print("  %-44s %d 个" % (os.path.basename(fp), n))
    if len(changed) > 15:
        print("  ...（共 %d 文件）" % len(changed))
    if not dry and changed:
        print("备份:", bak)
    return 0


if __name__ == "__main__":
    sys.exit(main())
