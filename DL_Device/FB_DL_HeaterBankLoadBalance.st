(*
    FB_DL_HeaterBankLoadBalance —— 加热器组负载均衡选主
    ------------------------------------------------------------------
    分类      : DL_Device / Thermal
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : clean-room 自有实现；仅借鉴「按累计工时轮换主用」的公开运维常识语义，
                未复制任何闭源厂商源码，码位 100% 自有
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R76 冲刺批 C3 · #2）
    ------------------------------------------------------------------
    功能说明  : N 路加热器（rN 钳位 2..8）按累计运行工时选主：每拍从可用通道
                （健康 AND 投运允许 AND 工时有限）中选累计工时最小者为主通道，
                工时相同（容差内）按通道号小者优先；主通道故障自动顺延次小工时通道；
                超温（fTemp > fDerateTh）整组降额占空比至 fDerateDuty，带滞回恢复。
                边界：只产出主通道号与各通道占空比指令，不直接驱动 DO/PWM 硬件，
                工时累计由上位系统维护、本件只读。
    R6 口径    : 主状态机 E_DL_HeatBalState（eIdle/eRun/eFault）为 ENUM+CASE+ELSE，
                ELSE 置 16#0005_1E06 并回 eFault；选主逻辑为无跨拍状态驻留的判据链
                （FOR 升序遍历 + 严格小于 + 容差，天然满足「同工时通道号小者优先」），
                判据链等价 CASE 的兜底由「全通道不可用 → 1E01」分支承担。
    错误码    : 16#0005_1E00 参数非法（占空比出 [0,1] / 滞回为负 / 降额阈不大于滞回）——故障级
                16#0005_1E01 全部通道不可用，无主可选——故障级，锁存至复位沿
                16#0005_1E02 主通道故障顺延次小工时通道——信息级，顺延拍单发
                16#0005_1E03 超温降额激活——信息级，降额期间持续发布
                16#0005_1E04 通道工时非有限，按不可用剔除该通道——信息级，条件存在即发布
                16#0005_1E05 温度采样非有限，保持降额占空比（安全侧）——故障级，条件级不锁存
                16#0005_1E06 CASE 落 ELSE 兜底——故障级
    码位总账  : 16#0005_1E00..1E06 全部定义并使用，无空悬码位；
                信息级码同拍多发时以后赋值者可见（1E05 优先级最高，最后赋值）
    状态机    : eIdle --bBankEnable 且参数合法--> eRun；eRun 内全通道不可用 → eFault
                （1E01 锁存，bReset 上升沿复位）；1E05 为条件级故障不转 eFault、
                保持降额占空比继续选主；1E00 门禁非法直接转 eFault。
    防御口径  : 工时比较用绝对容差 DL_HB_EPS（工时差归一无需除法，本件无除法运算，
                分母不存在）；通道下标一律 1..8 硬界内，nMaster 只能取自
                1..nEff（nEff 已钳位 2..8），占空比映射用等值比较杜绝越界；
                非有限判定按 NaN f<>f、±Inf (f-f)<>(f-f)。
    修订记录  : 2026-11-23 v1.0.0 首次入库（R76 冲刺批 C3 · #2）
*)
TYPE E_DL_HeatBalState :
(
    eIdle  := 0,   // 待机，整组未投运，占空比全零 / idle, bank off, all duties zero
    eRun   := 10,  // 运行，每拍重算选主与占空比 / running, master selection and duties recomputed every scan
    eFault := 20   // 故障，主通道清零、占空比全零，锁存码等复位 / fault, master cleared, duties zero, code latched for reset
);
END_TYPE

FUNCTION_BLOCK FB_DL_HeaterBankLoadBalance
VAR_INPUT
    rN          : INT;                     // 配置通道数，钳位到 2..8 / configured channel count, clamped to 2..8
    aHours      : ARRAY[1..8] OF LREAL;    // 各通道累计运行工时 [h]，上位维护、本件只读 / accumulated run hours [h] per channel, maintained upstream, read-only here
    aHealthy    : ARRAY[1..8] OF BOOL;     // 各通道健康标志，TRUE = 可用 / per-channel health flag, TRUE = available
    aEnabled    : ARRAY[1..8] OF BOOL;     // 各通道投运允许，TRUE = 参与选主 / per-channel enable, TRUE = joins the selection
    fTemp       : REAL;                    // 加热组温度采样 [°C] / bank temperature sample [°C]
    fDerateTh   : REAL := 80.0;            // 超温降额阈值 [°C]，必须大于滞回 / derate threshold [°C], must exceed the hysteresis
    fDerateHys  : REAL := 2.0;             // 降额恢复滞回 [°C]，非负 / derate release hysteresis [°C], non-negative
    fDerateDuty : REAL := 0.5;             // 降额占空比 [0..1] / derated duty cycle [0..1]
    fNomDuty    : REAL := 1.0;             // 正常占空比 [0..1] / nominal duty cycle [0..1]
    bBankEnable : BOOL;                    // 整组投运命令 / bank enable command
    bReset      : BOOL;                    // 故障复位请求，上升沿生效 / fault reset request, edge-active
