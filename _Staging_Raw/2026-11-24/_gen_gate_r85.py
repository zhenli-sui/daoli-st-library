# -*- coding: utf-8 -*-
"""Assemble GATE_R85.md from verified artifacts. Read-only w.r.t. all .st sources."""
import io, json

R = r"C:\Library\_Staging_Raw\2026-11-24"
rows = json.load(io.open(R + r"\_r85_rows.json", encoding="utf-8"))
l1 = json.load(io.open(R + r"\_l1_r85.json", encoding="utf-8"))
l2 = json.load(io.open(R + r"\_l2_r85.json", encoding="utf-8"))
man = json.load(io.open(R + r"\_r85_manifest.json", encoding="utf-8"))
import hashlib as _h
comb = _h.sha256("".join(m["sha256"] for m in man).encode()).hexdigest()

npass = sum(1 for r in rows if r[5] == "PASS")
n = len(rows)
pct = round(100.0 * npass / n, 1)

L = []
w = L.append
w("`L2 PASS %d / FAIL 0 / EXEMPT 0 ｜ 通过率 %s%%`" % (npass, pct))
w("")
w("# GATE R85 — 编译验证席裁决（道莅工业代码库工厂）")
w("")
w("> 裁决人：编译验证席（一票否决）｜日期 2026-11-24｜轮次 R85｜待裁 %d 件（全部新增，registry 内零重叠）" % n)
w("> **结论：PASS —— 准予入库**（L1 全清、L2 %d/%d 串行可复现；零豁免；另列 41 项非阻断挂账）" % (npass, n))
w("> **但 L3 向量门 0/%d 覆盖，本裁决仅证明「能编译」，不证明「行为正确」。**" % n)
w("")
w("---")
w("")
w("## 0. 方法学与可复现（先披露两次作废运行 + 一次并发写入事件）")
w("")
w("### 0.1 【重要】被裁件在我编译期间仍在被并发改写")
w("")
w("**第一次 L1/L2 跑完（L2 落盘 19:06:46）后，我发现 40 件的 mtime 仍在推进至 19:09:43**，"
  "且经 SHA-256 比对确认**内容确实在变**（19:08→19:09:43 间至少 9 件内容变更，含 R527 所在的 "
  "`FB_DL_LadlePourWeightCtrl`）。即我的首版裁决建立在**移动靶**上，已作废。")
w("")
w("处置：轮询至连续 2 个 12 秒周期无内容变化（末次写 19:09:43），随后**冻结内容指纹并全量重跑 L1+L2**，"
  "本报告全部结论均基于该稳定快照。")
w("")
w("**认证快照指纹**：40 件 SHA-256 逐件清单见 `_r85_manifest.json`；合并指纹 "
  "`sha256(all)=%s…`。后续若任一被裁件内容变动，本裁决即自动失效，须重跑。" % comb[:16])
w("")
w("> ⚠ 对主控的提醒：若编码席仍在改 R85 文件，请**先停止写入再请求验收**；"
  "否则任何编译裁决都只能代表某一瞬间。建议注册闸同时校验该合并指纹。")
w("")
w("### 0.2 我自己的两次调用失误（已作废）")
w("")
w("本轮我自己的调用失误产生过两次**完全虚假**的全 FAIL 结果，已作废并重跑，此处如实留痕，"
  "以免后人误引数字：")
w("")
w("| 运行 | 命令形态 | 结果 | 判定 |")
w("|---|---|---|---|")
w("| #1 | `l2_check.py --round R85` + `tr '\\n' ' '` 传参 | `TOTAL=42 PASS=0 FAIL=42` | **作废**：①`--round` 非该脚本参数，被当成 2 个目标文件；②路径文件为 CRLF，`tr` 后残留 `\\r`，40 个路径全部指向不存在文件，rc=1 且 stderr 为空 |")
w("| #2 | `xargs -a paths` 传参 | `TOTAL=40 PASS=0 FAIL=40` | **作废**：`xargs` 吞掉反斜杠，路径被拼成 `LibraryDL_ProcessFC_DL_...` |")
w("| #3 | Python 驱动直接调 `l2_check.main()`，路径原样传 | `PASS=40 FAIL=0 TOTAL=40 jobs=1` | **采信**：串行 jobs=1，连跑两次同结果 |")
w("")
w("有效运行的命令（可逐字复现）：")
w("")
w("```bash")
w("# L1（复用 dl_gate.gate_file，逐件，不改源码）")
w("python C:\\Library\\_Staging_Raw\\2026-11-24\\_l1_driver_r85.py")
w("# L2（串行 jobs=1，严禁 --jobs>1）")
w("python C:\\Library\\_Staging_Raw\\2026-11-24\\_l2_driver_r85.py")
w("```")
w("")
w("**闸门有效性负向对照（证明「能 FAIL」而不是空转）**——这是 100% 通过率可信的前提：")
w("")
w("| 注入缺陷（副本，不改源件） | 期望 | 实测 |")
w("|---|---|---|")
w("| 删 `END_IF` | 解析报错 | `E006 Missing expected Token [KeywordEndIf...]` ✅ |")
w("| 插 `FOR i := 1 DOWNTO 1` | 复现库级缺陷 | `E007 Unexpected token: expected KeywordTo but found DOWNTO` ✅ |")
w("| 注入未声明标识符 `superTempVar` | 符号解析报错 | `E048 Could not resolve reference to superTempVar` ✅ |")
w("")
w("三条对照全部命中 → L2 %d/%d PASS 不是假阴性。**另：`DOWNTO` 在 40 件中出现 0 次**"
  "（`grep -rin DOWNTO` 空），故已知库级缺陷 E007 本轮不触发。" % (npass, n))
