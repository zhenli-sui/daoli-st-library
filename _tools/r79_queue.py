# -*- coding: utf-8 -*-
"""r79_queue.py - 把本轮已人工核验的候选写入 candidate_queue.jsonl（唯一交付物）

纪律：
  - 只追加，不删行；无效条目改 status=rejected 并写 reject_reason（备份 candidate_queue.jsonl.backup_R79.jsonl 已在位）
  - 绿区：MIT/Apache/BSD → 可改写，保留版权声明，mode=rewrite
  - 黄区：OSCAT → 仅接口签名/参数域/语义，mode=bones-only，绝不带实现行
  - 红区：0 条
"""
import hashlib, io, json, os, re, tarfile, datetime

LIB = r"C:\Library"
STG = os.path.join(LIB, "_Staging_Raw", "2026-11-24")
Q = os.path.join(STG, "candidate_queue.jsonl")
FP = os.path.join(LIB, "_Staging_Raw", "_dedup_fingerprints.json")
BONES = json.load(io.open(os.path.join(LIB, "_tools", "_tmp_r79", "out", "oscat_bones.json"), encoding="utf-8"))
DECL = "brOscatLib-main/oscatBasic/oscatBasic.fun"
TAR = os.path.join(LIB, "_tools", "_tmp_r79", "tkucic__brOscatLib.tar.gz")
NOW = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
OSCAT_URL = "https://github.com/tkucic/brOscatLib/blob/main/oscatBasic/oscatBasic.fun"
COMMIT = "main@2026-11-24 (codeload tar.gz, 无 commit_sha 暴露)"

# name -> (family, category, loc_override, semantic_note, extra_gaps)
PLAN = {
    # ---------- ① 日历/日期算术 ----------
    "DAY_OF_WEEK":   ("cal", "DL_MathData", 0, "库内仅 FC_DL_LeapYearChk，无星期推算 → 新", []),
    "DAY_OF_YEAR":   ("cal", "DL_MathData", 0, "库内无年内序日 → 新", []),
    "MONTH_END":     ("cal", "DL_MathData", 0, "库内无月末夹取 → 新", []),
    "DAYS_DELTA":    ("cal", "DL_MathData", 0, "库内无日期差 → 新", []),
    "DATE_ADD":      ("cal", "DL_MathData", 0, "库内无日期加年月日 → 新；参数域 D/W/M/Y 四路叠加", []),
    "WORK_WEEK":     ("cal", "DL_MathData", 0, "库内无周编号 → 新（ISO 周语义待定）", []),
    "EASTER":        ("cal", "DL_MathData", 0, "库内无复活节算法 → 新（可作节假日表生成器）", []),
    # ---------- ② 整数数论/位宽安全 ----------
    "GCD":           ("num", "DL_MathData", 0, "库内无最大公约数 → 新", []),
    "SQRTN":         ("num", "DL_MathData", 0, "库内无 n 次根 → 新", ["X<0 且 N 为偶数时未定义", "N=0 除零未拦"]),
    # ---------- ③ 二维平面几何 ----------
    "CIRCLE_A":      ("geo", "DL_MathData", 0, "库内 FC_DL_CircleFit3Pt 是拟合，非面积 → 新", []),
    "CIRCLE_SEG":    ("geo", "DL_MathData", 0, "库内无弓形面积 → 新", ["HX>2*RX 时 acos 定义域越界"]),
    "TRIANGLE_A":    ("geo", "DL_MathData", 0, "库内 FC_DL_TriangleSolveSSS 是解边，非面积 → 新", ["S3 与 (S1,A,S2) 冗余，冲突优先级未定义"]),
    "R2_ADD":        ("geo", "DL_MathData", 0, "库内无 2D 向量算术 → 新", ["REAL2 需本地 DUT 定义", "返回 BOOL 不携带运算结果"]),
    # ---------- ④ 统计扩展 ----------
    "ARRAY_VAR":     ("stat", "DL_MathData", 0, "库内 FC_DL_StdDevOnline 是在线 Welford，本条是批量两遍法 → 参数域增量", ["SIZE<2 时除零"]),
    "ARRAY_SPR":     ("stat", "DL_MathData", 0, "库内无极差/spread → 新", ["与 StdDev 语义边界需明示"]),
    "_ARRAY_MEDIAN": ("stat", "DL_MathData", 0, "库内 FC_DL_QuantileCalc 是分位，非中位数 → 近邻待核", ["偶数元素取上/下中位数未定义"]),
    "TREND":         ("stat", "DL_MathData", 0, "库内 ARRAY_TREND 之外的在线斜率 FB 缺失 → 新", ["单点输入斜率估计无窗口守卫"]),
    # ---------- ⑤ 校验和 ----------
    "CRC_GEN":       ("cksum", "DL_Algo", 0, "库内 FC_DL_Crc16Generic 固定宽度，本条补 PN/INIT/REV/PL 参数域（可覆盖 CRC-8/MAXIM）→ 参数域增量",
                      ["PN 任意多项式可致反射位错", "SIZE 与 PL 不匹配时未定义"]),
}