END_VAR
VAR_OUTPUT
    nMaster     : INT;                     // 当前主通道号 1..8，0 = 无主 / current master channel 1..8, 0 = none
    aDuty       : ARRAY[1..8] OF REAL;     // 各通道占空比指令 [0..1]，非主通道恒 0 / duty command [0..1] per channel, non-master channels are 0
    bDerated    : BOOL;                    // 整组降额标志 / bank derated flag
    eState      : E_DL_HeatBalState;       // 当前状态镜像输出 / current state mirror output
    nErrCode    : UDINT;                   // 错误码，0 = 无错；信息级随条件发布、故障级锁存回放 / error code, 0 = none; info codes conditional, fault codes latched
    bError      : BOOL;                    // 故障级标志，仅故障级码置位 / fault-class flag, raised only by fault-class codes
    bValid      : BOOL;                    // 输出可用标志，= NOT bError / outputs valid flag, equals NOT bError
END_VAR
VAR
    _eState      : E_DL_HeatBalState;      // 当前状态 / current state
    _uErrLatch   : UDINT;                  // 故障码锁存副本，故障态每拍回放 / latched fault code republished inside the fault state
    rtReset      : R_TRIG;                 // 复位上升沿检测 / reset rising-edge detector
    _nEff        : INT;                    // 钳位后的有效通道数 2..8 / effective channel count clamped to 2..8
    _nBest       : INT;                    // 本拍选出的主通道号 / master channel selected this scan
    _nMasterPrev : INT;                    // 上一拍主通道号，顺延观测用 / previous-scan master channel for the fallback observation
    _fBest       : LREAL;                  // 本拍最小工时 [h] / smallest hours found this scan [h]
    _fDuty       : REAL;                   // 本拍主通道占空比 [0..1] / master duty this scan [0..1]
    _i           : INT;                    // FOR 循环变量，1..8 硬界 / FOR loop index within the hard 1..8 bounds
    _bAvail      : BOOL;                   // 通道可用临时量 / per-channel availability scratch
    _bParOk      : BOOL;                   // 参数门禁结果 / parameter gate result
    _bTempBad    : BOOL;                   // 温度采样非有限标志 / non-finite temperature flag
    _bDerateLatch : BOOL;                  // 降额滞回锁存 / derate hysteresis latch
END_VAR
VAR CONSTANT
    DL_HB_EPS   : LREAL := 1.0E-9;         // 工时比较容差 [h]，容差内视为同工时 / hours comparison tolerance [h], inside it hours count as equal
    DL_HB_TOL   : REAL  := 1.0E-6;         // 占空比域比较容差 [无量纲] / duty domain comparison tolerance [dimensionless]
    DL_HB_ZERO  : REAL  := 0.0;            // 零占空比 [0..1] / zero duty [0..1]
    DL_HB_ONE   : REAL  := 1.0;            // 满占空比域上界 [0..1] / full-duty domain upper bound [0..1]
    DL_HB_CHMIN : INT   := 2;              // 通道数下限 / channel count lower bound
    DL_HB_CHMAX : INT   := 8;              // 通道数上限（数组硬界）/ channel count upper bound, the array hard bound
END_VAR

// 段 1｜边缘检测无条件周期刷新（R7：严禁放入 IF / CASE；本件无 TON）
// segment 1, edge detector refreshed unconditionally, never inside IF/CASE; no TON in this FB
rtReset(CLK := bReset);

// 段 2｜输出与错误状态预置；故障态从锁存副本回放（R45 配对）
// segment 2, preset outputs and error status; the fault state replays from the latch
nMaster := 0;                              // 预置无主 / preset no master
bDerated := FALSE;                         // 预置未降额 / preset not derated
nErrCode := 0;                             // 预置无错误码 / preset no error code
bError := FALSE;                           // 预置无故障标志 / preset no fault flag
bValid := TRUE;                            // 预置输出可用 / preset outputs valid
IF _eState = E_DL_HeatBalState.eFault THEN
    nErrCode := _uErrLatch;                // 重发布锁存故障码 / republish the latched fault code
    bError := TRUE;                        // 故障态恒置故障标志 / fault flag stays raised in the fault state
    bValid := FALSE;                       // 故障态输出不可信 / outputs not valid in the fault state
