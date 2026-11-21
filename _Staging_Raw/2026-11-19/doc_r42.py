# -*- coding: utf-8 -*-
"""R42 文档增量收口：README / CHANGELOG / VERSION×2 / ROADMAP / MATRIX / EVOLOG / 双账本（全部追加式）"""
import io, os, glob

LIB = "C:/Library"

def rd(p): return io.open(p, encoding="utf-8").read()
def wr(p, t): io.open(p, "w", encoding="utf-8", newline="\n").write(t)

# ---- 1. README.md 数字行 ----
lines_dl = sum(len(io.open(f, encoding="utf-8", errors="ignore").read().splitlines()) for f in glob.glob(os.path.join(LIB, "DL_*", "*.st")))
rm = os.path.join(LIB, "README.md")
t = rd(rm)
t = t.replace("Total%20Components-725%20%2F%2010%2C000", "Total%20Components-745%20%2F%2010%2C000")
t = t.replace("SFT%20Corpus-725%20records", "SFT%20Corpus-745%20records")
t = t.replace("**Total Components: 725 / 10,000**", "**Total Components: 745 / 10,000**")
t = t.replace("**Version: v2.33.0**", "**Version: v2.34.0**")
t = t.replace("**SFT 语料: 725 条**", "**SFT 语料: 745 条**")
t = t.replace("**全库约 152,922 行**", "**全库约 %s 行**" % format(lines_dl, ","))
wr(rm, t)
print("README ok, dl_lines=", lines_dl)

# ---- 2. CHANGELOG.md 顶部前插 v2.34.0 ----
cp = os.path.join(LIB, "CHANGELOG.md")
t = rd(cp)
sec = """## v2.34.0 — 2026-11-19（R42 / Process+Device 偏科轮 20 新件 + 4 返修 + 终审当场修 2 件）

### Added（20 新件：DL_Process +15 / DL_Device +5）
- DL_Process（+15）：FB_DL_OcvProbeDock / FB_DL_FramingPressSeq / FB_DL_BinderFeederSeq / FB_DL_SafetyDoorAuditBank / FB_DL_GlassFeederAccum / FB_DL_WaferCountPreset / FB_DL_SeasonMonthSched / FB_DL_HydronicMeterAudit / FB_DL_PipeScannerRoute / FB_DL_RecipeSearchFifo / FB_DL_PollAuditBank / FB_DL_CassetteMapVerify / FB_DL_PalletGripperSafe / FB_DL_ElTestStation / FB_DL_HeatExchangerFoulingTrend
- DL_Device（+5）：FB_DL_RobotArmVibrationWatch / FB_DL_RoofUnitDoorSw / FB_DL_FilmSpliceCurtain / FB_DL_DamperBitDiag / FB_DL_BmsPdiGateway

### Fixed（6 件 v1.0.1）
- FB_DL_ConveyorDirMismatch（R41 挂账 P0 当轮修）/ FB_DL_AxisInposGuard / FB_DL_CascadeWindupLink / FB_DL_AxisAbortSafeSeq（R41 终审挂账）
- FB_DL_ElTestStation（R42 终审当场修：锁存相位迁移闸缺失，0397 解除式不可达）/ FB_DL_HydronicMeterAudit（R42 终审当场修：_eState 漏声明编译阻断 + 饱和锁存后 eRun 不冻结）

### 总库
- registry 725→745（v2.34.0），JSONL 745 条（badjson=0，NEW20 20/20 MATCH，返修重注入 6/6）；机检 24/24 PASS + 终审返修 2/2 PASS。

---

"""
t = t.replace("## v2.33.0", sec + "## v2.33.0", 1)
wr(cp, t)
print("CHANGELOG ok")

