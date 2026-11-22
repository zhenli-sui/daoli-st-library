# -*- coding: utf-8 -*-
"""R72 docs: README / CHANGELOG / VERSION×5 / MATRIX / EVOLOG / ROADMAP 全增量追加."""
import json, os, re, datetime, io

LIB = r"C:\Library"
TODAY = "2026-11-23"

def read(p): return open(p, encoding="utf-8").read()
def write(p, s): open(p, "w", encoding="utf-8", newline="\n").write(s)

reg = json.load(open(os.path.join(LIB, "INDEX_REGISTRY.json"), encoding="utf-8"))
total = reg["total_components"]; counts = reg["counts"]; ver = reg["version"]
jl = sum(1 for _ in open(os.path.join(LIB, "_AI_Training_Dataset", "daoli_st_sft_dataset.jsonl"), encoding="utf-8"))
lines_sum = sum(c.get("line_count", 0) for c in reg["components"])
print("registry", total, counts, ver, "sft", jl, "lines", lines_sum)

# ---- README ----
p = os.path.join(LIB, "README.md")
s = read(p)
s = s.replace("Total%20Components-1206%20%2F%2010%2C000-blue", "Total%20Components-1218%20%2F%2010%2C000-blue")
s = s.replace("Level%200%20DL--Base-152%20open-success", "Level%200%20DL--Base-154%20open-success")
s = s.replace("Level%200%20DL--MathData-288%20open-success", "Level%200%20DL--MathData-294%20open-success")
s = s.replace("Level%201%20DL--Device-220%20open-yellow", "Level%201%20DL--Device-221%20open-yellow")
s = s.replace("Level%201%20DL--Motion-125%20open-yellow", "Level%201%20DL--Motion-126%20open-yellow")
s = s.replace("Level%202%20DL--Process-286%20open-yellow", "Level%202%20DL--Process-288%20open-yellow")
s = s.replace("SFT%20Corpus-1239%20records-informational", "SFT%20Corpus-1252%20records-informational")
old_bold = re.search(r"> \*\*Total Components: [^\n]*\n", s).group(0)
new_bold = ("> **Total Components: %d / 10,000 (%.2f%%)** ｜ **Phase 2: 常态节奏 10~20 件/轮（R60 起按 R249/R193/R362 动态下调）** ｜ "
            "**Version: v%s** ｜ **SFT 语料: %d 条** ｜ **全库约 %s 行**\n") % (
    total, total/100.0, "2.64.0", jl, "{:,}".format(lines_sum))
s = s.replace(old_bold, new_bold)
r72_line = ("> **R72（%s）**：**13/20 如实少报**——12 新件（MathData 5：IntModChk·FiniteClassify·ArrayCumSumLreal·CharCodeConvert·WordToBinString·HmsToTodChk｜"
            "Base 2：DaysInMonthChk·BlinkOutput｜Device 1：OilLevelWatch｜Motion 1：ToolChangerSeq（C3）｜Process 2：RejectBlowCtrl·SipLineSterilSeq）"
            "+ 1 点修（AirSpecificVolume v1.0.1 补 bValid 全回执，E032/R381 首用）；总库 1,206→**1,218**（154/294/135/221/126/288），SFT **1,252**，"
            "机检 13/13 PASS，L2 闸 12/13 PASS（OilLevelWatch 为 INTERFACE-PROPERTY 覆盖面缺口①，不改码）；零检索轮（WebSearch 0/3），撞名拒 14 条。\n") % TODAY
anchor = "> **R66（2026-11-22）**"
assert anchor in s
s = s.replace(anchor, r72_line + "\n" + anchor, 1)
write(p, s); print("README ok")