END_IF

// 段 3｜参数门禁与通道数钳位：rN 钳位属正常行为不报错，其余非法即锁存 1E00 转 eFault
// segment 3, parameter gate and channel clamp; rN clamping is normal behaviour, other violations latch 1E00 and jump to eFault
_nEff := rN;                               // 取配置通道数 / take the configured channel count
IF _nEff < DL_HB_CHMIN THEN
    _nEff := DL_HB_CHMIN;                  // 钳到下限 2 / clamp to the lower bound 2
END_IF
IF _nEff > DL_HB_CHMAX THEN
    _nEff := DL_HB_CHMAX;                  // 钳到上限 8（数组硬界）/ clamp to the upper bound 8, the array hard bound
END_IF
_bParOk := (fDerateDuty > (DL_HB_ZERO - DL_HB_TOL)) AND (fDerateDuty < (DL_HB_ONE + DL_HB_TOL))
       AND (fNomDuty > (DL_HB_ZERO - DL_HB_TOL)) AND (fNomDuty < (DL_HB_ONE + DL_HB_TOL))
       AND (fDerateHys > (DL_HB_ZERO - DL_HB_TOL)) AND (fDerateTh > fDerateHys);
_bTempBad := (fTemp <> fTemp) OR ((fTemp - fTemp) <> (fTemp - fTemp)); // 温度 NaN/±Inf 判定 / temperature NaN or infinite
IF (NOT _bParOk) AND (_eState <> E_DL_HeatBalState.eFault) THEN
    _uErrLatch := 16#0005_1E00;            // 锁存参数非法码 / latch the illegal parameter code
    nErrCode := 16#0005_1E00;              // 故障级码赋值 3 行内置 bError / fault-class assignment with bError inline
    bError := TRUE;
    bValid := FALSE;
    _eState := E_DL_HeatBalState.eFault;   // 参数不可信直接转故障 / untrusted parameters jump to fault
END_IF

// 段 4｜主状态机：CASE + ELSE 兜底（R6）；选主判据链在 eRun 相内每拍全量重算
// segment 4, main state machine, CASE with ELSE fallback; the selection chain inside eRun is recomputed fully every scan
CASE _eState OF
E_DL_HeatBalState.eIdle:
    // 拍 N 进入：复位或未投运；本拍行为：占空比全零（预置已清）；拍 N+1 转出：投运且参数合法 → eRun
    // entered after reset or when off; duties stay zero via the preset; exits to eRun on bank enable with legal parameters
    IF bBankEnable AND _bParOk THEN
        _bDerateLatch := FALSE;            // 新投运清降额锁存 / clear the derate latch on a fresh start
        _nMasterPrev := 0;                 // 清上一拍主通道观测 / clear the previous-master observation
        _eState := E_DL_HeatBalState.eRun; // 进运行相 / enter the run phase
    END_IF

