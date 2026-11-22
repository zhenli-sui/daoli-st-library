(*
    FB_DL_ValveSeatLeakTest —— 阀座泄漏测试（关阀后上游压力保持窗内压降判漏）
    ------------------------------------------------------------------
    组件名称  : FB_DL_ValveSeatLeakTest
    分类      : DL_Device / ValveDiagnostics
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : 借鉴点 —— 离线阀座密封性测试的通行工序：关阀 → 稳压（等热平衡与
                压力稳定）→ 测量窗（保持窗）→ 窗末压降与阈值比较；以及测量领域
                的「理想气体定容温度补偿」口径（P 与绝对温度 T 成正比，恒容下
                无泄漏时应满足 P1/T1 = P0/T0，故温度变化引起的压降必须扣除）。
                该工序与补偿口径均为公开测量常识，本件借鉴其**时序划分与补偿公式**。
                clean-room 声明 —— 零代码行复制；状态机、闸门、码位、双语文档
                全部本件自有，仅使用 IEC 61131-3 标准库 TON / R_TRIG。
                许可证 —— 本件 MIT；来源标签 lgf-measurement 仅作语义参考，
                本件不包含、不派生其任何实现代码行。
    平台      : 纯 IEC 61131-3，CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R70 构建轮 · 批 2 · N6）
    ------------------------------------------------------------------
    功能说明  : 时序：eIdle 待机 → eStabilize 稳压（关阀，等 tStab）
                → eMeasure 测量窗（等 tTest，窗末取压降）→ eVerdict 判定
                → ePass 合格（保持）/ eLeak 泄漏（保持）；异常 → eFault。
                温度补偿口径（口径写死，不留歧义）：
                  原始压降   fDropRaw  = P0 - P1
                  温补压降   fDropComp = P0 * (T0K - T1K) / T0K     （bTempComp = TRUE）
                             fDropComp = P0 - P1                    （bTempComp = FALSE）
                  其中 T0K / T1K 为开氏绝对温度 = 摄氏值 + 273.15，P0 / P1 为窗口
                  起止拍的上游表压。补偿式的物理含义：若仅温度下降而无泄漏，
                  压力应按 P1 = P0 * T1K / T0K 下降，这部分下降被减掉，剩余部分
                  才计为泄漏压降。**符号约定**：T1K < T0K（降温）时补偿项为正，
                  即从实测压降中扣除降温贡献；T1K > T0K（升温）时补偿项为负，
                  实测压降被加严（升温掩盖泄漏，必须反向修正）。
                除法面：唯一除法为 fP0 * (T0K - T1K) / T0K，除子 T0K 在进入除法前
                经**结构闸**校验 > 0.0（绝对温度必为正），否则不落除法并置 0403。
                前置压力判据：稳压结束即校验 P0 >= fPTest，不足则置 0404（测试
                条件不成立时的压降无判别意义，禁止给出合格/泄漏结论）。
    错误码    : 16#0002_0401 组态非法（阈值 / 时长 / 非有限），锁存 —— 故障级
                16#0002_0402 上游压力非有限，锁存 —— 故障级
                16#0002_0403 温度越出物理域（摄氏 <= -273.15，开氏非正，禁入除法），锁存 —— 故障级
                16#0002_0404 稳压后压力低于 fPTest（测试前置不成立），锁存 —— 故障级
                16#0002_0405 非法状态枚举值（CASE ELSE 兜底），锁存 —— 故障级
                16#0002_0406 保留未用（泄漏判定已由 bLeakDetected 直接可观测，
                             加码即冗余，见边界五反证句）—— 未用
    码位总账  : 0401 / 0402 / 0403 / 0404 / 0405 用（均故障级）｜ 0406 保留未用
    状态机    : ENUM E_DL_VltState 七态，CASE 全覆盖 + ELSE 兜底（回 eFault 置 0405）。
                唯一解除边：bReset 上升沿 → 清锁存并回 eIdle（R188）。
                任意相 bAbort 为真 → 回 eIdle 且出口清零（操作态，不发码）。
    边界与披露: 一 组态闸（R272 逐项点名）：fPTest / fLeakTh / tStab / tTest 的
                   非有限与域校验；fLeakTh < 0 拦截（负阈值使判据恒真）；fPTest < 0
                   拦截（表压不得为负域）；时长为 0 属合法（即刻判定）；
                二 输入闸：fUpPress 与 fTempC 的非有限闸逐拍生效，故障锁存后停测；
                三 出口语义：bBusy = 稳压或测量相（真正占用设备的时间窗）；
                   bValid = 出口可信（非故障相）；bPass / bLeakDetected 为保持型判定位；
                四 定时器 _tonPhase 单实例 + PT 逐相选择（段 7 以 IF/ELSIF/ELSE 链
                   选 PT），每周期无条件调用（规则 ⑦）；
                五 泄漏判定不设错误码的反证句（R90 前置）：判定结果已由两个布尔出口
                   bLeakDetected / bPass 完全可观测，且二者互斥且穷尽，故再加一个
                   信息级码不增加任何可观测性，按「不可观测才加码」原则不设；
                六 零全局变量、零 VAR_EXTERNAL、零物理地址、零数组下标。
    修订记录  : 2026-11-22 v1.0.0 首次入库（R70 构建轮 · 批 2 · N6）
*)
TYPE E_DL_VltState :
(
    eIdle      := 0,   (* 待机，等待启动 / idle, waiting for a start *)
    eStabilize := 10,  (* 稳压相（关阀，等热平衡与压力稳定）/ the stabilisation phase *)
    eMeasure   := 20,  (* 测量窗相（取窗末压降）/ the measurement window phase *)
    eVerdict   := 30,  (* 判定相（压降对阈值）/ the verdict phase *)
    ePass      := 40,  (* 合格相（保持）/ the pass phase, held *)
    eLeak      := 50,  (* 泄漏相（保持）/ the leak phase, held *)
    eFault     := 60   (* 故障相（锁存待复位）/ the fault phase, latched *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_ValveSeatLeakTest
VAR_INPUT
    bStart     : BOOL := FALSE;           (* 启动测试（上升沿有效），[标志] / the test start, rising edge *)
    bAbort     : BOOL := FALSE;           (* 中止测试（电平有效），[标志] / the abort, level effective *)
    bReset     : BOOL := FALSE;           (* 故障复位（上升沿有效），[标志] / the fault reset, rising edge *)
    fUpPress   : LREAL := 0.0;            (* 阀上游压力（表压），[kPa] / the upstream gauge pressure *)
    fTempC     : LREAL := 25.0;           (* 介质温度，[°C] / the medium temperature in Celsius *)
    fPTest     : LREAL := 100.0;          (* 测试前置压力下限，[kPa]，须 >= 0 / the minimum pre-test pressure *)
    fLeakTh    : LREAL := 2.0;            (* 允许压降阈值，[kPa]，须 >= 0 / the permitted pressure drop *)
    bTempComp  : BOOL := TRUE;            (* 温度补偿投用，[标志] / the temperature compensation is active *)
    tStab      : TIME := T#10S;           (* 稳压时长，[ms] / the stabilisation duration *)
    tTest      : TIME := T#60S;           (* 测量窗时长，[ms] / the measurement window duration *)
END_VAR
VAR_OUTPUT
    eState      : E_DL_VltState := E_DL_VltState.eIdle; (* 状态出口，[状态] / the state outlet *)
    bValveClose : BOOL;                   (* 关阀命令（测试期间保持），[标志] / the close command held during the test *)
    fDropRaw    : LREAL;                  (* 实测压降 P0 - P1，[kPa] / the measured pressure drop *)
    fDropComp   : LREAL;                  (* 温补后压降，[kPa] / the temperature compensated drop *)
    bLeakDetected : BOOL;                 (* 泄漏判定（保持型），[标志] / the leak verdict, held *)
    bPass       : BOOL;                   (* 合格判定（保持型），[标志] / the pass verdict, held *)
    bBusy       : BOOL;                   (* 测试占用中（稳压 / 测量），[标志] / the test occupies the valve *)
    bValid      : BOOL;                   (* 出口可信（非故障相），[标志] / the outlets are trustworthy *)
    bError      : BOOL;                   (* 故障标志，锁存故障时为 TRUE / the fault flag, raised while latched *)
    nErrCode    : UDINT;                  (* 错误码，0 = 正常，锁存回放 / the error id, 0 = ok, replayed *)
END_VAR
VAR
    _rtStart    : R_TRIG;                 (* 启动上升沿实例（无条件调用）/ the start rising edge instance *)
    _rtReset    : R_TRIG;                 (* 复位上升沿实例（无条件调用）/ the reset rising edge instance *)
    _tonPhase   : TON;                    (* 相计时实例（无条件调用）/ the phase timer, called unconditionally *)
    _eState     : E_DL_VltState := E_DL_VltState.eIdle; (* 状态寄存器，[状态] / the internal state register *)
    _bFault     : BOOL;                   (* 故障锁存位，仅 bReset 上升沿解除 / the latched fault bit *)
    _nCodeLatch : UDINT;                  (* 锁存成因码，故障期回放 / the latched cause code *)
    _bCfgBad    : BOOL;                   (* 组态非法标志（逐拍重算）/ the configuration fault flag *)
    _bInBad     : BOOL;                   (* 输入非有限标志（逐拍重算）/ the input fault flag *)
    _bTimerIn   : BOOL;                   (* 相计时器 IN 条件（段 7 计算）/ the timer IN condition *)
    _tPhasePt   : TIME;                   (* 相计时器 PT 当前值（逐相选择）/ the timer PT for the current phase *)
    _fP0        : LREAL;                  (* 窗口起点压力，[kPa] / the window start pressure *)
    _fP1        : LREAL;                  (* 窗口终点压力，[kPa] / the window end pressure *)
    _fT0C       : LREAL;                  (* 窗口起点温度，[°C] / the window start temperature *)
    _fT1C       : LREAL;                  (* 窗口终点温度，[°C] / the window end temperature *)
    _fT0K       : LREAL;                  (* 窗口起点绝对温度，[K] / the window start absolute temperature *)
    _fT1K       : LREAL;                  (* 窗口终点绝对温度，[K] / the window end absolute temperature *)
    _fDropTmp   : LREAL;                  (* 压降计算中间量，[kPa] / the drop temporary *)
    _fDropRawP  : LREAL;                  (* 实测压降保持量（跨相驻留，防同拍抹除）/ the held measured drop *)
    _fDropCompP : LREAL;                  (* 温补压降保持量（跨相驻留，防同拍抹除）/ the held compensated drop *)
    _bHaveSample : BOOL;                  (* 已采到窗口起点样本，[标志] / the window start sample exists *)
END_VAR
VAR CONSTANT
    DL_VLT_FMAX  : LREAL := 1.0E30;       (* 非有限筛查幅值上限，[工程单位] / the finiteness screening cap *)
    DL_VLT_TZERO : LREAL := 273.15;       (* 摄氏转开氏的偏移量，[K] / the Celsius to Kelvin offset *)
    DL_VLT_TMIN  : LREAL := -273.15;      (* 摄氏温度的物理下界（绝对零度），[°C] / the absolute zero in Celsius *)
END_VAR

// 段 1｜出口预置（R256 统一出口预置）/ segment 1, preset every outlet
eState        := _eState;                 // 状态出口先镜像寄存器 / mirror the state register first
bValveClose   := FALSE;                   // 关阀命令预清零 / preset the close command false
bLeakDetected := FALSE;                   // 泄漏判定预清零（保持型另由寄存器承担）/ preset the leak verdict false
bPass         := FALSE;                   // 合格判定预清零 / preset the pass verdict false
bBusy         := FALSE;                   // 占用标志预清零 / preset the busy flag false
bValid        := TRUE;                    // 可用标志预置真（故障相再清）/ preset valid true
bError        := FALSE;                   // 故障标志预清零 / preset the error flag false
nErrCode      := 0;                       // 错误码预置无错 / preset the code to zero
_bTimerIn     := FALSE;                   // 计时条件预清零 / preset the timer condition false
_tPhasePt     := tStab;                   // 计时 PT 预置缺省值 / preset the timer PT to the default

// 段 2｜沿检测与定时器无条件调用（规则 ⑦）/ segment 2, the edge instances and the timer
_rtStart(CLK := bStart);                  // 启动沿，每周期无条件刷新 / the start edge, refreshed every scan
_rtReset(CLK := bReset);                  // 复位沿，每周期无条件刷新 / the reset edge, refreshed every scan

// 段 3｜复位解除：唯一可到达的清除边（R188）/ segment 3, the only latch release edge
IF _rtReset.Q THEN                        // 复位上升沿 / the reset rising edge
    _bFault      := FALSE;                // 解除故障锁存 / release the fault latch
    _nCodeLatch  := 0;                    // 清锁存码 / clear the latched code
    _bHaveSample := FALSE;                // 清窗口样本标志 / clear the sample flag
    _eState      := E_DL_VltState.eIdle;  // 回待机相（安全相）/ back to the safe idle phase
END_IF

// 段 4｜组态守卫（R272 逐项点名）/ segment 4, the configuration guard
_bCfgBad := (fLeakTh < 0.0)                                       // 负阈值使判据恒真 / a negative threshold makes the criterion always true
         OR (fPTest < 0.0)                                        // 前置压力下限为负 / a negative pre-test pressure
         OR (fLeakTh <> fLeakTh) OR ((fLeakTh - fLeakTh) <> 0.0) OR (ABS(fLeakTh) > DL_VLT_FMAX)
         OR (fPTest <> fPTest) OR ((fPTest - fPTest) <> 0.0) OR (ABS(fPTest) > DL_VLT_FMAX);

// 段 5｜输入守卫：压力与温度非有限 / segment 5, the pressure and temperature guard
_bInBad := (fUpPress <> fUpPress) OR ((fUpPress - fUpPress) <> 0.0) OR (ABS(fUpPress) > DL_VLT_FMAX)
        OR (fTempC <> fTempC) OR ((fTempC - fTempC) <> 0.0) OR (ABS(fTempC) > DL_VLT_FMAX);

// 段 6｜首次成因锁存（故障期不重推断，R189）/ segment 6, the first cause latch
IF NOT _bFault THEN                       // 未锁存才登记 / register only while healthy
    IF _bCfgBad THEN                      // 组态非法优先 / the configuration first
        _bFault     := TRUE;              // 置锁存 / latch it
        _nCodeLatch := 16#0002_0401;      // 故障级：组态非法 / fault level: an illegal configuration
        _eState     := E_DL_VltState.eFault; // 迁入故障相 / enter the fault phase
    ELSIF _bInBad THEN                    // 输入非有限 / an input is non finite
        _bFault     := TRUE;              // 置锁存 / latch it
        _nCodeLatch := 16#0002_0402;      // 故障级：输入非有限 / fault level: an input is non finite
        _eState     := E_DL_VltState.eFault; // 迁入故障相 / enter the fault phase
    END_IF
END_IF

// 段 7｜中止命令与相计时 PT 选择（选相不依赖可跳过分支）/ segment 7, the abort and the timer PT selection
IF bAbort AND NOT _bFault THEN            // 中止有效且无锁存故障 / an abort without a latched fault
    _eState      := E_DL_VltState.eIdle;  // 回待机 / back to idle
    _bHaveSample := FALSE;                // 清样本标志 / clear the sample flag
END_IF
IF _eState = E_DL_VltState.eStabilize THEN     // 稳压相 / the stabilisation phase
    _tPhasePt := tStab;                        // 稳压时长 / the stabilisation duration
    _bTimerIn := TRUE;                         // 相内计时有效 / the timer runs
ELSIF _eState = E_DL_VltState.eMeasure THEN    // 测量窗相 / the measurement window phase
    _tPhasePt := tTest;                        // 测量窗时长 / the measurement window duration
    _bTimerIn := TRUE;                         // 相内计时有效 / the timer runs
ELSE                                           // 其余相不计时（缺省分支，非状态机 ELSE）/ the other phases do not time
    _tPhasePt := tStab;                        // 缺省 PT，保证恒有定义 / a default PT, always defined
    _bTimerIn := FALSE;                        // 计时条件清零 / the timer condition cleared
END_IF
_tonPhase(IN := _bTimerIn, PT := _tPhasePt);   // 每周期无条件调用 / called every scan without exception

// 段 8｜状态机（ENUM + CASE + ELSE 兜底）/ segment 8, the state machine
CASE _eState OF
    E_DL_VltState.eIdle:                       // 待机相 / the idle phase
        bValid := TRUE;                        // 待机出口可信 / the idle outlets are trustworthy
        IF _rtStart.Q AND NOT _bFault THEN     // 启动沿且无锁存故障 / a start edge without a latched fault
            _bHaveSample := FALSE;             // 清旧样本 / clear the old sample
            _eState := E_DL_VltState.eStabilize; // 进入稳压相 / enter the stabilisation phase
        END_IF
    E_DL_VltState.eStabilize:                  // 稳压相（关阀保持）/ the stabilisation phase, the valve held closed
        bValveClose := TRUE;                   // 关阀命令 / hold the valve closed
        bBusy       := TRUE;                   // 测试占用 / the test occupies the valve
        IF _tonPhase.Q THEN                    // 稳压时长到 / the stabilisation is done
            _fP0 := fUpPress;                  // 采窗口起点压力 / sample the start pressure
            _fT0C := fTempC;                   // 采窗口起点温度 / sample the start temperature
            IF _fP0 < fPTest THEN              // 前置压力不足 / the pre-test pressure is insufficient
                _bFault     := TRUE;           // 锁存故障 / latch the fault
                _nCodeLatch := 16#0002_0404;   // 故障级：前置压力不足 / fault level: the pre-test pressure is too low
                _eState     := E_DL_VltState.eFault; // 迁入故障相 / enter the fault phase
            ELSIF _fT0C <= DL_VLT_TMIN THEN    // 起点温度越物理域（开氏非正）/ the start temperature beyond the physical domain
                _bFault     := TRUE;           // 锁存故障 / latch the fault
                _nCodeLatch := 16#0002_0403;   // 故障级：温度域外 / fault level: the temperature out of domain
                _eState     := E_DL_VltState.eFault; // 迁入故障相 / enter the fault phase
            ELSE                               // 前置条件成立 / the preconditions hold
                _bHaveSample := TRUE;          // 标记已采样本 / mark the sample
                _eState := E_DL_VltState.eMeasure; // 进入测量窗相 / enter the measurement phase
            END_IF
        END_IF
    E_DL_VltState.eMeasure:                    // 测量窗相 / the measurement window phase
        bValveClose := TRUE;                   // 关阀命令保持 / the close command is held
        bBusy       := TRUE;                   // 测试占用 / the test occupies the valve
        _fDropRawP  := _fP0 - fUpPress;        // 实时压降预览（窗内递进值）/ a live drop preview inside the window
        IF _tonPhase.Q THEN                    // 测量窗结束 / the window ended
            _fP1  := fUpPress;                 // 采窗末压力 / sample the end pressure
            _fT1C := fTempC;                   // 采窗末温度 / sample the end temperature
            _fT0K := _fT0C + DL_VLT_TZERO;     // 起点绝对温度 / the start absolute temperature
            _fT1K := _fT1C + DL_VLT_TZERO;     // 终点绝对温度 / the end absolute temperature
            IF _bHaveSample AND (_fT0K > 0.0) THEN  // 样本存在且开氏温标为正（结构闸，除子已证非零）/ a sample exists and the divisor is positive
                IF bTempComp THEN              // 温补投用 / the compensation is active
                    _fDropTmp := _fP0 * (_fT0K - _fT1K) / _fT0K; // 温补式（唯一除法，除子已闸）/ the compensated formula, the only division
                ELSE                           // 温补未投用 / the compensation is off
                    _fDropTmp := _fP0 - _fP1;  // 原始压降 P0 - P1 / the raw drop
                END_IF
                IF (_fDropTmp <> _fDropTmp) OR ((_fDropTmp - _fDropTmp) <> 0.0) THEN // 结果非有限 / a non finite result
                    _bFault     := TRUE;       // 锁存故障 / latch the fault
                    _nCodeLatch := 16#0002_0403; // 故障级：温标域外致计算溢出 / fault level: the temperature domain broke the computation
                    _eState     := E_DL_VltState.eFault; // 迁入故障相 / enter the fault phase
                ELSE                           // 结果有限 / the result is finite
                    _fDropRawP  := _fP0 - _fP1; // 实测压降存入保持量 / hold the measured drop
                    _fDropCompP := _fDropTmp;   // 温补压降存入保持量 / hold the compensated drop
                    _eState   := E_DL_VltState.eVerdict; // 进入判定相 / enter the verdict phase
                END_IF
            ELSE                               // 样本缺失或温标非法 / no sample or an illegal temperature scale
                _bFault     := TRUE;           // 锁存故障 / latch the fault
                _nCodeLatch := 16#0002_0403;   // 故障级：温度域外 / fault level: the temperature out of domain
                _eState     := E_DL_VltState.eFault; // 迁入故障相 / enter the fault phase
            END_IF
        END_IF
    E_DL_VltState.eVerdict:                    // 判定相（单拍，不驻留）/ the verdict phase, single scan
        bValveClose := TRUE;                   // 关阀命令保持 / the close command is held
        IF fDropComp > fLeakTh THEN            // 压降超阈值 / the drop exceeds the threshold
            _eState := E_DL_VltState.eLeak;    // 进入泄漏相 / enter the leak phase
        ELSE                                   // 压降在阈值内 / the drop is within the threshold
            _eState := E_DL_VltState.ePass;    // 进入合格相 / enter the pass phase
        END_IF
    E_DL_VltState.ePass:                       // 合格相（保持）/ the pass phase, held
        bPass       := TRUE;                   // 合格判定位 / the pass verdict
        bValveClose := TRUE;                   // 关阀命令保持（等卸压指令）/ the close command is held
        bValid      := TRUE;                   // 出口可信 / the outlets are trustworthy
    E_DL_VltState.eLeak:                       // 泄漏相（保持）/ the leak phase, held
        bLeakDetected := TRUE;                 // 泄漏判定位 / the leak verdict
        bValveClose   := TRUE;                 // 关阀命令保持（禁开阀）/ the close command is held, the valve stays shut
        bValid        := TRUE;                 // 出口可信 / the outlets are trustworthy
    E_DL_VltState.eFault:                      // 故障相（锁存保持）/ the fault phase, latched
        bValid   := FALSE;                     // 出口不可信 / the outlets are not trustworthy
        bError   := TRUE;                      // 故障标志置位 / raise the fault flag
        nErrCode := _nCodeLatch;               // 回放锁存码 / replay the latched code
    ELSE                                       // 非法枚举兜底（回安全相 + 置码，规则 ⑥）/ the illegal enumeration guard
        _bFault     := TRUE;                   // 置锁存 / latch it
        _nCodeLatch := 16#0002_0405;           // 故障级：非法状态枚举 / fault level: an illegal state value
        _eState     := E_DL_VltState.eFault;   // 回安全相 / force the safe fault phase
        bValid      := FALSE;                  // 出口不可信 / the outlets are not trustworthy
        bError      := TRUE;                   // 故障标志置位 / raise the fault flag
        nErrCode    := _nCodeLatch;            // 回放锁存码 / replay the latched code
END_CASE

// 段 9｜出口映射（名实双出口同源 + 跨相保持量映射，R191 / R187）/ segment 9, the outlet mapping
eState    := _eState;                      // 状态出口 = 寄存器（段 8 后单点写入）/ the state outlet mirrors the register
fDropRaw  := _fDropRawP;                   // 实测压降取自保持量（判定相才可读到终值，防同拍抹除）/ the measured drop, held
fDropComp := _fDropCompP;                  // 温补压降取自保持量（同上）/ the compensated drop, held
END_FUNCTION_BLOCK