w("")
w("---")
w("")
w("## 1. 逐件裁决表")
w("")
w("| 序号 | 名称 | 类型/复杂度 | L1 | L2 | 错误码 | 根因 | 建议动作 |")
w("|---|---|---|---|---|---|---|---|")
for r in rows:
    w("| %d | `%s` | %s/C%d | %s | %s | %s | %s | %s |" % tuple(r))
w("")
w("> L1 判据：`PASS` = 无 BLOCK/MAJOR；`MAJOR→MINOR` 见 §3.2（我依据证据主动降级，非工具原判）。"
  "L2 判据：RuSTy 1.0.8 `--check` rc==0，串行 jobs=1。")
w("")
w("---")
w("")
w("## 2. FAIL 件最小修法清单")
w("")
w("**无 FAIL 件。** L2 %d/%d 通过，无可执行修法需要回派编码席。" % (npass, n))
w("")
w("---")
w("")
w("## 3. 非阻断挂账（允许入库，但须本轮或下轮清）")
w("")
w("### 3.1 【族级 · %d/%d 件】文件头缺 `VERSION: x.y.z`（L1 `VER_HEADER` MINOR）" % (n, n))
w("")
w("**这是本轮最值得单列的系统性缺陷：40 件无一例外全部缺失。** 按检查项 #11，"
  "版本头必须存在且与 registry `version` 一致——现 40 件均为新增件（registry 内零重叠），"
  "若注册时补 `version` 而源码无版本头，将直接演化为 `VER_MISMATCH`（MAJOR，阻断）。")
w("")
w("最小修法（**已实测有效**，见下）：在头注释 `Complexity:` 行之后插入一行")
w("")
w("```iecst")
w("  VERSION   : 1.0.0            (* 版本 / Version *)")
w("```")
w("")
w("**关键坑（本轮实测发现）**：`dl_gate.py` 的 VERSION 正则只扫**文件前 1200 字符**。"
  "4 个 C4 件（`FB_DL_QuenchTemperLineSeq` / `FB_DL_AnodizeLineTransferSeq` / "
  "`FB_DL_DieCastCycleSupervise` / `FB_DL_SugarPanBatchSeq`）头注释长达 1559 字符，"
  "**若按直觉补在头注释末尾 `*)` 之前，仍会被判 `VER_HEADER` 缺失**。"
  "统一插在 `Complexity:` 行后（字符位 85–167，恒 <1200）方为安全解。")
w("")
w("验证证据（在副本上试改，源件未动）：`FC_DL_WortExtractYieldCalc` 与 "
  "`FB_DL_QuenchTemperLineSeq` 插入后 `VER_HEADER` 消失、verdict=PASS。")
w("")
w("### 3.2 【1 件】`FB_DL_LadlePourWeightCtrl` L67 `R527_TON_CROSS_PHASE`（工具判 MAJOR，**我裁定 MINOR**）")
w("")
w("工具原判：`tonPourTo` 的 `IN` 为跨相 OR（`eFast OR eSlow`），疑似「本相超时」被误作「累计看门狗」。")
w("")
w("**但该件已三重声明意图为「全程累计超时」，规则自身文本亦允许此豁免口径**"
  "（规则原文：*须注释声明为累计看门狗或拆两个 TON*）：")
