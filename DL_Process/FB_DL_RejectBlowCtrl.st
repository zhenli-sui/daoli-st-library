(*
    FB_DL_RejectBlowCtrl —— 输送线剔除气吹执行时序（NG 预告 → 距离/速度延时 → 定宽气吹 → 对账）
    ------------------------------------------------------------------
    组件名称  : FB_DL_RejectBlowCtrl
    分类      : DL_Process / Rejection
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : 自研线 s9-conv（R7 先例同口径）：剔除气吹执行时序属输送线
                工程惯例的 clean-room 自有实现；判定域（视觉 / 称重）与
                诊断域（堵塞）归邻件，本件零借用；实现 / 引脚名 / 码位 /
                对账口径 100% 自有；无闭源参考。
    平台      : 纯 IEC 61131-3（ENUM + CASE + TON / R_TRIG + 标准换算），
                CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R72 构建轮 · 批 4 · 序号 11）
    ------------------------------------------------------------------
    功能说明  : 灌装 / 包装线吹除 NG 瓶：eIdle →（bNgFlag 上升沿布防）
                eArm（延时窗 = fDistNgToGate / fBeltVel 秒换算毫秒，组态
                容差即引脚侧自行加权，本件按纯行程 / 速度口径）→ eBlow
                （定宽气吹脉冲 tBlowPulse）→ eConfirm（确认窗 tConfirmWin
                满拍**复验一次** NG 离线状态，R41/R42 同拍竞态口径：窗满拍
                反馈迟到临界收敛以窗满拍采样为准）→ eIdle。
                对账口径（漏剔 / 误剔 / 剔除三值互斥，窗满拍一次性判归）：
                ① 漏剔 uMissCount：窗满拍 bNgFlag 仍在位（气吹未吹走 NG）；
                ② 误剔 uFalseCount：布防后气吹执行拍 bNgFlag 已离线（无 NG
                   确认却执行气吹——预告为伪沿，好品被吹）；
                ③ 剔除 uRejectCount：气吹拍 NG 在位且窗满拍已离线（正常剔除）。
                漏剔 / 误剔计数直接进 OEE 质量因子。
                安全口径：
                ① fBeltVel 非有限 / <= 0 → **拒收布防 + NG 漏剔计数**（不发
                   气吹，防静默放行——速度不明即不剔除，宁可人工清台），
                   信息级；执行中途速度失效同样撤销布防 + 漏剔计数；
                ② 除法先判后除：fDistNgToGate / fBeltVel 仅在速度过闸后执行；
                   毫秒换算 LREAL→DINT 前做实数上界钳制（DL_RBC_TMAX，
                   防溢出方向翻转，R151）；
                ③ 失能 → bBlowCmd 清零 + 布防撤销（停机相输出清零，R57）；
                   计数保留（OEE 台账语义）；
                ④ 组态闸：tBlowPulse / tConfirmWin 非正 或 fDistNgToGate
                   非有限 / 非正 → 故障锁存（锁存期 NG 沿一律按漏剔计数，
                   宁多计不漏计）。
    错误码    : 16#0005_0630 速度不明拒剔（fBeltVel 非有限 / 非正，布防撤销
                            + 漏剔计数），条件期重算 —— 信息级，不置 bError
                16#0005_0631 组态非法（tBlowPulse / tConfirmWin 非正 /
                            fDistNgToGate 非有限 / 非正），锁存至复位沿
                            —— 故障级
                加码反证句（R90）：0630 由「布防撤销 + 漏剔计数递增」唯一
                观测（正常剔除路径漏剔计数不动）；0631 与 0630 输出可分
                （bError 与锁存回放 vs 条件信息级），成因互斥（组态表 vs
                运行速度），故各立一码。
    码位总账  : 16#0005_0630 用 ｜ 16#0005_0631 用
                （0620~0622 / 3036~3038 已由同段邻件占用，本件不占）
    边界与披露: 一 R_TRIG（rtNg / rtReset）与 TON（tonPhase）每拍**无条件
                   调用**（规则 ⑦）；tonPhase PT 按相选择（布防延时 / 气吹
                   定宽 / 确认窗三态一实例，R367 逐相 PT 口径），IN = 相驻留
                   显式变量；
                二 零全局变量、零 VAR_EXTERNAL、零物理地址；
                三 归属 Ownership：E_DL_RejectPhase 属主为本文件（全库唯一
                   定义，R264），引用件只引用不重声明；
                四 状态机 ENUM + CASE 必带 ELSE 兜底（非法枚举值 → eFault
                   锁存）+ 段 5b 统一故障迁入闸（R274）；
                五 域闸逐项点名（R272）：fBeltVel / fDistNgToGate 双浮点引脚
                   全部纳入非有限与符号闸；
                六 换算链：tArmDelay := DINT_TO_TIME(LREAL_TO_DINT(钳制后的
                   行程毫秒))，钳制上界 2147483000 ms（< 2^31 − 347，
                   LREAL_TO_DINT 域内可表反算，R63）；
                七 分工声明：FB_DL_VisionResultGate（视觉结果放行闸）、
                   FB_DL_WeightCheckReject（称重 NG 判定）、
                   FB_DL_ConveyorJamDetect（堵塞诊断）——三者均属「判定」域，
                   本件只做「预告 → 延时 → 气吹 → 对账」**执行时序**域
                   （R363 邻接共存先例），不判 NG、不诊断堵塞；
                八 复位沿作用域（R311）：清故障锁存 + 清锁存码 + 迁 eIdle +
                   撤布防，**不清** uRejectCount / uMissCount / uFalseCount
                   （OEE 台账语义，只随失能保留、由上位归档后清）；
                九 依赖声明：仅 Standard.library（TON / R_TRIG），零厂商
                   方言；
                十 接口契约：bNgFlag 须为**电平型**预告（预告对象离线前保持
                   在位），脉型预告会在气吹拍被判为误剔（uFalseCount 虚高）
                   ——脉型上游须先展宽再接入；失能相（bEn = FALSE）的 NG 沿
                   不布防不计数（停线工况，宁缺勿滥口径）。
    验收向量  : V1 正常剔除：NG 沿 → 行程延时 → 气吹拍 NG 在位 → 窗满拍
                NG 离线 → uRejectCount + 1；
                V2 漏剔：窗满拍 bNgFlag 仍在位 → uMissCount + 1；
                V3 误剔：气吹拍 bNgFlag 已离线 → uFalseCount + 1；
                V4 fBeltVel = 0 / NaN → NG 沿按漏剔计数、不发气吹、0630；
                V5 tBlowPulse = T#0MS → 0631 锁存；V6 失能 → bBlowCmd 清零
                + 布防撤销；V7 复位沿 → 解锁回 eIdle（计数不清）。
                算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    修订记录  : 2026-11-23 v1.0.0 首次入库（R72 构建轮 · 批 4 · 序号 11）
*)
TYPE E_DL_RejectPhase :
(
    eIdle    := 0,                         // 空闲：等 NG 预告沿布防 / idle, waiting for the NG leading edge
    eArm     := 10,                        // 布防延时：行程 / 速度换算延时窗 / armed, the travel delay window
    eBlow    := 20,                        // 定宽气吹：tBlowPulse 定宽脉冲 / blowing, the fixed width pulse
    eConfirm := 30,                        // 确认窗：窗满拍复验 NG 离线 / confirm, the recheck window
    eFault   := 60                         // 故障：锁存待复位 / fault, latched until the reset
);
END_TYPE

