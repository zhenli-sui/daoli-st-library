# -*- coding: utf-8 -*-
# Git Data API bulk push via api.github.com (github.com:443 blocked by local proxy)
import base64, json, os, sys, time, urllib.request, concurrent.futures, io

TOK = open(r"C:/Library/_tools/.gh_token").read().strip()
OWNER, REPO = "zhenli-sui", "daoli-st-library"
API = f"https://api.github.com/repos/{OWNER}/{REPO}"
HDRS = {"Authorization": "Bearer " + TOK, "Accept": "application/vnd.github+json", "User-Agent": "daoli-push", "Content-Type": "application/json"}
LIB = r"C:/Library"
EXCLUDE_DIRS = {".git", "_tools\\rusty", "_archive", "rusty"}
EXCLUDE_NAMES = {".gh_token", "plc.exe", "plc2.exe", "vcr.exe"}
MAX_SINGLE = 90 * 1024 * 1024

def api(method, url, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    last = None
    for attempt in range(6):
        req = urllib.request.Request(API + url, data=data, headers=HDRS, method=method)
        try:
            with urllib.request.urlopen(req, timeout=600) as r:
                return json.loads(r.read().decode() or "{}")
        except urllib.error.HTTPError as e:
            body_txt = ""
            try: body_txt = e.read().decode()[:400]
            except Exception: pass
            if e.code in (409, 404) and method == "GET": return {}
            if e.code == 403 and ("rate limit" in body_txt.lower() or "secondary" in body_txt.lower() or "abuse" in body_txt.lower()):
                wait = 60 * (attempt + 1)
                print(f"[403 rate-limit] waiting {wait}s: {body_txt[:120]}", flush=True)
                time.sleep(wait); last = e; continue
            if e.code == 401:  # R83：突发并发下偶发 401 Bad credentials → 退避重试
                time.sleep(8 * (attempt + 1)); last = e; continue
            if e.code >= 500 or e.code == 429:
                last = e; time.sleep(3 * (attempt + 1)); continue
            raise RuntimeError(f"{e.code} {body_txt}") from e
        except Exception as e:
            last = e; time.sleep(2 * (attempt + 1))
    raise last

CACHE = r"C:/Library/_Staging_Raw/gh_blob_cache.json"
_blob_cache = {}
if os.path.exists(CACHE):
    _blob_cache = json.load(open(CACHE, encoding="utf-8"))

def save_cache():
    json.dump(_blob_cache, open(CACHE, "w", encoding="utf-8"))

def pick_files():
    out = []
    for root, dirs, files in os.walk(LIB):
        rel = os.path.relpath(root, LIB)
        parts = rel.split(os.sep)
        if any(p in {".git", "rusty", "_archive"} for p in parts): 
            dirs[:] = []; continue
        dirs[:] = [d for d in dirs if d not in {".git", "rusty", "_archive", "__pycache__"}]
        if rel == "_Staging_Raw":  # keep only battle/plan/gate/qa/harvest reports of last 3 days dirs
            dirs[:] = [d for d in dirs if d >= "2026-11-21"]
        # R83 修复：日期子目录内的采集仓解包目录（含 "__"）、轮次临时目录（r7x/r8x）不入库
        if rel.startswith("_Staging_Raw") and rel != "_Staging_Raw":
            dirs[:] = [d for d in dirs if "__" not in d and not (len(d) == 3 and d[0] == "r" and d[1].isdigit())]
        if rel == "_tools":
            dirs[:] = [d for d in dirs if d not in {"_tmp_r79", "vcrx2"}]
        for f in files:
            if f in EXCLUDE_NAMES or f.endswith(".exe") or f.endswith(".bak") or ".bak" in f or f.startswith(".gh_token"): continue
            if f.endswith((".cab", ".dll", ".tar.gz", ".zip", ".7z")) or f.startswith(("gh_blob_cache", "gh_missing")): continue
            p = os.path.join(root, f)
            try:
                sz = os.path.getsize(p)
            except OSError:
                continue
            if sz > MAX_SINGLE: print("SKIP too big:", p, sz); continue
            out.append(p)
    return out

def upload_blob(p):
    rel = os.path.relpath(p, LIB).replace(os.sep, "/")
    raw = open(p, "rb").read()
    import hashlib
    key = rel + ":" + str(hashlib.sha1(raw).hexdigest()) + ":" + str(len(raw))
    if key in _blob_cache:
        return rel, _blob_cache[key], len(raw)
    body = {"content": base64.b64encode(raw).decode(), "encoding": "base64"}
    r = api("POST", "/git/blobs", body)
    _blob_cache[key] = r["sha"]
    if len(_blob_cache) % 50 == 0: save_cache()
    return rel, r["sha"], len(raw)

files = pick_files()
print("files to upload:", len(files), flush=True)
entries, total = [], 0
with concurrent.futures.ThreadPoolExecutor(max_workers=int(os.environ.get("PUSH_WORKERS","1"))) as ex:
    for rel, sha, sz in ex.map(upload_blob, files):
        entries.append({"path": rel, "mode": "100644", "type": "blob", "sha": sha})
        total += sz
        if len(entries) % 200 == 0: print("blobs:", len(entries), f"{total/1e6:.1f}MB", flush=True)
print("all blobs done:", len(entries), f"{total/1e6:.1f}MB", flush=True)
save_cache()

# 增量建树：GitHub 对单次 tree 输入有体积上限，422 会直接拒绝整棵树。
# 改为 base_tree 链式分块：每块以「上一块产出的树」为 base，最终树 = 远端原树 + 本次全部改动。
_ref = api("GET", "/git/ref/heads/main")
_base_commit = _ref["object"]["sha"]
_base_tree = api("GET", f"/git/commits/{_base_commit}")["tree"]["sha"]
print("base tree:", _base_tree, "entries:", len(entries), flush=True)
prev_tree = _base_tree
CHUNK = 400
for i in range(0, len(entries), CHUNK):
    chunk = entries[i:i + CHUNK]
    r = api("POST", "/git/trees", {"base_tree": prev_tree, "tree": chunk})
    prev_tree = r["sha"]
    print(f"tree chunk {i // CHUNK + 1}: {len(chunk)} entries -> {prev_tree}", flush=True)
final_tree = prev_tree

_MSG = os.environ.get("PUSH_MSG", "R86: library snapshot v2.78.0 via API push")
commit = api("POST", "/git/commits", {"message": _MSG, "tree": final_tree})
print("commit:", commit["sha"], flush=True)
try:
    api("GET", "/git/ref/heads/main")
    api("PATCH", "/git/refs/heads/main", {"sha": commit["sha"], "force": True})
except Exception:
    api("POST", "/git/refs", {"ref": "refs/heads/main", "sha": commit["sha"]})
print("ref updated -> main", commit["sha"], flush=True)