# ---- CHANGELOG ----
p = os.path.join(LIB, "CHANGELOG.md")
s = read(p)
entry = """## v2.64.0 — 2026-11-23（R72 十二件入册 + AirSpecificVolume v1.0.1 契约级点修 ｜ 零检索轮）

### Added（12 件：DL_MathData 5 / DL_Base 2 / DL_Device 1 / DL_Motion 1 / DL_Process 2 / DL_Algo 0 避让）
- DL_MathData 5 件：`FC_DL_IntModChk`（DINT 取模防御包装：除零闸 + DINT_MIN/−1 溢出面拦截）｜`FC_DL_FiniteClassify`（LREAL 非有限四态分类原子，R79 判据原子化全库首件）｜`FC_DL_ArrayCumSumLreal`（数组前缀累计序列，双遍扫描 + 守卫计数器；LGF 统计线借鉴）｜`FC_DL_CharCodeConvert`（单字符↔码双向，码域/串长域闸）｜`FC_DL_WordToBinString`（WORD→16 字符定长二进制文本，MSB-first SHL 掩码法）｜`FC_DL_HmsToTodChk`（时/分/秒合成 TOD，钳位照算 + 属主件委托全回执）
- DL_Base 2 件：`FC_DL_DaysInMonthChk`（年月→当月天数，闰年律复用 LeapYearChk 单源；承诺段与属主窗口求交 [1998,2099]）｜`FB_DL_BlinkOutput`（方波闪烁：tOn/tOff 独立两相 + 零值组态锁存防静默失效；OSCAT BLINK 行为定义借鉴）
- DL_Device 1 件：`FB_DL_OilLevelWatch`（油位双阈值迟滞监视：非有限安全侧收紧 + NE107 出口 + 电平式解除双路）
- DL_Motion 1 件：`FB_DL_ToolChangerSeq`（换刀机构顺控 C3：取刀/换刀/回库六相 + 互锁保持相防半程掉刀 + 逐相超时；与 TurretToolSelect 分工）
- DL_Process 2 件：`FB_DL_RejectBlowCtrl`（剔除气吹执行时序：布防延时换算 + 确认窗复验 + 漏剔/误剔对账）｜`FB_DL_SipLineSterilSeq`（管路 SIP 灭菌顺控：保温跌破回升温从零重计，无菌保证不断点续计）

### Fixed
- `FC_DL_AirSpecificVolume` v1.0.1：段 5 属主件调用补第 6 形参回执 `bValid => _bPwsVld`（E032 编译合规，契约级修复行为零变更，R381 新规首用）；同族复核另报 8 处省略式调用挂账（R333 只挂账不改码）。

### Tooling
- L2 闸 stub 补齐：`INT_TO_UINT`/`UINT_TO_INT` 标准换算声明 + `CONCAT__STRING`/`MID__STRING` 重整名声明（RuSTy 泛型外部桩实例化缺口，闸侧资产不属库交付物）。

"""
anchor = "## v2.63.0"
assert anchor in s
s = s.replace(anchor, entry + anchor, 1)
write(p, s); print("CHANGELOG ok")

# ---- VERSION ×5 ----
ver_add = {
 "DL_MathData": ("v1.33", "- `FC_DL_IntModChk` / `FC_DL_FiniteClassify` / `FC_DL_ArrayCumSumLreal` / `FC_DL_CharCodeConvert` / `FC_DL_WordToBinString` / `FC_DL_HmsToTodChk` 六件入册（T0 防御包装 4 + LGF 统计线 1 + 组态入口 1）；`FC_DL_AirSpecificVolume` v1.0.1 点修（补 `bValid => _bPwsVld` 全 6 形参回执，E032 契约级修复行为零变更）。"),
 "DL_Base": ("v1.32", "- `FC_DL_DaysInMonthChk` / `FB_DL_BlinkOutput` 两件入册（日历原子复用 LeapYearChk 单源；OSCAT BLINK 行为定义借鉴，零值组态锁存防静默失效）。"),
 "DL_Device": ("v1.26", "- `FB_DL_OilLevelWatch` 入册（油位双阈值迟滞 + 非有限安全侧收紧 + NE107 出口）。"),
 "DL_Motion": ("v1.25", "- `FB_DL_ToolChangerSeq` 入册（C3，六相换刀顺控，互锁保持相防半程掉刀；与 TurretToolSelect 分工互引）。"),
 "DL_Process": ("v1.31", "- `FB_DL_RejectBlowCtrl` / `FB_DL_SipLineSterilSeq` 两件入册（气吹执行时序对账；SIP 保温跌破从零重计）。"),
}
for lib, (v, body) in ver_add.items():
    p = os.path.join(LIB, lib, "VERSION.md")
    s = read(p)
    s = s.rstrip("\n") + "\n\n## %s — %s（R72 追加）\n\n%s\n" % (v, TODAY, body)
    write(p, s)
print("VERSION x5 ok")

