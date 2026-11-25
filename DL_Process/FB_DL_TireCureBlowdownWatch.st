(*
  Name: FB_DL_TireCureBlowdownWatch
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 轮胎硫化，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 按固定观察窗累计两个量：冷凝水总量 _fAccumKg 与排凝阀动作次数 _iAccumAct，
           窗口到点后按「单位动作排水量」比对：
           ratio = 累计冷凝水 / (动作次数 × 单次期望排水量)。
        2) 双向故障判别：
           ① 比值过高（> fBlockRatio）或窗口内动作次数为零而冷凝水已超限 → 判排凝阀堵塞（码 0322 / 0324），
              即水积在腔内排不出去，会稀释硫化温度场并造成胶囊局部过冷；
           ② 比值过低（< fLeakRatio）→ 判排凝阀泄漏（码 0323），即阀频繁动作但排水极少，
              说明阀芯未关严、蒸汽直排，属能耗与安全问题。
        3) 窗口自复位由 TON 的 IN := xEnable AND NOT tonWin.Q 驱动（R188），
           窗口到点仅置 Q 一拍，用于「判定 + 清累计」的一次性动作，不靠外部沿清零。
  边界条件：1) 非有限值闸：冷凝水量、期望排水量、两个比值阈值、窗口先过
           NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf；命中即锁码 0326 进故障相，
           绝不把 NaN 累加进窗口（NaN 一旦进入累计器，整个窗口乃至后续窗口永久污染，R19）。
        2) 分母零闸：比值式分母 = 动作次数 × 单次期望排水量，动作次数为零时走独立判据（码 0324），
           单次期望排水量 fExpectKgPerAct 必须 > DL_EPS 否则锁码 0325（判据全体失效）。
        3) 阈值域闸：须满足 0.0 < fLeakRatio < fBlockRatio，否则两向判据重叠、必有一向永不触发，
           越域锁码 0325。
        4) 累计器安全：非有限值命中时把两个累计器一并清零（码 0326 已锁存），
           并中止本窗口的判定，防污染值跨窗口传播。
        5) 定时器周期刷新（R7）：窗口 TON 与两个边沿实例全部在 CASE 之外无条件调用。
        6) 故障解除路径：故障相内 xReset 上升沿 AND NOT xFault AND 入参/组态合法 → 清锁存回正常，
           回正常后窗口与累计器全部重新起算（不自恢复）。
        7) 状态机兜底：CASE 全态覆盖 + ELSE 强制回故障相并置码 0328、清全部输出。
        8) 输出安全初值（R25）：xBlocked / xLeaking 初值 FALSE，fRatioPct 初值 0.0，正常相显式赋值。
  量纲自证：ratio = (kg) / (无因次 * kg) = 无因次 [-]；fRatioPct = 无因次 * 100 = 百分数 [%]；
           fAccumKg 为累计质量 [kg]，nAccumAct 为动作次数（计数，无量纲）[count]。
  码表 Error codes（本件子带 0091_032x，故障级一律 3 行内置 _uFault/_bFault/_eState）:
    16#0091_0321 信息级：观察窗累计中，尚未判定（不置故障位）
    16#0091_0322 故障级：排凝阀堵塞（单位动作排水量比值过高）
    16#0091_0323 故障级：排凝阀泄漏（单位动作排水量比值过低，蒸汽直排）
    16#0091_0324 故障级：窗口内动作次数为零但冷凝水超限（阀未动作）
    16#0091_0325 故障级：组态越域（期望排水量/比值阈值/窗口非法）
    16#0091_0326 故障级：入参非有限（NaN 或 Inf），累计器已清
    16#0091_0327 故障级：外部故障输入 xFault
    16#0091_0328 故障级：状态机落 ELSE 兜底（非法相位 ID）

  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

