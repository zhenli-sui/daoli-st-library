# -*- coding: utf-8 -*-
"""R85 L2 driver: calls l2_check.main() with exact paths (no shell mangling). Serial jobs=1."""
import io, sys
sys.path.insert(0, r"C:\Library\_tools")
import l2_check

paths = [l.strip() for l in io.open(r"C:\Library\_Staging_Raw\2026-11-24\_r85_paths_lf.txt",
                                    encoding="utf-8") if l.strip()]
assert len(paths) == 40, len(paths)
out = r"C:\Library\_Staging_Raw\2026-11-24\_l2_r85.json"
sys.argv = ["l2_check.py", "--out", out] + paths   # no --jobs => serial 1
rc = l2_check.main()
print("driver rc", rc)