# ---- MATRIX ----
p = os.path.join(LIB, "SOURCE_HUNTING_MATRIX.md")
s = read(p)
r72_row = "| R72 | 2026-11-23 | 零检索轮（WebSearch 0/3）| iec-std-wrapper×6｜lgf-math×1｜t1-1-oscat-basic×1｜t2-6-rockwell-aoi×2｜t2-2-lbp×1｜s9-conv×1｜roadmap-t02-calendar×1 = 12 | T0 八组维持 8/8（族内补口 6 件）；无 ☐→◐ 开组、无整组收口（收口率仍 9/27）；撞名三查拒 14 条（含精确同名 6 条）；**两处台账备注勘误**：T2-8「NE107 仲裁件待挖」与 T1-6「凸轮动态修调待挖」属主实测在册改判已覆盖；L2 闸 12/13 PASS（1 例覆盖面缺口①）|"
anchor = "| R71 | 2026-11-22"
idx = s.find(anchor)
assert idx >= 0
line_end = s.find("\n", idx)
s = s[:line_end+1] + r72_row + "\n" + s[line_end+1:]
s = s.replace("NE107 仲裁件待挖", "NE107 仲裁件（R72 勘误：HealthAggregator 等属主在册，已覆盖）")
s = s.replace("凸轮动态修调待挖", "凸轮动态修调（R72 勘误：CamDynTrim 等属主在册，已覆盖）")
write(p, s); print("MATRIX ok")

# ---- EVOLOG ----
p = os.path.join(LIB, "AGENT_EVOLUTION_LOG.md")
s = read(p)
s = s.rstrip("\n") + """

## R72（2026-11-23）—— E032 同族清账启幕 + 闸侧 stub 缺口补齐范式

- **新增规则 +9**：PLC R387~R391（委托返回类型不得错接 BOOL 局部 / TON 调用严禁写进相分支 / 沿事件信息标志须保持域 / 锁存期台账记账对齐头注 / 承诺段必须与属主窗口求交且事实类禁钳位）｜总监 R392~R395（选题前置词根属主探测防假真空 / 归位随最近邻属主实测 category / 矩阵「待挖」取材前先验属主 / 挂账标识符按源码前缀族重命名），游标 **R395**。
- **L2 闸增量**：本轮 12 新件 + 1 点修 12/13 PASS；三类新缺口入册——stub 缺 INT_TO_UINT 类标准换算（补声明）、RuSTy 泛型外部桩不实例化（以重整名 CONCAT__STRING/MID__STRING 直接声明解决，闸侧资产）、依赖接口属主 ENUM 的 FB 命中覆盖面缺口①（OilLevelWatch，不改码）。同族省略式调用全库实测 133 调用点，VaporPressureSat 族 8 处缺 `bValid =>` 挂账 R73。
- **固化窗口**：FB-51 后第 11 轮，本轮增量 9 < 10 不固化；累计待固化候选 34 条转维护方。
- **能力边界变化**：「编码期自纠 → 账本 R 编号 → 当轮 CoT 回填」闭环连续第 3 轮稳定运行；L2 闸从「抽样资格」升级为「每轮交付资格项」（新件逐件过闸，缺口留档三类裁定）。
"""
write(p, s); print("EVOLOG ok")

# ---- ROADMAP 小结（不补写新待办，55>30）----
p = os.path.join(LIB, "ROADMAP.md")
s = read(p)
s = s.rstrip("\n") + """

## R72 构建轮小结（2026-11-23）

> **R72 小结**：12 新件（MathData 5 / Base 2 / Device 1 / Motion 1 / Process 2）+ 1 点修（AirSpecificVolume v1.0.1 E032 全回执），总库 1,206→**1,218**，v2.64.0，SFT 1,239→**1,252**，机检 13/13 PASS，L2 闸 12/13 PASS（OilLevelWatch 覆盖面缺口①留档）。零检索轮，撞名拒 14 条。对 20 目标如实少报 13，零注水。待办 55 > 30，本轮不补写新待办。
> **R73 待办（P0）**：① VaporPressureSat 族 8 处缺 `bValid =>` 回执点修（HumidityRatioCalc×2 / MixAirStateCalc / RhFromDewPoint×2 / DewPointToPpmV / NightPurgeCtrl×2）；② 扩展复核 ~20 处多出参 FC 零回执调用点挂账候审（DryerExhaustHumidityCtl / ChamberPurgeDry / WeightClassifySort 等，R333 口径）；③ L2 闸每轮交付资格项常态化；④ 值守三项顺延第 4 轮（oss_harvest token 试跑 / MatIEC 71 方言件 / GATE MAJOR 存量人核）。
"""
write(p, s); print("ROADMAP ok")
