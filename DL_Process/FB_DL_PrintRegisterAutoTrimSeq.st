(*
  DL Factory R83 | FB_DL_PrintRegisterAutoTrimSeq
  功能：印刷套准自动调整状态机，横纵套准误差超差后按三级阶梯逐级小步修正，每步等稳定窗后复评，超步数上限锁故障码。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
  ------------------------------------------------------------------
  分类 DL_Process ｜ 复杂度 cx4 ｜ 版本 v1.0.0 ｜ 平台 纯 IEC 61131-3（TON、R_TRIG、LREAL）
  边界：一 只出三级修正命令，不驱动版辊电机本体、不做套准标记识别（识别归前级视觉件属主）；
        二 阶梯次序固定：一 色标偏移（管横向）→ 二 版辊相位（管纵向）→ 三 张力微调（管纵向残差）；
           一与二同属偏移域共用 eVern 相、由 _nLadder 区分下发通道；三独立占 eTens 相（力值量禁与长度量混加）；
        三 每步下发后等回执沿（脉冲语义，须回零后再置位），否则超时锁 104；每相只允许一个专属定时器，
           IN 只串本相使能与锁存闸，相迁移即 IN 归假并自复位（R18）；tonVern 与 tonTens 分属互斥相、
           无同拍双窗，故 R100 配比约束不适用；
        四 小步下发前方向分列（偏正 ｜ 偏负各占一分支，R146），下发后立即饱和到本通道限值；
        五 命令累加量在复位沿保持末值（已下发修正不得被复位抹掉），作用域在段 1 逐项声明；
           无全局变量、无外部变量声明、无物理地址寻址。
  量纲自检：长度量 [mm] 通道 = fErrCross / fTolCross / fStepVernier / fCmdLimit 与 fErrMachine / fTolMachine / fStepPhase；
        力值量 [N] 通道 = fStepTension / fTensLimit（禁与长度量相加）；组态闸另校各步长落在本通道限值内防越窗振荡。
  输出契约：三级命令为累加型且已饱和；bDone 为电平保持位（新循环起点同拍清零，R28 5.9）；iErrCode 为锁存回放，故障锁存唯一解除路径为 bReset 上升沿（R188）。
  修订记录：2026-11-24 v1.0.0 R83 首版（批 R83 · 序号 37）
*)

TYPE E_DL_PraPhase :
(
    eIdle   := 0,  // 空闲等启动沿 / idle, waiting for the start edge
    eEval   := 10, // 评估：判容差选阶梯并下发（单拍相）/ evaluate, judge and issue in one scan
    eVern   := 20, // 偏移修正等回执（承载阶梯一二）/ offset trim, waiting for the acknowledgement
    eTens   := 30, // 张力修正等回执（承载阶梯三）/ tension trim, waiting for the acknowledgement
    eSettle := 40, // 稳定等稳定窗 / settling, waiting for the window
    eDone   := 50, // 完成：误差在容差内 / done, the error is inside the tolerance
    eFault  := 90  // 故障：成因锁存等复位沿 / fault, the cause is latched until the reset edge
);
END_TYPE

TYPE E_DL_PraCause :
(
    eNone      := 0, // 无成因 / no cause
    eCfgBad    := 1, // 组态越域或量纲失配（故障级，与 bError 配对）/ configuration out of domain, fault grade paired with bError
    eNotFinite := 2, // 入参非有限 NaN 或 Inf（故障级，与 bError 配对）/ non-finite input, fault grade paired with bError
    eStepLimit := 3, // 步数上限耗尽仍超差（故障级，与 bError 配对）/ step budget exhausted, fault grade paired with bError
    eAckTo     := 4, // 步进回执超时（故障级，与 bError 配对）/ acknowledgement timeout, fault grade paired with bError
    ePhaseBad  := 5  // 非法相位兜底（故障级，与 bError 配对）/ illegal phase fallback, fault grade paired with bError
);
END_TYPE