w("")
w("- L10 `边界条件 ③：浇注**全程**有超时监控`")
w("- L34 `tPourTo : TIME; (* 浇注**全程**超时 [ms] Pouring overall timeout *)`")
w("- L49 `tonPourTo: TON; (* 浇注**全程**超时（专用超时件） / Pouring timeout *)`")
w("")
w("行为核验：L67 每拍无条件刷新（合规，未置于 IF/CASE 内）；相位回 `Idle/Done/Fault` 时 "
  "IN=FALSE → 定时器复位，故每个浇注循环获得完整 `tPourTo` 预算，Fast→Slow 期间累计不误复位——"
  "**这正是「全程超时」的正确语义，无隐患**。")
w("")
w("裁定：**MINOR（注释口径）**，不阻断。建议最小修法：把 L34/L49 注释词改为「累计看门狗 / "
  "accumulated watchdog」以与规则口径对齐（零行为变更），或促使 `R527` 识别「全程/累计/overall/watchdog」"
  "声明后降为 WARN（见 §4.4）。")
w("")
w("---")
w("")
w("## 4. 静态闸 selftest 与锚点命中明细")
w("")
w("### 4.1 selftest")
w("")
w("```")
w("python C:\\Library\\_tools\\dl_gate.py --selftest   →   SELFTEST PASS")
w("```")
w("")
w("15 例全过：10 反例（unclosed_if / cross_end / case_no_else / gvl / direct_io / nested_comment / "
  "missing_decl / out_no_assign / end_var_missing / var_external）全部 BLOCK 命中，5 正例全 PASS。")
w("**无假阳性**，故本轮 L1 结论采信。")
w("")
w("> ⚠ 工具缺口：我的职责要求回归集 **≥20 例**（10 反 + 10 正），现仅 **15 例**（10 反 + 5 正）。"
  "正例覆盖不足意味着「判据过严」类假阳性风险未充分被回归网兜住。建议补 5 个正例，"
  "尤其覆盖：多 TON 累计看门狗、含 `DOWNTO` 的合法件（现行编译器不支持，应作 EXEMPT 正例）、"
  "带装饰性 `========*)` 长头注释件。")
w("")
w("### 4.2 四个指定锚点")
w("")
w("| 锚点 | 命中 | 说明 |")
w("|---|---|---|")
w("| `R509_FOR_DOWNTO` (BLOCK) | **0 件** | 40 件 `grep -rin DOWNTO` 为空。已用注入对照证明该锚点在 RuSTy 1.0.8 上确会报 `E007`，属真实可触发缺陷，非规则空转 |")
w("| `R525_UNIT_LABEL_INVERTED` | **0 件** | 40 件无 `RAD_TO_DEG`/`DEG_TO_RAD` 型名实不符常量 |")
w("| `R526_CONST_ZERO_REF` (WARN) | **0 件** | 无「声明后零引用」常量 |")
w("| `R527_TON_CROSS_PHASE` (MAJOR) | **1 件** | `FB_DL_LadlePourWeightCtrl` L67；经证据核验降级 MINOR，见 §3.2 |")
w("")
w("### 4.3 我补做的两项闸外检查（`dl_gate.py` 覆盖不到）")
w("")
w("**(a) 码段唯一 / 编号家族冲突**——`dl_gate` 仅在「name 已在 registry」时比对码段，"
  "本轮 40 件全是新增件，仓内比对**必然空转**。我改为对 40 件彼此 + 对 registry 全表比对：")
w("")
w("- 精确码段冲突（`16#XXXX_YYYY`）：**无**")
w("- 族前缀冲突（`16#0020`–`16#0030`）：**无**，11 个 FB 各占一族，一族一件，干净")
w("- 与 registry 现有码段冲突：**无**")
w("")
w("**(b) 29/40 件无任何错误码**——逐件核查后**判定非缺陷**（见 §5.2），未误判。")
w("")
w("### 4.4 工具链改进建议（须先跑 selftest 回归，不得无回归改判据）")
w("")
w("1. `DECL_UNKNOWN_TYPE` 白名单缺口（**129 条 WARN，全部为假阳性**）：`TON`(58)、`R_TRIG`(27)、"
  "及本文件内自声明 `E_DL_*` 枚举(44)。L2 全通过即证其合法。建议：白名单纳入 IEC 标准功能块，"
  "并让 gate 识别同文件 `TYPE ... END_TYPE` 声明。")
w("2. `R527` 精度：命中「全程/累计/overall/watchdog」声明时降 MAJOR→WARN，否则每轮把所有累计看门狗件误报。")
w("3. `VER_HEADER` 的 1200 字符窗口偏窄，长装饰头注释件（C4）会被误判为「未补版本」。建议扫首个 `*)` 之前全文。")
w("4. selftest 正例补至 ≥10 例（见 §4.1）。")
w("")
w("---")
w("")
w("## 5. 库级 / 族级共性问题（本轮最有价值产出）")
w("")
w("### 5.1 【确认缺陷 · 40/40 · 100%】VERSION 头全族缺失")
w("")
w("见 §3.1。这是唯一确认为真实、且覆盖全批的缺陷。**建议注册闸前置校验：源码无版本头则拒绝写 registry**，"
  "否则「注册时有版本、源码无版本」将批量生成 `VER_MISMATCH`。")
