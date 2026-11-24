# -*- coding: utf-8 -*-
"""R68 文档增量：README 徽章+摘要行 / CHANGELOG 节 / 5xVERSION / 4xMANUAL 注记（全追加式/替换式）"""
import io, re

LIB = r"C:\Library"


def rd(p):
    return io.open(p, encoding="utf-8").read()


def wr(p, s):
    io.open(p, "w", encoding="utf-8", newline="").write(s)


# ---------- 1. README ----------
p = LIB + r"\README.md"
s = rd(p)
pairs = [
    ("Total%20Components-1163", "Total%20Components-1179"),
    ("DL--Base-145", "DL--Base-148"),
    ("DL--MathData-278", "DL--MathData-280"),
    ("DL--Device-207", "DL--Device-213"),
    ("DL--Motion-121", "DL--Motion-122"),
    ("DL--Process-278", "DL--Process-282"),
    ("SFT%20Corpus-1190", "SFT%20Corpus-1206"),
    ("**Total Components: 1,163 / 10,000 (11.63%)**", "**Total Components: 1,179 / 10,000 (11.79%)**"),
    ("**Version: v2.59.0**", "**Version: v2.60.0**"),
    ("**SFT 语料: 1,190 条**", "**SFT 语料: 1,206 条**"),
]
for a, b in pairs:
    assert s.count(a) >= 1, a
    s = s.replace(a, b)

r68 = (
    "> **R68（2026-11-22）**：16 新件（Base 3：联锁旁路全生命周期审计·时钟漂移监视·诊断码文本查表｜"
    "MathData 2：字节序组装/拆解双向对｜"
    "Device 6：流量计 K 系数漂移（§19.6 漂移件重建）·视觉相机健康看门狗·视觉光源组·星型卸料器·变极双速电机·控制柜热管理｜"
    "Process 4：缠绕膜顺控·室外气温重置·窑压定值控制·车辆过磅顺控｜Motion 1：轴上电自检）；"
    "**收口 3 处就地修**（三件 METHOD 补 END_METHOD / TruckScale 段 7 皮毛槽镜像输出）；"
    "**终审 5+1 抽 + 定向全量扩面：就地修 9 件 10 处 v1.0.1**（8 件同型「组态锁存解除路径不可达」+ 2 处死路径：超时重测每拍清窗 / 总圈计数 255 闸），挂账 7 项转 R69；"
    "总库 1,163→**1,179**（148/280/134/213/122/282），SFT **1,206** 条（bad=0），机检 16/16 PASS，零检索轮（9 组取材，撞名拒 20 条含精确同名 3 条）。\n"
)
m = re.search(r"> \*\*R67（2026-11-22）\*\*.*?\n", s)
assert m, "R67 summary not found"
s = s[: m.end()] + r68 + s[m.end():]
wr(p, s)
print("README OK")

