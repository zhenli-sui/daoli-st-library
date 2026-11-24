# -*- coding: utf-8 -*-
"""R83 增量推送：base_tree 增量提交（仅本轮新增 .st + 改动文档），不重建全树"""
import base64, json, os, time, urllib.request, urllib.error

TOK = open(r"C:/Library/_tools/.gh_token").read().strip()
API = "https://api.github.com/repos/zhenli-sui/daoli-st-library"
HDRS = {"Authorization": "Bearer " + TOK, "Accept": "application/vnd.github+json",
        "User-Agent": "daoli-push", "Content-Type": "application/json"}
LIB = r"C:/Library"


def api(method, url, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    for attempt in range(5):
        req = urllib.request.Request(API + url, data=data, headers=HDRS, method=method)
        try:
            with urllib.request.urlopen(req, timeout=300) as r:
                return json.loads(r.read().decode() or "{}")
        except urllib.error.HTTPError as e:
            body = ""
            try:
                body = e.read().decode()[:300]
            except Exception:
                pass
            if e.code in (401, 403, 429, 500, 502, 503):
                time.sleep(5 * (attempt + 1))
                continue
            raise RuntimeError("%d %s" % (e.code, body)) from e
    raise RuntimeError("retries exhausted")


ref = api("GET", "/git/ref/heads/main")
head = ref["object"]["sha"]
commit = api("GET", "/git/commits/" + head)
base_tree = commit["tree"]["sha"]
print("HEAD", head, "base_tree", base_tree, flush=True)

targets = []
CUT = 1764038400  # 2026-11-24 13:00 +08:00 之后改动
for cat in ["DL_Base", "DL_MathData", "DL_Algo", "DL_Device", "DL_Motion", "DL_Process"]:
    for f in os.listdir(os.path.join(LIB, cat)):
        fp = os.path.join(LIB, cat, f)
        if f.endswith(".st") and os.path.getmtime(fp) > CUT:
            targets.append(fp)
for rel in ["README.md", "CHANGELOG.md", "ROADMAP.md", "AGENT_EVOLUTION_LOG.md", "SOURCE_HUNTING_MATRIX.md"]:
    p = os.path.join(LIB, rel)
    if os.path.exists(p):
        targets.append(p)

# 与远端已有树比对：只提交内容变化的文件
remote = api("GET", "/git/trees/" + base_tree + "?recursive=1")
remote_map = {e["path"]: e["sha"] for e in remote.get("tree", []) if e["type"] == "blob"}
print("remote blobs", len(remote_map), flush=True)

entries = []
import hashlib
for p in targets:
    raw = open(p, "rb").read()
    gsha = hashlib.sha1(("blob %d" % len(raw)).encode() + bytes([0]) + raw).hexdigest()
    rel = os.path.relpath(p, LIB).replace(os.sep, "/")
    if remote_map.get(rel) == gsha:
        continue
    blob = api("POST", "/git/blobs", {"content": base64.b64encode(raw).decode(), "encoding": "base64"})
    entries.append({"path": rel, "mode": "100644", "type": "blob", "sha": blob["sha"]})
    if len(entries) % 25 == 0:
        print("  staged", len(entries), flush=True)

print("changed entries", len(entries), flush=True)
if not entries:
    print("NO_CHANGES")
    raise SystemExit

tree = api("POST", "/git/trees", {"base_tree": base_tree, "tree": entries})
newc = api("POST", "/git/commits", {
    "message": "R83: +39 components (1,609 total, SFT 1,648) - printing/textile/plating/sorting/warehouse families",
    "tree": tree["sha"], "parents": [head]})
api("PATCH", "/git/refs/heads/main", {"sha": newc["sha"]})
print("PUSHED", newc["sha"], flush=True)
