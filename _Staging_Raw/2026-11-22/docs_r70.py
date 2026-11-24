# -*- coding: utf-8 -*-
"""R70 docs + evolution increments (append-only, no full rewrite)."""
import io, os, re, datetime

LIB = r"C:\Library"
TS = "2026-11-22"
TOTAL, SFT, VER = 1199, 1231, "v2.62.0"
CNT = {"DL_Base":151,"DL_MathData":286,"DL_Algo":135,"DL_Device":218,"DL_Motion":124,"DL_Process":285}

def rd(p): return io.open(p, encoding="utf-8").read()
def ap(p, s):
    with io.open(p, "a", encoding="utf-8") as f: f.write(s)

# ---------- README: badge + summary line (in-place field replace, append summary) ----------
p = os.path.join(LIB, "README.md"); s = rd(p)
s = s.replace("Total%20Components-1189%20%2F%2010%2C000", "Total%20Components-1199%20%2F%2010%2C000")
s = s.replace("Total%20Components-1,189", "Total%20Components-1,199")
s = s.replace("SFT%20Corpus-1221%20records", "SFT%20Corpus-1231%20records")
s = re.sub(r"^> \*\*Total Components: [\d,]+ / 10,000 \([\d.]+%\)\*\*.*$",
           "> **Total Components: 1,199 / 10,000 (11.99%)** ｜ **Phase 2: 常态节奏 10~20 件/轮（R60 起按 R249/R193/R362 动态下调）** ｜ **Version: v2.62.0** ｜ **SFT 语料: 1,231 条** ｜ **全库约 238,000 行**",
           s, count=1, flags=re.M)
r70 = ("\n> **R70（2026-11-22）**：**10/20 如实少报**（R362 超时判据配额 13→10，未注水）——10 新件（MathData 3：ModPosWrap·LerpClamped·ScaleRangeWatch｜Process 2：BatchDoseSeq·PumpAlternationLead｜Device 3：ValveSeatLeakTest·ConveyorJamDetect·CabinetTempDerate｜Motion 1：AxisSoftLimitGuard｜Base 1：RecipeStepExec）；"
       "总库 1,189→**1,199**（151/286/135/218/124/285），SFT **1,231**（+10），机检 10/10 PASS（dl_gate MAJOR 0/BLOCK 0）；零检索轮（WebSearch 0/3）。"
       "**值守突破**：RuSTy（PLC-lang v1.0.8）真编译器已下载就位（122MB），但因本机缺 UCRT API-set 转发 DLL（`api-ms-win-crt-*.dll`）暂不可执行，L2 编译闸仍未开（连欠 7 轮，修法已定位：装 VC++2015-2022 运行库或 KB2999226）。\n")
anchor = "\n> **R69（2026-11-22）**"
s = s.replace(anchor, r70 + anchor, 1)
io.open(p, "w", encoding="utf-8").write(s)
print("README ok")

# ---------- CHANGELOG ----------
p = os.path.join(LIB, "CHANGELOG.md"); s = rd(p)
entry = """## v2.62.0 — 2026-11-22（R70 构建轮）
- 新增 10 件（全部 v1.0.0，2,075 行）：
  - `DL_MathData`（+3）：`FC_DL_ModPosWrap`（MOD 负数归正 + 模数零域闸）｜`FC_DL_LerpClamped`（线性插值 t 域钳位，禁外推）｜`FB_DL_ScaleRangeWatch`（工程量标定区间越界监视，回差 + 延时确认）
  - `DL_Process`（+2）：`FB_DL_BatchDoseSeq`（预/快/慢/落料/校验五相定量给料，欠重超重分码）｜`FB_DL_PumpAlternationLead`（多泵运行小时选主 + 故障切备 + 周期轮换）
  - `DL_Device`（+3）：`FB_DL_ValveSeatLeakTest`（压降保持 + 温度修正判定）｜`FB_DL_ConveyorJamDetect`（无件流 + 电流双判据）｜`FB_DL_CabinetTempDerate`（多点取最大 + 分级线性降额 + 失效保持窗）
  - `DL_Motion`（+1）：`FB_DL_AxisSoftLimitGuard`（减速距离预判 + 越限方向禁止 + 反向放行退出）
  - `DL_Base`（+1）：`FB_DL_RecipeStepExec`（步推进/步超时/暂停续步/跳步拒绝，单定时器逐相 PT 解耦）
- 合计 1,199 / 10,000；SFT 语料 1,231 条（+10，bad=0）；机检 10/10 PASS。
- 已知偏差：`nErrCode` 统一 UDINT（码段 16#0002_xxxx 为 32 位，WORD 域不足，已写入各件头注释）；L2 真编译闸未开（RuSTy 就位待 UCRT）。

"""
if "## v2.62.0" not in s:
    i = s.find("## v2.61.0")
    s = s[:i] + entry + s[i:] if i > 0 else s + "\n" + entry
    io.open(p, "w", encoding="utf-8").write(s)