FUNCTION_BLOCK FB_DL_RejectBlowCtrl
VAR_INPUT
    bNgFlag       : BOOL := FALSE;         (* 上游 NG 预告（视觉 / 称重判定输出），[标志] / the upstream NG leading flag *)
    fBeltVel      : LREAL := 1000.0;       (* 输送带速度，[mm/s]，非有限或非正拒剔 / the belt velocity in mm per second *)
    fDistNgToGate : LREAL := 500.0;        (* NG 检测位到气吹位间距，[mm]，禁非有限 / 非正 / the distance from the detector to the gate in mm *)
    tBlowPulse    : TIME := T#100MS;       (* 气吹定宽，[ms]，禁非正 / the blow pulse width *)
    tConfirmWin   : TIME := T#200MS;       (* 剔除确认窗，[ms]，禁非正 / the reject confirmation window *)
    bEn           : BOOL := FALSE;         (* 使能，[标志]，FALSE 撤布防清气吹（计数保留）/ the enable *)
    bReset        : BOOL := FALSE;         (* 故障复位，[标志]，上升沿唯一解除 / the fault reset *)
END_VAR
VAR_OUTPUT
    bBlowCmd    : BOOL := FALSE;           (* 气吹指令出口（定宽脉冲），[标志] / the blow command outlet *)
    uRejectCount: UDINT := 0;              (* 剔除成功计数（OEE 台账），[件] / the successful reject count *)
    uMissCount  : UDINT := 0;              (* 漏剔计数（窗满 NG 仍在位 / 速度不明拒剔），[件] / the miss count *)
    uFalseCount : UDINT := 0;              (* 误剔计数（气吹拍 NG 已离线），[件] / the false reject count *)
    eState      : E_DL_RejectPhase := E_DL_RejectPhase.eIdle; // 主状态机当前态 [状态] / the current state
    bError      : BOOL := FALSE;           (* 故障标志，与锁存同源（R191）/ the fault flag from the latch *)
    nErrCode    : UDINT := 16#0000_0000;   (* 错误码，0 = 正常，故障锁存回放（R187）/ the error id *)
