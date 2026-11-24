# -*- coding: utf-8 -*-
"""R85 L1 driver: read-only, reuses dl_gate.gate_file per target. No source edits."""
import io, json, os, sys
sys.path.insert(0, r"C:\Library\_tools")
import dl_gate

paths = [l.strip() for l in io.open(r"C:\Library\_Staging_Raw\2026-11-24\_r85_paths.txt",
                                    encoding="utf-8") if l.strip()]
reg = dl_gate.load_registry_index()
out = []
for p in paths:
    r = dl_gate.gate_file(p, reg, False)
    out.append(r)
json.dump(out, io.open(r"C:\Library\_Staging_Raw\2026-11-24\_l1_r85.json", "w",
                       encoding="utf-8"), ensure_ascii=False, indent=1)
from collections import Counter
c = Counter(r["verdict"] for r in out)
print("L1 TOTAL %d | %s" % (len(out), dict(c)))
for r in out:
    hard = [i for i in r["issues"] if i["level"] in ("BLOCK", "MAJOR")]
    if r["verdict"] != "PASS":
        print("%-6s %-42s %s" % (r["verdict"], os.path.basename(r["file"]),
                                 "; ".join("%s@L%d:%s" % (i["code"], i["line"], i["detail"][:50])
                                           for i in hard[:4])))
