# ROUND_PLAN_R40 — 第 40 轮派单计划（2026-11-19 04:48 起，总监规划环节）

## 本轮统计
- 总库：**690 / 10,000（6.90%）**（registry v2.31.0）
- 今日（11-19）：**20 / 200**（R39 产出）
- 距 500 计划差额：**+190（已达成）**；本轮目标 690 → ~710
- 源矩阵覆盖率：本轮 T0 快车道零检索轮（源标签统一 iec-std-wrapper），无新增外部源；T1/T2 组均复用既有矩阵条目
- P0 债务：R39 件 5 抽终审已执行——2 高危挂账（AxisLimitRecovery / MutexOwnerAudit，文件头警示已加，v1.0.1 不改逻辑），1 中危挂账（LaminatorPressCtrl），1 轻微（HjtPvdSeq），1 PASS（TankLevelStrapping）

## 选题依据
T0 快车道未收口组优先（对照全库 grep 双查）：T0-1 剩 SR/RS/分频变体；T0-2 剩 TP 包装；T0-5 剩降型/进位口径/域转换原子；T0-6 剩 ToLower/ToUdint；另补 MAX/MIN/LIMIT/MUX 内建防御与时间标量饱和（各平台边界行为不一致的实证缺口）。已注册件（TonEx/TofEx/RtoEx/CtuEx/CtdEx/CtudEx/TruncEx/RoundSat/FloorEx/CeilEx/字符串九函数/SHL/SHR/ROL/ROR 全族/BCD 全族/三角函数域检查族）一律不重复立项。

## 派单表

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 |
|---|---|---|---|---|---|---|---|
| 1 | FC_DL_MaxNanEx | DL_MathData | FC_DL_ | MAX 内建防御包装：任一入参 NaN/Inf 时按口径输出安全侧并置错误码 | iec-std-wrapper | 低 | 1 |
| 2 | FC_DL_MinNanEx | DL_MathData | FC_DL_ | MIN 内建防御包装：NaN/Inf 拦截 + 双语错误码 | iec-std-wrapper | 低 | 1 |
| 3 | FC_DL_LimitEx | DL_MathData | FC_DL_ | LIMIT 内建防御包装：xmin>xmax 域反转时按错误码拒绝而非平台未定义行为 | iec-std-wrapper | 低 | 1 |
| 4 | FC_DL_RealEqTolEx | DL_MathData | FC_DL_ | 浮点容差判等原子（红线 5 原子化）：容差下限防死判 + NaN 判不等 | iec-std-wrapper | 低 | 1 |
| 5 | FC_DL_RangeCheckEx | DL_MathData | FC_DL_ | 标量域检查纯函数：输出是否在域内 + 越上/下侧别 | iec-std-wrapper | 低 | 1 |
| 6 | FC_DL_RealToDintSat | DL_MathData | FC_DL_ | REAL/LREAL→DINT 防御降型：NaN/Inf/越界钳位至 DINT 极限 + 错误码 | iec-std-wrapper | 低 | 2 |
| 7 | FC_DL_RealToRealSat | DL_MathData | FC_DL_ | LREAL→REAL 防御降型：幅值越 REAL 域钳位 + 非有限值拦截 | iec-std-wrapper | 低 | 2 |
| 8 | FC_DL_RoundBankEx | DL_MathData | FC_DL_ | ROUND 明确口径包装：0.5 进位方向平台差异显式化（半进/半退可选）+ 溢出钳位 | iec-std-wrapper | 中 | 2 |
| 9 | FC_DL_DegToRadEx | DL_MathData | FC_DL_ | 度→弧度转换原子：输入域检查 + 输出非有限值拦截 | iec-std-wrapper | 低 | 2 |
| 10 | FC_DL_RadToDegEx | DL_MathData | FC_DL_ | 弧度→度转换原子：同上对称口径 | iec-std-wrapper | 低 | 2 |
| 11 | FC_DL_TimeAddSat | DL_MathData | FC_DL_ | TIME+TIME 饱和加法：溢出不回绕、钳位至 TIME 上限 + 错误码 | iec-std-wrapper | 低 | 3 |
| 12 | FC_DL_TimeScaleSat | DL_MathData | FC_DL_ | TIME×REAL 缩放饱和：负/非有限因子拦截，结果饱和不回绕 | iec-std-wrapper | 低 | 3 |
| 13 | FC_DL_MuxIntEx | DL_MathData | FC_DL_ | MUX 多路选择防御包装：选择值越路数时钳边界输出 + 信息码（平台未定义行为显式化） | iec-std-wrapper | 低 | 3 |
| 14 | FC_DL_StringToLowerEx | DL_MathData | FC_DL_ | LOWERCASE 防御包装：255 上限显式截断标志 + 空串直通 | iec-std-wrapper | 低 | 3 |
| 15 | FC_DL_StringToUdintEx | DL_MathData | FC_DL_ | 字符串→UDINT 防御解析：非法字符/越 UDINT 域拒绝置错误码（复用既有解析口径） | iec-std-wrapper | 中 | 3 |
| 16 | FB_DL_SrEx | DL_Base | FB_DL_ | SR 置位优先双稳态防御包装：双输入同拍仲裁显式化 + 主从输出镜像 | iec-std-wrapper | 低 | 4 |
| 17 | FB_DL_RsEx | DL_Base | FB_DL_ | RS 复位优先双稳态防御包装：同拍仲裁与 SR 严格对偶，注释逐字对照 | iec-std-wrapper | 低 | 4 |
| 18 | FB_DL_EdgeDivider | DL_Base | FB_DL_ | N 分频变体：输入沿 N 分频输出，N=0/1 防御钳位，输出脉宽单周期保证 | iec-std-wrapper | 中 | 4 |
| 19 | FB_DL_TpEx | DL_Base | FB_DL_ | TP 定宽脉冲防御包装：重触发语义明确化、PT 钳位、首扫零假触发 | iec-std-wrapper | 低 | 4 |
| 20 | FC_DL_IndexClampEx | DL_MathData | FC_DL_ | 数组下标钳位原子：越界按边界钳位并置信息码，供全部数组访问防御复用 | iec-std-wrapper | 低 | 4 |

## 依赖说明
全部为 Level 0 防御性包装，内部委托平台内建函数 + 统一错误码/钳位，无跨件依赖、无层级倒挂；批 1 原子先行为批 2~4 提供判等/域检口径（仅语义引用，不实例化调用）。

## 严禁事项重申
- 禁止重实现数学内核（MAX/MIN/LIMIT/MUX/ROUND 一律委托内建 + 外围守卫）
- 已注册同义件（列表见上）不得以变体名凑数；本轮 20 件均经全库同名 + 同义邻件双查

*道莅工控代码库产品总监 R40 规划｜2026-11-19 04:5x*