END_VAR
VAR
    _bInit      : BOOL := FALSE;           (* 首拍初始化标志（R310）/ the first scan flag *)
    _eState     : E_DL_RejectPhase := E_DL_RejectPhase.eIdle; // 内部状态寄存器 / the internal state register
    _bFault     : BOOL := FALSE;           (* 故障锁存副本，仅复位沿解除 / the fault latch copy *)
    _nCodeLatch : UDINT := 0;              (* 锁存成因码，故障期回放 / the latched cause code *)
    _bVelBad    : BOOL := FALSE;           (* 速度不明标志（逐拍重算，R272 闸）/ the velocity invalid flag *)
    _bCfgBad    : BOOL := FALSE;           (* 组态非法标志（逐拍重算，仅用于首次锁存）/ the config fault flag *)
    _bBlow      : BOOL := FALSE;           (* 气吹单相内部位（统一出口映射）/ the internal blow bit *)
    _bFalseSus  : BOOL := FALSE;           (* 误剔嫌疑标志（气吹拍 NG 已离线登记）/ the false reject suspect flag *)
    _tArmDelay  : TIME := T#0S;             (* 布防延时换算值（过闸后逐拍重算）[ms] / the computed arm delay *)
    _tPhasePt   : TIME := T#0S;             (* 逐相 PT 预置（R367：每拍先给缺省再按相覆盖）[ms] / the per phase PT preset *)
    _fDelayMs   : LREAL := 0.0;             (* 行程毫秒中间量（钳制前）[ms] / the travel milliseconds temporary *)
    nDelayMs    : DINT := 0;                (* 钳制后的行程毫秒 [ms] / the clamped travel milliseconds *)
    rtNg        : R_TRIG;                  (* NG 预告上升沿实例（无条件调用）/ the NG leading edge instance *)
    rtReset     : R_TRIG;                  (* 复位沿实例（无条件调用）/ the reset edge instance *)
    tonPhase    : TON;                     (* 相计时实例（逐相 PT，无条件调用，R367）/ the phase timer *)
    _bPhaseIn   : BOOL := FALSE;           (* 相驻留判据（tonPhase IN 显式变量）/ the phase residency flag *)
END_VAR
VAR CONSTANT
    DL_RBC_CODE_VEL : UDINT := 16#0005_0630; // 速度不明信息码 [码] / the velocity info code
    DL_RBC_CODE_CFG : UDINT := 16#0005_0631; // 组态非法故障码 [码] / the config fault code
    DL_RBC_TZERO    : TIME := T#0S;          (* 零时长哨兵 [ms] / the zero duration sentinel *)
    DL_RBC_TMAX     : LREAL := 2147483000.0; (* 换算毫秒钳制上界（< 2^31 可表反算，R63）[ms] / the conversion clamp ceiling *)
    DL_RBC_CMAX     : UDINT := 2147483000;   (* 计数饱和上限（UDINT 域，防回绕）[件] / the count saturation cap *)
    DL_RBC_MS_SEC   : LREAL := 1000.0;       (* 秒到毫秒换算常量乘子 [ms/s] / the seconds to milliseconds multiplier *)
    DL_RBC_FZERO    : LREAL := 0.0;          (* 浮点零哨兵 [mm/s 或 mm] / the float zero sentinel *)
    DL_RBC_ZERO     : UDINT := 0;            (* 无符号零哨兵 [码或件] / the unsigned zero sentinel *)
    DL_RBC_ONE      : UDINT := 1;            (* 计数步进 [件] / the count step *)
END_VAR

// 段 0｜沿检测无条件周期调用（规则 ⑦）/ segment 0, the unconditional edge refresh
rtNg(CLK := bNgFlag);                      // NG 预告沿 / the NG leading edge
rtReset(CLK := bReset);                    // 复位沿 / the reset edge

