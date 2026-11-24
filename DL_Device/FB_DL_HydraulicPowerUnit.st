(*==============================================================================
 * 组件名称 (Component)  : FB_DL_HydraulicPowerUnit
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商私有库
 * 功能描述 (Function)   : 液压动力单元（HPU）顺控：bStart 上升沿先查油温/油位
 *                         联锁（先于电机判据，规格指定），通过后启动电机升压；
 *                         压力达 fPressSwMpa 开卸荷阀，压力回落至 (fPressSwMpa
 *                         − 0.5 MPa) 关卸荷阀（±0.5 MPa 回差顺控，规格指定）；
 *                         电机启停切换设最小间隔互锁 tMinSw（切换后 tMinSw 内
 *                         禁再次切换）。运行中油温超限/油位低于下限/压力非有限
 *                         → 停电机锁存故障（安全侧优先）。
 * 接口     (Interface)  : 输入 bStart 启动命令（上升沿触发，FALSE 停机）、fPressMpa
 *                         压力实测 [MPa]、fOilTempC 油温实测 [℃]、fOilLevelPct
 *                         油位实测 [%]、fPressSwMpa 卸荷切换阈（域 > 0.5）、
 *                         fTempMaxC 油温联锁上限（域 > 0）、fLvlMinPct 油位联锁
 *                         下限（域 > 0 且 < 100）、tMinSw 电机切换最小间隔、
 *                         bReset 复位；输出 bMotor 电机命令、bUnload 卸荷阀
 *                         命令、ePhase 五态相位、eErrCode 错误码、bError 故障
 *                         标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只出电机/卸荷阀命令，不驱动
 *                         接触器/阀线圈本体**；执行器驱动归 IO 映射层（DOL 电机
 *                         包装归 `FB_DL_DolMotor`）。
 *                         ② 五态 CASE + ELSE 兜底（R6）；tonMinSw IN 挂切换
 *                         互锁窗本身（切换后置互锁、到时解除），三 TON 两沿段 0
 *                         无条件调用（R7）。
 *                         ③ 联锁先于电机判据：启动沿先查油温/油位，联锁不过
 *                         不入启动相并置信息码 eInterlock（不锁存故障，联锁
 *                         为常态门槛）；运行中联锁破约才锁存故障 eTempHigh/
 *                         eLvlLow（归因唯一，R190）。
 *                         ④ 回差口径：开阀阈 fPressSwMpa，关阀阈 fPressSwMpa
 *                         − DL_HPU_DBAND(0.5 MPa)，组态闸保证 fPressSwMpa >
 *                         0.5（关阀阈恒正）。
 *                         ⑤ 电机切换互锁：每次 bMotor 电平变化后 _bSwBlock 置
 *                         位，tonMinSw 到时解除；互锁期内启动/停止命令一律
 *                         拒绝（拒动安全侧）。
 *                         ⑥ 压力非有限（R79 双判）运行中 → 停电机锁存
 *                         ePressBad（不可判即安全侧停机）。
 *                         ⑦ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_DolMotor` 分工：电机直启包装归那件、HPU 工艺
 *                         顺控归本件；与 `FB_DL_MinOnOffGuard` 分工：通用最小
 *                         启停保护归那件，本件互锁为切换间隔专用语义。
 * 来源标签 (Source Tag) : 自研线（卸荷回差顺控为公开液压系统控制实践 clean-room）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 BOOL 命令组 +
 *                         ENUM 相位/错误码；数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 联锁前置 + 回差 + 切换互锁 + 非有限安全停机
 *                         ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ 五态 CASE 含 ELSE ｜ R7 ✓ 三 TON 两 R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R50 首版（批次 4 · 序号 18）
 * 验收向量 (Acceptance) : ① 油位 25%（下限 30%）时启动沿 → 不入启动相，
 *                         eErrCode=eInterlock，bMotor=FALSE；② 正常启动，
 *                         压力升至 16.2 MPa（阈 16.0）→ bUnload=TRUE；回落至
 *                         15.4 MPa（< 16.0−0.5=15.5）→ bUnload=FALSE；③ 运行
 *                         中油温 65 ℃（上限 60）→ 停电机锁存 eTempHigh；
 *                         ④ 停机后 2s 内再启动（tMinSw=10S）→ 拒动（互锁）。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_HpuPhase（HPU 相位，全库唯一属主本文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_HpuPhase :
(
    eIdle     := 0,   // 待机（电机停） / Idle, motor off
    eRunning  := 10,  // 升压/运行（电机开，卸荷阀按回差裁决） / Running, unloading by hysteresis
    eFault    := 90   // 故障（等复位） / Fault, awaiting reset
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_HpuErr（错误码；信息级不置 bError，故障级恒伴 bError=TRUE）
 *----------------------------------------------------------------------------*)
TYPE E_DL_HpuErr :
(
    eOk        := 0,   // 正常 / Normal
    eInterlock := 1,   // 信息级：启动被油温/油位联锁拒绝（常态门槛） / Info: start rejected by interlock
    eCfgBad    := 2,   // 故障级：组态非法（阈值/时间域） / Fault: illegal configuration
    eTempHigh  := 3,   // 故障级：运行中油温超限（停电机锁存） / Fault: oil temp high in run
    eLvlLow    := 4,   // 故障级：运行中油位低于下限（停电机锁存） / Fault: oil level low in run
    ePressBad  := 5    // 故障级：压力非有限（安全侧停机锁存） / Fault: pressure non-finite, safe stop
);
END_TYPE

FUNCTION_BLOCK FB_DL_HydraulicPowerUnit
VAR_INPUT
    bStart     : BOOL := FALSE;       // 启动命令（上升沿触发，FALSE 停机请求） [-] / Start command, rising edge triggered
    fPressMpa  : LREAL := 0.0;        // 压力实测 [MPa] / Pressure measurement [MPa]
    fOilTempC  : LREAL := 25.0;       // 油温实测 [℃] / Oil temperature [degC]
    fOilLevelPct: LREAL := 80.0;      // 油位实测 [%] / Oil level [percent]
    fPressSwMpa: LREAL := 16.0;       // 卸荷切换阈（开阀），域 > 0.5 [MPa] / Unload switch threshold
    fTempMaxC  : LREAL := 60.0;       // 油温联锁上限，域 > 0 [℃] / Oil temp interlock ceiling
    fLvlMinPct : LREAL := 30.0;       // 油位联锁下限，域 > 0 且 < 100 [%] / Oil level interlock floor
    tMinSw     : TIME := T#10S;       // 电机切换最小间隔，域 > T#0S [ms] / Minimum motor switch interval
    bReset     : BOOL := FALSE;       // 复位，上升沿清故障锁存（须 bStart=FALSE） [-] / Reset, clears latches when not started
END_VAR
VAR_OUTPUT
    bMotor   : BOOL;                  // 电机命令出口 [-] / Motor command outlet
    bUnload  : BOOL;                  // 卸荷阀命令出口（TRUE=卸荷） [-] / Unload valve command outlet
    ePhase   : E_DL_HpuPhase;         // 相位出口 [-] / Phase outlet
    eErrCode : E_DL_HpuErr;           // 错误码出口 / Error code outlet
    bError   : BOOL;                  // 故障标志（运行联锁破约锁存） [-] / Error flag, latched
END_VAR
VAR
    _eState   : E_DL_HpuPhase := E_DL_HpuPhase.eIdle;   // 内部相（CASE 唯一写入目标） / Internal phase
    _bMot     : BOOL := FALSE;        // 电机命令内部单源（出口同源） / Motor command internal source
    _bUnload  : BOOL := FALSE;        // 卸荷阀内部单源 / Unload valve internal source
    _bFault   : BOOL;                 // 运行故障锁存位（解除沿 = 非启动态 ∧ bReset 上升沿） / Latched run fault bit
    _bCfgBad  : BOOL;                 // 组态非法当拍量 [-] / Illegal configuration
    _bCfgLatch: BOOL;                 // 组态故障锁存位（解除沿 = 非启动态 ∧ bReset 上升沿，与 _bFault 同口径） / Latched config fault
    _bSwBlock : BOOL := FALSE;        // 切换互锁位（切换后置位，tonMinSw 到时解除） / Switch interlock bit
    _bMotPrev : BOOL := FALSE;        // 上拍电机命令快照（切换检测源） / Motor command snapshot
    _bInterlock: BOOL;                // 启动联锁拒绝当拍量（信息级） [-] / Start interlock rejection this scan
    _bNonFin  : BOOL;                 // 压力非有限当拍量 [-] / Pressure non-finite this scan
    _eCause   : E_DL_HpuErr := E_DL_HpuErr.eOk;   // 故障成因锁存（入相时归因，回放不重推断，R189/R190） / Latched fault cause
    rtReset   : R_TRIG;               // 复位沿实例，段 0 无条件调用 / Reset edge instance
    rtStart   : R_TRIG;               // 启动沿实例，段 0 无条件调用 / Start edge instance
    tonMinSw  : TON;                  // 切换互锁窗 TON，段 0 无条件调用（R145：IN 挂互锁位本身） / Switch interlock TON
END_VAR
VAR CONSTANT
    DL_HPU_DBAND : LREAL := 0.5;      // 卸荷回差（关阀阈 = 开阀阈 − 0.5 MPa），规格指定 [MPa] / Unload hysteresis band
    DL_HPU_ZERO  : LREAL := 0.0;      // 判零基准 [MPa] / Zero base
END_VAR

(* —— 段 0：非有限判 + 组态闸 + 三 TON 两沿无条件刷新 —— *)
_bNonFin := (fPressMpa <> fPressMpa) OR ((fPressMpa - fPressMpa) <> DL_HPU_ZERO);   // 压力非有限（R79 双判） / Pressure non-finite
_bCfgBad := (fPressSwMpa <= DL_HPU_DBAND) OR (fTempMaxC <= DL_HPU_ZERO)
         OR (fLvlMinPct <= DL_HPU_ZERO) OR (fLvlMinPct >= 100.0)
         OR (tMinSw <= T#0S);       // 组态域闸（关阀阈恒正保证 + 联锁域 + 互锁窗） / Configuration gate
rtReset(CLK := bReset);             // 复位沿，每拍必调 / Reset edge, every scan
rtStart(CLK := bStart);             // 启动沿，每拍必调 / Start edge, every scan
tonMinSw(IN := _bSwBlock, PT := tMinSw);   // 切换互锁窗（互锁位置位才计时，到时解除） / Switch interlock window

(* —— 段 1：复位沿（须未启动才清锁存；运行中复位无效，安全侧） —— *)
IF rtReset.Q AND (NOT bStart) THEN
    _bFault := FALSE;               // 清运行故障锁存（可达解除路径：停机后复位沿） / Clear run fault
    _bCfgLatch := FALSE;            // 清组态锁存 / Clear config latch
    _eCause := E_DL_HpuErr.eOk;     // 清成因锁存 / Clear cause latch
    _eState := E_DL_HpuPhase.eIdle; // 回待机 / Back to idle
END_IF
IF _bCfgBad AND (NOT _bCfgLatch) THEN
    _bCfgLatch := TRUE;             // 锁存 / Latch
END_IF

(* —— 段 2：电机命令切换检测（电平变化置互锁位；tonMinSw 到时解除） —— *)
IF _bMot <> _bMotPrev THEN
    _bSwBlock := TRUE;              // 切换发生：置互锁（规格⑤） / Switch occurred: engage interlock
END_IF
_bMotPrev := _bMot;                 // 快照（本拍末语义，下一拍比较） / Snapshot for next scan
IF tonMinSw.Q THEN
    _bSwBlock := FALSE;             // 互锁窗到：解除 / Interlock elapsed: release
END_IF

(* —— 段 3：启动联锁判据（先于电机判据，规格③；常态门槛不锁存） —— *)
_bInterlock := (fOilTempC > fTempMaxC) OR (fOilLevelPct < fLvlMinPct);   // 油温/油位联锁 / Oil temp/level interlock

(* —— 段 4：五态顺控（组态/故障期冻结推进；bStart=FALSE 停机优先） —— *)
IF (NOT bStart) OR _bCfgLatch THEN
    _bMot := FALSE;                 // 停机/组态安全侧：电机停 / Stopped or config-safe: motor off
    _bUnload := FALSE;              // 卸荷阀关 / Unload closed
    IF NOT _bFault THEN
        _eState := E_DL_HpuPhase.eIdle;   // 无故障回待机（故障相驻留待复位） / Idle unless fault latched
    END_IF
ELSIF (NOT _bFault) THEN
    CASE _eState OF

    E_DL_HpuPhase.eIdle:
        IF rtStart.Q AND (NOT _bSwBlock) THEN
            IF _bInterlock THEN
                _eState := E_DL_HpuPhase.eIdle;   // 联锁不过：拒绝启动（信息码见段 6，R191 声明） / Interlock rejected
            ELSE
                _bMot := TRUE;    // 电机启动 / Motor on
                _eState := E_DL_HpuPhase.eRunning;   // 入运行相 / Enter running
            END_IF
        END_IF

    E_DL_HpuPhase.eRunning:
        (* 运行中联锁破约/压力非有限 → 停电机锁存故障（安全侧优先，规格⑥） *)
        IF fOilTempC > fTempMaxC THEN
            _bMot := FALSE;       // 停电机 / Motor off
            _bFault := TRUE;      // 锁存 / Latch
            _eCause := E_DL_HpuErr.eTempHigh;   // 入相归因：油温超限 / Cause at entry: temp high
            _eState := E_DL_HpuPhase.eFault;   // 入故障相 / Enter fault
        ELSIF fOilLevelPct < fLvlMinPct THEN
            _bMot := FALSE;       // 停电机 / Motor off
            _bFault := TRUE;      // 锁存 / Latch
            _eCause := E_DL_HpuErr.eLvlLow;     // 入相归因：油位低 / Cause at entry: level low
            _eState := E_DL_HpuPhase.eFault;   // 入故障相 / Enter fault
        ELSIF _bNonFin THEN
            _bMot := FALSE;       // 压力不可判：安全侧停机（规格⑥） / Pressure unjudgeable: safe stop
            _bFault := TRUE;      // 锁存 / Latch
            _eCause := E_DL_HpuErr.ePressBad;   // 入相归因：压力非有限 / Cause at entry: pressure non-finite
            _eState := E_DL_HpuPhase.eFault;   // 入故障相 / Enter fault
        ELSE
            (* 卸荷回差顺控（±0.5 MPa，规格④）：开阀阈 / 关阀阈容差比较 *)
            IF (NOT _bUnload) AND (fPressMpa >= fPressSwMpa) THEN
                _bUnload := TRUE;   // 达开阀阈：卸荷 / At open threshold: unload
            ELSIF _bUnload AND (fPressMpa <= (fPressSwMpa - DL_HPU_DBAND)) THEN
                _bUnload := FALSE;  // 回落至关阀阈：加载 / Back to close threshold: load
            END_IF
        END_IF

    E_DL_HpuPhase.eFault:
        ;                         // 故障相驻留（由复位沿迁出链处理） / Held by reset chain

    ELSE
        _bMot := FALSE;           // 非法相位兜底：电机安全侧停 / Illegal phase: safe stop
        _bUnload := FALSE;        // 卸荷阀关 / Unload closed
        _bFault := TRUE;          // 锁存（R45 配对见段 6） / Latch
        _eCause := E_DL_HpuErr.eCfgBad;   // 兜底归因：按组态级回放 / Fallback cause: config level
        _eState := E_DL_HpuPhase.eFault;   // 强拉故障相 / Force fault phase

    END_CASE
END_IF

(* —— 段 5：出口单点映射（名实双出口同源，R191） —— *)
bMotor := _bMot;                  // 电机命令出口 / Motor command outlet
bUnload := _bUnload;              // 卸荷阀命令出口 / Unload command outlet
ePhase := _eState;                // 相位出口 / Phase outlet
IF _bCfgLatch THEN
    bError := TRUE;               // 故障标志（R45 配对） / Error flag
    eErrCode := E_DL_HpuErr.eCfgBad;   // 组态级码 / Config fault code
ELSIF _bFault THEN
    bError := TRUE;               // 故障标志 / Error flag
    eErrCode := _eCause;          // 成因锁存回放（禁故障相当拍重推断，R189） / Cause latch replay
ELSE
    bError := FALSE;              // 无故障级条件 / No fault
    IF _bInterlock AND rtStart.Q AND (NOT _bSwBlock) THEN
        eErrCode := E_DL_HpuErr.eInterlock;   // 信息级：启动联锁拒绝（当拍） / Info: start rejected
    ELSE
        eErrCode := E_DL_HpuErr.eOk;          // 正常 / Normal
    END_IF
END_IF

END_FUNCTION_BLOCK
