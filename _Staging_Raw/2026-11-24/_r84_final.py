# -*- coding: utf-8 -*-
"""R84 终选：按名精确取块 → 块级 loc / 签名 / 缺口 → 生成入队行"""
import hashlib, io, json, os, re, tarfile, urllib.request

UA = {"User-Agent": "daoli-oss-hunter/1.0"}
LIB = r"C:\Library"
STG = os.path.join(LIB, "_Staging_Raw", "2026-11-24")

PICK = [
    # (repo, license, family, 文件路径片段, 块名, kind, 说明)
    ("mutito/PV-RTPP", "MIT", "A", "RTPP_CALC/FB_RTPP.xml", "FB_RTPP", "FB",
     "光伏屋顶电站性能比(RTPP)计算：辐照/温度/发电量 → PR，含传感器均值与效率折算"),
    ("mutito/PV-RTPP", "MIT", "A", "RTPP_CALC/FB_RTPP_CALC.xml", "FB_RTPP_CALC", "FB",
     "RTPP 数值折算层：多路传感器工程量与实际功率对齐"),
    ("mutito/PV-RTPP", "MIT", "A", "RTPP_CALC/RTPP_REG.xml", "RTPP_REG", "TYPE",
     "RTPP 寄存器/遥测结构体：PV 电站量测点定义（可作为 DUT 模板骨）"),
    ("Beckhoff-USA-Community/PackML_PLC_Example", "MIT", "B", "EquipmentModules/FB_Unwind.TcPOU", "FB_Unwind", "FB",
     "VFFS 制袋机放卷设备模块：PackML 相序 + 膜卷直径/张力 + 换卷报警 + 配方"),
    ("Beckhoff-USA-Community/PackML_PLC_Example", "MIT", "B", "EquipmentModules/FB_PullWheel.TcPOU", "FB_PullWheel", "FB",
     "牵引轮（拉膜）模块：速度/张力设定与相序管理，薄膜线速度闭环骨架"),
    ("Beckhoff-USA-Community/PackML_PLC_Example", "MIT", "B", "EquipmentModules/FB_Sealer.TcPOU", "FB_Sealer", "FB",
     "立式封口模块：封刀温度/停留时间/压力三量协同与 PackML 相序"),
    ("Beckhoff-USA-Community/PackML_PLC_Example", "MIT", "B", "DUTs/Recipe/ST_UnwindRecipe.TcDUT", "ST_UnwindRecipe", "TYPE",
     "放卷配方结构体：膜卷参数与张力设定域（配方 DUT 模板）"),
    ("Beckhoff-USA-Community/PackML_PLC_Example", "MIT", "B", "DUTs/Recipe/ST_PullWheelsRecipe.TcDUT", "ST_PullWheelsRecipe", "TYPE",
     "牵引轮配方结构体：轮径/速比参数域"),
    ("Inxton/tcopen-app-templates", "MIT", "E", "OscilatingFeeder/TcoOscilatingConveyorFeeder.TcPOU", "TcoOscilatingConveyorFeeder", "FB",
     "摆动式给料输送（泡罩线上料）：启停/节拍/堵料检测与工位互锁"),
]

SIG = re.compile(r"^\s*(FUNCTION_BLOCK|FUNCTION|INTERFACE|TYPE|CLASS)\s+([A-Za-z_]\w*)", re.I | re.M)
NEXT = re.compile(r"^\s*(FUNCTION_BLOCK|FUNCTION|INTERFACE|TYPE|CLASS)\s+[A-Za-z_]", re.I | re.M)
VARBLK = re.compile(r"VAR(_INPUT|_OUTPUT|_IN_OUT)?\b(.*?)END_VAR", re.I | re.S)


def unwrap(txt):
    if "<![CDATA[" not in txt:
        return txt
    parts = []
    for m in re.finditer(r"<!\[CDATA\[(.*?)\]\]>", txt, re.S):
        b = m.group(1)
        for a, c in (("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&"), ("&quot;", '"'), ("&apos;", "'")):
            b = b.replace(a, c)
        parts.append(b)
    return "\n".join(parts)


def vars_of(text):
    ins, outs, inouts = [], [], []
    for m in VARBLK.finditer(text):
        kind = (m.group(1) or "").upper()
        tgt = ins if kind in ("", "_INPUT") else (outs if kind == "_OUTPUT" else inouts)
        for line in m.group(2).split("\n"):
            mm = re.match(r"\s*([A-Za-z_]\w*)\s*:\s*([A-Za-z_][\w\.\[\]\.]*)\s*(?::=.*)?[;:]", line)
            if mm:
                tgt.append("%s:%s" % (mm.group(1), mm.group(2)))
    return ins, outs, inouts