# ---- 3. DL_Process/VERSION.md 追加 v1.17.0 ----
vp = os.path.join(LIB, "DL_Process", "VERSION.md")
sec = """
## v1.17.0 — 2026-11-19（R42：+15 新件 + 3 件 v1.0.1 返修）

### Added（15 新件，批次 1~4）
批次 1：FB_DL_OcvProbeDock / FB_DL_FramingPressSeq / FB_DL_BinderFeederSeq / FB_DL_SafetyDoorAuditBank
批次 2：FB_DL_GlassFeederAccum / FB_DL_WaferCountPreset / FB_DL_SeasonMonthSched / FB_DL_HydronicMeterAudit / FB_DL_PipeScannerRoute
批次 3：FB_DL_RecipeSearchFifo / FB_DL_PollAuditBank / FB_DL_CassetteMapVerify / FB_DL_PalletGripperSafe / FB_DL_ElTestStation
批次 4：FB_DL_HeatExchangerFoulingTrend

### Fixed（3 件 v1.0.1，对外引脚契约不变）
- FB_DL_ConveyorDirMismatch：R41 终审挂账 P0 当轮修（沿直连 TON.IN 致 036D/036E 检出不可达）。
- FB_DL_ElTestStation：R42 终审当场修——新增段 4A 故障锁存相位迁移闸：0397/0398/0399 锁存后 _eState 强制迁 eFault，断 tonCamTo 跨锁存期 IN 保持（否则复位清锁后下一拍立即重锁，解除式不可达），并冻结 eTrig/eMap 相内归档副作用。
- FB_DL_HydronicMeterAudit：R42 终审当场修——补声明内部相位变量 _eState（首版漏声明，编译阻断，机检盲区）+ 段 4A 迁移闸：0385/0386/0387 锁存后强制入 eFault，冻结 eRun 相内累计递增（否则饱和锁存后 fEnergyKwh 持续越限增长）。

### 已知挂账（返修池）
- FB_DL_CassetteMapVerify：轻——04BA 失配检出沿与 04BB 首错定位沿同拍互斥，04BA 在出口不可观测（头注释已声明后到优先）；0392 组态锁存期间相位不迁 eFault（eIdle 相无副作用，无冻结需求）。R43 起排程。

### 计数
- 组件 161→176；码位段 0005 窗口 0385~0399 / 04AD~04C1 零冲突（全文口径实扫）。
"""
t = rd(vp)
if not t.endswith("\n"): t += "\n"
wr(vp, t + sec)
print("VERSION_Process ok")

# ---- 4. DL_Device/VERSION.md 追加 v1.17.0 ----
vd = os.path.join(LIB, "DL_Device", "VERSION.md")
sec = """
## v1.17.0 — 2026-11-19（R42：+5 新件）

### Added（5 新件，批次 4）
- FB_DL_RobotArmVibrationWatch：晶圆传送机械手振动特征监视（高通分量 + 特征窗分级）
- FB_DL_RoofUnitDoorSw：屋顶机检修门-风机联锁（重启抑制轻量组态）
- FB_DL_FilmSpliceCurtain：接膜工位光幕屏蔽序列（2 传感器模式屏蔽时序）
- FB_DL_DamperBitDiag：风阀执行器位诊断打包/解包（位段提取 + 位打包复用）
- FB_DL_BmsPdiGateway：楼宇侧 PDI 对象网关轮询（复用 PDI 调度 + 异常上报）

### 码位
- Device 05xx 副带首次启用（首开分段理由已逐件落头注释，R192 落地）；全文口径实扫零冲突。

### 计数
- 组件 140→145；机检 5/5 PASS。
"""
t = rd(vd)
if not t.endswith("\n"): t += "\n"
wr(vd, t + sec)
print("VERSION_Device ok")

# ---- 5. ROADMAP.md 勾选 20 件 ----
rp = os.path.join(LIB, "ROADMAP.md")
t = rd(rp)
NAMES = ["FB_DL_OcvProbeDock","FB_DL_FramingPressSeq","FB_DL_BinderFeederSeq","FB_DL_SafetyDoorAuditBank",
"FB_DL_GlassFeederAccum","FB_DL_WaferCountPreset","FB_DL_SeasonMonthSched","FB_DL_HydronicMeterAudit",
"FB_DL_PipeScannerRoute","FB_DL_RecipeSearchFifo","FB_DL_PollAuditBank","FB_DL_CassetteMapVerify",
"FB_DL_PalletGripperSafe","FB_DL_ElTestStation","FB_DL_HeatExchangerFoulingTrend","FB_DL_RobotArmVibrationWatch",
"FB_DL_RoofUnitDoorSw","FB_DL_FilmSpliceCurtain","FB_DL_DamperBitDiag","FB_DL_BmsPdiGateway"]
checked = 0
for n in NAMES:
    new_t = t.replace("- [ ] `%s`" % n, "- [x] `%s`" % n, 1)
    if new_t != t:
        checked += 1
        t = new_t
wr(rp, t)
print("ROADMAP checked =", checked)

