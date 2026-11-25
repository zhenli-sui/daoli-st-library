import json, os

OUT = r'C:\Library\_AI_Training_Dataset\daoli_st_sft_dataset.jsonl'
FP = r'C:\Library\DL_Algo\FB_DL_PeltierTempCtrl.st'
src = open(FP, encoding='utf-8').read()

lines = open(OUT, encoding='utf-8').read().splitlines()
hit = 0
new = []
for ln in lines:
    o = json.loads(ln)
    # 通过 output 头部组件名识别
    if 'FB_DL_PeltierTempCtrl' in o['output'][:400] and 'PeltierTempCtrl' not in o['instruction'][:40]:
        o['output'] = src
        hit += 1
    new.append(json.dumps(o, ensure_ascii=False))

open(OUT, 'w', encoding='utf-8').write("\n".join(new) + "\n")
print("REINJECT", hit, "LINES", len(new))