// 段 1｜首拍初始化（R310）/ segment 1, the first scan init
IF NOT _bInit THEN                         // 首拍一拍 / the first scan
    _bInit := TRUE;                        // 置首拍标志 / raise the first scan flag
    _bFault := FALSE;                      // 故障锁存显式清零 / clear the fault latch explicitly
    _eState := E_DL_RejectPhase.eIdle;     // 状态显式落空闲 / place the state to idle
END_IF

// 段 2｜域闸（R272 全枚举：fBeltVel / fDistNgToGate 双引脚；非有限双判 R79）/ segment 2, the domain gates
_bVelBad := (fBeltVel <> fBeltVel) OR ((fBeltVel - fBeltVel) <> DL_RBC_FZERO) OR (fBeltVel <= DL_RBC_FZERO); // 速度非有限或非正 / the velocity invalid
_bCfgBad := (tBlowPulse <= DL_RBC_TZERO) OR (tConfirmWin <= DL_RBC_TZERO) // 定宽或确认窗非正 / a non positive pulse or window
         OR (fDistNgToGate <> fDistNgToGate) OR ((fDistNgToGate - fDistNgToGate) <> DL_RBC_FZERO) // 间距非有限 / the distance non finite
         OR (fDistNgToGate <= DL_RBC_FZERO); // 间距非正 / a non positive distance

// 段 3｜复位沿与首次成因锁存（复位沿唯一解除，R188；故障期不重推断，R189）/ segment 3, the reset edge and the first cause latch
IF rtReset.Q THEN                          // 复位上升沿 / the reset rising edge
    _bFault := FALSE;                      // 清故障锁存（恒可达，R152 自证）/ clear the fault latch
    _nCodeLatch := DL_RBC_ZERO;            // 清锁存码（作用域 R311：不清三计数，台账语义）/ clear the latched code
    _eState := E_DL_RejectPhase.eIdle;     // 迁回空闲 / back to idle
END_IF
IF (NOT _bFault) AND _bCfgBad THEN         // 组态非法未锁存命中 / a config fault hit
    _bFault := TRUE;                       // 置锁存 / latch the fault
    _nCodeLatch := DL_RBC_CODE_CFG;        // 登记组态码 / register the config code
END_IF

// 段 4｜布防延时换算（先判后除：速度过闸才做除法；实数上界钳制防换算溢出）/ segment 4, the arm delay conversion
IF (NOT _bVelBad) AND (NOT _bCfgBad) THEN  // 双闸通过才换算 / both gates passed
    _fDelayMs := (fDistNgToGate / fBeltVel) * DL_RBC_MS_SEC; // 行程 / 速度 × 1000（除子已闸非零非有限）/ the travel milliseconds
    IF _fDelayMs > DL_RBC_TMAX THEN        // 实数上界钳制（防 LREAL_TO_DINT 溢出方向翻转，R151）/ the clamp before narrowing
        nDelayMs := LREAL_TO_DINT(DL_RBC_TMAX); // 钳到上界 / clamp to the ceiling
    ELSIF _fDelayMs < DL_RBC_FZERO THEN    // 负值防御（双闸后结构性不可达，兜底口径）/ the negative guard
        nDelayMs := 0;                     // 钳到零 / clamp to zero
    ELSE                                   // 域内换算 / the in domain conversion
        nDelayMs := LREAL_TO_DINT(_fDelayMs); // 标准降位转换 / the standard narrowing
    END_IF
    _tArmDelay := DINT_TO_TIME(nDelayMs);  // 毫秒转 TIME / the milliseconds to TIME
ELSE                                       // 闸未通过 / the gates failed
    _tArmDelay := DL_RBC_TZERO;            // 延时清零（布防路径已拒收）/ zero the delay
END_IF