# ---------- 2. CHANGELOG ----------
p = LIB + r"\CHANGELOG.md"
s = rd(p)
sec = """## v2.60.0 — 2026-11-22（R68 十六件入册 + 收口 3 处就地修 + 终审 9 件 10 处 v1.0.1 ｜ 零检索轮）

### Added（16 件：DL_Base 3 / DL_MathData 2 / DL_Device 6 / DL_Process 4 / DL_Motion 1）
- DL_Base 3 件：`FB_DL_InterlockBypassAudit`（联锁旁路全生命周期审计：申请→时限→到期自动恢复 + 8 条环形事件台账 + 旁路计数 255 饱和）｜`FB_DL_ClockDriftMonitor`（本地 RTC vs 外部标准钟漂移率 [ms/h] 监视，回拨单列校钟事件）｜`FB_DL_DiagTextLookup`（诊断码→HMI 双语文本查表，越界默认行 + 255 截断四步样板）
- DL_MathData 2 件：`FC_DL_WordFromBytes` / `FC_DL_WordToBytes`（BYTE 数组 ↔ WORD/DWORD 双向，ABCD/CDAB/BADC/DCBA 四序，round-trip 逐字节验收；双向对，非凑数变体）
- DL_Device 6 件：`FB_DL_FlowMeterKFactorDrift`（**§19.6 已勾未注册漂移件重建**：K 回读比对 + 批次总量对拍 + 漂移折算 → NE107 分级）｜`FB_DL_CameraHealthWatch`（触发超时 / 心跳丢失 / NG 率趋势三判据独立确认窗）｜`FB_DL_VisionLightBank`（2~8 通道互斥仲裁 + 亮度保持 + 稳定延时）｜`FB_DL_RotaryAirlockCtrl`（星型卸料器：料位禁启 + 失速判据 + 反转点动解卡互斥）｜`FB_DL_TwoSpeedMotor`（变极双绕组：切换死区互锁 + 高速禁止位 + 反馈校验）｜`FB_DL_CabinetCoolingWatch`（柜内-环境温差 + 风扇双判据 + 滤网阻塞趋势）
- DL_Process 4 件：`FB_DL_StretchWrapSeq`（缠绕膜七态最小子集，圈数配方 + 圈边界暂停）｜`FB_DL_OutdoorTempReset`（OAT 线性重置供水设定 + 斜坡限速 + 最小水温联锁）｜`FB_DL_KilnPressureCtrl`（窑压定值闭环 + 抽力限幅 + 窑门扰动前馈）｜`FB_DL_TruckScaleSeq`（过磅七态 + 稳定窗判稳 + 皮毛配对台账 + 防作弊窗）
- DL_Motion 1 件：`FB_DL_AxisPowerOnSelfTest`（上电自检五步序检 + 结论锁存禁使能，轴状态零定义 R31）

### Fixed（收口期就地修 3 处）
- `FB_DL_InterlockBypassAudit` / `FB_DL_ClockDriftMonitor` / `FB_DL_TruckScaleSeq`：METHOD 块补 `END_METHOD`（编码期引用的 DolMotor 先例失实，METHOD 块原缺闭合词）
- `FB_DL_TruckScaleSeq`：段 7 补 `fTareLatched` / `fGrossLatched` 槽镜像输出（原漏赋值）

### Fixed（R68 终审就地修 9 件 10 处 → v1.0.1，单文件机检 9/9 PASS）
- 同型「组态锁存解除路径不可达」（8 件）：`ClockDriftMonitor` / `CameraHealthWatch` / `VisionLightBank` / `FlowMeterKFactorDrift` / `RotaryAirlockCtrl` / `TwoSpeedMotor` / `TruckScaleSeq` / `AxisPowerOnSelfTest` —— 置锁存后不迁相而清零行只写在不可达的 `eFault` 相，补可达解除式（复位沿 + 组态改对），引脚与码位不变
- `FB_DL_TruckScaleSeq`：超时重测清窗单拍化（`TON.Q` 常真导致每拍清窗，判稳永不可达）
- `FB_DL_StretchWrapSeq`：总圈计数上限改用 510（原以单段上界 255 作总数闸，合法配方 >255 圈死锁）

### Changed
- registry v2.59.0 → **v2.60.0**，`total_components` 1,163 → **1,179**（148/280/134/213/122/282，sum 断言过）；9 件 `version` 升 1.0.1 并追加标签 `r68-postfix`
- SFT 语料 1,190 → **1,206** 条（+16 新件，bad=0）
- 子库 VERSION 节号按实测 +1（R311）：Device 实测 v1.29 → **v1.30**、Motion 实测 v1.27 → **v1.28**（任务书假设 v1.28 / v1.27 滞后一轮）
- 本轮零检索轮（WebSearch 0 次，连续第 5 轮），取材复用源矩阵既有组：isa182 / lgf-converter / lbp / packml / s7motion / tcopen / oscat-building / roadmap-industry-pool / self-std

"""
anchor = "## v2.59.0"
i = s.index(anchor)
s = s[:i] + sec + s[i:]
wr(p, s)
print("CHANGELOG OK")

# ---------- 3. VERSION x5 ----------
def append_version(cat, ver, body):
    p = LIB + "\\" + cat + r"\VERSION.md"
    s = rd(p)
    assert ("## " + ver) not in s, ver
    if not s.endswith("\n"):
        s += "\n"
    wr(p, s + "\n" + body)
    print("VERSION", cat, ver)


append_version("DL_Base", "v1.39", """## v1.39 — 2026-11-22（R68 追加）

- 新增 3 件：`FB_DL_InterlockBypassAudit`（旁路全生命周期审计：申请/解除/超时三类事件 8 条环形台账 + 旁路计数 255 饱和；联锁本体归 `FB_DL_InterlockMatrix`）｜`FB_DL_ClockDriftMonitor`（RTC vs 标准钟漂移率 [ms/h] + 需校钟标志，只监视不写钟）｜`FB_DL_DiagTextLookup`（诊断码→双语文本查表，VAR_IN_OUT 数组注入零全局耦合）。
- 终审就地修：`FB_DL_ClockDriftMonitor` v1.0.1（组态锁存解除路径可达化，原 eFault 相不可达）。
- 子库累计 148 件。
""")

append_version("DL_MathData", "v1.39", """## v1.39 — 2026-11-22（R68 追加）

- 新增 2 件：`FC_DL_WordFromBytes`（BYTE 数组→WORD/DWORD，四字节序 + 长度不足高段补零）｜`FC_DL_WordToBytes`（WORD/DWORD→BYTE 数组，与前者构成 round-trip 双向对）。
- 子库累计 280 件。
""")