E_DL_HeatBalState.eRun:
    // 拍 N 进入：投运且参数合法；本拍行为：选主 → 顺延观测 → 超温降额 → 占空比映射；
    // 拍 N+1 转出：全通道不可用 → eFault（1E01）；温度非有限保持本相降额运行（1E05 条件级）
    // entered on enable with legal parameters; per scan: select master, observe fallback, derate, map duties;
    // exits to eFault only when no channel is available (1E01); a non-finite temperature keeps this phase derated (1E05)
    _nBest := 0;                           // 清本拍选主结果 / clear this scan's selection
    _fBest := 0.0;                         // 清最小工时 / clear the smallest hours
    FOR _i := 1 TO _nEff DO
        _bAvail := aHealthy[_i] AND aEnabled[_i]; // 可用 = 健康且投运允许 / available = healthy and enabled
        IF (aHours[_i] <> aHours[_i]) OR ((aHours[_i] - aHours[_i]) <> (aHours[_i] - aHours[_i])) THEN
            _bAvail := FALSE;              // 工时非有限剔除该通道 / exclude the channel on non-finite hours
            nErrCode := 16#0005_1E04;      // 信息级：条件存在即发布，不置 bError / info class, no fault flag
        END_IF
        IF _bAvail THEN
            IF (_nBest = 0) OR (aHours[_i] < (_fBest - DL_HB_EPS)) THEN
                _nBest := _i;              // 严格小于才替换：升序遍历 + 容差保证同工时小号优先 / strict less with tolerance keeps the lower index on ties
                _fBest := aHours[_i];      // 记录当前最小工时 / record the current minimum hours
            END_IF
        END_IF
    END_FOR
    IF (_nMasterPrev >= 1) AND (_nMasterPrev <= _nEff)
       AND ((NOT aHealthy[_nMasterPrev]) OR (NOT aEnabled[_nMasterPrev])) AND (_nBest > 0) THEN
        nErrCode := 16#0005_1E02;          // 信息级：主通道故障已顺延（下标受 _nMasterPrev<=_nEff<=8 保护）/ info: master fell over, index guarded
    END_IF
    IF _nBest = 0 THEN
        _uErrLatch := 16#0005_1E01;        // 锁存全通道不可用码 / latch the no-channel-available code
        nErrCode := 16#0005_1E01;          // 故障级码赋值 3 行内置 bError / fault-class assignment with bError inline
        bError := TRUE;
        bValid := FALSE;
        _nMasterPrev := 0;                 // 清观测防复位后误报顺延 / clear the observation to avoid a false fallback after reset
        _eState := E_DL_HeatBalState.eFault; // 转故障，占空比由预置全零 / go to fault, duties stay zero via the preset
    ELSE
        nMaster := _nBest;                 // 发布主通道号 / publish the master channel
        IF fTemp > fDerateTh THEN
            _bDerateLatch := TRUE;         // 超温进入降额 / enter derate on overtemperature
        ELSIF fTemp < (fDerateTh - fDerateHys) THEN
            _bDerateLatch := FALSE;        // 低于恢复阈退出降额（滞回）/ leave derate under the release threshold
        END_IF
        IF _bDerateLatch THEN
            _fDuty := fDerateDuty;         // 降额占空比 / derated duty
            nErrCode := 16#0005_1E03;      // 信息级：降额期间持续发布 / info class, published while derated
        ELSE
            _fDuty := fNomDuty;            // 正常占空比 / nominal duty
        END_IF
        IF _bTempBad THEN
            nErrCode := 16#0005_1E05;      // 温度非有限码最后赋值，显示优先级最高 / assigned last so it wins the display
            _fDuty := fDerateDuty;         // 安全侧：强制降额占空比 / safe side, force the derated duty
            bError := TRUE;                // 故障级码赋值 3 行内置 bError（条件级不锁存，条件消失自动恢复）/ fault-class trio, conditional not latched
            bValid := FALSE;
            bDerated := TRUE;              // 温度不可信视同降额 / untrusted temperature counts as derated
        END_IF
        FOR _i := 1 TO DL_HB_CHMAX DO
            IF _i = nMaster THEN
                aDuty[_i] := _fDuty;       // 主通道承载占空比（nMaster<=_nEff<=8，等值比较无越界）/ master carries the duty, equality test cannot overrun
            ELSE
                aDuty[_i] := DL_HB_ZERO;   // 非主通道恒零 / non-master channels stay zero
            END_IF
        END_FOR
        bDerated := _bDerateLatch OR bDerated; // 汇总降额标志 / merge the derate flag
        _nMasterPrev := nMaster;           // 更新上一拍主通道观测 / update the previous-master observation
    END_IF

E_DL_HeatBalState.eFault:
    // 拍 N 进入：全通道不可用或参数非法；本拍行为：主通道清零（预置）、占空比全零、锁存码回放；
    // 拍 N+1 转出：bReset 上升沿且参数已合法 → eIdle
    // entered on no-channel or illegal parameters; master cleared via the preset, duties zero, latch replays;
    // exits to eIdle on a reset edge with legal parameters
    IF rtReset.Q AND _bParOk THEN
        _uErrLatch := 0;                   // 清锁存码 / clear the latched code
        _eState := E_DL_HeatBalState.eIdle; // 回待机等投运 / back to idle awaiting enable
    END_IF

ELSE
    // 非法状态拦截：任何未定义枚举值一律锁存兜底码并转故障（R6）
    // illegal-state interception, any undefined enum value latches the fallback code and goes to fault
    _uErrLatch := 16#0005_1E06;            // 锁存兜底码 / latch the fallback code
    nErrCode := 16#0005_1E06;              // 故障级码赋值 3 行内置 bError / fault-class assignment with bError inline
    bError := TRUE;
    bValid := FALSE;
    _eState := E_DL_HeatBalState.eFault;
END_CASE

// 段 5｜状态镜像输出
// segment 5, state mirror output
eState := _eState;                         // 状态镜像输出 / state mirror output

END_FUNCTION_BLOCK