// 段 5｜主状态机（ENUM + CASE，ELSE 兜底；相驻留显式变量供段 0b 定时器）/ segment 5, the main state machine
CASE _eState OF

    E_DL_RejectPhase.eIdle:                // 空闲相：等 NG 沿布防 / the idle phase
        _bBlow := FALSE;                   // 气吹位清零 / clear the blow bit
        IF rtNg.Q AND bEn AND (NOT _bFault) AND (NOT _bVelBad) AND (NOT _bCfgBad) THEN // 布防沿 + 全量闸位复检（R274）/ the arming edge with the full gate recheck
            _bFalseSus := FALSE;           // 布防清嫌疑标志 / clear the suspect flag
            _eState := E_DL_RejectPhase.eArm; // 迁入布防相 / enter the arm phase
        ELSIF rtNg.Q AND bEn AND (NOT _bFault) AND (_bVelBad OR _bCfgBad) THEN // 速度不明的 NG 沿（组态非法沿已在段 3 先锁存，不会进入本支）/ the NG edge with an invalid velocity
            IF uMissCount < DL_RBC_CMAX THEN // 饱和闸（UDINT 域防回绕）/ the saturation cap
                uMissCount := uMissCount + DL_RBC_ONE; // 漏剔计数（速度不明即不剔除，宁可人工清台）/ count a miss
            END_IF
        END_IF                             // 失能相的 NG 沿不布防不计数（停线工况声明，头注释边界十）

    E_DL_RejectPhase.eArm:                 // 布防相：等行程延时 / the arm phase
        IF (NOT bEn) OR _bVelBad THEN      // 失能或速度中途失效：撤布防 + 漏剔计数 / the disarm on disable or velocity loss
            IF uMissCount < DL_RBC_CMAX THEN // 饱和闸 / the saturation cap
                uMissCount := uMissCount + DL_RBC_ONE; // 漏剔计数 / count a miss
            END_IF
            _eState := E_DL_RejectPhase.eIdle; // 撤布防回空闲 / disarm to idle
        ELSIF tonPhase.Q THEN              // 行程延时计满（零延时换算合法，立即吹口径）/ the delay elapsed
            _eState := E_DL_RejectPhase.eBlow; // 迁入气吹相 / enter the blow phase
        END_IF

    E_DL_RejectPhase.eBlow:                // 气吹相：定宽脉冲 + 误剔登记 / the blow phase
        _bBlow := TRUE;                    // 气吹位置位 / raise the blow bit
        IF (NOT bNgFlag) AND (NOT _bFalseSus) THEN // NG 已离线却执行气吹（电平型预告伪沿，接口契约见头注释边界十）登记嫌疑（一次性）/ the false reject registration
            _bFalseSus := TRUE;            // 置嫌疑标志（窗满拍判归互斥用）/ raise the suspect flag
            IF uFalseCount < DL_RBC_CMAX THEN // 饱和闸 / the saturation cap
                uFalseCount := uFalseCount + DL_RBC_ONE; // 误剔计数（布防后无 NG 确认却执行气吹）/ count a false reject
            END_IF
        END_IF
        IF (NOT bEn) OR _bVelBad THEN      // 气吹中失能 / 速度失效：撤气吹（安全侧停吹）/ the blow abort
            _bBlow := FALSE;               // 气吹位清零 / clear the blow bit
            _eState := E_DL_RejectPhase.eIdle; // 回空闲 / to idle
        ELSIF tonPhase.Q THEN              // 定宽计满 / the pulse elapsed
            _bBlow := FALSE;               // 定宽到撤气吹（R129 两拍口径：本拍撤、映射段不再改）/ drop the blow bit
            _eState := E_DL_RejectPhase.eConfirm; // 迁入确认相 / enter the confirm phase
        END_IF

    E_DL_RejectPhase.eConfirm:             // 确认相：窗满拍复验一次（R41/R42：窗满拍采样为准）/ the confirm phase
        IF (NOT bEn) THEN                  // 失能：撤销对账（失能拍不判归，声明口径）/ the disabled confirm
            _eState := E_DL_RejectPhase.eIdle; // 回空闲 / to idle
        ELSIF tonPhase.Q THEN              // 确认窗满拍 / the window full scan
            IF bNgFlag THEN                // 窗满拍 NG 仍在位（气吹未吹走 NG）/ the NG still present
                IF uMissCount < DL_RBC_CMAX THEN // 饱和闸 / the saturation cap
                    uMissCount := uMissCount + DL_RBC_ONE; // 漏剔计数 / count a miss
                END_IF
            ELSIF NOT _bFalseSus THEN      // 窗满离线且非误剔嫌疑（气吹拍在位）→ 正常剔除判归 / the normal reject verdict
                IF uRejectCount < DL_RBC_CMAX THEN // 饱和闸 / the saturation cap
                    uRejectCount := uRejectCount + DL_RBC_ONE; // 剔除成功计数 / count a reject
                END_IF
            END_IF                         // 误剔嫌疑者已在气吹拍计入 uFalseCount，三值互斥不重复判归
            _bFalseSus := FALSE;           // 判归完成清嫌疑 / clear the suspect flag
            _eState := E_DL_RejectPhase.eIdle; // 回空闲 / to idle
        END_IF

    E_DL_RejectPhase.eFault:               // 故障相：等复位沿（解除可达）；锁存期 NG 沿按漏剔计数（宁多计不漏计，码位声明口径）/ the fault phase with the miss accounting
        IF rtNg.Q AND bEn THEN             // 锁存期 NG 沿 / the NG edge while latched
            IF uMissCount < DL_RBC_CMAX THEN // 饱和闸 / the saturation cap
                uMissCount := uMissCount + DL_RBC_ONE; // 漏剔计数 / count a miss
            END_IF
        END_IF
        IF NOT _bFault THEN                // 锁存已清才迁出 / the exit after the latch cleared
            _eState := E_DL_RejectPhase.eIdle; // 迁回空闲 / back to idle
        END_IF

    ELSE                                   // 非法枚举值拦截 / the illegal enumeration guard
        _eState := E_DL_RejectPhase.eFault; // 落故障相 / force to the fault phase
        _bFault := TRUE;                   // 置锁存 / latch the fault
        _nCodeLatch := DL_RBC_CODE_CFG;    // 复用组态码（R90 反证：非法枚举不可达）/ reuse the config code