append_version("DL_Device", "v1.30", """## v1.30 — 2026-11-22（R68 追加）

- 新增 6 件：`FB_DL_FlowMeterKFactorDrift`（**§19.6 已勾未注册漂移件重建**，K 回读 + 批次总量 + 折算三委托 → NE107 分级）｜`FB_DL_CameraHealthWatch`（视觉相机三判据健康看门狗）｜`FB_DL_VisionLightBank`（光源组通道互斥 + 亮度保持 + 稳定延时）｜`FB_DL_RotaryAirlockCtrl`（星型卸料器料位联动 + 失速保护 + 反转点动）｜`FB_DL_TwoSpeedMotor`（变极双速电机死区互锁 + 反馈校验）｜`FB_DL_CabinetCoolingWatch`（柜内热管理三判据）。
- 终审就地修（同型组态锁存解除不可达）：`FB_DL_FlowMeterKFactorDrift` / `FB_DL_CameraHealthWatch` / `FB_DL_VisionLightBank` / `FB_DL_RotaryAirlockCtrl` / `FB_DL_TwoSpeedMotor` 均升 **v1.0.1**。
- 节号说明（R311 实测 +1）：实测上一节为 v1.29（R66 追加），本轮取 v1.30。
- 子库累计 213 件。
""")

append_version("DL_Process", "v1.36", """## v1.36 — 2026-11-22（R68 追加）

- 新增 4 件：`FB_DL_StretchWrapSeq`（缠绕膜七态最小子集，圈数配方 + 圈边界暂停，PackML 全集归属主）｜`FB_DL_OutdoorTempReset`（OAT 重置供水设定 + 斜坡 + 最小水温联锁）｜`FB_DL_KilnPressureCtrl`（窑压定值闭环 + 抽力限幅 + 窑门前馈）｜`FB_DL_TruckScaleSeq`（过磅七态 + 稳定窗 + 皮毛配对台账）。
- 终审就地修：`FB_DL_TruckScaleSeq` v1.0.1（组态锁存解除可达化 + 超时重测清窗单拍化）｜`FB_DL_StretchWrapSeq` v1.0.1（总圈计数上限 255→510，消除合法配方死锁）。
- 子库累计 282 件。
""")

append_version("DL_Motion", "v1.28", """## v1.28 — 2026-11-22（R68 追加）

- 新增 1 件：`FB_DL_AxisPowerOnSelfTest`（轴上电自检五步序检：驱动就绪→编码器回读→限位巡检→故障字扫描→结论锁存；轴状态零定义，bTestOk 供 `FB_DL_SingleAxis` 使能链消费）。
- 终审就地修：v1.0.1（组态锁存解除路径可达化，原 bCfgLatch 全文件零清零 → 自检永久不可重测）。
- 节号说明（R311 实测 +1）：实测上一节为 v1.27（R66 追加），本轮取 v1.28。
- 子库累计 122 件。
""")

# ---------- 4. MANUAL 注记（4 库，追加式） ----------
manual_notes = {
    "MANUAL_DL_Base.md": "- `FB_DL_InterlockBypassAudit` / `FB_DL_ClockDriftMonitor` / `FB_DL_DiagTextLookup`（R68）：旁路审计 / 漂移监视 / 诊断文本查表；`ClockDriftMonitor` 于 R68 终审升 v1.0.1（组态锁存解除式补可达）。",
    "MANUAL_DL_Device.md": "- `FB_DL_FlowMeterKFactorDrift`（§19.6 重建）/ `FB_DL_CameraHealthWatch` / `FB_DL_VisionLightBank` / `FB_DL_RotaryAirlockCtrl` / `FB_DL_TwoSpeedMotor` / `FB_DL_CabinetCoolingWatch`（R68）：六件设备健康与驱动件；前五件于 R68 终审升 v1.0.1（同型组态锁存解除式补可达，对外引脚与码位不变）。",
    "MANUAL_DL_Process.md": "- `FB_DL_StretchWrapSeq` / `FB_DL_OutdoorTempReset` / `FB_DL_KilnPressureCtrl` / `FB_DL_TruckScaleSeq`（R68）：包装顺控 / OAT 重置 / 窑压控制 / 过磅称重；`StretchWrapSeq` 与 `TruckScaleSeq` 于 R68 终审升 v1.0.1（总圈上限 510 / 超时清窗单拍化），引脚契约不变。",
    "MANUAL_DL_Motion.md": "- `FB_DL_AxisPowerOnSelfTest`（v1.0.1，R68）：上电自检五步序，`bTestOk` 供使能链消费；R68 终审补组态锁存解除式（原不可重测）。",
}
for f, note in manual_notes.items():
    p = LIB + "\\" + f
    s = rd(p)
    if not s.endswith("\n"):
        s += "\n"
    wr(p, s + "\n## R68 新增件与终审就地修（2026-11-22）\n\n" + note + "\n")
    print("MANUAL", f)