w("")
w("### 5.2 【已核查 · 排除 · 29 件】「无错误码」不是缺陷")
w("")
w("29 件无错误码，分两类，均已核到规范依据，**不判缺陷**：")
w("")
w("- **25 个 FC 为纯计算函数**（如 `FC_DL_WortExtractYieldCalc : REAL`），无 `bError`/`uErrId` 出口，"
  "与 registry 内 `FC_DL_CalcMoveTime` 等纯算件同型，符合库风格。")
w("- **4 个 C4 状态机 FB** 有 `bError`（赋值 6–7 处）但无 `uErrId`。我一度疑为缺陷，"
  "但实测 **registry 内 929 个已注册 FB 中仅 19 个（2.0%）含 `uErrId`** → 「无事件码」是库内绝对主流规范，"
  "故不判缺陷。**此处特意记录我的排除推理，避免后续轮次重复误报。**")
w("")
w("（非阻断建议：4 个 C4 件仅布尔 `bError`、无事件码，现场运维定位能力偏弱，可考虑后续补码段；"
  "但这是**增强**而非缺陷。）")
w("")
w("### 5.3 【工具侧 · 129 条】`DECL_UNKNOWN_TYPE` 全量假阳性")
w("")
w("见 §4.4-1。**风险提示**：若后续有人「按 WARN 清零」的直觉去改这些类型声明，会破坏合法 IEC 语法。"
  "建议直接在 gate 修，勿动源码。")
w("")
w("---")
w("")
w("## 6. 豁免件清单")
w("")
w("**零豁免。**")
w("")
w("40 件无一件需要援引「编译器不支持合法 IEC 语法」口径：`DOWNTO` 出现 0 次，"
  "其余件全部在 RuSTy 1.0.8 直接编译通过。**零豁免为最理想结果，且本轮未为追求零豁免而放水**——"
  "`R527` 是真命中，我按证据降级而非无视；3 条负向对照亦证明闸门未空转。")
w("")
w("---")
w("")
w("## 7. 置信度声明")
w("")
w("| 维度 | 结论 | 可信度 |")
w("|---|---|---|")
w("| L1 静态闸 | 39 PASS + 1 MAJOR（降 MINOR） | **高**：selftest 15/15 无假阳性 |")
w("| L2 真编译闸 | %d/%d PASS，串行 jobs=1，连跑 2 次同结果 | **高**：3 条负向对照全部能 FAIL；已排除并行 E004 假阳性 |" % (npass, n))
w("| L3 向量门 | **0/%d 未覆盖** | **低**：`_TESTS\\` 下无任何本批向量，行为正确性完全未验证 |" % n)
w("| 码段唯一性 | 无冲突 | **高**：已做批内 + registry 双向比对 |")
w("")
w("**因此**：本裁决对「能否编译入库」负责，判定 **PASS**；"
  "对「能否上机运行」**不负责**，需补 L3。建议优先为 4 个 C4 状态机（`FB_DL_QuenchTemperLineSeq`、"
  "`FB_DL_AnodizeLineTransferSeq`、`FB_DL_DieCastCycleSupervise`、`FB_DL_SugarPanBatchSeq`）"
  "与含除零/非有限路径的计算 FC 生成向量，覆盖：组态非法、除零、非有限、边界钳位、复位路径、状态机兜底。")
w("")
w("---")
w("")
w("## 8. 注册闸指令")
w("")
w("按我的职责边界，本次 `verdict = PASS`，**注册脚本可放行**，但附两条硬条件：")
w("")
w("1. 写入 registry 前，必须为 40 件补齐 `VERSION` 头（§3.1 修法），并令 registry `version` 与之一致；"
  "否则下一轮 L1 将批量报 `VER_MISMATCH`（MAJOR）。")
w("2. `FB_DL_LadlePourWeightCtrl` 的 L34/L49 注释口径按 §3.2 微调（零行为变更）。")
w("")
w("*本报告未修改任何 `.st` 源码、未写 registry/JSONL。所有数字可由 §0 命令复现。*")

io.open(R + r"\GATE_R85.md", "w", encoding="utf-8").write("\n".join(L) + "\n")
print("written GATE_R85.md lines", len(L))
