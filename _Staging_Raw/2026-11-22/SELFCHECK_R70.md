# SELFCHECK_R70 —— 道莅代码库 R70 构建轮 自检报告

- 构建轮次：R70（唯一一次编码调用，未召唤任何子代理，未并行交错写同一文件）
- 落盘日期：2026-11-22
- 版本：全部 1.0.0
- 目标件数：10 ｜ 实际落盘：10 ｜ 失败：0
- 总行数：2075 行
- 未改动：INDEX_REGISTRY.json / *.jsonl / README / ROADMAP / 任何文档（收口由主控脚本执行，本报告为唯一新增文档）

## 一 逐件清单（文件名 / 路径 / 行数 / 复杂度 / 来源标签）

| # | 文件名 | 路径 | 行数 | 复杂度 | 来源标签 |
|---|--------|------|------|--------|----------|
| 1 | FC_DL_ModPosWrap.st | C:\Library\DL_MathData\ | 89 | 2 | iec-std-wrapper |
| 2 | FC_DL_LerpClamped.st | C:\Library\DL_MathData\ | 125 | 2 | self-std |
| 3 | FB_DL_ScaleRangeWatch.st | C:\Library\DL_MathData\ | 183 | 3 | lgf-math |
| 4 | FB_DL_BatchDoseSeq.st | C:\Library\DL_Process\ | 310 | 3 | isa88 |
| 5 | FB_DL_PumpAlternationLead.st | C:\Library\DL_Process\ | 250 | 3 | self-std |
| 6 | FB_DL_ValveSeatLeakTest.st | C:\Library\DL_Device\ | 280 | 3 | lgf-measurement |
| 7 | FB_DL_ConveyorJamDetect.st | C:\Library\DL_Device\ | 154 | 2 | self-std |
| 8 | FB_DL_AxisSoftLimitGuard.st | C:\Library\DL_Motion\ | 198 | 3 | s7motion |
| 9 | FB_DL_RecipeStepExec.st | C:\Library\DL_Base\ | 235 | 3 | packml |
| 10 | FB_DL_CabinetTempDerate.st | C:\Library\DL_Device\ | 251 | 2 | ne107 |

目录存在性：DL_MathData / DL_Process / DL_Device / DL_Motion / DL_Base 五个目录事前已确认存在，无新建目录动作。

## 二 7 项红线逐件逐项核对

符号说明：✔ = 通过（附判定依据），N/A = 本件结构上不适用（附理由）。

通用判定依据（全部 10 件一致适用，下文只写差异项）：
- 红线 ①「零 GVL / 零 VAR_EXTERNAL」：脚本 grep `g_[A-Za-z]`、`VAR_EXTERNAL` 均无命中（头注释中的「零 VAR_EXTERNAL」文字为**文档声明句**，非代码引用，已人工确认）。
- 红线 ②「零物理地址」：grep `%I`、`%Q`、`%M` 全库零命中。
- 红线 ③「纯 IEC 61131-3」：仅使用 BOOL/INT/DINT/UDINT/LREAL/TIME/ARRAY/ENUM 与标准库 TON、R_TRIG；grep `__[A-Za-z]` 零命中（无 `__ISVALIDREF` 等双下划线扩展）、grep `\bAS\b` 零命中（无 AS 方言转换）。
- 红线 ⑤「逐变量双语注释」：脚本逐行扫描全部 VAR / VAR_CONSTANT / TYPE 段，无一例缺注释（0 命中）。输出变量不加 `_` 前缀、FB 内部变量一律 `_` 前缀，脚本核对通过。
- 红线 ⑦「定时器/沿实例无条件调用」：脚本比对「实例声明名 vs `_xxx(...)` 调用名」，10 件全部 inst == calls，无遗漏：
  ScaleRangeWatch(_rtReset,_tonHigh,_tonLow)｜BatchDoseSeq(_rtStart,_rtReset,_tonPhase)｜PumpAlternationLead(_rtReset,_tonRotate)｜ValveSeatLeakTest(_rtStart,_rtReset,_tonPhase)｜ConveyorJamDetect(_rtReset,_tonNoPart,_tonConfirm)｜AxisSoftLimitGuard(_rtReset，本件无 TON/TOF/TP)｜RecipeStepExec(_rtStart,_rtReset,_rtDone,_rtJump,_tonStep)｜CabinetTempDerate(_rtReset,_tonSensFault)。
- 语句级开闭配对（R271 三族独立断言）：脚本按「语句首关键字」独立计数，未合并总计数、未凭缩进判断 —— IF 与 END_IF 十件全等；CASE 与 END_CASE 十件全等；FOR 与 END_FOR 全等（PumpAlternationLead 9/9、CabinetTempDerate 1/1，其余无 FOR）。