print("CHANGELOG ok")

# ---------- VERSION (touched sublibraries) ----------
touch = {"DL_MathData": ("FC_DL_ModPosWrap（MOD 负数归正）｜FC_DL_LerpClamped（插值钳位）｜FB_DL_ScaleRangeWatch（标定区间监视）", 286),
         "DL_Process": ("FB_DL_BatchDoseSeq（五相定量给料）｜FB_DL_PumpAlternationLead（泵轮换主备）", 285),
         "DL_Device": ("FB_DL_ValveSeatLeakTest（阀座压降试验）｜FB_DL_ConveyorJamDetect（堵料双判据）｜FB_DL_CabinetTempDerate（柜温降额）", 218),
         "DL_Motion": ("FB_DL_AxisSoftLimitGuard（软限位守卫）", 124),
         "DL_Base": ("FB_DL_RecipeStepExec（配方步序执行器）", 151)}
for cat, (items, total) in touch.items():
    p = os.path.join(LIB, cat, "VERSION.md"); s = rd(p)
    vs = re.findall(r"^## v(\d+)\.(\d+)", s, re.M)
    if vs:
        maj, mi = int(vs[0][0]), int(vs[0][1]) + 1
    else:
        maj, mi = 1, 0
    if "（R70 追加）" in s:
        continue
    ap(p, "\n## v%d.%d — %s（R70 追加）\n- 新增：%s。\n- 子库累计 %d 件。\n" % (maj, mi, TS, items, total))
print("VERSION ok")

# ---------- SOURCE_HUNTING_MATRIX: R70 row ----------
p = os.path.join(LIB, "SOURCE_HUNTING_MATRIX.md")
ap(p, "\n| R70 | %s | 零检索轮（WebSearch 0/3）| lgf-math×1｜lgf-measurement×1｜s7motion×1｜isa88×1｜packml×1｜ne107×1｜t0-std-wrapper×1｜self-std×3 = 10 | T0 八组维持 8/8（包装补口 1 件）；无 ☐→◐ 开组、无整组收口（收口率仍 9/27）；撞名三查零拒单（10 候选全过，均对 registry 实时精确匹配）|\n" % TS)
print("MATRIX ok")

# ---------- ROADMAP: 小结（不补待办，55>30） ----------
p = os.path.join(LIB, "ROADMAP.md")
ap(p, """
## R70 构建轮小结（%s）

> **R70 小结**：10 新件（MathData 3 / Device 3 / Process 2 / Motion 1 / Base 1），总库 1,189→**1,199**，v2.62.0，SFT 1,221→**1,231**，机检 10/10 PASS。配额 10（R362 超时判据 −20%），对 20 目标如实少报，零注水。待办 55 > 30，本轮不补写新待办。
> **R71 待办（P0）**：① **L2 编译闸修复**（RuSTy 已下载 `C:\\Library\\_tools\\rusty\\plc.exe`，缺 UCRT API-set 转发 DLL；装 VC++2015-2022 x64 运行库后跑 `plc.exe --help` 验证，通即可对存量件抽样真编译）；② `FB_DL_ScaleRangeWatch` 若上位机量程下发为 0 时换算段是否结构早退（本轮组态闸仅判 rawMax-rawMin，需复核量程零域）；③ 值守：oss_harvest GITHUB_TOKEN 单仓试跑｜MatIEC CI 71 方言件裁决。
""" % TS)
print("ROADMAP ok")