FUNCTION_BLOCK FB_DL_PrintRegisterAutoTrimSeq
VAR CONSTANT
    DL_PRA_LADDER_VERN   : INT := 1; // 阶梯一：色标偏移通道 [级] / ladder one, the register mark offset channel [stage]
    DL_PRA_LADDER_PHASE  : INT := 2; // 阶梯二：版辊相位通道 [级] / ladder two, the plate cylinder phase channel [stage]
    DL_PRA_LADDER_TENS   : INT := 3; // 阶梯三：张力微调通道 [级] / ladder three, the tension trim channel [stage]
    DL_PRA_PHASE_TRY_MAX : INT := 2; // 阶梯二连续复用预算，超限升阶梯三 [次] / the reuse budget of ladder two [time]
END_VAR
VAR_INPUT
    bEnable      : BOOL := TRUE;   // 使能，失能退回空闲（命令保持末值）[-] / enable, a disable returns to idle holding the commands
    bReset       : BOOL := FALSE;  // 复位上升沿清故障锁存与步数 [-]/ reset rising edge clears the latch and the steps
    bStart       : BOOL := FALSE;  // 启动电平，上升沿起一轮调整 [-]/ start level, its rising edge begins one round
    bStepAck     : BOOL := FALSE;  // 步进执行回执（脉冲语义须回零）[-]/ the step acknowledgement, pulse semantics
    fErrCross    : LREAL := 0.0;   // 横向套准误差（正 = 偏大）[mm] / the cross register error, positive means too large [mm]
    fErrMachine  : LREAL := 0.0;   // 纵向套准误差（正 = 偏大）[mm] / the machine register error, positive means too large [mm]
    fTolCross    : LREAL := 0.10;  // 横向容差半带宽 [mm] / the cross tolerance half band [mm]
    fTolMachine  : LREAL := 0.10;  // 纵向容差半带宽 [mm] / the machine tolerance half band [mm]
    fStepVernier : LREAL := 0.05;  // 色标偏移单步量（阶梯一）[mm] / the offset step of ladder one [mm]
    fStepPhase   : LREAL := 0.05;  // 版辊相位单步等效位移（阶梯二）[mm] / the phase step of ladder two [mm]
    fStepTension : LREAL := 2.0;   // 张力微调单步量（阶梯三）[N] / the tension step of ladder three [N]
    fCmdLimit    : LREAL := 5.0;   // 长度通道命令饱和限（对称）[mm] / the symmetric length channel command limit [mm]
    fTensLimit   : LREAL := 200.0; // 张力通道命令饱和限（对称）[N] / the symmetric tension channel command limit [N]
    nMaxStep     : INT := 20;      // 单轮步数上限 [步] / the step budget of one round [step]
    tSettle      : TIME := T#2S;   // 单步后稳定窗 [毫秒] / the settling window after each step [millisecond]
    tAckTo       : TIME := T#10S;  // 步进回执超时窗 [毫秒] / the acknowledgement timeout [millisecond]
END_VAR
VAR_OUTPUT
    bBusy       : BOOL := FALSE;   // 本轮调整进行中 [-] / the round is in progress
    bDone       : BOOL := FALSE;   // 到达容差（保持式，新循环起点清零）[-] / reached the tolerance, held until a new round
    bFault      : BOOL := FALSE;   // 故障锁存 [-] / the fault latch
    bError      : BOOL := FALSE;   // 故障标志，与锁存位同源 [-] / the fault flag sharing the latch source
    iErrCode    : INT := 0;        // 错误码（锁存回放，复位沿清零）[码] / the error code replayed from the latch [code]
    ePhase      : E_DL_PraPhase := E_DL_PraPhase.eIdle; // 相位出口 [枚举] / the phase outlet [enum]
    fVernierOut : LREAL := 0.0;    // 色标偏移命令（累加已饱和）[mm] / the offset command, accumulated [mm]
    fPhaseOut   : LREAL := 0.0;    // 版辊相位命令（累加已饱和）[mm] / the phase command, accumulated [mm]
    fTensionOut : LREAL := 0.0;    // 张力微调命令（累加已饱和）[N] / the tension command, accumulated [N]
    nStepUsed   : INT := 0;        // 本轮已执行步数 [步] / the executed step count [step]
    nLadderIdx  : INT := 1;        // 当前阶梯编号（诊断 1/2/3）[级] / the current ladder index for diagnostics [stage]
    bInTol      : BOOL := FALSE;   // 横纵误差均在容差内 [-] / both errors are inside the tolerance
    bStepActive : BOOL := FALSE;   // 某级小步正在等回执 [-] / a step is waiting for the acknowledgement
