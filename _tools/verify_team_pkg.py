# -*- coding: utf-8 -*-
"""校验 daoli-lib-factory 团队包结构完整性。"""
import os, json, io, re, sys

T = r"C:\Users\Administrator\.workbuddy\plugins\cache\my-experts\daoli-lib-factory\1.0.0"
pkg_path = os.path.join(T, ".codebuddy-plugin", "plugin.json")
pkg = json.load(io.open(pkg_path, encoding="utf-8"))

FM = re.compile(r"^---\n(.*?)\n---\n", re.S)
NAME = re.compile(r"^name:[ ]*(\S+)", re.M)
ZH = re.compile(r"^[ ]{2}zh:[ ]*\"(.+?)\"", re.M)

ok = True
print("plugin: %s | expertType: %s | lead: %s" % (pkg["name"], pkg["expertType"], pkg["agentName"]))
for a in pkg["agents"]:
    rel = a.replace("./", "").replace("/", os.sep)
    f = os.path.join(T, rel)
    if not os.path.exists(f):
        print("[MISS] %s" % a)
        ok = False
        continue
    txt = io.open(f, encoding="utf-8").read()
    m = FM.match(txt)
    fm = m.group(1) if m else ""
    n = NAME.search(fm)
    z = ZH.search(fm)
    want = os.path.basename(f)[:-3]
    good = bool(n) and n.group(1) == want
    print("%s %-26s id=%-22s zh=%s" % ("[OK]  " if good else "[FAIL]", os.path.basename(f),
                                       n.group(1) if n else "-", z.group(1) if z else "-"))
    ok = ok and good

team = pkg.get("teamInfo", {})
members = team.get("memberAgents", [])
declared = [x for x in pkg.get("agents", [])]
print("\nteamInfo.leadAgent = %s" % team.get("leadAgent"))
print("teamInfo.memberAgents = %s" % members)
for mid in members + [team.get("leadAgent")]:
    hit = any(os.path.basename(d)[:-3] == mid for d in declared)
    if not hit:
        print("[FAIL] teamInfo 引用了未在 agents 中声明的成员: %s" % mid)
        ok = False

print("\n结论: %s" % ("团队包结构通过" if ok else "存在缺陷"))
sys.exit(0 if ok else 1)