# ---- 6. SOURCE_HUNTING_MATRIX.md 追加 R42 行 ----
mp = os.path.join(LIB, "SOURCE_HUNTING_MATRIX.md")
row = "| R42 | 零检索轮（Process 15 : Device 5 偏科轮，不跨池凑数） | 池深化：roadmap-pv-p2（EL 检测）+ roadmap-semi-p2（花篮 Mapping）+ roadmap-li-p1（OCV 探针台）+ t2-2-lbp（装框/供料/积放/分输）+ t2-8-isa182（安全门/光幕屏蔽）+ t1-2-oscat-building（季切换/水系审计/结垢/RTU 门联锁）+ t1-3-oscat-network（轮询台账）+ t1-4-codesys-forge（配方 FIFO/BMS PDI）+ t2-7-packml（码垛夹手安全）+ t2-6-rockwell-aoi（机械手振动）+ t2-1-lgf（计数预置/风阀位诊断） | 20 件（OcvProbeDock / FramingPressSeq / BinderFeederSeq / SafetyDoorAuditBank / GlassFeederAccum / WaferCountPreset / SeasonMonthSched / HydronicMeterAudit / PipeScannerRoute / RecipeSearchFifo / PollAuditBank / CassetteMapVerify / PalletGripperSafe / ElTestStation / HeatExchangerFoulingTrend / RobotArmVibrationWatch / RoofUnitDoorSw / FilmSpliceCurtain / DamperBitDiag / BmsPdiGateway）◐ 深化；触及源组 ☐→◐；Device 05xx 副带首开；终审 3 抽 2 当场修 v1.0.1 |\n"
t = rd(mp)
if not t.endswith("\n"): t += "\n"
wr(mp, t + row)
print("MATRIX ok")

# ---- 7. AGENT_EVOLUTION_LOG.md 追加 R42 节 ----
ep = os.path.join(LIB, "AGENT_EVOLUTION_LOG.md")
sec = """
## R42（2026-11-19 · 20 新件（Process 15/Device 5）+ 4 返修 + 终审收尾）
- 20 新件全落盘（registry 725→745 / v2.34.0，counts Base 83 / MathData 197 / Algo 74 / Device 145 / Motion 70 / Process 176），JSONL 745（badjson=0、NEW20 20/20 MATCH、4 返修重注入 MATCH）；机检 24/24 PASS（含 R228A/B、ENUM 冒号、占位符、「同上」禁词 29 处拦截、码位全文口径碰撞零冲突）。
- 4 件 R41 挂账返修 v1.0.1 当轮完成（ConveyorDirMismatch 严重 / AxisInposGuard / CascadeWindupLink / AxisAbortSafeSeq）并重注入。
- 终审 3 抽（复杂度最高件）：ElTestStation 严重（锁存后相位不迁 eFault，tonCamTo IN 跨锁存期保持 → 0397 复位后下拍重锁，解除式不可达；R252 家族第 3 变体）与 HydronicMeterAudit 编译阻断（_eState 漏声明，机检盲区）+ 饱和锁存后 eRun 不冻结——两件当场修至 v1.0.1（头注释返修节 + registry + JSONL 原地重注入三处记账闭合）；CassetteMapVerify 轻（04BA 同拍被 04BB 覆盖出口不可观测）记返修池。
- Process 15:5 Device 偏科按池余量如实分配不跨池凑数；Device 05xx 副带首开分段理由落头注释；「同上」残留 29 处机检拦截（R92 第 2 次复发）。
- 进化游标：PLC R258~R262 / 总监 R263~R267，共 10 条；R43 计划：全库码位普查第 4 次挂账转正（P0 首位）、编译验证债开启、返修池 CassetteMapVerify、常态 20 件→765。
"""
t = rd(ep)
if not t.endswith("\n"): t += "\n"
wr(ep, t + sec)
print("EVOLOG ok")

