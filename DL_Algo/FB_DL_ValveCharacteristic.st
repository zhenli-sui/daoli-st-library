(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ValveCharacteristic
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（ABS / LN / SQRT / MIN / MAX / R_TRIG）
 * 功能描述 (Function)   : 把「期望流量百分比」按调节阀固有特性折算为「阀位百分比」，
 *                         支持线性 / 等百分比 / 快开三种特性，带可调比、行程上下限、
 *                         输出死区与饱和标志。现场用途：等百分比阀按线性给定会让小流量段
 *                         分辨率不足、大流量段增益过高并引起振荡；本件把特性补偿收回
 *                         PLC 侧，工艺员不再靠「凭经验把给定调弯」。
 *                         死区只压输出抖动，不改变内部限幅结果；掉使能保持上次阀位
 *                         （阀位突跳比保持更危险），阀位回零由上层安全逻辑负责。
 * 出口契约 (Exit)       : fTravel 为最终阀位给定，域为生效行程上下限之间；
 *                         bSaturated 表示输出被流量给定域、可调比下限或行程上下限任一截断；
 *                         bError 为故障级锁存，只由 2010 / 2011 / 2012 三码置位，
 *                         bReset 上升沿清故障回空闲。信息码 2001 / 2002 / 2003 每拍重算。
 * 开源溯源 (Origin)     : 来源标签 isa88-process（工艺参数域）。许可证：ISA-88 为公开标准，
 *                         无源码可复制；调节阀流量特性公式取自公开的过程控制教材定义。
 *                         借鉴点：把「特性」做成**枚举参数域**而非三个独立功能块——三种特性
 *                         共用同一套限幅、死区与状态机，拆块会产生三份重复代码，
 *                         且特性切换在配方里属于运行期行为。
 *                         clean-room 独立实现，与任何厂商阀门功能块无代码关联。
 * 码位说明 (Codes)      : 信息级 16#0002_2001（输出被下限截断）/ 2002（输出被上限截断）/
 *                         2003（死区保持）；故障级 16#0002_2010（行程配置非法）/
 *                         2011（可调比对数的二次守卫触发）/ 2012（非法特性枚举兜底）。
 *                         共 6 码，全部落在 R12 计划第 1.2 节本件码段内。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: ABS / LN / SQRT / MAX / R_TRIG
 * 红线自检 (Redline)    : 1 ✓ 零全局变量表依赖、零外部变量声明、零物理地址
 *                         2 ✓ 纯 IEC 61131-3，无指针、无厂商库
 *                         3 ✓ 对数与开方先做域守护、可调比下限保证对数分母不为零、
 *                             行程上下限倒置直接判故障而不交换、死区比较用容差不用判等
 *                         4 ✓ 全变量中英双语同行注释
 *                         5 ✓ 三态 ENUM + CASE 全覆盖 + ELSE 兜底（2012）；特性选择亦全覆盖
 *                         6 ✓ R_TRIG 实例在 CASE 之外每拍无条件刷新
 *                         7 ✓ END_FUNCTION_BLOCK 位于文件最后有效行
 * 规格偏离留档 (Deviation):
 *   计划 3.11 节正文提到 2004 / 2005 / 2006 三个「输入钳位」码，但同计划第 1.2 节给本件
 *   只分配了 2001~2003 与 2010~2012 六个码，两者冲突。按「码位表为准、不得自创」的纪律，
 *   本实现对输入钳位采取如下归并：流量给定越界钳位并入 2001 / 2002（越界必然让输出打端点，
 *   语义与截断一致）；可调比与死区的钳位属整定参数修正，不单独置码，仅钳位后照算，
 *   并在头注释与本段注释中写明，不再占用段外码。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（R12 · DL_Algo 工艺参数域）
 *   2026-11-15  v1.0.1  终审修复：投运与故障复位首拍不再强制阀位回行程下限
 *                       （原实现 fLast := fLoTravel 会让阀门在复位当拍直冲最小开度，
 *                       与本件「不做阀位回零、突跳比保持更危险」的契约自相矛盾）；
 *                       改为「保持上次阀位并夹到生效行程内」，同时补齐行程域的出口保证
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_ValveCharKind（归属 DL_Algo，与本功能块同文件）
 * 含义: 调节阀固有流量特性。三种特性共用同一套限幅与死区逻辑。
 *----------------------------------------------------------------------------*)
