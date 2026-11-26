# -*- coding: utf-8 -*-
"""R82 P0: 重建 _dedup_fingerprints.json
旧库仅 84 条（覆盖 5.6%），键值为 hash->符号名形态不可用，导致签名指纹去重道实际降级为批内互比。
新库三道可用：
  1) sig  : 接口指纹（VAR_INPUT/VAR_OUTPUT 的类型序列，与变量名无关）—— 抓「换名同构」
  2) api  : 名称指纹（去前缀/去通用词后的词根集合，排序拼接）—— 抓「换序同名」
  3) kind : 结构指纹（FB/FC + 出参个数 + 是否状态机）—— 辅助分层
"""
import os, re, json, hashlib, glob

LIB = r"C:\Library"
OUT = os.path.join(LIB, "_Staging_Raw", "_dedup_fingerprints.json")
GEN = {"fb","fc","dl","st","i","e","calc","chk","seq","ctrl","ctl","mgr","mon","monitor",
       "guard","idx","index","rate","ratio","value","level","time","param","data","cfg",
       "config","set","get","unit","conv","convert","util","helper","base","est","adj","new"}

VAR_SEC = re.compile(r"^\s*VAR_(INPUT|OUTPUT|IN_OUT)\b", re.I)
END_SEC = re.compile(r"^\s*END_VAR\b", re.I)
DECL = re.compile(r"^\s*([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)\s*:\s*([^;]+);", re.S)


def norm_type(t):
    t = re.sub(r":=.*$", "", t).strip()
    t = re.sub(r"\[[^\]]*\]", "[]", t)          # 数组维度归一
    t = re.sub(r"\s+", "", t).upper()
    return t


def analyze(path):
    src = open(path, encoding="utf-8", errors="replace").read()
    name = os.path.splitext(os.path.basename(path))[0]
    body = re.sub(r"\(\*.*?\*\)", "", src, flags=re.S)
    body = re.sub(r"//[^\n]*", "", body)

    kind = "FB" if re.search(r"\bFUNCTION_BLOCK\b", body, re.I) else \
           ("FC" if re.search(r"\bFUNCTION\b", body, re.I) else
            ("TYPE" if re.search(r"\bTYPE\b", body, re.I) else
             ("IFACE" if re.search(r"\bINTERFACE\b", body, re.I) else "OTHER")))

    ins, outs, inout = [], [], []
    cur = None
    for ln in body.split("\n"):
        u = ln.strip()
        if re.match(r"^VAR_INPUT\b", u, re.I):
            cur = ins; continue
        if re.match(r"^VAR_OUTPUT\b", u, re.I):
            cur = outs; continue
        if re.match(r"^VAR_IN_OUT\b", u, re.I):
            cur = inout; continue
        if re.match(r"^VAR\b", u, re.I):
            cur = None; continue
        if re.match(r"^END_VAR\b", u, re.I):
            cur = None; continue
        if cur is None:
            continue
        m = DECL.match(u)
        if not m:
            continue
        typ = norm_type(m.group(2))
        n = len([x for x in m.group(1).split(",") if x.strip()])
        for _ in range(n):
            cur.append(typ)

    sig_src = kind + "|I:" + ",".join(ins) + "|O:" + ",".join(outs) + "|IO:" + ",".join(inout)
    sig = hashlib.sha1(sig_src.encode()).hexdigest()[:16]

    toks = [t.lower() for t in re.findall(r"[A-Z]?[a-z]+|[A-Z]+(?![a-z])", name)]
    toks = [t for t in toks if t not in GEN and len(t) > 2]
    api = hashlib.sha1("|".join(sorted(set(toks))).encode()).hexdigest()[:16]

    sm = bool(re.search(r"CASE\b", body, re.I)) and bool(re.search(r"END_CASE", body, re.I))
    return {
        "name": name, "kind": kind, "sig": sig, "api": api,
        "in_n": len(ins), "out_n": len(outs), "sm": sm,
        "lines": body.count("\n") + 1,
        "tokens": sorted(set(toks)),
        "file": os.path.relpath(path, LIB).replace("\\", "/"),
    }


def main():
    files = sorted(glob.glob(os.path.join(LIB, "DL_*", "*.st")))
    recs = []
    for p in files:
        try:
            recs.append(analyze(p))
        except Exception as e:
            print("SKIP", p, e)
    by_sig, by_api = {}, {}
    for r in recs:
        by_sig.setdefault(r["sig"], []).append(r["name"])
        by_api.setdefault(r["api"], []).append(r["name"])
    sig_dup = {k: v for k, v in by_sig.items() if len(v) > 1}
    api_dup = {k: v for k, v in by_api.items() if len(v) > 1}

    tok_idx = {}
    for r in recs:
        for t in r["tokens"]:
            tok_idx.setdefault(t, []).append(r["name"])

    db = {
        "built_at": "2026-11-24T11:25:00+08:00",
        "round": "R82",
        "count": len(recs),
        "schema": "sig=接口类型序列指纹 / api=词根集指纹 / tokens=倒排索引",
        "components": {r["name"]: {k: r[k] for k in
                       ("kind","sig","api","in_n","out_n","sm","lines","file")} for r in recs},
        "sig_groups": sig_dup,
        "api_groups": api_dup,
        "token_index": {k: v for k, v in tok_idx.items() if len(v) >= 2},
    }
    json.dump(db, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("files", len(files), "records", len(recs))
    print("sig groups(dup)", len(sig_dup), "api groups(dup)", len(api_dup))
    print("token index", len(db["token_index"]))
    print("top sig dup:", sorted(((len(v), k, v[:4]) for k, v in sig_dup.items()), reverse=True)[:3])


if __name__ == "__main__":
    main()
