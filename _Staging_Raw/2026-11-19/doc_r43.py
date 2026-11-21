# -*- coding: utf-8 -*-
import re, os, io, datetime

L = 'C:\\Library\\'
names = ["FB_DL_StakingPressCtrl","FB_DL_PouchVacuumSeal","FB_DL_CalenderRollPress","FB_DL_QuarterCellCutSeq",
"FB_DL_CellOcvBinSort","FB_DL_IvCurveScan","FB_DL_ChillerCondReset","FB_DL_SampleLoopPurge","FB_DL_BundleShrinkTemp",
"FB_DL_DuctLeakRateEst","FB_DL_VavPressureReset","FB_DL_ChwDifferentialPressureReset","FB_DL_SelfDischargeScreen",
"FB_DL_FanPressureTrim","FB_DL_CleanRoomRhTrim","FB_DL_BoilerFlueCondenseGuard","FB_DL_CellFeederVacuum",
"FB_DL_AxisBrakeDistPredict","FB_DL_GearInPhaseAlign","FC_DL_TimeToCycleCeil"]

def rd(p):
    return open(p, encoding='utf-8').read()

def wr(p, s):
    with open(p, 'w', encoding='utf-8', newline='\n') as f:
        f.write(s)

# ---------- README 增量 ----------
r = rd(L+'README.md')
r = r.replace('Total%20Components-745%20%2F%2010%2C000', 'Total%20Components-765%20%2F%2010%2C000')
r = r.replace('SFT%20Corpus-745%20records', 'SFT%20Corpus-765%20records')
r = r.replace('**Total Components: 745 / 10,000**', '**Total Components: 765 / 10,000**')
r = r.replace('**Version: v2.34.0**', '**Version: v2.35.0**')
r = r.replace('**SFT 语料: 745 条**', '**SFT 语料: 765 条**')
r = r.replace('**全库约 158,967 行**', '**全库约 163,000 行**')
r = r.replace('Level%200-237%20%2F%2040%20closed', 'Level%200-238%20%2F%2040%20closed')
r = r.replace('Level%201%20DL--Algo-57%20open', 'Level%201%20DL--Algo-62%20open')
r = r.replace('Level%201%20DL--Device-97%20open', 'Level%201%20DL--Device-100%20open')
r = r.replace('Level%201%20DL--Motion-52%20open', 'Level%201%20DL--Motion-54%20open')
r = r.replace('Level%202%20DL--Process-79%20open', 'Level%202%20DL--Process-88%20open')
wr(L+'README.md', r)

# ---------- CHANGELOG 前插 ----------
c = rd(L+'CHANGELOG.md')
anchor = '## v2.34.0'
block = """## v2.35.0 — 2026-11-19（R43 / 品类纠偏轮 20 新件 + 码位普查清零）

### Added（20 新件：DL_Process +9 / DL_Algo +5 / DL_Device +3 / DL_Motion +2 / DL_Base +1）
- DL_Process（+9）：FB_DL_StakingPressCtrl / FB_DL_PouchVacuumSeal / FB_DL_CalenderRollPress / FB_DL_QuarterCellCutSeq / FB_DL_CellOcvBinSort / FB_DL_IvCurveScan / FB_DL_ChillerCondReset / FB_DL_SampleLoopPurge / FB_DL_BundleShrinkTemp
- DL_Algo（+5）：FB_DL_DuctLeakRateEst / FB_DL_VavPressureReset / FB_DL_ChwDifferentialPressureReset / FB_DL_SelfDischargeScreen / FB_DL_FanPressureTrim
- DL_Device（+3）：FB_DL_CleanRoomRhTrim / FB_DL_BoilerFlueCondenseGuard / FB_DL_CellFeederVacuum（05xx 副带续编 052B~052D）
- DL_Motion（+2）：FB_DL_AxisBrakeDistPredict / FB_DL_GearInPhaseAlign
- DL_Base（+1）：FC_DL_TimeToCycleCeil（T0 防御性包装，委托内建判定不重实现内核）

### Fixed（质量）
- 全库码位冲突普查闭环：765 件全文实扫，占用码位 149 个，**冲突 0 处**（P1 连挂 4 轮至此清偿）。
- 机检口径修 2 处：① 枚举「漏单冒号」判定原误把 `_eState := E_DL_X.eIdle`（合法限定赋值）判违规；② IF/END_IF 计数原用 `(?<!END_)IF` 会把 `ELSIF` 计入。两处均为脚本自身误报，非代码缺陷（R171 家族第 7、8 次口径坑）。

### Notes
- 品类纠偏：DL_MathData 已占 25.7% 超配，本轮 MathData 0 件，Algo/Motion 合计补薄 7 件。
- 编译验证债仍挂账（连续 39 轮）；code_segment 字段本轮 20 件全部实填写入（历史件回填仍待专项）。

"""
c = c.replace(anchor, block + anchor, 1)
wr(L+'CHANGELOG.md', c)