| # | ①GVL/EXTERNAL | ②物理地址 | ③纯 IEC | ④除零/越界/浮点容差 | ⑤双语注释 | ⑥CASE+ELSE | ⑦定时器无条件 |
|---|---|---|---|---|---|---|---|
| 1 FC_DL_ModPosWrap | ✔ 无 | ✔ 无 | ✔ | ✔ 模数 0 结构早退 RETURN，全件唯一除法面即内建 MOD；整数无浮点比较面，N/A | ✔ | N/A 纯函数无状态机 | N/A 无定时器/沿 |
| 2 FC_DL_LerpClamped | ✔ 无 | ✔ 无 | ✔ | ✔ 三入参非有限闸 + 结构早退；无除法；浮点比较全为不等式或容差式 | ✔ | N/A 同上 | N/A 无定时器/沿 |
| 3 FB_DL_ScaleRangeWatch | ✔ 无 | ✔ 无 | ✔ | ✔ 无除法；回差判据全为不等式；组态闸 8 个浮点入参逐项点名（R272） | ✔ | N/A 单相监视无状态机（已在头注释写明） | ✔ 两 TON + 一 R_TRIG |
| 4 FB_DL_BatchDoseSeq | ✔ 无 | ✔ 无 | ✔ | ✔ 无除法；阈值比较全为 `>=`/`<`；无数组下标 | ✔ | ✔ CASE 八分支 + ELSE(回 eFault 置 0309) | ✔ 一 TON + 两 R_TRIG，PT 逐相选择 |
| 5 FB_DL_PumpAlternationLead | ✔ 无 | ✔ 无 | ✔ | ✔ 无除法；FOR 以常量 DL_PMP_N 定界 + 索引前显式 1..N 校验（双防线）；小时相等用容差 DL_PMP_HTOL，浮点不直比 | ✔ | N/A 无顺序相（组合逻辑） | ✔ 一 TON（自复位口径 IN := bEn AND NOT Q）+ 一 R_TRIG |
| 6 FB_DL_ValveSeatLeakTest | ✔ 无 | ✔ 无 | ✔ | ✔ 唯一除法 `P0*(T0K-T1K)/T0K` 前有 `_fT0K > 0.0` 结构闸；结果非有限复检；无数组下标 | ✔ | ✔ CASE 七分支 + ELSE(回 eFault 置 0405) | ✔ 一 TON + 两 R_TRIG |
| 7 FB_DL_ConveyorJamDetect | ✔ 无 | ✔ 无 | ✔ | ✔ 无除法；电流判据回差式全为不等式；组态闸含「回差吞没置位线」拦截 | ✔ | N/A 双判据无顺序相（已在头注释写明） | ✔ 两 TON + 一 R_TRIG |
| 8 FB_DL_AxisSoftLimitGuard | ✔ 无 | ✔ 无 | ✔ | ✔ 唯一除法 `v²/(2a)` 前有双结构闸（fDecel>0 且 2*fDecel>0）；余量比较改写为乘法，全件仅一个除法点；无数组下标 | ✔ | N/A 组合判据 + 越限保持（已在头注释写明） | ✔ 一 R_TRIG（本件无 TON/TOF/TP） |
| 9 FB_DL_RecipeStepExec | ✔ 无 | ✔ 无 | ✔ | ✔ 无除法、无数组；跳步目标按 1..nStepTotal 区间校验，越界即「拒绝」而非索引 | ✔ | ✔ CASE 五分支 + ELSE(回 eFault 置 0704) | ✔ 一 TON + 四 R_TRIG |
| 10 FB_DL_CabinetTempDerate | ✔ 无 | ✔ 无 | ✔ | ✔ 无除法；FOR 以常量 DL_CAB_N 定界；温度比较全为不等式；六组态量逐项点名 + 系数单调反置拦截 | ✔ | ✔ CASE 四分支 + ELSE(回 eNormal 置 0803) | ✔ 一 TON + 一 R_TRIG |

补充（任务硬性第 5 条）：
- 时序类 7 件（#3~#10 中除 FC 两件外的全部）均具备：输入域闸（非有限/越界，结构早退或分支跳过，绝不带病运算）、失败锁存 + `bReset` 上升沿解除（唯一可到达清除边）、失能/故障相输出清零或压最保守值、`bValid` / `bBusy` / `bError` + `nErrCode` 四出口。
- **类型披露**：任务书写作 `nErrCode`(WORD)，但码段为 `16#0002_xxxx`（32 位），WORD 仅 16 位无法容纳（会编译报常量超域）。故 8 个 FB 的 `nErrCode` 统一声明为 **UDINT**，命名保留 `nErrCode` 不变，码段与任务书一致。此为**有意偏离**，理由已写在各件头注释「错误码」节内，请主控确认。

## 三 自纠记录（编码期发现并当场修正，共 9 条）