TYPE E_DL_ValveCharKind :
(
    eLinear       := 0,    // 线性特性：阀位与流量成正比 / Linear: travel proportional to flow
    eEqualPercent := 10,   // 等百分比特性：单位阀位变化引起的流量变化与当前流量成正比 / Equal percentage
    eQuickOpen    := 20    // 快开特性：小阀位即获大流量，后段渐平 / Quick opening, fast rise then flat
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_ValveCharState（归属 DL_Algo，与本功能块同文件）
 * 含义: 特性补偿块的离散状态。
 *----------------------------------------------------------------------------*)
TYPE E_DL_ValveCharState :
(
    eIdle   := 0,     // 空闲：等待使能与行程配置校验 / Idle: waiting for enable and travel validation
    eActive := 10,    // 运行：折算特性、限幅、死区、输出 / Active: convert, clamp, deadband, publish
    eFault  := 99     // 故障：配置非法或枚举兜底，输出保持上次 / Fault: invalid config, travel held
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_ValveCharacteristic
 * 调用约定: 每个扫描周期无条件调用一次；bEnable 为 FALSE 时阀位保持上次值。
 * 无状态泄漏: 全部状态驻留于实例私有 VAR，零全局引用，可多实例并行。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_ValveCharacteristic
VAR_INPUT
    bEnable       : BOOL;                                // 使能，FALSE 时阀位保持上次输出 / Enable, holds the last travel when FALSE
    bReset        : BOOL;                                // 上升沿清故障回空闲 / Rising edge clears the fault
    fFlowCmd      : REAL := 0.0;                         // 期望流量 [百分比]，域 0~100 / Desired flow in percent, 0..100
    eChar         : E_DL_ValveCharKind := E_DL_ValveCharKind.eEqualPercent;  // 固有特性 [-] / Inherent characteristic
    fRangeability : REAL := 30.0;                        // 可调比 [-]，域 2~100，越界钳位 / Rangeability, clamped to 2..100
    fMinTravel    : REAL := 0.0;                         // 最小阀位 [百分比]，域 0~100 / Minimum travel in percent
    fMaxTravel    : REAL := 100.0;                       // 最大阀位 [百分比]，域 0~100 / Maximum travel in percent
    fDeadband     : REAL := 0.2;                         // 输出死区 [百分比]，变化小于此值保持上次 / Output deadband in percent
END_VAR
VAR_OUTPUT
    fTravel       : REAL;                                // 阀位给定 [百分比]，域 fMinTravel~fMaxTravel / Travel command in percent
    bSaturated    : BOOL;                                // 输出被上下限或可调比下限截断 TRUE / Output clamped
    bError        : BOOL;                                // 故障级锁存，仅 2010~2012 置位 / Latched fault
    uErrorId      : UDINT;                               // 事件码，0 = 无事件 / Event code, zero means none
    eState        : E_DL_ValveCharState;                 // 主状态机当前状态 / Current state
END_VAR
VAR
    fbTrigReset   : R_TRIG;                              // 复位沿，CASE 之外每拍刷新 / Reset edge, refreshed outside CASE
    ePhase        : E_DL_ValveCharState := E_DL_ValveCharState.eIdle;  // 内部状态 / Internal state
    fFlowVal      : REAL;                                // 钳位后的期望流量 [百分比] / Clamped flow command in percent
    fQ            : REAL;                                // 归一化流量 [0~1] / Normalised flow
    fR            : REAL;                                // 生效可调比 [-] / Effective rangeability
    fRaw          : REAL;                                // 未限幅的阀位 [百分比] / Unlimited travel in percent
    fLast         : REAL;                                // 上次输出阀位 [百分比] / Last travel command
    fLoTravel     : REAL;                                // 生效行程下限 [百分比] / Effective lower bound
    fHiTravel     : REAL;                                // 生效行程上限 [百分比] / Effective upper bound
    fQMin         : REAL;                                // 可调比下限对应的归一化流量 [0~1] / Normalised flow at the rangeability floor
    fDeadUse      : REAL;                                // 生效死区宽度 [百分比] / Effective deadband width
    bClampLo      : BOOL;                                // 下限截断标记 / Lower clamp flag
    bClampHi      : BOOL;                                // 上限截断标记 / Upper clamp flag
END_VAR
VAR CONSTANT
    DL_PCT_MAX    : REAL := 100.0;                       // 百分比满量程 [百分比] / Percent full scale
    DL_R_MIN      : REAL := 2.0;                         // 可调比下限 [-] / Minimum rangeability
    DL_R_MAX      : REAL := 100.0;                       // 可调比上限 [-] / Maximum rangeability
    DL_DB_MAX     : REAL := 5.0;                         // 死区宽度上限 [百分比] / Deadband ceiling in percent
    DL_EPS        : REAL := 1.0E-6;                      // 浮点判零容差 [-] / Float zero tolerance
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜复位沿每拍无条件刷新（严禁放进 CASE 内部）
 *      Reset edge refreshed unconditionally on every scan
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bReset);

