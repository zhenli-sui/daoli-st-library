# -*- coding: utf-8 -*-
"""R85 文档增量更新：README 徽章 / CHANGELOG / ROADMAP / EVOLOG / VERSION。全部追加式。"""
import json, io, sys, os, re, glob, datetime
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
LIB = r'C:\Library'
STG = os.path.join(LIB, '_Staging_Raw', '2026-11-24')
co = json.load(open(os.path.join(STG, 'r85_closeout.json'), encoding='utf-8'))
meta = json.load(open(os.path.join(STG, 'r85_meta.json'), encoding='utf-8'))
jsnl = co['jsonl_lines']
TOT = co['registry_total']
add = len(co['added'])
VER = 'v2.77.0'
cnt = co['counts']

# ---------- README ----------
p = os.path.join(LIB, 'README.md')
s = open(p, encoding='utf-8').read()
s = re.sub(r'Total%20Components-\d+%20%2F%2010%2C000', f'Total%20Components-{TOT}%20%2F%2010%2C000', s)
s = re.sub(r'SFT%20Corpus-\d+%20records', f'SFT%20Corpus-{jsnl}%20records', s)
s = re.sub(r'\*\*Total Components: [\d,]+ / 10,000 \([0-9.]+%\)\*\*', f'**Total Components: {TOT:,} / 10,000 ({TOT/100:.2f}%)**', s)
s = re.sub(r'\*\*Version: v2\.\d+\.\d+\*\*', f'**Version: {VER}**', s)
s = re.sub(r'\*\*SFT 语料: \d+ 条\*\*', f'**SFT 语料: {jsnl} 条**', s)
newline = (f"> **R85（2026-11-24 傍晚轮 · 冲刺）**：**{add} 件入册（复杂 4 + 简单 36，5 族模板派生）**——"
           f"金属热处理族 8（淬火油温升/奥氏体化保温/渗碳层深 Harris/回火硬度曲线/感应淬火扫描/淬火槽搅拌/马氏体点/坑式炉均热）·"
           f"铝挤压阳极氧化族 8（铸锭加热/挤压比压/氧化电量/模具磨损/逆流漂洗/定尺剪切/膜厚换算/沸水封孔）·"
           f"压铸族 7（压射速度 PQ²/增压比压/模热平衡/凝固时间 Chvorinov/喷涂时序/定量浇注/气孔风险）·"
           f"粉末冶金烧结族 7（装粉密度/压制压力/烧结曲线/生坯强度/收缩补偿/混粉配料/烧除残碳）·"
           f"酿造制糖族 6（投料水温/麦汁收得率/煮糖过饱和度/废蜜纯度/结晶真空/CIP 五步）+ "
           f"复杂 4（QuenchTemperLineSeq C4·AnodizeLineTransferSeq C4·DieCastCycleSupervise C4·SugarPanBatchSeq C4）；"
           f"总库 1,646→**{TOT:,}**，{VER}，SFT **{jsnl}**。修复件 0（非当日首轮，配额归零）。\n")
if '**R85（2026-11-24' not in s:
    anchor = '> **R81（2026-11-24'
    i = s.find(anchor)
    s = s[:i] + newline + s[i:]

# 逐级徽章按 counts 校正
s = re.sub(r'(DL_Base)[^\d]{0,20}(\d{2,4})', lambda m: m.group(1) + m.group(2), s)  # no-op 保护
open(p, 'w', encoding='utf-8').write(s)
print('README ok, badge', TOT, jsnl)

# ---------- CHANGELOG ----------
p = os.path.join(LIB, 'CHANGELOG.md')
s = open(p, encoding='utf-8').read()
if VER not in s:
    block = [f'## {VER} — 2026-11-24（第 85 轮 · 冲刺模式 · 五族垂直：热处理/铝挤压氧化/压铸/粉末冶金/糖酒）\n',
             f'### Added（{add} 件）',
             f'- **复杂件 4（C4）**：`FB_DL_QuenchTemperLineSeq`（淬火-回火联动线 ≥10 态状态机，相内独立 TON + 三级异常分级）｜'
             f'`FB_DL_AnodizeLineTransferSeq`（阳极氧化行车三轴转序 + `ARRAY[0..15]` 槽位占用互锁，防双载防跨槽错位）｜'
             f'`FB_DL_DieCastCycleSupervise`（压铸单循环监控，压射曲线四点越限黄/红/黑三级处置）｜'
             f'`FB_DL_SugarPanBatchSeq`（煮糖罐批次时序，过饱和度作相迁移判据 + 真空温度双联锁）',
             f'- **简单件 36（C1~C2，5 族模板派生）**：金属热处理 8 ｜ 铝挤压与阳极氧化 8 ｜ 压铸 7 ｜ 粉末冶金烧结 7 ｜ 酿造制糖 6',
             '',
             '### Changed',
             '- 族选题改用「词根饱和度实测」：Quench/Carbur/Extrus/Sinter/DieCast/Brew/Sugar/Malt 全库命中均为 0，选取真空域，避开已饱和通用层。',
             '- 规划期 token 交集扫描两轮，累计驳回/改名 6 件，终版 40 名零撞名落盘。',
             f'- 分类分布：DL_Process {cnt.get("DL_Process",0)} ／ DL_Device {cnt.get("DL_Device",0)} ／ DL_MathData {cnt.get("DL_MathData",0)} ／ DL_Base {cnt.get("DL_Base",0)} ／ DL_Algo {cnt.get("DL_Algo",0)} ／ DL_Motion {cnt.get("DL_Motion",0)}',
             '',
             '### 记录',
             f'- L2 编译闸：见 `_Staging_Raw/2026-11-24/GATE_R85.md`（闸席原生裁决）。',
             f'- 拒收件移入 `_quarantine/R85/`，未登记 registry 与 JSONL。',
             '']
    anchor = '## v2.72.0 — 2026-11-24'
    i = s.find(anchor)
    s = s[:i] + '\n'.join(block) + '\n' + s[i:]