END_CASE

// 段 5b｜故障统一迁入闸（置于状态机之后，R274 迁入完备性）/ segment 5b, the unified fault entry gate
IF _bFault AND (_eState <> E_DL_RejectPhase.eFault) THEN // 已锁存但不在故障相 / latched but not in the fault phase
    _eState := E_DL_RejectPhase.eFault;    // 任何相检出故障一律落故障相 / any phase with a latch lands in the fault phase
END_IF

// 段 5c｜失能停机相输出清零（锁存保留，R57 / R191 声明）/ segment 5c, the disable clearing
IF (NOT bEn) AND (_eState <> E_DL_RejectPhase.eFault) THEN // 失能且不在故障相 / disabled, not in the fault phase
    _eState := E_DL_RejectPhase.eIdle;     // 撤布防回空闲（CASE 已逐相处理，此处兜底）/ disarm to idle
    _bBlow := FALSE;                       // 气吹位清零 / clear the blow bit
END_IF

// 段 6｜逐相 PT 预置与相计时无条件调用（R367：每拍先给缺省 PT 再按相覆盖，
//        tonPhase 调用体在分支之外每拍必达，红线 5）/ segment 6, the per phase
//        PT preset and the unconditional timer call
_tPhasePt := tConfirmWin;                  // 缺省 PT（R367 口径）/ the default PT
IF _eState = E_DL_RejectPhase.eArm THEN    // 布防相 PT = 换算延时 / the arm PT
    _tPhasePt := _tArmDelay;               // 覆盖为换算延时 / override with the delay
END_IF
IF _eState = E_DL_RejectPhase.eBlow THEN   // 气吹相 PT = 定宽 / the blow PT
    _tPhasePt := tBlowPulse;               // 覆盖为定宽 / override with the pulse
END_IF
_bPhaseIn := (_eState = E_DL_RejectPhase.eArm) OR (_eState = E_DL_RejectPhase.eBlow) OR (_eState = E_DL_RejectPhase.eConfirm); // 相驻留显式变量 / the residency flag
tonPhase(IN := _bPhaseIn AND bEn AND (NOT _bFault), PT := _tPhasePt); // 无条件周期调用（规则 ⑦）/ the unconditional call

// 段 7｜统一出口（名实双出口同源，R191）/ segment 7, the unified outlet
bBlowCmd := _bBlow AND bEn AND (NOT _bFault); // 气吹出口（失能 / 故障双保险清零）/ the blow outlet
eState := _eState;                         // 状态出口 / the state outlet
bError := _bFault;                         // 故障标志与锁存同源 / the fault flag from the latch
IF _bFault THEN                            // 故障锁存回放（R187）/ the latched replay
    nErrCode := _nCodeLatch;               // 回放锁存码 / replay the latched code
ELSIF _bVelBad THEN                        // 速度不明信息级（条件期重算，R187 信息级口径）/ the velocity info
    nErrCode := DL_RBC_CODE_VEL;           // 信息级 / info level
ELSE                                       // 无事件 / no event
    nErrCode := DL_RBC_ZERO;               // 正常 / ok
END_IF
END_FUNCTION_BLOCK