(*------------------------------------------------------------------------------
 * 段 2｜输入调理：流量给定的域钳位，与整定参数的可调比 / 死区钳位
 *      Input conditioning: flow clamp plus rangeability and deadband clamps
 *      流量越界钳位必然把输出打到端点，语义等同截断，故并入 2001 / 2002 报码
 *      A clamped flow command drives the output to an end point, reported as 2001 / 2002
 *      可调比与死区的钳位只是整定参数修正，不单独置码，钳位后照算
 *      Rangeability and deadband clamps are tuning fixes and carry no dedicated code
 *-----------------------------------------------------------------------------*)
bClampLo  := FALSE;
bClampHi  := FALSE;
fFlowVal  := fFlowCmd;
IF NOT (fFlowVal >= 0.0) THEN
    fFlowVal := 0.0;
    bClampLo := TRUE;
ELSIF fFlowVal > DL_PCT_MAX THEN
    fFlowVal := DL_PCT_MAX;
    bClampHi := TRUE;
END_IF

fR := fRangeability;
IF NOT ((fR >= DL_R_MIN) AND (fR <= DL_R_MAX)) THEN
    IF fR > DL_R_MAX THEN
        fR := DL_R_MAX;
    ELSIF fR < DL_R_MIN THEN
        fR := DL_R_MIN;
    ELSE
        (* 非有限值：按上限处理，保证对数分母远离零 *)
        (* Non finite value: fall back to the ceiling so the logarithm stays safe *)
        fR := DL_R_MAX;
    END_IF
END_IF

fDeadUse := ABS(fDeadband);
IF NOT (fDeadUse <= DL_DB_MAX) THEN
    fDeadUse := DL_DB_MAX;
END_IF

fLoTravel := fMinTravel;
fHiTravel := fMaxTravel;

(*------------------------------------------------------------------------------
 * 段 3｜主状态机：三态全覆盖 + ELSE 兜底；掉使能只保持阀位，不推进任何相位
 *      Main state machine; a disabled block only holds the travel
 *-----------------------------------------------------------------------------*)
IF NOT bEnable THEN
    fTravel    := fLast;
    bSaturated := FALSE;