# ---- 8. PLC_EXPERT_EVOLUTION.md 追加 ----
plc = os.path.join(LIB, "_EXPERT_EVOLUTION", "PLC_EXPERT_EVOLUTION.md")
sec = """
## R42（2026-11-19）新经验 5 条（游标 R258 起）
- [R258] 终审缺陷族 | FB_DL_ElTestStation 0397/0398 锁存后 _eState 不迁 eFault：tonCamTo IN=(相位=eTrig) 跨锁存期保持 TRUE，复位清锁后下一拍 Q 恒 TRUE 立即重锁 → 解除式不可达；且 0399 锁存期间 eTrig→eMap 归档计数照常递增（严重，当场修 v1.0.1） | R252 家族第 3 变体：故障锁存与相位机脱钩，锁存只改 bError 不改相位 | 新规则：锁存置位必须同步迁相，或段尾固定加「IF _bFault AND (_eState<>eFault) THEN _eState:=eFault」迁移闸（置于解除段之后防同拍抢迁）；带 TON 的相锁存必须断 IN
- [R259] 机检盲区 | FB_DL_HydronicMeterAudit 段 4/CASE 引用 _eState 但 VAR 区漏声明，机检 24/24 PASS 照过——结构正则不查标识符声明完备性（编译阻断级，当场补声明修 v1.0.1） | 机检只能抓已固化形态，「引用未声明变量」属语义层缺口 | 新规则：机检新增「_eState 引用必查声明」条目；CASE/解除段引用的内部状态量纳入「声明完备性」抽检清单
- [R260] 模板残留 | 24 件模板句「同上」残留 29 处被机检 BANNED-WORD 全数拦截（R92 第 2 次复发） | 模板复制不删提示词是高频复发债，机检兜底有效但每轮都浪费返修动作 | 新规则：「同上/待补充/TODO」三词全文自查固化为落盘前最后一步，机检命中即返修不挂账
- [R261] 码位纪律 | Device 05xx 副带首次启用，与子库既有码段不连续 | R192 要求新开码段写明分段理由，首开件是分段理由唯一落点 | 新规则：新开码段首件头注释必须含「分段理由」句，随件归档（R192 落地件）
- [R262] 正面案例 | 2 件终审当场修三处记账一次闭合（头注释返修节 + registry 版本/行数 + JSONL 原地重注入 FIXED 2/2），badjson=0 | 当场修复路径已可复制，返修不产生语料漂移 | 新规则：终审当场修固定按「改码→改头注释→registry→JSONL 重注入→机检复跑」五步链执行，缺步即视为未收口
"""
t = rd(plc)
if not t.endswith("\n"): t += "\n"
wr(plc, t + sec)
print("PLC ledger ok")

# ---- 9. DIRECTOR_EVOLUTION.md 追加 ----
dr = os.path.join(LIB, "_EXPERT_EVOLUTION", "DIRECTOR_EVOLUTION.md")
sec = """
## R42（2026-11-19）新经验 5 条（游标 R263 起）
- [R263] 工具缺陷 | 首版选题脚本首列名提取错位（列名提取未行首锚定，误读相邻列） | 派单表脚本产出必须先自校表头，否则错列静默流入派单 | 新规则：选题/派单脚本列名提取一律行首锚定正则；脚本产出先打印表头自校再发单
- [R264] 选题纪律 | 本轮 Process 15 : Device 5 偏科按两池余量如实分配，未跨池凑数 | 跨池凑数会制造同义变体与低质件（R244 续） | 新规则：单轮子库配比 = 池余量真实比例，余量不足如实少报转 ROADMAP，禁跨池凑件
- [R265] 预算归因 | 编码 36 分钟逼近窗顶，主因 = 复杂度 6 件占比过高（可行动因子：件复杂度 × 串行编码） | R196 可行动归因要求同步砍件动作，不能只记时长 | 新规则：单轮编码超 30 分钟即触发砍件——复杂度 6 件降为 4 件或延后，阈值写入派单模板
- [R266] 终审方法 | 3 抽 2 挂账均当场修复（迁移闸缺失 + 声明缺失），当场修五步链一次闭合；CassetteMapVerify 轻缺陷记池不当场改 | 「严重可修当场修、轻微记账」分流避免了超时 | 新规则：「锁存相位迁移闸缺失」列为终审第 6 式（锁存置位点与相位机联动检查）；声明完备性列为抽检项
- [R267] 产量节奏 | 今日 4 轮 75/200；总库 745/10,000（7.45%），距 500 目标已超额 +245 | 常态 20 件/轮 + 3~4 轮/日节奏可持续，瓶颈在终审与编译债不在选题 | 新规则：R43 常态 20 件→765；全库码位普查第 4 次挂账转正 P0 首位，编译验证债同步开启（R195 闸）
"""
t = rd(dr)
if not t.endswith("\n"): t += "\n"
wr(dr, t + sec)
print("DIRECTOR ledger ok")
