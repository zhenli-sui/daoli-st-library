# -*- coding: utf-8 -*-
"""R76 文档增量更新：README / CHANGELOG / 6×VERSION / ROADMAP / EVOLOG"""
import os, re, json, datetime

R = r'C:\Library'
REG = os.path.join(R, 'INDEX_REGISTRY.json')
d = json.load(open(REG, encoding='utf-8'))
TOT = d['total_components']
CNT = d['counts']
VER = 'v2.68.0'
PCT = TOT / 10000 * 100
SFT = sum(1 for ln in open(os.path.join(R, '_AI_Training_Dataset', 'daoli_st_sft_dataset.jsonl'), encoding='utf-8') if ln.strip())

# ---------- README ----------
p = os.path.join(R, 'README.md')
s = open(p, encoding='utf-8').read()
s = re.sub(r'Total%20Components-\d+%20%2F%2010%2C000-blue', f'Total%20Components-{TOT}%20%2F%2010%2C000-blue', s, count=1)
s = re.sub(r'(> \*\*Total Components: )[\d,]+( / 10,000 \()[\d.]+(%\)\*\*)',
           rf'\g<1>{TOT:,}\g<2>{PCT:.2f}\g<3>', s, count=1)
s = re.sub(r'\| \*\*Version: v[\d.]+', f'| **Version: {VER}', s, count=1)
s = re.sub(r'\| \*\*SFT 语料: \d+ 条', f'| **SFT 语料: {SFT} 条', s, count=1)
anchor = '## v2.67.0'
line = (f"\n> **v2.68.0（R76 · 2026-11-23）**：39 件入册（复杂 4 / 简单 35，5 族模板派生）｜总库 **{TOT:,}/10,000（{PCT:.2f}%）**｜"
        f"SFT 语料 **{SFT}** 条｜**L2 闸 40/40 PASS = 100%**（两批均原生编译闸席独立裁决）｜审校拒收 1（AngleDiffDeg 与在库 AngleDiffWrap 度制同义）｜"
        f"开源队列 53 条（绿区 52）溯源 17/39 = 43.6%｜冲刺模式复杂件压至 4。\n")
if 'v2.68.0（R76' not in s:
    # 插到徽章段之后第一条分隔线前
    idx = s.find('---', s.find('Total Components'))
    if idx > 0:
        s = s[:idx] + line + '\n' + s[idx:]
    else:
        s = s + line
open(p, 'w', encoding='utf-8').write(s)
print('README ok', TOT, SFT)

# ---------- CHANGELOG ----------
p = os.path.join(R, 'CHANGELOG.md')
s = open(p, encoding='utf-8').read()
if 'v2.68.0' not in s.split('\n\n')[3]:
    block = f"""## {VER} — 2026-11-23（R76 冲刺轮：39 件入册 ｜ 5 族模板批量派生 ｜ L2 闸 40/40 = 100%）

### Added（39 件：DL_Base 14 / DL_MathData 15 / DL_Algo 6 / DL_Device 2 / DL_Motion 1 / DL_Process 1）
- **复杂件 4（C3）**：`FB_DL_BrakeReleaseInterlock`（伺服抱闸释放互锁：使能建立/力矩确认/松闸输出/闸位反馈四相，双 TON 无条件刷新，超时回退上闸态）｜`FB_DL_HeaterBankLoadBalance`（加热器组按累计工时选主，工时并列按通道号，超温整组降额）｜`FB_DL_ChillerDoorPurgeSeq`（冷机检修门吹扫放行链，门位+风压+计时三条件，急停最高优先撤放行）｜`FB_DL_AnalogDriftWatch`（双通道冗余漂移指数遗忘估计，两级阈值分级，单边非有限短路累积）
- **简单件 35（C1~C2，5 族）**：位运算族 8（BitMaskRange/BitReverse8/BitReverse16/BitRunLength/BitLowestSet/BitSwapPairs/BitCountTransitions/BitFillLowestZero）｜角度归一化族 7（AngleLerpShort/AngleQuadrant/AngleBisector/AngleToCompass/AngleTolInside/AngleReflect/AngleUnwrapStep）｜字节序族 6（BytesToWord/DwordToWords/WordsToDword/EndianProbe/LwordToDwords/DwordsToLword）｜三角函数族 8（SinDeg/CosDeg/TanDegChk/AsinDegChk/AcosDegChk/Atan2Deg/SincSafe/HypotChk）｜迟滞限幅族 6（HystWindow3/HystLatchAlarm/HystCounterStep/HystTimeQualified/ClampDintChk/WrapToRange）

### Changed
- 冲刺模式：日目标 300 差额过大时复杂件上限压至 4，其余全部简单件族模板派生（本轮 36 简单件单次调用批量写盘，编码耗时 12 分钟）。
- 反三角实现改用 ATAN2 恒等式（本机 stub 缺 ASIN/ACOS 标准件），语义等价且纯 IEC。

### Fixed
- `FC_DL_AngleLerpShort` 头注释弧差方向笔误（fA-fB → fB-fA，实现本已正确）。
- `FC_DL_HystLatchAlarm` 出参 fOff 注释与复位判据不符（注释改为「仅作参数校验」）。
- SFT 语料历史 25 条缺 `output` 字段（R70~R73 遗留）已按 registry 同名件回填源码。

### Rejected（拒收 1）
- `FC_DL_AngleDiffDeg`：与在库 `FC_DL_AngleDiffWrap`（R41）同为度制最短带符号弧差，仅 ±180 折返方向相反，判语义重复，移入 `_quarantine/`。

"""
    i = s.find('## v2.67.0')
    s = s[:i] + block + s[i:]
    open(p, 'w', encoding='utf-8').write(s)