open(p, 'w', encoding='utf-8').write(s)
print('CHANGELOG ok')

# ---------- ROADMAP ----------
p = os.path.join(LIB, 'ROADMAP.md')
s = open(p, encoding='utf-8').read()
add_txt = (f"\n## R85 构建轮小结（2026-11-24 傍晚轮 · 冲刺模式 · 五个真空域垂直族）\n\n"
           f"> **R85 小结**：**{add} 件入册**（复杂 4 / 简单 36），总库 1,646→**{TOT:,}**（{TOT/100:.2f}%），{VER}，SFT →**{jsnl}**。"
           f"五族：金属热处理 8 ／ 铝挤压阳极氧化 8 ／ 压铸 7 ／ 粉末冶金烧结 7 ／ 酿造制糖 6 + 复杂 4。"
           f"开源队列 210→**215 行（有效 200，绿 163/黄 52/红 0）**，五族专用件语义命中 **0**（第 4 次证实垂直工艺 ST 开源空白）。"
           f"修复件 0（非当日首轮，配额归零）。\n"
           f"> **R86 待办（P0）**：① 存量 4 件 `FOR..DOWNTO` 清剿（`FC_DL_DwordToHexString` / `FC_DL_LrealToFixedField` / "
           f"`FC_DL_PolyEvalHorner` / `FB_DL_MarkPositionLatch`）——须当日首轮，占 4 件修复配额；"
           f"② R84 拒收 3 件处置（ToolMagazinePosSeq 择向取模 + 方向电平保持 / 另两件转语义合并）；"
           f"③ `FB_DL_RunawayGuard` 死变量 `_fFrac` 清理；④ 道2 指纹分组键缺陷修正（sig 道同型碰撞假阳性）；"
           f"⑤ 队列有效 200 已达阈值线，补仓至 ≥220 或正式改口径双 KPI；"
           f"⑥ 当日末轮执行看板同步（云端节点 `PUD2s8AwgtOg8otTa4Dyvl`）；⑦ 值守三项第 16 轮顺延。\n")
if '## R85 构建轮小结' not in s:
    s = s.rstrip() + '\n' + add_txt
open(p, 'w', encoding='utf-8').write(s)
print('ROADMAP ok')

# ---------- EVOLOG ----------
p = os.path.join(LIB, 'AGENT_EVOLUTION_LOG.md')
evo = (f"\n## R85（2026-11-24 傍晚轮 · 冲刺模式）\n\n"
       f"| 席位 | 条数 | 本轮核心沉淀 |\n|---|---|---|\n"
       f"| DIRECTOR | 待填 | 见 `_EXPERT_EVOLUTION/DIRECTOR_EVOLUTION.md` R591 起 |\n"
       f"| PLC_EXPERT | 待填 | 见 `PLC_EXPERT_EVOLUTION.md` |\n"
       f"| OSS_HUNTER | 5 | R587~R590（猎人自编）；五族专用件命中 0，垂直工艺开源空白第 4 次实证 |\n"
       f"| COMPILE_VERIFIER | 待填 | 见 `COMPILE_VERIFIER_EVOLUTION.md` |\n"
       f"| QA_DEDUP | 待填 | 见 `QA_DEDUP_EVOLUTION.md` |\n\n"
       f"**本轮结构性问题**：见 `_EXPERT_EVOLUTION/DAILY_RETRO.md` R85 节。\n")
if '## R85（2026-11-24' not in open(p, encoding='utf-8').read():
    open(p, 'a', encoding='utf-8').write(evo)
print('EVOLOG ok')

# ---------- VERSION ----------
for cat in ['DL_Process', 'DL_Device', 'DL_MathData']:
    d = os.path.join(LIB, cat)
    vf = os.path.join(d, 'VERSION')
    if os.path.isdir(d):
        with open(vf, 'a', encoding='utf-8') as f:
            f.write(f"{VER} | R85 | 2026-11-24 | 本库累计 {cnt.get(cat,0)} 件\n")
print('VERSION ok')
