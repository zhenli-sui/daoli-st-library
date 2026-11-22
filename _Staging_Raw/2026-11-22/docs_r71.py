# -*- coding: utf-8 -*-
"""R71 文档增量：README 徽章 / CHANGELOG / 5×VERSION.md / MATRIX 台账 / EVOLOG（全增量，不重写）。"""
import io, os, re, datetime

LIB = r"C:\Library"
TS = "2026-11-22"
TOTAL, SFT = 1206, 1239
C = {"DL_Base": 152, "DL_MathData": 288, "DL_Algo": 135, "DL_Device": 220, "DL_Motion": 125, "DL_Process": 286}

# ---------- 1. README 徽章（顺带修正 R70 遗留的分库徽章漂移） ----------
p = os.path.join(LIB, "README.md")
s = io.open(p, encoding="utf-8").read()
subs = [
    (r"Total%20Components-\d+%20%2F%2010%2C000", "Total%%20Components-%d%%20%%2F%%2010%%2C000" % TOTAL),
    (r"Level%200%20DL--Base-\d+%20open", "Level%%200%%20DL--Base-%d%%20open" % C["DL_Base"]),
    (r"Level%200%20DL--MathData-\d+%20open", "Level%%200%%20DL--MathData-%d%%20open" % C["DL_MathData"]),
    (r"Level%201%20DL--Algo-\d+%20open", "Level%%201%%20DL--Algo-%d%%20open" % C["DL_Algo"]),
    (r"Level%201%20DL--Device-\d+%20open", "Level%%201%%20DL--Device-%d%%20open" % C["DL_Device"]),
    (r"Level%201%20DL--Motion-\d+%20open", "Level%%201%%20DL--Motion-%d%%20open" % C["DL_Motion"]),
    (r"Level%202%20DL--Process-\d+%20open", "Level%%202%%20DL--Process-%d%%20open" % C["DL_Process"]),
    (r"SFT%20Corpus-\d+%20records", "SFT%%20Corpus-%d%%20records" % SFT),
]
n = 0
for pat, rep in subs:
    s, k = re.subn(pat, rep, s, count=1)
    n += k
io.open(p, "w", encoding="utf-8").write(s)
print("README badges patched", n, "/", len(subs))

# ---------- 2. CHANGELOG 前插 ----------
p = os.path.join(LIB, "CHANGELOG.md")
s = io.open(p, encoding="utf-8").read()
anchor = "## v2.60.0"
block = """## v2.63.0 — 2026-11-22（R71 七件入册 + ScaleRangeWatch v1.0.1 增益零域点修 ｜ 零检索轮 ｜ L2 真编译闸落地）

### Added（7 件：DL_MathData 2 / DL_Device 2 / DL_Base 1 / DL_Motion 1 / DL_Process 1）
- DL_MathData 2 件：`FC_DL_AirSpecificVolume`（湿空气比容 m³/kg 干空气；饱和压复用属主件 `FC_DL_VaporPressureSat` 常量单源，分母先判后除）｜`FC_DL_TriangleSolveSSS`（SSS 三边解角：三角不等式容差闸 + ACOS 入参钳位 + 三角和复验三闸）
- DL_Device 2 件：`FB_DL_AxisEncBatteryWatch`（绝对值编码器电池欠压监视：双阈值迟滞 + 输入非有限安全侧收紧 + NE107 分级出口）｜`FB_DL_PumpPrimingWatch`（离心泵灌泵期监视：双判据交叉验证 + 双定时器无条件刷新）
- DL_Base 1 件：`FC_DL_DurationFormat`（TIME 时长四分量分解，HMI 显示专用，常量除子级联零除零面）
- DL_Motion 1 件：`FB_DL_FlyingShearSync`（飞剪同步：测长→进窗→同步→剪切→退出五相，同步窗内线速失配即退相，不留给「带病下刀」路径）
- DL_Process 1 件：`FB_DL_LaneDivertCtrl`（道岔分流：到件→动作→尾件→恢复四相，失能回夹先于状态机）

### Fixed（PATCH 级点修）
- `FB_DL_ScaleRangeWatch` **v1.0.1**：补**增益零域**组态闸（`ABS(fGain) <= DL_SRW_GMIN`，GMIN=1.0E-15）——v1.0.0 在 `fGain=0.0` 时工程值被钉死在偏置值、上下限报警永久不触发且无故障码（保护静默失效）。码位沿用 `16#0002_0121` 不新开，不改引脚。

### Docs
- 徽章口径修正：分库徽章自 R70 起与 registry 漂移（合计 1,179 ≠ 1,199），本轮按 registry 实测重算回写（1,206 / 152·288·135·220·125·286 / SFT 1,239）。

"""
s = s.replace(anchor, block + anchor, 1)
io.open(p, "w", encoding="utf-8").write(s)
print("CHANGELOG prepended")

