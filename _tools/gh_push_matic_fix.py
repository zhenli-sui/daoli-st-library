# -*- coding: utf-8 -*-
"""Push changed tool files to GitHub via Git Data API and dispatch CI."""
import base64, json, urllib.request

tok = open("C:/Library/_tools/.gh_token").read().strip()
H = {"Authorization": "Bearer " + tok, "Accept": "application/vnd.github+json", "User-Agent": "daoli-push"}
A = "https://api.github.com/repos/zhenli-sui/daoli-st-library"

def api(m, u, p=None):
    d = json.dumps(p).encode() if p is not None else None
    r = urllib.request.Request(A + u, data=d, headers=H, method=m)
    return json.loads(urllib.request.urlopen(r, timeout=120).read().decode() or "{}")

FILES = [
    "_tools/matic_manifest.py",
    "_tools/matic_runner.py",
]

head = api("GET", "/git/ref/heads/main")["object"]["sha"]
parent = api("GET", "/git/commits/" + head)
tree_entries = []
for f in FILES:
    raw = open("C:/Library/" + f, "rb").read()
    blob = api("POST", "/git/blobs", {"content": base64.b64encode(raw).decode(), "encoding": "base64"})["sha"]
    tree_entries.append({"path": f.replace("\\", "/"), "mode": "100644", "type": "blob", "sha": blob})

tree = api("POST", "/git/trees", {"base_tree": parent["tree"]["sha"], "tree": tree_entries})["sha"]
commit = api("POST", "/git/commits", {
    "message": "fix(ci): resolve library root from script location in matic_manifest/matic_runner (Linux CI compatible)",
    "tree": tree, "parents": [head],
})["sha"]
api("PATCH", "/git/refs/heads/main", {"sha": commit})
print("pushed:", commit)

req = urllib.request.Request(
    A + "/actions/workflows/iec-compile.yml/dispatches",
    data=json.dumps({"ref": "main"}).encode(),
    headers={**H, "Content-Type": "application/json"}, method="POST")
print("dispatch:", urllib.request.urlopen(req).status)