print('CHANGELOG ok')

# ---------- VERSION.md（6 库，仅本轮触及） ----------
touch = {'DL_Base': '14 件（8 位运算 + 6 字节序）', 'DL_MathData': '15 件（7 角度 + 8 三角）',
         'DL_Algo': '6 件（4 迟滞 + 2 限幅）', 'DL_Device': '2 件（负载均衡 / 漂移监测）',
         'DL_Motion': '1 件（抱闸释放互锁）', 'DL_Process': '1 件（冷机门吹扫联锁）'}
for cat, desc in touch.items():
    p = os.path.join(R, cat, 'VERSION.md')
    s = open(p, encoding='utf-8').read()
    if 'R76' in s:
        continue
    s = s.rstrip() + f"""

## R76 · {VER} · 2026-11-23
- 新增 {desc}，本库累计 **{CNT[cat]}** 件。
- 全部经本地 RuSTy L2 真编译闸 PASS（串行 jobs=1），审校 12 项扫查 + 三道去重通过。
"""
    open(p, 'w', encoding='utf-8').write(s)
print('VERSION ok')

# ---------- ROADMAP ----------
p = os.path.join(R, 'ROADMAP.md')
s = open(p, encoding='utf-8').read()
if 'R76 构建轮小结' not in s:
    s = s.rstrip() + f"""

## R76 构建轮小结（2026-11-23）

> **R76 小结**：**39 件入册**（复杂 4 + 简单 35，5 族模板派生），总库 1,288→**{TOT:,}**，{VER}，SFT 1,327→**{SFT}**（并回填 25 条历史缺 output）。**L2 闸 40/40 PASS = 100%**（批 A 36 件、批 B 4 件，均由原生编译闸席独立裁决，主控未代判）。审校：批 A 35 PASS / 拒收 1（AngleDiffDeg vs 在库 AngleDiffWrap 度制同义）/ MINOR 4；批 B 见 QA_REVIEW_R76。开源队列 29→**53 条**（绿区 52），溯源 17/39 = 43.6%。
> **R77 待办（P0）**：① 闸侧「IEC 保留字撞名」静态告警 + FB-PROPERTY 剥离预处理器（连挂 3 轮）；② 开源队列剔除 `FC_DL_ReverseBitsWord` 等 registry 死条目（库内无源文件，R76 审校发现）；③ 码位子带 0005_1Dxx~2000 已启用，需统一码位台账；④ 值守三项第 8 轮顺延（MatIEC-CI 待配 remote / GITHUB_TOKEN 真检索 / GATE MAJOR 人核）；⑤ 产能补偿：今日 124/300，剩余轮次按每轮 ≥45 件。
"""
    open(p, 'w', encoding='utf-8').write(s)
print('ROADMAP ok')

# ---------- EVOLOG ----------
p = os.path.join(R, 'AGENT_EVOLUTION_LOG.md')
s = open(p, encoding='utf-8').read()
if 'R76 冲刺轮' not in s:
    s = s.rstrip() + f"""

## R76 冲刺轮（2026-11-23 15:54 → 16:5x）

- **模式转变生效**：修复席位本轮 0 件（当日非首轮），产出全部为新增，复杂件压至 4，简单件 36 件按 5 族模板派生。**编码席一次调用写盘 36 件的实测耗时 12 分钟**，对比 R74/R75 一件一调用（22~33 分钟）产率提升 ≥2.5 倍，验证「族模板批量派生」是产能瓶颈的正解。
- **闸独立性首次完全落实**：批 A 36 件、批 B 4 件均由 `daoli-compile-verifier` 原生召唤独立复编译裁决（R74 主控代判属流程违规，本轮纠正），主控预筛不参与正式结论。结果 40/40 PASS。
- **审校价值再验证**：批 A 唯一拒收件 `AngleDiffDeg` 的撞名对象 `AngleDiffWrap` 不在主控给的邻居清单内，靠审校席实测比对才发现——说明「撞名三查」不能只依赖计划期人工清单，须以 registry 全量语义比对为准。
- **新增红线 R437**：简单件族模板派生时，同族件必须共享同一错误码前缀与同一套非有限拦截口径，否则族内行为不可预期。
- **新增红线 R438**：批 A 36 件零失败的关键前置是编码席「写前预查桩」（确认 ASIN/ACOS 等标准件在 iec_std_stub 中是否存在），缺失标准件即改用恒等式内联——该动作应固化为编码席标准首步。
- 进化账本五席各追加（游标 R433 → **R446**）。
"""
    open(p, 'w', encoding='utf-8').write(s)
print('EVOLOG ok')
print('TOT', TOT, CNT, 'SFT', SFT)