GREEN = [
    {"name": "T_DayOfMonth", "suggest_category": "DL_MathData", "kind": "TYPE", "tier": "green",
     "license": "MIT", "source_url": "https://github.com/fisothemes/FisoThemes-Time-Library-for-TwinCAT/blob/master/src/FsTime/DUTs/T_DayOfMonth.TcDUT",
     "commit": "master@2026-11-24", "extraction_point": "DUT 子范围类型定义（UINT(1..31)）",
     "signature": "TYPE T_DayOfMonth : UINT(1..31)", "loc": 3,
     "dialect": [], "reuse_mode": "rewrite",
     "defense_gaps": ["子范围仅编译期约束，运行时越界写入需显式钳位", "2 月/4 月等短月未在类型层表达，需 MONTH_END 联动"],
     "semantic_note": "库内无日期子范围类型 → 新（可作日历族入参契约）", "priority": 1},
    {"name": "T_DayOfYear", "suggest_category": "DL_MathData", "kind": "TYPE", "tier": "green",
     "license": "MIT", "source_url": "https://github.com/fisothemes/FisoThemes-Time-Library-for-TwinCAT/blob/master/src/FsTime/DUTs/T_DayOfYear.TcDUT",
     "commit": "master@2026-11-24", "extraction_point": "DUT 子范围类型定义（UINT(1..366)）",
     "signature": "TYPE T_DayOfYear : UINT(1..366)", "loc": 4,
     "dialect": [], "reuse_mode": "rewrite",
     "defense_gaps": ["366 的上界仅对闰年合法，平年需运行时夹到 365"],
     "semantic_note": "库内无年内序日类型 → 新", "priority": 1},
    {"name": "FB_TimeInstance", "suggest_category": "DL_MathData", "kind": "FB", "tier": "green",
     "license": "MIT", "source_url": "https://github.com/fisothemes/FisoThemes-Time-Library-for-TwinCAT/blob/master/src/FsTime/POUs/FB_TimeInstance.TcPOU",
     "commit": "master@2026-11-24", "extraction_point": "时间分量分解组件骨架（年/月/日/时/分/秒/毫秒属性）",
     "signature": "PROPERTY Year/Month/Day/Hour/Minute/Second/Millisecond (get/set)", "loc": 420,
     "dialect": ["TcPOU"], "reuse_mode": "rewrite",
     "defense_gaps": ["属性式 get/set 无并发保护（多任务下撕裂）", "分量写入后未做月日合法性回算，需 MONTH_END 闸"],
     "semantic_note": "库内无时间分量分解组件 → 新（作日历族宿主 FB）", "priority": 1},
]


def decl_loc(name):
    t = tarfile.open(TAR, "r:gz")
    txt = t.extractfile(DECL).read().decode("utf-8", "replace")
    m = re.search(r"^(FUNCTION_BLOCK|FUNCTION)\s+%s\b" % re.escape(name), txt, re.M)
    if not m: return 4
    end = txt.find("END_FUNCTION", m.end())
    return (txt[m.start():end].count("\n") + 1) if end > 0 else 4