DEFECT = [
    (r"/\s*[A-Za-z_]\w*\s*(?:;|,|\))", "存在裸除法，需检查除子闸"),
    (r"\bREAL_TO_INT\b|\bTRUNC\b|\bLREAL_TO_INT\b", "存在浮点转整，需检查越界钳位"),
    (r"\bWHILE\b", "存在 WHILE，需检查守卫计数"),
    (r"%[IQM]", "含物理地址直接寻址，移植时需抽象"),
    (r"__SYSTEM|SysFile|\bTc2_|\bTc3_|System\.|PlcApp", "含平台方言依赖，clean-room 时需剥离"),
    (r"\bTON\b|\bTOF\b|\bR_TRIG\b", "依赖平台定时器/边沿块，需映射到 IEC 标准定时器"),
]


def gaps(text):
    g = [m for p, m in DEFECT if re.search(p, text)]
    if re.search(r"\bCASE\b", text, re.I) and not re.search(r"(?<![A-Za-z])ELSE(?![A-Za-z])", text):
        g.append("CASE 状态机无 ELSE 兜底（非法相号无默认分支）")
    if re.search(r"ARRAY\[", text) and re.search(r"\[[A-Za-z_]\w*\]", text):
        g.append("数组下标为变量，需检查越界钳位")
    return g[:5] or ["未见明显防御缺口，需人工判定增量价值"]


def dialect(text):
    d = set()
    for p, t in [(r"__SYSTEM", "__SYSTEM"), (r"SysFile", "SysFile"), (r"\bTC_|\bTc2_|\bTc3_", "TC_"),
                 (r"\bSystem\.", "System."), (r"%[IQM]", "%I/%Q"), (r"^\s*METHOD\b", "OOP-METHOD"),
                 (r"\bINTERFACE\b", "INTERFACE"), (r"\bEXTENDS\b", "EXTENDS")]:
        if re.search(p, text, re.M):
            d.add(t)
    return sorted(d)


def norm_base(n):
    return re.sub(r"^(fb_|fc_|i_|st_|e_|tc_|mc_|smc_|dl_|tco|plb|pls|plr|cu)", "", n.lower())


cache = {}
rows = []
for repo, lic, fam, frag, blk, kind, desc in PICK:
    if repo not in cache:
        raw = urllib.request.urlopen(urllib.request.Request(
            "https://codeload.github.com/%s/tar.gz/HEAD" % repo, headers=UA), timeout=150).read()
        cache[repo] = tarfile.open(fileobj=io.BytesIO(raw), mode="r:gz")
    tf = cache[repo]
    target = None
    for m in tf.getmembers():
        if m.isfile() and frag.lower() in m.name.lower():
            target = m
            break
    if not target:
        print("MISS", blk); continue
    txt = unwrap(tf.extractfile(target).read().decode("utf-8", "replace"))
    # 定位块起点与其后第一个顶层块起点
    start = None
    for s in SIG.finditer(txt):
        if s.group(2) == blk:
            start = s.start(); break
    if start is None:
        print("BLOCK-NOT-FOUND", blk); continue
    nxt = len(txt)
    for s in NEXT.finditer(txt, start + 10):
        nxt = s.start(); break
    body = txt[start:nxt]
    ins, outs, inouts = vars_of(body)
    fp = hashlib.sha1((norm_base(blk) + "|" + ",".join(sorted(i.split(":")[1] for i in ins))).encode()).hexdigest()[:16]
    rows.append({
        "name": blk,
        "suggest_category": "DL_Process",
        "kind": kind,
        "tier": "green",
        "license": lic,
        "source_url": "https://github.com/%s/blob/HEAD/%s" % (repo, target.name.split("/", 1)[1]),
        "commit": "HEAD(2026-11-24 codeload)",
        "extraction_point": "%s — %s" % (blk, frag),
        "signature": ("VAR_INPUT: " + ", ".join(ins[:12]) if ins else "VAR_INPUT: (无)") +
                     (" || VAR_IN_OUT: " + ", ".join(inouts[:6]) if inouts else "") +
                     (" || VAR_OUTPUT: " + ", ".join(outs[:8]) if outs else ""),
        "loc": body.count("\n") + 1,
        "dialect": dialect(body),
        "defense_gaps": gaps(body),
        "dedup": {"name": "pass", "fingerprint": "new", "semantic": "new"},
        "priority": 1,
        "family": fam,
        "fp": fp,
        "note": desc,
    })
    print("%-32s %-6s loc=%-5d in=%-2d out=%-2d gaps=%d" % (blk, fam, body.count("\n") + 1, len(ins), len(outs), len(gaps(body))))

json.dump(rows, open(os.path.join(STG, "_r84_final.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("FINAL rows:", len(rows))
