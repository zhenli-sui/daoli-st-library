(*==============================================================================
 * 组件名称 (Component)  : FB_DL_BiasAdaptiveTrim
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（ABS），零厂商私有库
 * 功能描述 (Function)   : 稳态偏置自适应修调（外挂修调器）：对闭环残差做带外积分、带内泄漏
 *                           |fErr| > fBand  →  _fTrim += fKiTrim × fErr × fCycle
 *                           |fErr| <= fBand →  _fTrim -= fLeak × _fTrim × fCycle
 *                         输出钳 [fTrimMin, fTrimMax] 并置 bSatLim。适用换热器结垢、阀门
 *                         磨损等缓慢漂移型稳态偏差的轻量外挂修正，不动主回路 PID 整定。
 * 接口     (Interface)  : 输入 fErr 闭环残差（工程单位）、bInService 投用、fKiTrim 修调积分
 *                         增益（1/s）、fBand 误差死区（工程单位）、fLeak 带内泄漏系数（1/s）、
 *                         fTrimMin/fTrimMax 修调限幅（工程单位）、fCycle 扫描周期（s，<=0
 *                         时用缺省周期）、bReset 复位；输出 fTrim 修调量、bSatLim 触限、
 *                         bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只出修调偏置量，不注入任何回路、不接管
 *                         主 PID 整定**；注入点由上层叠加到设定值或输出偏置端。
 *                         ② bInService=FALSE 冻结不遗忘（退出即保持 _fTrim，防重投扰动，
 *                         语义写死不得由调用方假设）；bSatLim 复位。
 *                         ③ 非有限 fErr 当拍跳过（保持当拍 _fTrim 不动，R245）。
 *                         ④ fCycle <= 0 拒算，改用缺省扫描周期常量（防零周期积分跳变）。
 *                         ⑤ Anti-Windup：钳位后积分方向不改——限幅结果直接覆写 _fTrim，
 *                         不允许越限累积（`FB_DL_AntiWindupLink` 同族语义）。
 *                         ⑥ 组态闸：fTrimMin >= fTrimMax、fBand < 0、fLeak < 0 → 锁存
 *                         bError，冻结输出 fTrim=0 安全侧，解除沿 = bReset 上升沿。
 *                         ⑦ 零全局耦合（无 GVL / 无 VAR_EXTERNAL / 无物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_Integrator` 分工：纯积分器无死区/泄漏/限幅闭环语义，
 *                         本件是带遗忘的闭环偏置修调；二者不互调不复制。
 * 来源标签 (Source Tag) : 自研线（带泄漏积分 clean-room）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 LREAL 修调量 + BOOL 组；
 *                         数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 周期缺省闸 + 非有限跳过 + 钳位 Anti-Windup ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（无 ENUM 状态机） ｜ R7 ✓ 一 R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R48 首版（批次 2 · 序号 7）
 *                         验收向量：带外正残差积分上行；进入死区泄漏回落；触限后不累积；
 *                         退出投用冻结不遗忘；fCycle=0 用缺省周期。
 *==============================================================================*)

FUNCTION_BLOCK FB_DL_BiasAdaptiveTrim
VAR_INPUT
    fErr      : LREAL := 0.0;    // 闭环残差（被修调量实测与目标差） [工程单位] / Closed-loop residual
    bInService: BOOL := FALSE;   // 投用开关（FALSE=冻结保持不遗忘） [-] / In-service switch, FALSE freezes and holds
    fKiTrim   : LREAL := 0.1;    // 修调积分增益 [1/s] / Trim integral gain [1/s]
    fBand     : LREAL := 0.0;    // 误差死区半宽（带内不积分只泄漏） [工程单位] / Error deadband half-width
    fLeak     : LREAL := 0.0;    // 带内泄漏系数（遗忘速率） [1/s] / In-band leakage coefficient [1/s]
    fTrimMin  : LREAL := -10.0;  // 修调下限 [工程单位] / Trim lower limit
    fTrimMax  : LREAL := 10.0;   // 修调上限 [工程单位] / Trim upper limit
    fCycle    : LREAL := 0.0;    // 扫描周期（<=0 时用缺省周期） [s] / Scan cycle time, default used when <= 0
    bReset    : BOOL := FALSE;   // 复位，上升沿清组态故障锁存 [-] / Reset, rising edge clears config fault
END_VAR
VAR_OUTPUT
    fTrim   : LREAL;             // 修调偏置输出（已限幅） [工程单位] / Trim bias output, limited
    bSatLim : BOOL;              // 修调量触限（饱和发生，非故障） [-] / Trim hit the limit
    bError  : BOOL;              // 组态故障标志（锁存） [-] / Configuration fault flag, latched
END_VAR
VAR
    _fTrim    : LREAL := 0.0;    // 修调量锁存（投用退出即保持） / Latched trim, held when out of service
    _fCy      : LREAL;           // 当拍有效周期 [s] / Effective cycle this scan [s]
    _bErrLatch: BOOL;            // 组态故障锁存位（解除沿 = bReset 上升沿） / Latched config fault, cleared by reset edge
    rtReset   : R_TRIG;          // 复位沿实例，段 0 无条件调用 / Reset edge instance
    _bNonFin  : BOOL;            // 残差非有限当拍量 [-] / Non-finite residual this scan
    _fRaw     : LREAL;           // 当拍未限幅修调量 [工程单位] / Unlimited trim this scan
    _bSat     : BOOL;            // 当拍触限内部量（统一出口映射） / Saturation internal this scan
END_VAR
VAR CONSTANT
    DL_BAT_EPS      : LREAL := 1.0E-6;   // 浮点判零容差 [工程单位] / Float zero epsilon
    DL_BAT_CYCLEDEF : LREAL := 0.01;     // 缺省扫描周期（fCycle<=0 时启用） [s] / Default cycle time
    DL_BAT_ONE      : LREAL := 1.0;      // 单位常量（泄漏基） [无量纲] / Unit constant for leakage base
END_VAR

(* —— 段 0：非有限判 + 组态闸 + 周期派生 + 沿刷新 —— *)
_bNonFin := (fErr <> fErr) OR ((fErr - fErr) <> 0.0);       // 残差非有限（NaN 自不等 / Inf 差非零，R245） / Non-finite residual tests
IF (fTrimMin >= fTrimMax) OR (fBand < 0.0) OR (fLeak < 0.0) THEN
    _bErrLatch := TRUE;                                     // 组态域闸：锁存（R188 解除沿 = bReset 上升沿） / Config gate: latch
END_IF
IF fCycle > 0.0 THEN
    _fCy := fCycle;                                         // 组态周期有效 / Configured cycle valid
ELSE
    _fCy := DL_BAT_CYCLEDEF;                                // 周期缺省兜底（拒算零周期） / Default cycle fallback
END_IF
rtReset(CLK := bReset);                                     // 复位沿，每拍必调 / Reset edge, every scan

(* —— 段 1：复位沿 —— *)
IF rtReset.Q THEN
    _bErrLatch := FALSE;                                    // 清组态故障锁存 / Clear config fault latch
END_IF

(* —— 段 2：修调主算（未投用冻结不遗忘；故障期强制安全侧） —— *)
_bSat := FALSE;                                             // 触限内部量预清 / Saturation internal preset
IF _bErrLatch THEN
    _fTrim := 0.0;                                          // 故障安全侧：修调归零 / Fault safe side: trim forced zero
ELSIF NOT bInService THEN
    (* 未投用：_fTrim 冻结保持（防重投扰动，头注释②声明），bSatLim 复位 *)
    ;                                                       // 冻结分支无赋值（保持即语义） / Freeze branch holds by design
ELSIF _bNonFin THEN
    (* 残差非有限：当拍跳过积分与泄漏（保持 _fTrim 不动，R245） *)
    ;                                                       // 跳过分支保持 / Skip branch holds
ELSE
    IF ABS(fErr) > fBand THEN
        _fRaw := _fTrim + fKiTrim * fErr * _fCy;            // 带外积分：增益×残差×周期 / Out-of-band integration
    ELSE
        _fRaw := _fTrim - fLeak * _fTrim * _fCy;            // 带内泄漏：遗忘速率×修调×周期 / In-band leakage decay
    END_IF
    IF _fRaw > fTrimMax THEN
        _fTrim := fTrimMax;                                 // 上限覆写（Anti-Windup：不越限累积） / Ceiling overwrite, no windup
        _bSat := TRUE;                                      // 记触限 / Mark saturation
    ELSIF _fRaw < fTrimMin THEN
        _fTrim := fTrimMin;                                 // 下限覆写 / Floor overwrite
        _bSat := TRUE;                                      // 记触限 / Mark saturation
    ELSE
        _fTrim := _fRaw;                                    // 域内正常接受 / In-domain accept
    END_IF
END_IF

(* —— 段 3：出口单点映射（名实双出口同源，R191） —— *)
fTrim   := _fTrim;                                          // 修调量出口 / Trim outlet
bSatLim := _bSat AND (NOT _bErrLatch) AND bInService;       // 触限出口（冻结/故障期不复位不误报） / Saturation outlet
bError  := _bErrLatch;                                      // 故障标志出口 / Error flag outlet

END_FUNCTION_BLOCK