| # | 文件 | 问题 | 处置 |
|---|------|------|------|
| 1 | FB_DL_ScaleRangeWatch | 段 8 单一 ELSE 分支把头注释「失能相输出清零」与「故障相保持末次良好值」混在一处，属隐性回夹自相矛盾 | 拆为「失能优先 → fEng 清零 / bError 清零 / 码清零」与「故障相 → 保持末次良好值 + 回放锁存码」两分支，与头注释边界三逐字对齐 |
| 2 | FC_DL_LerpClamped | 初稿结果饱和分支用 `ABS(fT-1.0)` 与字面 1.0 直接比较（浮点直比） | 改为 `ABS(_fT - 1.0) <= DL_LRP_TOL` 容差口径 |
| 3 | FB_DL_BatchDoseSeq | 出口段残留 `nErrCode := nErrCode;` 自赋值死语句（R261 禁止） | 删除该段，信息级 0310 由段 9 单点写入、无后续覆盖 |
| 4 | FB_DL_PumpAlternationLead | 头注释「边界三」写成自问自答的未定稿句式，且「夹住是否发码」结论悬空 | 改写为定稿：按工程极限 1.0E12 h 夹住、不发码，并补「加码前须有现有输出组合不可观测的反证句」 |
| 5 | FB_DL_PumpAlternationLead | 失能分支未镜像 `arRunHours` 到 `_afHours`，上电首拍/失能期小时出口可能为 0（小时被"清零"） | 失能分支补镜像与出口赋值，并在头注释边界四写明「小时不被失能清零」 |
| 6 | FB_DL_ValveSeatLeakTest | 温补未投用分支残留一行反向赋值 `_fDropTmp := _fP1 - _fP0;` 后被下一行覆盖（死语句 + 方向矛盾） | 删除残留行，仅保留 `_fDropTmp := _fP0 - _fP1;` |
| 7 | FB_DL_ValveSeatLeakTest | 压降结果在判定相跨拍丢失（段 1 统一预置清零、ePass/eLeak 不再赋值 → 同拍抹除类缺陷） | 新增保持量 `_fDropRawP` / `_fDropCompP`，测量窗与判定相写保持量，段 9 统一映射到 `fDropRaw` / `fDropComp` |
| 8 | FB_DL_AxisSoftLimitGuard | 三处：头注释声明「提前 RETURN 早退」但实现为闸跳过（注释与实现不符）；用 `INT_TO_LREAL(_iSign)` 引入整型转实数依赖；组态闸内 `(fPosMax-fPosMin)/2.0` 多余除法点 | 注释改为「闸不成立则整段跳过并置 0501」；符号改用 LREAL 型 `_fSign` 直接赋值，消除转换依赖；余量判据改写为 `fMargin * 2.0 >= 行程`，全件仅剩一个除法点 |
| 9 | FB_DL_RecipeStepExec / FB_DL_CabinetTempDerate | 前者步号切换后 TON 跨步累计（第二步必立刻超时）；后者 `END_CASE` 缩进错落入分支层级内 | 前者增设 `_bTimerRestart` 单拍复位机制（推进/跳步/暂停恢复均复位，段 8 统一请求），并在头注释写明「暂停期间步超时计时复位」；后者 `END_CASE` 归位顶层 |

## 四 历史教训四项复核（逐项过）

1. **漏声明 VAR_OUTPUT 变量**：脚本反查「赋值左侧标识符是否全部在声明区」+「每个 VAR_OUTPUT 是否至少被赋值一次」—— 10 件 unknown_LHS 全部为空（其余命中项经人工确认均为声明行本身、TYPE 枚举成员或头注释伪代码），unassigned 全部为空。
2. **注释嵌套 `(* (* *) *)`**：全 10 件逐行检查 `(*` 单行出现次数 ≤ 1；头注释为单一 `(* ... *)` 块，块内不再出现 `(*`；声明行注释用单层 `(* *)`，逻辑行注释一律用 `//`，两族不交叉。
3. **枚举单冒号**：TYPE 段全部枚举成员为 `eXxx := n,` / 末项 `eXxx := n` + `);`，脚本 regex 复查无 `eXxx :` 形式。
4. **隐性回夹 / 锁存副本与实时镜像混用**：PumpAlternationLead 判据只用 `_abFaultLatch`，`abFault` 引脚仅用于「并入锁存」，二者不共用同一判据（头注释显式声明）；其余各件 `_bFault` 类锁存位与引脚值亦严格分离，故障期一律回放锁存码，不按当下输入重推断。

## 五 未做事项（明确披露）

- 未编译（本轮无 CODESYS / TwinCAT 环境），「编译器已证」列全部为空，需在合并轮补跑三平台编译。
- 未运行算法用例脚本，「算法已证」列全部为空。
- 未改动任何注册表 / 清单 / 文档（按要求留待主控脚本收口）。
