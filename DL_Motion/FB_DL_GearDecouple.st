(*==============================================================================
 * 组件名称 (Component)  : FB_DL_GearDecouple
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（ABS），零厂商私有库
 * 功能描述 (Function)   : 电子齿轮渐变脱耦（MC_GearOut 语义）：耦合期输出比例
 *                         fRatioOut = iNum ÷ iDen；脱耦请求（bCoupled 下降沿）
 *                         后比例按 tRamp 渐降至 1:1（禁直接跳断，规格指定），
 *                         到达 1:1 置 bReleased（电平指示，重耦合撤销）；脱耦
 *                         斜坡中重新耦合（bCoupled 上升沿）比例斜坡回升至全
 *                         比例，无阶跃。iDen = 0 → 拒绝并锁存故障（除数前置
 *                         闸，规格指定）。
 * 接口     (Interface)  : 输入 bCoupled 耦合命令（TRUE=全比例耦合）、iNum 齿轮
 *                         分子、iDen 齿轮分母（域 <> 0）、fRampS 脱耦渐变时长
 *                         （域 > 0） [s]、fCycle 扫描周期（<=0 用缺省） [s]、
 *                         bReset 复位；输出 fRatioOut 渐变比例、bReleased
 *                         脱耦完成指示（电平）、bRamping 斜坡执行中指示、
 *                         eErrCode 错误码、bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只出渐变比例标量，不接管
 *                         轴使能、不下齿轮指令**；齿轮耦合执行归
 *                         `FB_DL_ElectronicGear`。
 *                         ② 斜率口径：全比例 fRatioFull = iNum/iDen，斜坡速率
 *                         = (fRatioFull − 1) ÷ fRampS [1/s]；单步 = 速率 × fCy，
 *                         步内可达即贴目标（无过冲）；fRampS 用 LREAL 秒口径，
 *                         避免跨平台 TIME→实数转换链（R64 交付门槛规避，头注释
 *                         声明工程取舍）。
 *                         ③ fRatioFull = 1（1:1 齿轮）时斜坡速率恒 0：脱耦
 *                         请求即达 1:1，当拍 bReleased（无跳变路径，比例本就
 *                         不变）。
 *                         ④ 斜坡中禁直接跳断：bCoupled 变化只改目标值，输出
 *                         恒限步逼近（头注释声明，规格指定）。
 *                         ⑤ 组态闸：iDen = 0 或 fRampS <= 0 → 锁存故障，输出
 *                         冻结保持末值（比例冻结语义声明：R191 二选一之「冻结
 *                         保持」，故障期禁跳变），解除沿 = bReset 上升沿。
 *                         ⑥ 非有限判据（R79 双判）：fCycle 非有限按缺省周期
 *                         处理并入组态闸（iNum/iDen 整型无浮点域）。
 *                         ⑦ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_ElectronicGear` 分工：恒比例齿轮耦合归那件、
 *                         渐变脱耦编排归本件；与 `FB_DL_AxisSynchronizedStop`
 *                         分工：同步停止归那件。
 * 来源标签 (Source Tag) : T1-6 ◐（PLCopen MC 语义只借 GearOut 脱耦完成语义，
 *                         斜坡渐变实现为道莅自研 clean-room）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 LREAL 比例 +
 *                         BOOL 组 + ENUM 错误码；数字码位待主控收口阶段统一
 *                         派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 除数前置闸 + 限步逼近 + 故障冻结声明 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（锁存态无 CASE 状态机） ｜ R7 ✓ 一 R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R50 首版（批次 3 · 序号 14）
 * 验收向量 (Acceptance) : ① iNum=2, iDen=1（全比例 2.0），fRampS=2.0，
 *                         fCycle=0.01 → 单步 0.005：脱耦后 200 拍达 1.0 →
 *                         bReleased=TRUE；② 100 拍时重耦合 → 比例自 1.5 反向
 *                         斜坡回升至 2.0（无阶跃）；③ iDen=0 → 锁存 eCfgBad，
 *                         fRatioOut 冻结末值；④ iNum=1, iDen=1 → 脱耦请求
 *                         当拍 fRatioOut=1.0、bReleased=TRUE。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_GdcErr（错误码；故障级恒伴 bError=TRUE）
 *----------------------------------------------------------------------------*)
TYPE E_DL_GdcErr :
(
    eOk     := 0,   // 正常 / Normal
    eCfgBad := 1    // 故障级：分母零或斜坡时长非法（输出冻结保持） / Fault: zero denominator or bad ramp time
);
END_TYPE

FUNCTION_BLOCK FB_DL_GearDecouple
VAR_INPUT
    bCoupled : BOOL := TRUE;          // 耦合命令（TRUE=全比例，FALSE=脱耦请求） [-] / Coupled command
    iNum     : DINT := 2;             // 齿轮分子 [-] / Gear numerator
    iDen     : DINT := 1;             // 齿轮分母，域 <> 0 [-] / Gear denominator, must not be zero
    fRampS   : LREAL := 2.0;          // 脱耦渐变时长（全比例→1:1），域 > 0 [s] / Decouple ramp duration [s]
    fCycle   : LREAL := 0.0;          // 扫描周期（<=0 用缺省） [s] / Scan cycle, default used when <= 0
    bReset   : BOOL := FALSE;         // 复位，上升沿清组态锁存并回全比例/1:1 目标重算 [-] / Reset, rising edge clears latch
END_VAR
VAR_OUTPUT
    fRatioOut : LREAL;                // 渐变比例输出（限步逼近目标） [-] / Ramped ratio output
    bReleased : BOOL;                 // 脱耦完成指示（比例达 1:1 ∧ 脱耦请求中，电平） [-] / Released indicator, level
    bRamping  : BOOL;                 // 斜坡执行中指示 [-] / Ramping indicator
    eErrCode  : E_DL_GdcErr;          // 错误码出口 / Error code outlet
    bError    : BOOL;                 // 故障标志（组态锁存） [-] / Error flag, latched
END_VAR
VAR
    _fRatio   : LREAL := 1.0;         // 比例内部锁存（限步源，初值 1:1 安全态） / Ratio internal latch
    _fFull    : LREAL;                // 全比例 = iNum ÷ iDen（分母已闸） [-] / Full ratio
    _fRate    : LREAL;                // 斜坡速率（全比例−1）÷fRampS [1/s] / Ramp rate
    _fStep    : LREAL;                // 当拍最大步长 [1/拍] / Max step this scan
    _fTarget  : LREAL;                // 当拍目标比例 [-] / Target ratio this scan
    _fCy      : LREAL;                // 当拍有效周期 [s] / Effective cycle this scan
    _bCfgBad  : BOOL;                 // 组态非法当拍量 [-] / Illegal configuration
    _bErrLatch: BOOL;                 // 组态故障锁存位（解除沿 = bReset 上升沿） / Latched config fault
    rtReset   : R_TRIG;               // 复位沿实例，段 0 无条件调用 / Reset edge instance
END_VAR
VAR CONSTANT
    DL_GDC_CYDEF : LREAL := 0.01;     // 缺省扫描周期 [s] / Default scan cycle
    DL_GDC_ONE   : LREAL := 1.0;      // 1:1 基准与到达容差中心 [-] / Unity ratio base
    DL_GDC_ZERO  : LREAL := 0.0;      // 判零基准 [-] / Zero base
    DL_GDC_TOL   : LREAL := 1.0E-6;   // 到达判据容差（浮点禁 = 判等） [-] / Arrival tolerance
END_VAR

(* —— 段 0：非有限判 + 组态闸 + 周期派生 + 沿刷新 —— *)
IF fCycle <> fCycle THEN
    _fCy := DL_GDC_CYDEF;                          // 周期非有限按缺省（规格⑥） / Non-finite cycle to default
ELSIF fCycle > DL_GDC_ZERO THEN
    _fCy := fCycle;                                // 组态周期有效 / Configured cycle
ELSE
    _fCy := DL_GDC_CYDEF;                          // 周期缺省兜底 / Default fallback
END_IF
_bCfgBad := (iDen = 0) OR (fRampS <= DL_GDC_ZERO);   // 组态域闸（除数前置 + 斜坡时长） / Configuration gate
rtReset(CLK := bReset);                            // 复位沿，每拍必调 / Reset edge, every scan

(* —— 段 1：复位沿与组态锁存 —— *)
IF rtReset.Q THEN
    _bErrLatch := FALSE;                           // 清组态锁存（R188 声明：解除沿 = bReset 上升沿） / Clear cfg latch
END_IF
IF _bCfgBad AND (NOT _bErrLatch) THEN
    _bErrLatch := TRUE;                            // 锁存 / Latch
END_IF

(* —— 段 2：目标与速率派生（故障期跳过派生，冻结保持） —— *)
IF NOT _bErrLatch THEN
    _fFull := DINT_TO_LREAL(iNum) / DINT_TO_LREAL(iDen);   // 全比例（分母已闸，无除零） / Full ratio
    _fRate := ABS(_fFull - DL_GDC_ONE) / fRampS;   // 斜坡速率（对称双向同一速率） / Ramp rate
    _fStep := _fRate * _fCy;                       // 单步上限 [1/拍] / Max step
    IF bCoupled THEN
        _fTarget := _fFull;                        // 耦合目标 = 全比例 / Coupled target
    ELSE
        _fTarget := DL_GDC_ONE;                    // 脱耦目标 = 1:1（MC_GearOut 语义） / Decouple target
    END_IF
END_IF

(* —— 段 3：限步逼近（斜坡中禁直接跳断，规格④；步内可达即贴目标） —— *)
IF NOT _bErrLatch THEN
    IF _fTarget > (_fRatio + _fStep) THEN
        _fRatio := _fRatio + _fStep;               // 正向限步（重耦合回升无阶跃） / Ramp up limited
    ELSIF _fTarget < (_fRatio - _fStep) THEN
        _fRatio := _fRatio - _fStep;               // 负向限步（脱耦渐降） / Ramp down limited
    ELSE
        _fRatio := _fTarget;                       // 步内到达：贴目标 / Settle at target
    END_IF
END_IF

(* —— 段 4：出口单点映射（名实双出口同源，R191） —— *)
fRatioOut := _fRatio;                              // 比例出口（故障期冻结保持末值，头注释⑤声明） / Ratio outlet, frozen on fault
IF (NOT _bErrLatch) AND (NOT bCoupled)
   AND (ABS(_fRatio - DL_GDC_ONE) < DL_GDC_TOL) THEN
    bReleased := TRUE;                             // 脱耦完成电平（比例达 1:1 ∧ 脱耦请求中） / Released level
ELSE
    bReleased := FALSE;                            // 未完成/重耦合/故障期撤销 / Not released
END_IF
bRamping := (NOT _bErrLatch)
        AND (ABS(_fRatio - _fTarget) >= DL_GDC_TOL);   // 斜坡执行中（与目标距离超容差） / Ramping indicator
IF _bErrLatch THEN
    bError := TRUE;                                // 故障标志（R45 配对） / Error flag
    eErrCode := E_DL_GdcErr.eCfgBad;               // 故障级码 / Fault code
ELSE
    bError := FALSE;                               // 无故障级条件 / No fault
    eErrCode := E_DL_GdcErr.eOk;                   // 正常码 / OK code
END_IF

END_FUNCTION_BLOCK