TYPE E_DL_TcsBlowdownState :
(
    eTcsBdNormal  := 0,     // 正常：窗口比值在带内 / Normal, window ratio within the band
    eTcsBdBlocked := 10,    // 排凝阀堵塞：水排不出去 / Blocked blowdown valve, water cannot be discharged
    eTcsBdLeaking := 20,    // 排凝阀泄漏：蒸汽直排 / Leaking blowdown valve, steam blows through
    eTcsBdFault   := 90     // 故障：入参/组态非法，锁存待解除 / Fault, invalid input, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_TireCureBlowdownWatch
VAR_INPUT
    xEnable         : BOOL;   // 监视使能 [bool] / Monitoring enable [bool]
    xReset          : BOOL;   // 故障复位（上升沿有效）[bool] / Fault reset, rising edge [bool]
    xFault          : BOOL;   // 外部故障汇总 [bool] / External fault aggregate [bool]
    xCyclePulse     : BOOL;   // 周期完成脉冲（每个模压周期一个脉冲）[bool] / Cycle-complete pulse [bool]
    fCondensateKg   : REAL;   // 本周期冷凝水量增量 [kg] / Condensate increment of this cycle [kg]
    nActCount       : INT;    // 本周期排凝阀动作次数 [count] / Blowdown valve actuations this cycle [count]
    fExpectKgPerAct : REAL;   // 单次动作期望排水量 [kg/act] / Expected discharge per actuation [kg/act]
    fBlockRatio     : REAL;   // 堵塞判定比值上限 [-] / Blockage upper ratio limit [-]
    fLeakRatio      : REAL;   // 泄漏判定比值下限 [-] / Leakage lower ratio limit [-]
    tWindow         : TIME;   // 观察窗时长 [TIME] / Observation window duration [TIME]
END_VAR
VAR_OUTPUT
    fRatioPct       : REAL;   // 窗口单位动作排水量比值（百分数显示）[%] / Window ratio, percent display [%]
    fAccumKg        : REAL;   // 窗口累计冷凝水量 [kg] / Accumulated condensate in the window [kg]
    nAccumAct       : INT;    // 窗口累计动作次数 [count] / Accumulated actuations in the window [count]
    xBlocked        : BOOL;   // 堵塞标志 [bool] / Blockage flag [bool]
    xLeaking        : BOOL;   // 泄漏标志 [bool] / Leakage flag [bool]
    xWindowDone     : BOOL;   // 窗口到点脉冲（单拍）[bool] / Window-complete single-shot flag [bool]
    eState          : E_DL_TcsBlowdownState;   // 状态出口，段尾单点映射 / State outlet, single-point mapped
    nErrId          : UDINT;  // 事件码，0 = 无事件 / Event code, 0 = none
END_VAR
VAR
    tonWin          : TON;    // 观察窗定时（自复位由 IN 取反驱动，R188）[TIME] / Observation window timer
    rtCycle         : R_TRIG; // 周期脉冲上升沿检测 [bool] / Cycle pulse rising edge detector
    rtReset         : R_TRIG; // 复位上升沿检测 [bool] / Reset rising edge detector
    _eState         : E_DL_TcsBlowdownState := E_DL_TcsBlowdownState.eTcsBdNormal;   // 内部相位（CASE 唯一写入目标）
    _fAccumKg       : REAL := 0.0;   // 窗口累计冷凝水量 [kg] / Accumulated condensate [kg]
    _iAccumAct      : INT := 0;      // 窗口累计动作次数 [count] / Accumulated actuations [count]
    _fRatioRaw      : REAL := 0.0;   // 窗口比值原始值（无因次）[-] / Raw window ratio [-]
    _fRatioRawPct   : REAL := 0.0;   // 窗口比值百分数原始值 [%] / Raw window ratio in percent [%]
    _bFinOk         : BOOL := FALSE; // 实值入参有限性总闸结果 / Finiteness gate aggregate result
    _bCfgOk         : BOOL := FALSE; // 阈值与窗口组态域闸结果 / Threshold and window domain gate result
    _bJudgeThis     : BOOL := FALSE; // 本拍需执行窗口判定（窗口到点）[bool] / Judge this cycle flag
    _bBlockedL      : BOOL := FALSE; // 堵塞锁存位 [bool] / Latched blockage flag
    _bLeakingL      : BOOL := FALSE; // 泄漏锁存位 [bool] / Latched leakage flag
    _bFault         : BOOL := FALSE; // 故障锁存位 [bool] / Latched fault flag
    _uInfo          : UDINT := 16#0000_0000;   // 信息码，每拍重算 / Info code, recomputed every cycle
    _uFault         : UDINT := 16#0000_0000;   // 故障码锁存 / Latched fault code
END_VAR
VAR CONSTANT
    DL_EPS         : REAL := 1.0E-9;      // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_BIG         : REAL := 1.0E12;      // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_PCT         : REAL := 100.0;       // 百分比换算因子 [%] / Percent conversion factor [%]
    DL_RATIO_HI    : REAL := 1000.0;      // 比值显示上限 [-] / Ratio display ceiling [-]
    DL_ACCUM_HI_KG : REAL := 10000.0;     // 累计水量物理上限 [kg] / Accumulated mass upper bound [kg]
    DL_ACT_HI      : INT := 100000;       // 累计次数物理上限 [count] / Accumulation count upper bound [count]
    DL_WATER_MIN_KG : REAL := 0.001;      // 判定「有冷凝水」的最小累计量 [kg] / Minimum condensate to judge [kg]
END_VAR

(* —— 段 0：单拍量预清零（锁存量 _uFault/_bFault/_bBlockedL/_bLeakingL/_fAccumKg/_iAccumAct 不入清单，R187①） —— *)
(*     注：_fRatioRaw / _fRatioRawPct 为「上一窗口判定值」保持量，故意不在此清零，供面板持续显示。 *)
_uInfo := 16#0000_0000;                     // 信息码每拍重算 / Info code recomputed
nErrId := 16#0000_0000;                     // 事件码缺省无事件 / Event code defaults to none

(* —— 段 1：非有限值闸与组态域闸（R19：不把 NaN 累加进窗口） —— *)
_bFinOk := (fCondensateKg > -DL_BIG) AND (fCondensateKg < DL_BIG)
           AND (fExpectKgPerAct > -DL_BIG) AND (fExpectKgPerAct < DL_BIG)
           AND (fBlockRatio > -DL_BIG) AND (fBlockRatio < DL_BIG)
           AND (fLeakRatio > -DL_BIG) AND (fLeakRatio < DL_BIG);
_bCfgOk := (fExpectKgPerAct > DL_EPS)                     // 期望单次排水量必须为正（比值分母）
           AND (fLeakRatio > DL_EPS)                       // 泄漏下限必须为正
           AND (fBlockRatio > fLeakRatio)                   // 堵塞上限必须严格大于泄漏下限
           AND (fBlockRatio <= DL_RATIO_HI)                // 上限须在显示域内
           AND (nActCount >= 0)                            // 动作次数不得为负
           AND (tWindow > T#0S);                           // 观察窗必须为正

(* —— 段 2：边沿与窗口定时器无条件周期刷新（R7：调用语句不得置于 IF/CASE 内） —— *)
rtCycle(CLK := xCyclePulse);                                                    // 周期脉冲上升沿，每拍必调
rtReset(CLK := xReset);                                                         // 复位上升沿，每拍必调
tonWin(IN := xEnable AND (NOT tonWin.Q), PT := tWindow);                        // 观察窗自复位（R188）
_bJudgeThis := tonWin.Q;                                                        // 窗口到点：本拍执行判定

(* —— 段 3：窗口累计（仅在有限值且组态合法时累加，防污染跨窗口传播） —— *)
IF rtCycle.Q AND _bFinOk AND _bCfgOk THEN
    _fAccumKg := _fAccumKg + fCondensateKg;             // 累计冷凝水 [kg]
    _iAccumAct := _iAccumAct + nActCount;               // 累计动作次数 [count]
END_IF

(* —— 段 4：全局故障拦截（优先级最高；已锁存则不再改写码值，禁同拍抹除） —— *)
IF xFault AND (NOT _bFault) THEN
    _uFault := 16#0091_0327;                // 故障级：外部故障输入
    _bFault := TRUE;                        // 锁存（3 行内置，R45 配对）
    _eState := E_DL_TcsBlowdownState.eTcsBdFault;
END_IF
IF (NOT _bFinOk) AND (NOT _bFault) THEN
    _uFault := 16#0091_0326;                // 故障级：入参非有限
    _bFault := TRUE;                        // 锁存
    _fAccumKg := 0.0;                       // 累计器清（防污染跨窗口）
    _iAccumAct := 0;                        // 计数清
    _eState := E_DL_TcsBlowdownState.eTcsBdFault;
END_IF
IF (NOT _bCfgOk) AND _bFinOk AND (NOT _bFault) THEN
    _uFault := 16#0091_0325;                // 故障级：组态越域（独立成因，R190）
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_TcsBlowdownState.eTcsBdFault;
END_IF

(* —— 段 5：相位机（只做迁移与锁存；出口在段 7 单点映射） —— *)
CASE _eState OF

E_DL_TcsBlowdownState.eTcsBdNormal:
    IF NOT xEnable THEN
        _uInfo := 16#0091_0321;             // 信息级：监视关闭，累计冻结（不置故障位）
    ELSIF _bJudgeThis THEN
        IF (_iAccumAct <= 0) AND (_fAccumKg > DL_WATER_MIN_KG) THEN
            _uFault := 16#0091_0324;        // 故障级：动作次数为零但水已积（阀未动作）
            _bBlockedL := TRUE;             // 堵塞锁存
            _eState := E_DL_TcsBlowdownState.eTcsBdBlocked;
        ELSIF (_iAccumAct > 0) AND (ABS(fExpectKgPerAct * INT_TO_REAL(_iAccumAct)) > DL_EPS) THEN
            _fRatioRaw := _fAccumKg / (fExpectKgPerAct * INT_TO_REAL(_iAccumAct));   // 比值 [-]
            _fRatioRawPct := _fRatioRaw * DL_PCT;                                    // 百分数显示 [%]
            IF _fRatioRaw > fBlockRatio THEN
                _uFault := 16#0091_0322;    // 故障级：比值过高，阀堵塞
                _bBlockedL := TRUE;         // 堵塞锁存
                _eState := E_DL_TcsBlowdownState.eTcsBdBlocked;
            ELSIF _fRatioRaw < fLeakRatio THEN
                _uFault := 16#0091_0323;    // 故障级：比值过低，阀泄漏
                _bLeakingL := TRUE;         // 泄漏锁存
                _eState := E_DL_TcsBlowdownState.eTcsBdLeaking;
            ELSE
                _uInfo := 16#0091_0321;     // 信息级：窗口比值合格，进入下一窗口
            END_IF
        ELSE
            _uInfo := 16#0091_0321;         // 信息级：窗口内无有效动作，无法判定
        END_IF
        _fAccumKg := 0.0;                   // 窗口结束：累计清零（判定后统一清，R187 同拍不抹判定）
        _iAccumAct := 0;                    // 窗口结束：计数清零
    ELSE
        _uInfo := 16#0091_0321;             // 信息级：累计中，尚未判定
    END_IF

E_DL_TcsBlowdownState.eTcsBdBlocked:
    IF rtReset.Q THEN
        _bBlockedL := FALSE;                // 解除路径：复位上升沿（可达，R188）
        _uFault := 16#0000_0000;            // 清锁存码
        _fAccumKg := 0.0;                   // 累计器重新起算
        _iAccumAct := 0;                    // 计数重新起算
        _eState := E_DL_TcsBlowdownState.eTcsBdNormal;
    END_IF

E_DL_TcsBlowdownState.eTcsBdLeaking:
    IF rtReset.Q THEN
        _bLeakingL := FALSE;                // 解除路径：复位上升沿（可达，R188）
        _uFault := 16#0000_0000;            // 清锁存码
        _fAccumKg := 0.0;                   // 累计器重新起算
        _iAccumAct := 0;                    // 计数重新起算
        _eState := E_DL_TcsBlowdownState.eTcsBdNormal;
    END_IF

E_DL_TcsBlowdownState.eTcsBdFault:
    IF rtReset.Q AND (NOT xFault) AND _bFinOk AND _bCfgOk THEN
        _bFault := FALSE;                   // 解除路径：复位沿 + 外部故障消失 + 入参/组态合法（可达，R188）
        _uFault := 16#0000_0000;            // 清锁存码
        _fAccumKg := 0.0;                   // 累计器重新起算
        _iAccumAct := 0;                    // 计数重新起算
        _eState := E_DL_TcsBlowdownState.eTcsBdNormal;
    END_IF

ELSE
    _uFault := 16#0091_0328;                // 故障级：非法相位 ID 兜底
    _bFault := TRUE;                        // 锁存
    _bBlockedL := FALSE;                    // 各级锁存清
    _bLeakingL := FALSE;
    _fAccumKg := 0.0;                       // 累计器清
    _iAccumAct := 0;
    _eState := E_DL_TcsBlowdownState.eTcsBdFault;             // 强制回故障相

END_CASE

(* —— 段 6：后置段（累计器域兜底：非有限或越量级即清零，防污染跨窗口） —— *)
IF NOT (_fAccumKg > -DL_BIG AND _fAccumKg < DL_BIG) THEN
    _fAccumKg := 0.0;                       // 内部状态自检：非有限即清零
END_IF
IF _fAccumKg > DL_ACCUM_HI_KG THEN
    _fAccumKg := DL_ACCUM_HI_KG;            // 越物理上限钳制，防累计器发散
END_IF
IF _iAccumAct > DL_ACT_HI THEN
    _iAccumAct := DL_ACT_HI;                // 越计数上限钳制，防整型溢出
END_IF
IF _iAccumAct < 0 THEN
    _iAccumAct := 0;                        // 负计数属异常，归零（不参与比值分母）
END_IF

(* —— 段 7：出口单点映射（名实同源；锁存位一律由状态导出，故障侧全清） —— *)
fRatioPct := LIMIT(0.0, _fRatioRawPct, DL_RATIO_HI * DL_PCT);                     // 比值百分数钳显示域 [%]
fAccumKg := MIN(_fAccumKg, DL_ACCUM_HI_KG);                                       // 累计量出口（已钳，单点写）
nAccumAct := _iAccumAct;                                                          // 累计次数出口
xBlocked := _bBlockedL AND (NOT _bFault);                                         // 堵塞位出口
xLeaking := _bLeakingL AND (NOT _bFault);                                         // 泄漏位出口
xWindowDone := _bJudgeThis;                                                       // 窗口到点单拍脉冲出口
eState := _eState;                                                                // 状态出口单点映射
IF _bFault OR _bBlockedL OR _bLeakingL THEN
    nErrId := _uFault;                      // 故障码锁存回放（不在故障相按当下输入重推断）
ELSE
    nErrId := _uInfo;                       // 信息码
END_IF

END_FUNCTION_BLOCK