END_VAR
VAR
    rtStart   : R_TRIG; // 启动沿，段 0 无条件刷新 / the start edge, refreshed unconditionally
    rtReset   : R_TRIG; // 复位沿，段 0 无条件刷新 / the reset edge, refreshed unconditionally
    rtAck     : R_TRIG; // 回执沿，段 0 无条件刷新 / the acknowledgement edge, refreshed unconditionally
    tonVern   : TON;    // 偏移回执超时窗，段 0 无条件刷新 / the offset acknowledgement timeout
    tonTens   : TON;    // 张力回执超时窗，段 0 无条件刷新 / the tension acknowledgement timeout
    tonSettle : TON;    // 稳定窗，段 0 无条件刷新 / the settling window
    _ePhase   : E_DL_PraPhase := E_DL_PraPhase.eIdle; // 内部相位，CASE 唯一写入目标 / the internal phase, the only CASE target
    _eCause   : E_DL_PraCause := E_DL_PraCause.eNone; // 故障级成因，锁存至复位沿 / the fault cause latched until reset
    _bFault   : BOOL := FALSE; // 故障锁存位 [-] / the fault latch
    _bReq     : BOOL := FALSE; // 本拍故障请求（单拍预清，R107）[-] / the scan fault request, pre-cleared
    _iErrTmp  : INT := 0;      // 本拍码位暂存 [码] / the scan code [code]
    _iErrLch  : INT := 0;      // 码位锁存槽 [码] / the latched code [code]
    _bDone    : BOOL := FALSE; // 完成位内部锁存（清零归属：段 1 复位沿与段 2 启动沿）[-] / the internal done bit
    _bInit    : BOOL := FALSE; // 首扫初始化完成标志（R310）[-] / the first scan initialisation flag
    _bCfgOk   : BOOL := FALSE; // 组态参数域内 [-] / the configuration is inside the domain
    _bFinOk   : BOOL := FALSE; // 全部浮点入参有限 [-] / every floating input is finite
    _bInTol   : BOOL := FALSE; // 容差判据原始值 [-] / the raw tolerance verdict
    _nLadder  : INT := 1;      // 当前阶梯编号 1/2/3 [级] / the current ladder index [stage]
    _nTry     : INT := 0;      // 阶梯二连续使用次数 [次] / the consecutive uses of ladder two [time]
    _nStep    : INT := 0;      // 已执行步数累计 [步] / the executed step count [step]
    _fVernAcc : LREAL := 0.0;  // 偏移命令累加量（复位保持末值）[mm] / the offset accumulator held across a reset [mm]
    _fPhaseA  : LREAL := 0.0;  // 相位命令累加量（复位保持末值）[mm] / the phase accumulator held across a reset [mm]
    _fTensAcc : LREAL := 0.0;  // 张力命令累加量（复位保持末值）[N] / the tension accumulator held across a reset [N]
END_VAR
// 段 0｜定时器与沿检测无条件周期刷新，IN 只串本相使能与锁存闸，禁 R_TRIG.Q 直连（R7 / R18 / FB50-1）
rtStart(CLK := bStart); // 启动沿无条件刷新 / unconditional refresh of the start edge
rtReset(CLK := bReset); // 复位沿无条件刷新 / unconditional refresh of the reset edge
rtAck(CLK := bStepAck); // 回执沿无条件刷新 / unconditional refresh of the acknowledgement edge
tonVern(IN := (_ePhase = E_DL_PraPhase.eVern) AND (NOT _bFault), PT := tAckTo); // 偏移回执超时窗，只串 eVern 相 / the offset timeout gated by eVern only
tonTens(IN := (_ePhase = E_DL_PraPhase.eTens) AND (NOT _bFault), PT := tAckTo); // 张力回执超时窗，只串 eTens 相 / the tension timeout gated by eTens only
tonSettle(IN := (_ePhase = E_DL_PraPhase.eSettle) AND (NOT _bFault), PT := tSettle); // 稳定窗，只串 eSettle 相 / the settling window gated by eSettle only

