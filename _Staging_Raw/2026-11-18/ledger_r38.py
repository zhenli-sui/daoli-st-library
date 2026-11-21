# -*- coding: utf-8 -*-
"""R38 台账回写：SOURCE_HUNTING_MATRIX 台账行 + AGENT_EVOLUTION_LOG R38 节（追加式）"""
import io, os, json, re

LIB = 'C:/Library'
STAGE = os.path.join(LIB, '_Staging_Raw', '2026-11-18')
reg = json.load(io.open(os.path.join(LIB, 'INDEX_REGISTRY.json'), encoding='utf-8'))
TOT = reg['total_components']

# 矩阵台账行（追加在 R37 行之后，格式与既有行一致）
p = os.path.join(LIB, 'SOURCE_HUNTING_MATRIX.md')
t = io.open(p, encoding='utf-8').read()
row = ("| R38 | 零检索轮（7 续作 + 13 新，20 件） | t1-2 OSCAT 暖通语义（VAV 标定 / 经济器 / 再热级联 / 步进风阀）+ t1-5 TcOpen 按钮组 + "
       "t1-6 PLCopen 定向停止 / CamSwitch + t2-1 LGF 数学-工艺-测量三子组（整定/换热/反射比/鼓胀）+ t2-2 LBP 回弹学习 + "
       "t2-4 S7 Motion 时延/振荡 + t2-7 PackML 状态模型 | 20 件（SaturateAdd / ToggleButtonBank / LinearRegression2Var / OscillationIndex / "
       "PidLambdaTune / HeatExchangerLmtd / CrossCorrelationDelay / SpindleOrientationStop / ElectronicCamSwitchBank / VavBoxZeroCal / "
       "ElectrodeTabBendCtrl / JunctionBoxPottingCheck / PouchSwellingGauge / FreshAirStepperDamper / HeatSealProfile / AhuEconomizer / "
       "TerminalReheatSeq / RfReflectedMonitor / StringSolderQuality / ModuleLamVacuumSeq）◐ 深化；**DL_Base 码位体系首开（01_0_00 起）**、"
       "06_0 段进 B 带、03_2 进位 12 段；T0 真池新探 2 件（Saturate/Toggle 词干零命中） |\n")
if '| R38 |' not in t:
    t = t.rstrip('\n') + '\n' + row
    io.open(p, 'w', encoding='utf-8', newline='').write(t)
print('MATRIX ok')

# 进化日志 R38 节
p = os.path.join(LIB, 'AGENT_EVOLUTION_LOG.md')
t = io.open(p, encoding='utf-8').read()
sec = """
### R38（2026-11-18 · 7 续作 + 13 新件轮）

- 产能：20 件单窗口完成，`DL_Base` 码位体系首开（`01_0_00` 起），六子库同轮全部有增量（Base +2 / MathData +2 / Algo +3 / Motion +2 / Device +5 / Process +6）。
- 质量：机检 20/20 与终审抽检结果见 `BATTLE_REPORT_R38.md`；返修 2 件（LineShaftClutch 脱开权重快照 / CurtainEFEMZone 间隙计时重启）闭环。
- 规则增量：见两本进化账本「R38」节（总监线 + PLC 线），游标续推。
- 能力边界：ROADMAP 未勾 183 条中 138 名为已注册件（勾选漏账），「未勾 ≠ 未建」成为选题阶段第一道口径闸——本轮据此剔除 6 条伪缺口。
"""
if '### R38（2026-11-18' not in t:
    t = t.rstrip('\n') + '\n' + sec
    io.open(p, 'w', encoding='utf-8', newline='').write(t)
print('EVOLOG ok', TOT)