# ---------- 3. 五库 VERSION.md 追加 ----------
ver_new = {"DL_Base": "1.31", "DL_MathData": "1.32", "DL_Device": "1.25", "DL_Motion": "1.24", "DL_Process": "1.30"}
sec = {
 "DL_Base": "- R71 新增 1 件：`FC_DL_DurationFormat`（TIME → 天/时/分/秒 四分量，HMI 显示纯函数，常量除子级联零除零面，毫秒余量置 `bTruncated`）。累计 %d 件。" % C["DL_Base"],
 "DL_MathData": "- R71 新增 2 件：`FC_DL_AirSpecificVolume`（湿空气比容，饱和压复用属主件常量单源）｜`FC_DL_TriangleSolveSSS`（SSS 解角三闸）。\n- R71 点修 1 件：`FB_DL_ScaleRangeWatch` **v1.0.1** 增益零域组态闸（R70 挂账清）。累计 %d 件。" % C["DL_MathData"],
 "DL_Device": "- R71 新增 2 件：`FB_DL_AxisEncBatteryWatch`（编码器电池欠压监视，输入非有限安全侧收紧）｜`FB_DL_PumpPrimingWatch`（灌泵期双判据交叉验证）。累计 %d 件。" % C["DL_Device"],
 "DL_Motion": "- R71 新增 1 件：`FB_DL_FlyingShearSync`（飞剪同步五相，同步窗线速失配即退相）。累计 %d 件。" % C["DL_Motion"],
 "DL_Process": "- R71 新增 1 件：`FB_DL_LaneDivertCtrl`（道岔分流四相，失能回夹先于状态机）。累计 %d 件。" % C["DL_Process"],
}
for lib, v in ver_new.items():
    p = os.path.join(LIB, lib, "VERSION.md")
    s = io.open(p, encoding="utf-8").read()
    m = re.search(r"\n## v", s)
    head = ("## v%s — %s（R71）\n\n" % (v, TS)) + sec[lib] + "\n\n---\n"
    s = s[:m.start() + 1] + head + s[m.start() + 1:]
    io.open(p, "w", encoding="utf-8").write(s)
    print("VERSION", lib, "->", v)

# ---------- 4. MATRIX 台账一行 ----------
p = os.path.join(LIB, "SOURCE_HUNTING_MATRIX.md")
s = io.open(p, encoding="utf-8").read()
row = ("\n| R71 | 2026-11-22 | 零检索轮（WebSearch 0/3）| t1-2-oscat-building×1｜t1-6-plcopen×1｜t2-6-rockwell-aoi×1｜t2-1-lgf-math×1｜t2-2-lbp×1｜s9-conv×1｜iec-std-wrapper×1 = 7 "
       "| T0 八组维持 8/8（T0 族内补口 1 件 DurationFormat）；无 ☐→◐ 开组、无整组收口（收口率仍 9/27）；撞名三查拒 9 条（对 registry 实时精确匹配）；"
       "**本轮同时落地 L2 真编译闸（RuSTy 1.0.8）**，存量 20 件抽样 16 PASS（4 例为 INTERFACE/PROPERTY 覆盖面缺口）|\n")
if not s.endswith("\n"):
    s += "\n"
s += row
io.open(p, "w", encoding="utf-8").write(s)
print("MATRIX row appended")

# ---------- 5. EVOLOG 追加 ----------
p = os.path.join(LIB, "AGENT_EVOLUTION_LOG.md")
s = io.open(p, encoding="utf-8").read()
blk = """
## R71（2026-11-22）—— L2 真编译闸落地：从「文本推演」到「语义验证」

- **本轮最大能力增量**：连续 8 轮悬置的 L2 编译验证债清零。载体重建路径：MatIEC（无 Windows 预编译、本机无 C 工具链）→ 改选 **RuSTy 1.0.8**（PLC-lang，Apache-2.0，单文件 exe）；本机缺 UCRT API-set 转发库（`api-ms-win-crt-*` 全无 + 缺 vcruntime140）导致退出码 127，**用 vc_redist 内嵌 CAB 逐层 expand 取 app-local DLL 解决，无需管理员、无需安装**。
- **新增工具链资产**：`_tools\rusty\plc.exe` + `iec_std_stub.st`（{external} 标准件声明桩，泛型表达）+ `_tools\l2_check.py`（接口预筛 + 依赖自动回溯 + 只 --check）+ `_tools\README_L2_GATE.md`（操作与裁定口径）。
- **基线（R71 seed=71 n=20）**：PASS 16 / FAIL 4 = 80%；4 例全为 RuSTy 对 `INTERFACE` 内 `PROPERTY` 支持不全（IEC 61131-3 第 3 版合法语法），**判定为编译器覆盖面缺口，不改库内代码**。第二类缺口：RuSTy 要求输出形参全给（E032），而全库普遍采用省略式调用（CODESYS/TwinCAT 均允许）。
- **规则增量（+6）**：R375 L2 闸裁定三分法（真缺陷 / 桩缺口 / 编译器覆盖面缺口，三者处置不同）｜R376 声明桩只声明不实现、不入 registry｜R377 app-local 依赖优先于系统目录，是免装修复的首选路径｜R378 编译器缺口不得驱动改码（防为过闸而牺牲跨平台合规）｜R379 抽样 seed 取日期保证可复现｜R380 全库抽样每日 ≤1 次，与「机检只扫增量」同口径。
- **专家进化条数**：PLC +3（R381~R383：输出形参省略的移植风险 / 常量除子级联优于变量除 / 反余弦域钳位必要性）｜总监 +3（R384~R386：编译器缺口裁定权归主控 / 徽章口径必与 registry 同源重算 / 点修须先对账「挂账描述 vs 源码事实」）。
- 累计新增规则：本轮 +6（R375~R380），游标 **R386**。
"""
s = s.rstrip() + "\n" + blk
io.open(p, "w", encoding="utf-8").write(s)
print("EVOLOG appended")