// 段 1｜首扫初始化与复位沿同块，作用域逐项声明（R310 / R311，两者初始化项同款）
IF (NOT _bInit) OR rtReset.Q THEN // 首扫一拍或复位沿 / the first scan or the reset edge
    _bInit := TRUE; // 首扫完成标志（复位沿重复置位同效）/ the first scan flag, the same effect on reset
    _bFault := FALSE; // 作用域一：清故障锁存位 / scope one, clear the fault latch
    _eCause := E_DL_PraCause.eNone; // 作用域一：清故障级成因 / scope one, clear the fault cause
    _iErrLch := 0; // 作用域一：清码位锁存槽 / scope one, clear the code slot
    _bDone := FALSE; // 作用域二：清完成位（电平保持位由复位沿解除）/ scope two, clear the held done bit
    _ePhase := E_DL_PraPhase.eIdle; // 作用域二：迁回空闲相 / scope two, migrate back to idle
    _nStep := 0; // 作用域三：清累计步数 / scope three, clear the accumulated steps
    _nLadder := DL_PRA_LADDER_VERN; // 作用域三：阶梯回到一 / scope three, the ladder returns to one
    _nTry := 0; // 作用域三：清阶梯二使用次数 / scope three, clear the ladder two counter
END_IF // 作用域之外的保持项：_fVernAcc ｜ _fPhaseA ｜ _fTensAcc 三项保持末值（已下发修正不得被复位抹掉）
// 段 2｜启动沿：新循环起点同拍清完成位与步数（R28 5.9 清零点）
IF rtStart.Q THEN // 启动沿 / the start edge
    _bDone := FALSE; // 完成位清零（上一轮遗留）/ clear the done bit left by the previous round
    _nStep := 0; // 步数清零 / clear the step count
    _nLadder := DL_PRA_LADDER_VERN; // 阶梯回到一 / the ladder returns to one
    _nTry := 0; // 阶梯二使用次数清零 / clear the ladder two counter