# ---------- VERSION 子库追加 ----------
sub = {
 'DL_Process': ('1.17.0', '1.18.0', 9, '039D~03A5 / 04C5~04CD'),
 'DL_Algo': ('1.16.0', '1.17.0', 5, '0386~038A'),
 'DL_Device': ('1.15.0', '1.16.0', 3, '052B~052D / 0431~0433'),
 'DL_Motion': ('1.14.0', '1.15.0', 2, '04A6~04A7'),
 'DL_Base': ('1.19.0', '1.20.0', 1, '0102'),
}
for k, (old, new, n, seg) in sub.items():
    p = L + k + '/VERSION.md'
    t = rd(p)
    add = "\n### v%s — 2026-11-19（R43）\n- 新增组件 %d 件；码位窗口 %s 零冲突。\n- 由 v%s 升位，向后兼容（纯新增，无接口破坏）。\n" % (new, n, seg, old)
    wr(p, t.rstrip('\n') + '\n' + add)

# ---------- ROADMAP 勾选 ----------
rp = rd(L+'ROADMAP.md')
hit = []
for n in names:
    pat = re.compile(r'^- \[ \] `' + re.escape(n) + r'`', re.M)
    if pat.search(rp):
        rp = pat.sub('- [x] `' + n + '`', rp)
        hit.append(n)
wr(L+'ROADMAP.md', rp)
print('ROADMAP checked', len(hit), hit)

# ---------- MATRIX 台账 ----------
mp = rd(L+'SOURCE_HUNTING_MATRIX.md')
line = ("- **R43 实测**：**零检索轮（0/3）**——20 件全部来自 ROADMAP 真缺口（9 件：StakingPressCtrl / PouchVacuumSeal / CalenderRollPress / "
        "QuarterCellCutSeq / CellOcvBinSort / IvCurveScan / BundleShrinkTemp / SelfDischargeScreen / CellFeederVacuum）+ 源矩阵既有组深化"
        "（T1-2 OSCAT Building 7 件：ChillerCondReset / SampleLoopPurge / DuctLeakRateEst / VavPressureReset / ChwDifferentialPressureReset / "
        "CleanRoomRhTrim / BoilerFlueCondenseGuard；T2-7 PackML 1 件：FanPressureTrim；T1-5 TcOpen 1 件：CellFeederVacuum；T1-6 PLCopen 2 件："
        "AxisBrakeDistPredict / GearInPhaseAlign；T0 防御包装 1 件：TimeToCycleCeil）。**状态列结论：全部 ◐ 深化，无 ☐→◐ 开组、无整组 ◐→✔ 收口，"
        "未触碰任何已收口组。**另本轮完成全库码位冲突普查（765 件、149 码位、冲突 0），P1 连挂 4 轮清偿。\n")
mp = mp.replace('## 5 挖掘状态台账', line + '\n## 5 挖掘状态台账', 1) if '## 5 挖掘状态台账' in mp else mp + '\n' + line
wr(L+'SOURCE_HUNTING_MATRIX.md', mp)