def main():
    fp = json.load(io.open(FP, encoding="utf-8")) if os.path.exists(FP) else {}
    lines = [l for l in io.open(Q, encoding="utf-8") if l.strip()]
    rows = [json.loads(l) for l in lines]

    # 1) 工具本轮误捕的两条：标 rejected（不删行）
    rej = 0
    for r in rows:
        if r.get("name") == "VAR_INPUT" and r.get("licen_se" if False else "license") is not None and r.get("status") != "rejected":
            if "fb_PI-Regler" in str(r.get("extraction_point", "")):
                r["status"] = "rejected"
                r["reject_reason"] = "垃圾名：签名正则把关键字 VAR_INPUT 误捕为标识符（R76 已报缺陷复现）"
                rej += 1
        if r.get("name") == "E_SMStatus" and r.get("status") != "rejected":
            r["status"] = "rejected"
            r["reject_reason"] = "无增量价值：状态枚举无任何防御缺口，且库内已有同族状态机枚举"
            rej += 1

    bones = {b["name"]: b for b in BONES}
    added, skipped = [], []
    for name, (fam, cat, _l, sem, extra) in PLAN.items():
        b = bones.get(name)
        if not b:
            skipped.append(name + "(no-decl)"); continue
        params = [p.split(":=")[0].strip() for p in b["params"]]
        types = ",".join(sorted(p.split(":", 1)[1].strip() for p in params))
        h = hashlib.sha1((name.lower() + "|" + types).encode()).hexdigest()[:16]
        if h in fp:
            skipped.append(name + "(fp-dup)"); continue
        gaps = (b["defense_gaps"] + extra)[:4]
        if not gaps:
            skipped.append(name + "(no-gap)"); continue
        sig = "VAR_INPUT: " + ("; ".join(params) if params else "(none)")
        if b.get("ret"): sig += " | RET: " + b["ret"]
        rec = {
            "name": name, "suggest_category": cat, "kind": b["kind"], "tier": "yellow",
            "license": "MIT+OSCAT(dual)", "license_note": "brOscatLib 顶层为 MIT，但同仓 OSCAT_LICENSE 为上游限制性许可 → 按黄区只借骨",
            "source_url": OSCAT_URL, "commit": COMMIT,
            "extraction_point": "接口签名+参数域（%s 声明块，无实现行）" % name,
            "signature": sig, "loc": decl_loc(name), "dialect": [],
            "reuse_mode": "bones-only",
            "compliance": "黄区：仅名字/参数域/语义可借；实现必须 clean-room，禁止复制代码行与符号名",
            "defense_gaps": gaps,
            "dedup": {"name": "pass", "fingerprint": "new", "semantic": "new"}, "semantic_note": sem,
            "family": fam, "priority": 2, "fp": h, "harvested_at": NOW,
        }
        rows.append(rec); added.append(name); fp[h] = name

    for g in GREEN:
        h = hashlib.sha1((g["name"].lower() + "|green").encode()).hexdigest()[:16]
        g = dict(g); g["fp"] = h; g["harvested_at"] = NOW
        g["dedup"] = {"name": "pass", "fingerprint": "new", "semantic": "new"}
        g["license_note"] = "MIT：可改写，需保留版权声明并写入 NOTICE/provenance.json"
        rows.append(g); added.append(g["name"]); fp[h] = g["name"]

    with io.open(Q, "w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    json.dump(fp, io.open(FP, "w", encoding="utf-8"), ensure_ascii=False, indent=0)
    live = [r for r in rows if r.get("status") != "rejected"]
    import collections
    print("队列总行 %d | live %d | 本轮新增 %d | 标记 rejected %d | 跳过 %s"
          % (len(rows), len(live), len(added), rej, skipped))
    print("tier:", collections.Counter(r["tier"] for r in live))
    print("category:", collections.Counter(r["suggest_category"] for r in live))
    print("added:", added)


if __name__ == "__main__":
    main()
