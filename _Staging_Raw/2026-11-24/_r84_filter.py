# -*- coding: utf-8 -*-
"""R84 后处理：垃圾名过滤 + 语义邻件（registry token 比对）+ 族别按路径订正 + 质量闸"""
import json, os, re, collections

LIB = r"C:\Library"
STG = os.path.join(LIB, "_Staging_Raw", "2026-11-24")
d = json.load(open(os.path.join(STG, "_r84_build.json"), encoding="utf-8"))
reg = json.load(open(os.path.join(LIB, "INDEX_REGISTRY.json"), encoding="utf-8"))

ACCESS = {"PUBLIC", "PRIVATE", "PROTECTED", "INTERNAL", "STATIC", "ABSTRACT", "OVERRIDE", "FINAL",
          "EXTENDS", "IMPLEMENTS", "METHOD", "PROPERTY", "ACTION", "TRANSITION"}
GENERIC_PREFIX = ("initialize_", "init_", "raise", "cyclic", "restore", "save", "on_", "do_", "get_", "set_")

STOP = {"fb", "fc", "dl", "st", "e", "i", "tc", "mc", "smc", "tco", "plb", "pls", "plr", "cu", "the", "and"}


def toks(s):
    s = re.sub(r"([a-z])([A-Z])", r"\1_\2", s)
    return [t for t in re.split(r"[_\W]+", s.lower()) if t and t not in STOP]


reg_tok = collections.defaultdict(set)   # token -> set(names)
for c in reg["components"]:
    for t in toks(c["name"]):
        reg_tok[t].add(c["name"])

kept, dropped = [], []
for b in d["build"]:
    n = b["name"]
    why = None
    if n.upper() in ACCESS: why = "access-modifier"
    elif b["kind"] == "METH": why = "method-not-block"
    elif n.lower().startswith(GENERIC_PREFIX): why = "generic-helper"
    elif not re.match(r"^[A-Za-z][A-Za-z0-9_]{3,}$", n): why = "bad-name"
    if why:
        dropped.append({"name": n, "why": why}); continue
    # 语义邻件：候选的每个实词 token 都能在 registry 同一组件名里找到 → 同义邻件
    tk = toks(n)
    if tk:
        common = set.intersection(*[reg_tok.get(t, set()) for t in tk]) if all(reg_tok.get(t) for t in tk) else set()
        if common:
            dropped.append({"name": n, "why": "semantic-neighbor:" + ",".join(sorted(common)[:2])}); continue
    # 族别按路径订正
    p = b["extraction_point"].lower()
    if "blister" in p or "paletiz" in p:
        b["family"] = "E"
    kept.append(b)

print("kept %d / dropped %d" % (len(kept), len(dropped)))
print(collections.Counter(k["why"].split(":")[0] for k in dropped))
print("--- dropped detail ---")
for x in dropped:
    print("   %-40s %s" % (x["name"][:40], x["why"]))
print("--- kept ---")
for b in kept:
    print("  %s %-42s %-58s loc=%d gaps=%d" % (b["family"], b["name"][:42], b["extraction_point"][:58], b["loc"], len(b["defense_gaps"])))

json.dump({"build": kept, "dropped": dropped, "log": d["log"]},
          open(os.path.join(STG, "_r84_build_f.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