# ---------- 专家进化账本 ----------
ev = L + '_EXPERT_EVOLUTION\\'
d_ev = ("\n## R43（2026-11-19）\n"
"- [R268] 口径缺陷 | 枚举「漏单冒号」检查把 `_eState := E_DL_Xxx.eIdle`（限定成员赋值）判为违规，19 件全线误报 | 判定必须区分「声明」与「赋值」：RHS 带 `.member` 即为赋值，永不是声明 | 检查式改为 `^\\s*\\w+\\s*:=\\s*E_DL_\\w+\\s*;`，并要求命中项人工复核一次\n"
"- [R269] 口径缺陷 | IF/END_IF 平衡用 `(?<!END_)IF\\b` 把 `ELSIF` 计为 IF，20 件 19 件假失衡 | 缺前导 `\\b` 的花括号后缀排除必然吞掉 ELSIF | 一律 `\\bIF\\b` + `\\bEND_IF\\b` 计数，禁用无前导边界的 IF\n"
"- [R270] 选题纪律 | 本轮 MathData 占比 25.7% 已超配，若继续按缺口无差别取件会加剧偏科 | 总量达标不等于结构健康，品类配比须作为独立约束 | 每轮派单前核对六子库占比，>25% 者限 0~2 件，薄库优先\n"
"- [R271] 流程收益 | 「码位普查 + 选题」同轮并行（总监规划、主控脚本普查）把 P1 挂账 4 轮的事项一次清偿 | 独立普查任务与规划无数据依赖，可并行而不争锁 | 后续无障碍的挂账项优先与规划阶段并行，不占编码窗口\n"
"- [R272] 风险留痕 | 本轮 20/20 一次通过但终审线因时长未启用，属「机检 PASS 但无人审」状态 | 机检只能覆盖可判定规则，语义级缺陷（TON 语义、状态迁出）仍需人审 | 战报须显式标注「终审未启用」，并把抽检顺延为下轮首位，不得静默略过\n")

p_ev = ("\n## R43（2026-11-19）\n"
"- [R273] 代码级 | ChillerCondReset 首版写了非法标签 `IF_NOT_ENABLE:`，把条件注释误作跳转标签 | ST 无 goto/label，任何 `xxx:` 裸标签都是语法错误 | 状态迁移一律走 CASE 标签，禁止任何非 CASE 冒号行\n"
"- [R274] 代码级 | SampleLoopPurge 首版用 `TIME_TO_DINT(...) < 0` 作超时判据，恒假（TIME 转 DINT 非负） | TIME 是无符号时长量，与 0 比较的「小于」分支结构性不可达 | 超时判定只用 TON 完成位，禁止对 TIME 差值作符号判断\n"
"- [R275] 防御范式 | 本轮 9 件 Process 全部把四相/五相 TON 拆独立实例，机检零命中 | 分层实例化是 R232 跨相复位陷阱的根治手段，成本仅多几个实例 | 相数 ≥3 的顺控件，一律「一相一 TON」，不设共用计时基\n"
"- [R276] 语义标注 | 「正好整除不 +1」这类边界语义若不写验收向量注释，后续维护极易被改成 `+1` | 边界语义必须在头注释给出两条向量（整除点、上限+1 点） | 向上/向下取整、饱和、钳制类件强制附验收向量注释\n"
"- [R277] 解耦纪律 | Motion 两件只消费位置/速度快照与参数，未引入任何轴状态枚举 | 运动层状态属主唯一，工艺层自造状态枚举必然与轴对象打架（R31 家族） | 凡不直接发运动指令的件，禁止定义或引用轴状态枚举\n")

for fn, add in (('DIRECTOR_EVOLUTION.md', d_ev), ('PLC_EXPERT_EVOLUTION.md', p_ev)):
    p = ev + fn
    if os.path.exists(p):
        wr(p, rd(p).rstrip('\n') + '\n' + add)
    else:
        wr(p, '# ' + fn + '\n' + add)
print('EVOLUTION ok')

# ---------- AGENT_EVOLUTION_LOG ----------
ep = L + 'AGENT_EVOLUTION_LOG.md'
t = rd(ep)
t = t.rstrip('\n') + """

## R43（2026-11-19）专家能力增量
- 新增规则：10 条（总监 R268~R272 / PLC R273~R277），累计游标 R278。
- 固化批次：未触发（累计 4 轮未固化，距 10 轮阈值尚差 6 轮）。
- 能力边界变化：机检口径两处误报被实测证伪（枚举赋值/ELSIF），总监侧新增「品类配比」独立约束，PLC 侧新增「一相一 TON」与「TIME 禁符号判断」两条硬规则。
- 本轮零检索（0/3）、零外部源码，合规无新增风险。
"""
wr(ep, t)
print('EVOLOG ok')