# ---------- EVOLOG ----------
p = os.path.join(LIB, "AGENT_EVOLUTION_LOG.md")
ap(p, """
## R70 专家能力增量（%s）
- 新增规则 8 条：PLC R367~R370 / 总监 R371~R374，游标 **R374**。
- 固化窗口：FB-51 后第 10 轮，累计候选 14 条 ≥10 达窗；固化需改写库外 Skill 规范文件（写入根契约外），继续转维护方落库（与 R68 6 条、R69 5 条合并为 25 条待固化包）。
- 能力边界变化：① 「语料 CoT 必须与代码段结构逐条对应」成为收口硬检项（本轮主控自查发现 3 条 CoT 描述了代码中不存在的相状态机，已改正）；② 真编译器接入路径由「无解」推进为「单点缺 DLL」，L2 闸进入可预期闭环。
""" % TS)
print("EVOLOG ok")

# ---------- Expert evolution ledgers ----------
p = os.path.join(LIB, "_EXPERT_EVOLUTION", "PLC_EXPERT_EVOLUTION.md")
ap(p, """
- [R367] 单定时器逐相 PT | BatchDoseSeq 五相若各建 TON 会跨相累计剩余时间 | 多实例=隐式状态残留 | 相状态机统一用**一个** TON 实例 + 逐相 `_tPhasePt` 预置（每拍先给缺省 PT），把「剩余时间跨相继承」从设计上消灭。
- [R368] 非有限筛查跨平台 | LREAL 判 NaN 用平台 `IS_FINITE` 不可移植（部分平台无此函数） | 可移植性优先 | 改用幅值上限常量（如 `1.0E30`）比较筛查，配合「末次良好值 + 是否曾有好值」双标志，避免 0.0 冒充真实值。
- [R369] 码段位宽与输出类型 | `nErrCode : WORD` 配 16#0002_xxxx 32 位码段，常量超域必编译失败 | 类型是域约束不是习惯 | 码段定 32 位则输出必须 UDINT；若坚持 WORD 则码段必须 ≤16#FFFF，二选一且写进头注释。
- [R370] 断线保持窗 | 传感器全失效时沿用上次值若无窗口会长期用陈旧值判安全 | 保持≠安全 | 失效保持必须带 `tHoldMax` 窗口 + 超窗转最坏情况（降额到最低/报警），窗口参数须组态闸非正拦截。
""")
p2 = os.path.join(LIB, "_EXPERT_EVOLUTION", "DIRECTOR_EVOLUTION.md")
ap(p2, """
- [R371] 配额与硬顶 | 上轮 70 分钟超顶后本轮若仍按 13 件必然再超 | 超时是配额问题不是执行问题 | 超顶后**下一轮配额立即 −20%** 并在 ROUND_PLAN 首行写明来源轮次（R362 落地验证：本轮 10 件 22 分钟完成）。
- [R372] 语料保真 | CoT 写「相状态机」而代码为判据链（本轮 3 条） | 语料错误比代码错误更难发现 | 收口前对每条新增语料**提取代码实际段标题/ENUM 名**回填 CoT，禁止凭选题意图书写架构描述。
- [R373] 真编译器选型 | MatIEC 无 Windows 预编译包长期阻塞 L2 闸 | 选型错则债永挂 | 改用 RuSTy（PLC-lang，Apache-2.0，Windows 单文件 exe），下载经 ghfast 镜像（直连 GitHub release 约 20KB/s，镜像 8MB/45s）。
- [R374] 运行库依赖 | 单文件 exe 仍可能依赖 UCRT API-set 转发 DLL，精简 Windows 镜像缺 `api-ms-win-crt-*` | 「单文件」不等于「零依赖」 | 接入外部二进制前先跑 `--help` 验证可执行性，失败即刻记录缺失 DLL 名并转值守项，不得计入「已具备」。
""")
print("EVOLUTION ok")
