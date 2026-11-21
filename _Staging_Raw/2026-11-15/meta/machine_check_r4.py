# -*- coding: utf-8 -*-
"""Round 04 Phase 3 机检：6 个 DL_Algo 组件红线与机检口径检查"""
import io, os, re, sys, json

ST_DIR = r"C:\Library\DL_Algo"
FILES = [
    "FB_DL_PidController.st",
    "FB_DL_CascadePid.st",
    "FB_DL_SplitRangeControl.st",
    "FB_DL_FeedforwardComp.st",
    "FB_DL_SmithPredictor.st",
    "FB_DL_RateLimiter.st",
]

FORBIDDEN = ["GVL", "VAR_EXTERNAL", "%I", "%Q", "%M", "POINTER TO", "REFERENCE TO", "__SYSTEM"]
PLACEHOLDERS = ["TODO", "FIXME", "待补", "待完善", "// 略", "// 同上", "..."]

DECL_START = re.compile(r"^\s*(VAR_INPUT|VAR_OUTPUT|VAR_IN_OUT|VAR|VAR CONSTANT|TYPE)\b")
DECL_END = re.compile(r"^\s*(END_VAR|END_TYPE)\b")

def check_file(path):
    results = []
    with io.open(path, "r", encoding="utf-8") as fh:
        lines = fh.read().splitlines()
    n = len(lines)

    # 1 forbidden tokens (whole text incl comments)
    for tok in FORBIDDEN:
        cnt = sum(l.count(tok) for l in lines)
        results.append(("FORBIDDEN:%s" % tok, cnt == 0, cnt))

    # 2 placeholders
    for tok in PLACEHOLDERS:
        cnt = sum(l.count(tok) for l in lines)
        results.append(("PLACEHOLDER:%s" % tok, cnt == 0, cnt))

    # 3 declaration-line comment coverage
    in_decl = False
    total_decl, missing = 0, []
    for i, l in enumerate(lines, 1):
        if DECL_START.match(l):
            in_decl = True
            continue
        if DECL_END.match(l):
            in_decl = False
            continue
        if in_decl:
            stripped = l.strip()
            if (not stripped) or stripped in ("(", ")") or stripped.startswith("(*"):
                continue
            if (":" in stripped or ":=" in stripped) and (";" in stripped or "," in stripped):
                total_decl += 1
                if "//" not in stripped:
                    missing.append(i)
    results.append(("DECL_COMMENT_COVERAGE", len(missing) == 0, missing if missing else "100%% (%d lines)" % total_decl))

    # 4 terminator
    last_nonempty = ""
    for l in reversed(lines):
        if l.strip():
            last_nonempty = l.strip()
            break
    ok_term = last_nonempty in ("END_FUNCTION_BLOCK", "END_FUNCTION")
    results.append(("END_TERMINATOR", ok_term, last_nonempty))

    # 5 line count
    ok_lines = 200 <= n <= 340
    results.append(("LINE_COUNT", ok_lines, n))

    # 6 CASE has ELSE
    n_case = sum(1 for l in lines if re.search(r"\bCASE\s+\w+", l))
    n_else = sum(1 for l in lines if l.strip() == "ELSE")
    results.append(("CASE_HAS_ELSE", n_case >= 1 and n_else >= n_case, "case=%d else=%d" % (n_case, n_else)))

    return results

def main():
    all_pass = True
    for f in FILES:
        p = os.path.join(ST_DIR, f)
        if not os.path.exists(p):
            print("FAIL %-28s 文件不存在" % f)
            all_pass = False
            continue
        results = check_file(p)
        fails = [r for r in results if not r[1]]
        status = "PASS" if not fails else "FAIL"
        if fails:
            all_pass = False
        print("%s %-28s" % (status, f))
        for name, ok, detail in results:
            if not ok:
                print("     - %s : %s" % (name, detail))
    print("=" * 50)
    print("总体结论:", "ALL PASS" if all_pass else "HAS FAIL")

if __name__ == "__main__":
    main()