END_IF
// 段 3｜组态域闸：参与判据换算的引脚逐项枚举，含量纲尺度自检（R151 / R20 / R272）
_bCfgOk := (fTolCross > 0.0) AND (fTolMachine > 0.0) AND (fCmdLimit > 0.0) AND (fTensLimit > 0.0) // 容差与两通道饱和限须为正 / the tolerances and both channel limits must be positive
    AND (fStepVernier > 0.0) AND (fStepVernier <= fCmdLimit) // 阶梯一步长正且在限内 / ladder one step positive and inside its limit
    AND (fStepPhase > 0.0) AND (fStepPhase <= fCmdLimit) // 阶梯二步长正且在限内 / ladder two step positive and inside its limit
    AND (fStepTension > 0.0) AND (fStepTension <= fTensLimit) // 阶梯三步长正且在限内 / ladder three step positive and inside its limit
    AND (nMaxStep >= 1) AND (tSettle > T#0S) AND (tAckTo > T#0S); // 步数预算与两个时间引脚域闸 / the step budget and the time gates
// 段 4｜非有限闸：9 个浮点入参显式全枚举，NaN 与 Inf 双拦截（R21 / R272）
_bFinOk := (fErrCross > -1.0E30) AND (fErrCross < 1.0E30) AND (fErrMachine > -1.0E30) AND (fErrMachine < 1.0E30) // 横纵误差有限 / both register errors are finite
    AND (fTolCross > -1.0E30) AND (fTolCross < 1.0E30) AND (fTolMachine > -1.0E30) AND (fTolMachine < 1.0E30) // 横纵容差有限 / both tolerances are finite
    AND (fStepVernier > -1.0E30) AND (fStepVernier < 1.0E30) AND (fStepPhase > -1.0E30) AND (fStepPhase < 1.0E30) // 阶梯一二步长有限 / the ladder one and two steps are finite
    AND (fStepTension > -1.0E30) AND (fStepTension < 1.0E30) // 阶梯三步长有限 / the ladder three step is finite
    AND (fCmdLimit > -1.0E30) AND (fCmdLimit < 1.0E30) AND (fTensLimit > -1.0E30) AND (fTensLimit < 1.0E30); // 两通道限值有限 / both channel limits are finite
// 段 5｜容差实时判据：两侧均须满足，且组态与有限性闸位同时成立
_bInTol := _bFinOk AND _bCfgOk AND (ABS(fErrCross) <= fTolCross) AND (ABS(fErrMachine) <= fTolMachine); // 双闸位与双容差同真 / both gates and both tolerances hold
// 段 6｜故障判据与锁存：请求位每拍预清，锁存与迁相同拍执行（R107 / FB50-1④ / R152）
_bReq := FALSE; // 单拍请求位预清（不含 Prev 快照与锁存量）/ pre-clear the single scan request
_iErrTmp := 0; // 本拍码位暂存预清 / pre-clear the scan code
IF (NOT _bFault) AND (NOT _bCfgOk) THEN // 组态越域 / the configuration is out of domain
    _eCause := E_DL_PraCause.eCfgBad; _iErrTmp := 101; // 故障级成因与码位：组态越域 / fault cause and code, the configuration is out of domain
    bError := TRUE; // R45 配对：故障级码位同拍置故障标志 / the fault flag paired with the code
    _bReq := TRUE; // 请求本拍锁存 / request the latch
END_IF
IF (NOT _bFault) AND (NOT _bFinOk) THEN // 入参非有限 / a non-finite input
    _eCause := E_DL_PraCause.eNotFinite; _iErrTmp := 102; // 故障级成因与码位：入参非有限 / fault cause and code, a non-finite input
    bError := TRUE; // R45 配对：故障级码位同拍置故障标志 / the fault flag paired with the code
    _bReq := TRUE; // 请求本拍锁存 / request the latch
END_IF
IF _bReq AND (NOT _bFault) THEN // 锁存只认当拍首因 / latch only the first cause of this scan
    _iErrLch := _iErrTmp; // 码位进锁存槽 / the code enters the latch slot
    _bFault := TRUE; // 置故障锁存位 / raise the fault latch
    _ePhase := E_DL_PraPhase.eFault; // 锁存同拍迁故障相 / migrate to the fault phase in the same scan
END_IF
// 段 7｜相位状态机：ENUM + CASE + ELSE 非法相位兜底（R6 / R128），相内锁存与迁相同分支（FB50-1④）
CASE _ePhase OF
E_DL_PraPhase.eIdle: // 空闲相：退出条件二（启动沿生效 ｜ 使能未给则驻留等下一沿）
    IF bEnable AND rtStart.Q THEN // 启动沿且使能 / the start edge while enabled
        _ePhase := E_DL_PraPhase.eEval; // 迁评估相（拍 N 进入：本相起点 ｜ 本拍行为：拒绝下发 ｜ 拍 N+1 转出：决策相）
    END_IF
E_DL_PraPhase.eEval: // 评估相：单拍决策——判容差、判步数、选阶梯、下发小步
    IF _bInTol THEN // 误差已入容差 / the errors are inside
        _bDone := TRUE; _ePhase := E_DL_PraPhase.eDone; // 置完成位（保持至新循环起点）并迁完成相 / raise done and migrate
    ELSIF _nStep >= nMaxStep THEN // 步数预算耗尽仍超差 / the budget is exhausted
        _eCause := E_DL_PraCause.eStepLimit; _iErrLch := 103; // 故障级成因与码位：步数耗尽 / fault cause and code, the step budget exhausted
        bError := TRUE; // R45 配对：故障级成因同拍置故障标志 / the fault flag paired with the cause
        _bFault := TRUE; _ePhase := E_DL_PraPhase.eFault; // 置锁存并迁故障相 / latch and migrate to the fault phase
    ELSIF (ABS(fErrCross) > fTolCross) THEN // 横向超差：走阶梯一（色标偏移）/ the cross error is out, take ladder one
        _nLadder := DL_PRA_LADDER_VERN; _nTry := 0; // 阶梯登记为一并清阶梯二计数 / register ladder one and clear the counter
        IF fErrCross > 0.0 THEN _fVernAcc := _fVernAcc - fStepVernier; ELSE _fVernAcc := _fVernAcc + fStepVernier; END_IF // 方向分列：偏正减步长 ｜ 偏负加步长 / direction split by the error sign
        IF _fVernAcc > fCmdLimit THEN _fVernAcc := fCmdLimit; ELSIF _fVernAcc < (0.0 - fCmdLimit) THEN _fVernAcc := (0.0 - fCmdLimit); END_IF // 双向饱和到通道限 / two sided saturation
        _nStep := _nStep + 1; _ePhase := E_DL_PraPhase.eVern; // 计一步并迁偏移修正相等回执 / count the step and wait for the acknowledgement
    ELSIF (ABS(fErrMachine) > fTolMachine) AND (_nTry < DL_PRA_PHASE_TRY_MAX) THEN // 纵向超差且阶梯二在预算内 / the machine error is out within the ladder two budget
        _nLadder := DL_PRA_LADDER_PHASE; _nTry := _nTry + 1; // 阶梯登记为二并计一次使用 / register ladder two and count one use
        IF fErrMachine > 0.0 THEN _fPhaseA := _fPhaseA - fStepPhase; ELSE _fPhaseA := _fPhaseA + fStepPhase; END_IF // 相位方向分列 / the phase direction split
        IF _fPhaseA > fCmdLimit THEN _fPhaseA := fCmdLimit; ELSIF _fPhaseA < (0.0 - fCmdLimit) THEN _fPhaseA := (0.0 - fCmdLimit); END_IF // 双向饱和到通道限 / two sided saturation
        _nStep := _nStep + 1; _ePhase := E_DL_PraPhase.eVern; // 计一步并迁偏移修正相等回执 / count the step and wait for the acknowledgement
    ELSE // 纵向超差且阶梯二预算耗尽：升阶梯三（张力微调）/ the budget is gone, escalate to ladder three
        _nLadder := DL_PRA_LADDER_TENS; // 阶梯登记为三 / register ladder three
        IF fErrMachine > 0.0 THEN _fTensAcc := _fTensAcc + fStepTension; ELSE _fTensAcc := _fTensAcc - fStepTension; END_IF // 偏正升张力 ｜ 偏负降张力 / raise the tension when the error is positive
        IF _fTensAcc > fTensLimit THEN _fTensAcc := fTensLimit; ELSIF _fTensAcc < (0.0 - fTensLimit) THEN _fTensAcc := (0.0 - fTensLimit); END_IF // 双向饱和到通道限 / two sided saturation
        _nStep := _nStep + 1; _ePhase := E_DL_PraPhase.eTens; // 计一步并迁张力修正相等回执 / count the step and wait for the acknowledgement
    END_IF
E_DL_PraPhase.eVern: // 偏移修正相：退出条件三（回执沿 ｜ 回执超时 ｜ 使能丢失），本拍事件优先于超时（R275）
    IF NOT bEnable THEN // 使能丢失 / the enable was lost
        _ePhase := E_DL_PraPhase.eIdle; // 退回空闲（命令保持末值）/ back to idle holding the commands
    ELSIF rtAck.Q THEN // 回执沿先消化 / digest the acknowledgement first
        _ePhase := E_DL_PraPhase.eSettle; // 迁稳定相 / migrate to settle
    ELSIF tonVern.Q THEN // 回执超时 / the acknowledgement timed out
        _eCause := E_DL_PraCause.eAckTo; _iErrLch := 104; // 故障级成因与码位：回执超时 / fault cause and code, the acknowledgement timeout
        bError := TRUE; // R45 配对：故障级成因同拍置故障标志 / the fault flag paired with the cause
        _bFault := TRUE; _ePhase := E_DL_PraPhase.eFault; // 置锁存并迁故障相 / latch and migrate to the fault phase
    END_IF
E_DL_PraPhase.eTens: // 张力修正相：退出条件三（回执沿 ｜ 回执超时 ｜ 使能丢失），本拍事件优先于超时（R275）
    IF NOT bEnable THEN // 使能丢失 / the enable was lost
        _ePhase := E_DL_PraPhase.eIdle; // 退回空闲（命令保持末值）/ back to idle holding the commands
    ELSIF rtAck.Q THEN // 回执沿先消化 / digest the acknowledgement first
        _ePhase := E_DL_PraPhase.eSettle; // 迁稳定相 / migrate to settle
    ELSIF tonTens.Q THEN // 回执超时 / the acknowledgement timed out
        _eCause := E_DL_PraCause.eAckTo; _iErrLch := 104; // 故障级成因与码位：回执超时 / fault cause and code, the acknowledgement timeout
        bError := TRUE; // R45 配对：故障级成因同拍置故障标志 / the fault flag paired with the cause
        _bFault := TRUE; _ePhase := E_DL_PraPhase.eFault; // 置锁存并迁故障相 / latch and migrate to the fault phase
    END_IF
E_DL_PraPhase.eSettle: // 稳定相：退出条件二（稳定窗到期 ｜ 使能丢失）
    IF NOT bEnable THEN // 使能丢失 / the enable was lost
        _ePhase := E_DL_PraPhase.eIdle; // 退回空闲 / back to idle
    ELSIF tonSettle.Q THEN // 稳定窗到期（拍 N 进入：本相起点 ｜ 本拍行为：拒绝新步进 ｜ 拍 N+1 转出：复评）
        _ePhase := E_DL_PraPhase.eEval; // 回评估相复评误差 / back to evaluate
    END_IF
E_DL_PraPhase.eDone: // 完成相：退出条件二（启动沿消失 ｜ 使能丢失），完成位由新循环起点清零
    IF (NOT bStart) OR (NOT bEnable) THEN // 启动电平消失或失能 / the start level dropped or the enable was lost
        _ePhase := E_DL_PraPhase.eIdle; // 回空闲相等下一轮 / back to idle for the next round
    END_IF
E_DL_PraPhase.eFault: // 故障相：成因锁存回放，唯一解除路径为 bReset 上升沿（R188）
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_PraPhase.eIdle; // 迁空闲（锁存位仍须复位沿解除）/ migrate to idle, the latch still needs the reset edge
    END_IF
ELSE // 非法相位兜底（R6 / R128）/ the illegal phase fallback
    _eCause := E_DL_PraCause.ePhaseBad; _iErrLch := 105; // 故障级成因与码位：非法相位 / fault cause and code, an illegal phase
    bError := TRUE; // R45 配对：故障级成因同拍置故障标志 / the fault flag paired with the cause
    _bFault := TRUE; _ePhase := E_DL_PraPhase.eFault; // 置锁存并迁故障相 / latch and migrate to the fault phase
END_CASE
IF _bFault AND (_ePhase <> E_DL_PraPhase.eFault) THEN // 段尾迁移闸：任何锁存路径不得留在业务相（FB50-1④）
    _ePhase := E_DL_PraPhase.eFault; // 统一迁故障相 / force the fault phase
END_IF
// 段 8｜统一出口：命令、状态与码位单点映射（故障期命令保持末值，不再推进）
fVernierOut := _fVernAcc; // 色标偏移命令单点映射 / single point mapping of the offset command
fPhaseOut := _fPhaseA; // 版辊相位命令单点映射 / single point mapping of the phase command
fTensionOut := _fTensAcc; // 张力命令单点映射 / single point mapping of the tension command
nStepUsed := _nStep; // 步数单点映射 / single point mapping of the step count
nLadderIdx := _nLadder; // 阶梯编号单点映射 / single point mapping of the ladder index
bInTol := _bInTol; // 容差判据单点映射 / single point mapping of the tolerance verdict
bStepActive := (_ePhase = E_DL_PraPhase.eVern) OR (_ePhase = E_DL_PraPhase.eTens); // 等回执判据 / the waiting acknowledgement verdict
bBusy := bEnable AND (_ePhase <> E_DL_PraPhase.eIdle) AND (_ePhase <> E_DL_PraPhase.eDone) AND (_ePhase <> E_DL_PraPhase.eFault); // 运行位排除空闲完成与故障三相 / the busy bit excludes idle, done and fault
bDone := _bDone; // 完成位单点映射（保持式）/ single point mapping of the held done bit
bFault := _bFault; // 故障锁存单点映射 / single point mapping of the latch
IF _bFault THEN // 故障期回放锁存码，不在故障相按当下输入重推（R152）/ replay the latched code
    iErrCode := _iErrLch; // 锁存码回放 / replay the latched code
    bError := TRUE; // 故障标志与锁存位同源 / the fault flag shares the latch source
ELSE // 非故障期 / outside fault
    iErrCode := 0; // 无故障码 / no error code
    bError := FALSE; // 无故障标志 / no fault flag
END_IF
ePhase := _ePhase; // 相位出口单点映射 / single point mapping of the phase
END_FUNCTION_BLOCK