ELSE

    CASE ePhase OF
        E_DL_ValveCharState.eIdle:
            (* 行程配置校验：越界或倒置一律判故障，绝不静默交换上下限 *)
            (* Travel validation: out of range or inverted is a fault, never swapped *)
            IF NOT ((fMinTravel >= 0.0) AND (fMinTravel <= DL_PCT_MAX)) THEN
                bError   := TRUE;
                uErrorId := 16#0002_2010;
                ePhase   := E_DL_ValveCharState.eFault;
            ELSIF NOT ((fMaxTravel >= 0.0) AND (fMaxTravel <= DL_PCT_MAX)) THEN
                bError   := TRUE;
                uErrorId := 16#0002_2010;
                ePhase   := E_DL_ValveCharState.eFault;
            ELSIF fMinTravel > fMaxTravel THEN
                bError   := TRUE;
                uErrorId := 16#0002_2010;
                ePhase   := E_DL_ValveCharState.eFault;
            ELSE
                (* 投运与故障复位不强制阀位回零：保持上次阀位并夹到生效行程内 *)
                (* Commissioning and fault reset hold the last travel, clamped into the travel band *)
                fLast      := MIN(MAX(fLast, fLoTravel), fHiTravel);
                fTravel    := fLast;
                bSaturated := FALSE;
                uErrorId   := 16#0000_0000;
                ePhase     := E_DL_ValveCharState.eActive;
            END_IF

        E_DL_ValveCharState.eActive:
            (* 信息码每拍重算，故障码由 bError 锁存 *)
            (* Informational codes are recomputed every scan, faults stay latched *)
            uErrorId   := 16#0000_0000;
            bSaturated := FALSE;
            fQ         := fFlowVal / DL_PCT_MAX;

            CASE eChar OF
                E_DL_ValveCharKind.eLinear:
                    fRaw := fQ * DL_PCT_MAX;

                E_DL_ValveCharKind.eEqualPercent:
                    fQMin := 1.0 / fR;
                    IF fQ <= fQMin THEN
                        (* 低于可调比下限：阀位归零并记下限截断 *)
                        (* Below the rangeability floor: travel drops to zero *)
                        fRaw     := 0.0;
                        bClampLo := TRUE;
                    ELSE
                        IF ABS(LN(fR)) < DL_EPS THEN
                            (* 二次守卫：正常钳位下不可达，防调用方绕过钳位直接注入 *)
                            (* Second guard: unreachable after clamping, protects against bypass *)
                            bError   := TRUE;
                            uErrorId := 16#0002_2011;
                            ePhase   := E_DL_ValveCharState.eFault;
                        ELSE
                            fRaw := DL_PCT_MAX * (1.0 + LN(fQ) / LN(fR));
                        END_IF
                    END_IF

                E_DL_ValveCharKind.eQuickOpen:
                    (* 先取零下界再开方，浮点误差导致的负小数不会变成非数 *)
                    (* Clamp to zero before the square root so rounding cannot yield NaN *)
                    fRaw := DL_PCT_MAX * (1.0 - SQRT(MAX(0.0, 1.0 - fQ)));

                ELSE
                    (* 非法特性枚举：终端安全态 + 段内末码 *)
                    (* Illegal characteristic: terminal safe state with the segment last code *)
                    bError   := TRUE;
                    uErrorId := 16#0002_2012;
                    ePhase   := E_DL_ValveCharState.eFault;
            END_CASE

            IF ePhase = E_DL_ValveCharState.eActive THEN
                (* 行程限幅：夹到生效上下限，截断方向决定报哪个信息码 *)
                (* Travel clamp: report the direction together with the clamp *)
                IF fRaw < fLoTravel THEN
                    fRaw     := fLoTravel;
                    bClampLo := TRUE;
                ELSIF fRaw > fHiTravel THEN
                    fRaw     := fHiTravel;
                    bClampHi := TRUE;
                END_IF

                IF bClampLo THEN
                    bSaturated := TRUE;
                    IF uErrorId = 16#0000_0000 THEN
                        uErrorId := 16#0002_2001;
                    END_IF
                END_IF
                IF bClampHi THEN
                    bSaturated := TRUE;
                    IF uErrorId = 16#0000_0000 THEN
                        uErrorId := 16#0002_2002;
                    END_IF
                END_IF

                (* 死区：只压输出抖动，内部限幅结果保持不变，比较用容差不用判等 *)
                (* Deadband suppresses jitter only, the clamped value stays untouched *)
                IF ABS(fRaw - fLast) < fDeadUse THEN
                    fTravel := fLast;
                    IF uErrorId = 16#0000_0000 THEN
                        uErrorId := 16#0002_2003;
                    END_IF
                ELSE
                    fTravel := fRaw;
                    fLast   := fRaw;
                END_IF
            END_IF

        E_DL_ValveCharState.eFault:
            (* 故障态保持上次阀位，只认复位沿；不在故障态做任何折算 *)
            (* Fault holds the last travel and only the reset edge leaves it *)
            fTravel := fLast;
            IF fbTrigReset.Q THEN
                bError   := FALSE;
                uErrorId := 16#0000_0000;
                ePhase   := E_DL_ValveCharState.eIdle;
            END_IF

        ELSE
            (* 兜底：枚举被在线改坏或跨版本不兼容，阀位保持并等待复位 *)
            (* Fallback: hold the travel and wait for a reset *)
            bError   := TRUE;
            uErrorId := 16#0002_2012;
            fTravel  := fLast;
            ePhase   := E_DL_ValveCharState.eFault;
    END_CASE

END_IF

(*------------------------------------------------------------------------------
 * 段 4｜状态出口：内部状态镜像到出口引脚，便于 HMI 直接显示
 *      State mirror to the output pin for direct HMI display
 *-----------------------------------------------------------------------------*)
eState := ePhase;
END_FUNCTION_BLOCK
