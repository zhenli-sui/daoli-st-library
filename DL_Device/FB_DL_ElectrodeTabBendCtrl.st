(*
  FB_DL_ElectrodeTabBendCtrl  —  极耳折弯角度与回弹补偿 / Electrode tab bend control with springback learning
  分类 Category : DL_Device
  码位 Code     : 16#03_2_13
  段位说明      : 03_2 段低半字节 00~0F 已满（05 为历史空穴留存），进位 13 段续号（R192）
  版本 Version  : 1.0.2
  来源 Source   : t2-2-lbp — IEC 61131-3 标准语义的道莅防御性实现
  溯源 Origin   : clean-room 实现，卷对卷极耳折弯公开工艺语义，未复制任何源码行
                  （与 FB_DL_RollerGapAdjust 分工：本件按「角度—回弹」双变量收敛；间隙调整由 RollerGapAdjust 承载）
  功能 Function : 1) 单向逼近：压头只发 CmdExtend（只进不退，防反向回弹迟滞），到位后测角；
                  2) 误差超 fAngleTolDeg 则按 fLearnGain 修正回弹学习值再弯一次，累计学习值限幅 [0, fSpringbackMaxDeg]；
                  3) 下发弯折角 fCmdAngleDeg = 目标角 + 回弹学习值；迭代收敛（|测角 − 目标| <= 容差）进 Done；
                  4) fLearnGain = 0 时学习值冻结（组态可关学习）。
  边界 Boundary : ① fTargetAngleDeg <= 0 或 > fAngleMaxDeg 判组态错；容差/迭代数/限幅/超时非法同判；
                  ② iPressCyl.bFault 判气缸故障进 Fault；步超 tStepTimeout 同判（安全侧回退）；
                  ③ 迭代数超 nMaxIteration 置 bIterationExhausted 且 bInTolerance := FALSE（不静默当作 OK，判废）；
                  ④ 回弹学习值跨批次掉电不保（本件不持非易失，持久化由上层承载）；
                  ⑤ 测角由 VAR_INPUT fAngleMeasDeg 注入（上位角度传感器，规格未列的必要引脚补充）；
                  ⑥ 解除式自证：bIterationExhausted 解除 = bReset 上升沿 AND eState = Idle（引脚可满足）；
                  ⑦ CASE 全态覆盖 + ELSE 兜底置故障相。
  依赖 Depends  : I_DL_Cylinder（注入，不实例化）；语义对齐 FB_DL_RateLimiter / FB_DL_ToleranceWindow（已注册，不实例化）
  码表 Error codes（本件格 03_2_13，子码步进 +0x100）:
    16#0003_0113 信息级：弯折迭代收敛（Done 相）
    16#0003_0213 故障级：组态非法（目标角越域 / 容差 <= 0 / 增益越 0..1 / 迭代 < 1 / 限幅 <= 0 / 超时 <= 0）
    16#0003_0313 故障级：气缸故障或步超时（逼近/测量两相独立计时），锁存至复位
    16#0003_0413 故障级：迭代耗尽判废（bIterationExhausted，bInTolerance = FALSE）
    16#0003_0513 故障级：状态机落 ELSE 兜底（非法相位 ID）

R39 返修（R38 终审挂账闭环，v1.0.2）: ① tonStep 三相共享无迁移断拍 → 拆分为三相独立实例
  （tonStepAppr 逼近超时 / tonHold 保压计时 / tonStepMeas 测量超时，IN 单相等式，跨相迁移拍必断，R228-A 达标）；
  ② eBend 复用超时计时作保压 → 保压计时改由独立实例 tonHold 承载（PT 沿用 tStepTimeout 参数，
  对外接口不变约束下保持 v1.0.1 保压时长口径；测量相补步超时保护，码 0313 覆盖口径随之扩全三相）；
  ③ eFault 无迁出 → eFault 相新增 bReset 上升沿迁出边回 eIdle（迁出条件 = 输入引脚 rtReset.Q，恒可达）。
  修订历史 Revision :
    2026-11-19  v1.0.2  R39 返修：三相 TON 拆分 + 保压分实例 + eFault 迁出边（R38 挂账三项闭环）
    2026-11-18  v1.0.0  R38 首版
*)

TYPE E_DL_TabBendState :
(
    eIdle     := 0,    // 空闲：等启动指令 / Idle, waiting for start
    eApproach := 10,   // 逼近：压头伸出至弯折位 / Approach, cylinder extending
    eBend     := 20,   // 弯折：保压至测角稳定 / Bend, pressing hold
    eMeasure  := 30,   // 测量：采测角并判收敛 / Measure, sampling angle
    eCorrect  := 40,   // 修正：更新回弹学习值 / Correct, updating learned springback
    eDone     := 50,   // 完成：收敛或判废落定 / Done, converged or scrapped
    eFault    := 90    // 故障：组态/气缸/超时锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_ElectrodeTabBendCtrl
VAR_INPUT
    bStart             : BOOL := FALSE;     // 启动指令（上升沿）/ Start command
    fAngleMeasDeg      : REAL := 0.0;       // 测角输入 [deg]（上位传感器注入）/ Measured angle input
    fTargetAngleDeg    : REAL := 90.0;      // 目标弯折角 [deg]，域 (0, fAngleMaxDeg] / Target bend angle
    fSpringbackInitDeg : REAL := 0.0;       // 初始回弹量 [deg]，域 [0, fSpringbackMaxDeg] / Initial springback
    fSpringbackMaxDeg  : REAL := 10.0;      // 回弹学习值限幅 [deg]，域 > 0 / Springback learning clamp
    fAngleMaxDeg       : REAL := 135.0;     // 目标角上限 [deg]，域 > 0 / Target angle ceiling
    fAngleTolDeg       : REAL := 0.5;       // 角度容差 [deg]，域 > 0 / Angle tolerance
    fLearnGain         : REAL := 0.5;       // 学习增益 [无量纲 0..1]，0 = 冻结学习 / Learning gain, 0 freezes
    nMaxIteration      : INT  := 5;         // 最大迭代数 [次]，域 >= 1 / Max iterations
    tStepTimeout       : TIME := T#3S;      // 单步超时 [ms]，域 > 0 / Step timeout
    bReset             : BOOL := FALSE;     // 复位（判废解除路径之一）/ Reset
END_VAR
VAR_OUTPUT
    fCmdAngleDeg          : REAL;           // 下发弯折角 [deg] = 目标 + 回弹 / Commanded bend angle
    fMeasAngleDeg         : REAL;           // 测角出口 [deg] / Measured angle outlet
    fSpringbackLearnedDeg : REAL;           // 回弹学习值 [deg] / Learned springback
    bInTolerance          : BOOL;           // 收敛在容差内 / Within tolerance
    bIterationExhausted   : BOOL;           // 迭代耗尽判废锁存 / Iteration exhausted latch
    nIteration            : INT;            // 当前迭代数 [次] / Iteration count
    nErrId                : UDINT;          // 事件码，0 = 无事件 / Event code
    eState                : E_DL_TabBendState;  // 状态出口，段尾单点映射 / State outlet
END_VAR
VAR_IN_OUT
    iPressCyl : I_DL_Cylinder;              // 压装气缸引用（注入，不实例化）/ Press cylinder reference
END_VAR
VAR
    tonStepAppr: TON;                       // 逼近相超时计时（单相独占）/ Approach timeout timer
    tonHold    : TON;                       // 保压相计时（单相独占，PT=tStepTimeout 口径）/ Bend hold timer
    tonStepMeas: TON;                       // 测量相超时计时（单相独占）/ Measure timeout timer
    tonFaultWch: TON;                       // 故障观察窗，自复位 / Fault watch window, self-resetting
    rtStart    : R_TRIG;                    // 启动上升沿 / Start rising edge
    rtReset    : R_TRIG;                    // 复位上升沿 / Reset rising edge
    _eState    : E_DL_TabBendState := E_DL_TabBendState.eIdle;   // 内部相位（CASE 唯一写入目标）/ Internal phase
    _rLearn    : REAL;                      // 回弹学习值内部量 / Internal learned springback
    _rErr      : REAL;                      // 角度误差暂存 [deg] / Angle error scratch
    _uFault    : UDINT;                     // 故障码锁存 / Latched fault code
    _uInfo     : UDINT;                     // 信息码，每拍重算 / Info code
    _bFault    : BOOL;                      // 故障锁存位 / Latched fault bit
    _bCfgBad   : BOOL;                      // 组态非法聚合 / Configuration invalid aggregate
    _bExhaust  : BOOL;                     // 迭代耗尽锁存（解除式）/ Iteration exhausted latch
END_VAR
VAR CONSTANT
    DL_WatchPt : TIME := T#2S;   // 故障观察窗 [ms]，自复位 / Fault watch window
END_VAR

(* —— 段 0：定时器与边沿无条件周期刷新（R182：调用语句不得置于 IF/CASE 内） —— *)
rtStart(CLK := bStart);                                          // 启动上升沿，每拍必调
rtReset(CLK := bReset);                                          // 复位上升沿，每拍必调
tonFaultWch(IN := (NOT tonFaultWch.Q), PT := DL_WatchPt);        // 观察窗自复位（表达式入参）
tonStepAppr(IN := (_eState = E_DL_TabBendState.eApproach), PT := tStepTimeout);  // 逼近超时（单相独占）
tonHold(IN := (_eState = E_DL_TabBendState.eBend), PT := tStepTimeout);          // 保压计时（单相独占，PT=保压口径）
tonStepMeas(IN := (_eState = E_DL_TabBendState.eMeasure), PT := tStepTimeout);   // 测量超时（单相独占）

(* —— 段 1：单拍量预清零（锁存量 _uFault/_bFault/_bExhaust/_rLearn 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;         // 信息码每拍重算
bInTolerance := FALSE;          // 收敛出口缺省 FALSE（Done 相单点置位）
bIterationExhausted := _bExhaust;   // 判废出口 = 解除式锁存量（禁同拍抹除）
_bCfgBad := FALSE;              // 组态非法预清零
nErrId := 16#0000_0000;         // 事件码缺省无事件

(* —— 段 2：组态域闸（覆盖全部参与判据换算的引脚，R151） —— *)
IF (fTargetAngleDeg <= 0.0) OR (fTargetAngleDeg > fAngleMaxDeg) OR (fAngleMaxDeg <= 0.0) THEN
    _bCfgBad := TRUE;           // 目标角越域
END_IF
IF (fAngleTolDeg <= 0.0) OR (fSpringbackMaxDeg <= 0.0) THEN
    _bCfgBad := TRUE;           // 容差/限幅非法
END_IF
IF (fLearnGain < 0.0) OR (fLearnGain > 1.0) THEN
    _bCfgBad := TRUE;           // 学习增益越 0..1
END_IF
IF (nMaxIteration < 1) OR (TIME_TO_DINT(tStepTimeout) <= 0) THEN
    _bCfgBad := TRUE;           // 迭代数/超时非法
END_IF
IF (fSpringbackInitDeg < 0.0) OR (fSpringbackInitDeg > fSpringbackMaxDeg) THEN
    _bCfgBad := TRUE;           // 初始回弹越域
END_IF

(* —— 段 3：复位沿（判废解除式：bReset AND eState = Idle） —— *)
IF rtReset.Q THEN
    IF _eState = E_DL_TabBendState.eIdle THEN
        _bExhaust := FALSE;     // 判废锁存清零（解除式自证路径）
        _bFault   := FALSE;     // 清故障锁存位
        _uFault   := 16#0000_0000;
        nIteration := 0;        // 迭代计数清零
    END_IF
END_IF

(* —— 段 4：下发角计算（目标 + 学习值，限幅 [0, fSpringbackMaxDeg]） —— *)
IF NOT _bCfgBad THEN
    _rLearn := MAX(0.0, MIN(_rLearn, fSpringbackMaxDeg));   // 学习值限幅（禁越界）
    fCmdAngleDeg := fTargetAngleDeg + _rLearn;              // 下发弯折角 = 目标 + 回弹
END_IF

(* —— 段 5：相位机（只做迁移与单发命令；出口在段 8） —— *)
CASE _eState OF

E_DL_TabBendState.eIdle:
    IF _bCfgBad THEN
        _uFault := 16#0003_0213;                // 故障级：组态非法
        _bFault := TRUE;                        // 锁存（复位沿可清）
        _eState := E_DL_TabBendState.eFault;
    ELSIF rtStart.Q AND (NOT _bExhaust) THEN
        _rLearn := fSpringbackInitDeg;          // 批次起步：装初始回弹量（跨批次不保持）
        nIteration := 0;                        // 迭代计数清零
        iPressCyl.CmdExtend();      // 单发伸出（单向逼近，只进不退）
        _eState := E_DL_TabBendState.eApproach; // 进逼近相
    END_IF

E_DL_TabBendState.eApproach:
    IF iPressCyl.bFault THEN
        _uFault := 16#0003_0313;                // 故障级：气缸故障
        _bFault := TRUE;
        iPressCyl.CmdStop();        // 安全侧停
        _eState := E_DL_TabBendState.eFault;
    ELSIF iPressCyl.bExtended THEN
        _eState := E_DL_TabBendState.eBend;     // 到位：进保压相
    ELSIF tonStepAppr.Q THEN
        _uFault := 16#0003_0313;                // 故障级：逼近相步超时
        _bFault := TRUE;
        iPressCyl.CmdStop();
        _eState := E_DL_TabBendState.eFault;
    END_IF

E_DL_TabBendState.eBend:
    IF iPressCyl.bFault THEN
        _uFault := 16#0003_0313;                // 故障级：气缸故障
        _bFault := TRUE;
        iPressCyl.CmdStop();
        _eState := E_DL_TabBendState.eFault;
    ELSIF tonHold.Q THEN
        _eState := E_DL_TabBendState.eMeasure;  // 保压到点：进测量相（独立实例，R228-A）
    END_IF

E_DL_TabBendState.eMeasure:
    fMeasAngleDeg := fAngleMeasDeg;             // 测角出口刷新
    _rErr := fMeasAngleDeg - fTargetAngleDeg;   // 误差 = 测角 − 目标
    IF tonStepMeas.Q THEN
        _uFault := 16#0003_0313;                // 故障级：测量相步超时（返修补全的第三相保护）
        _bFault := TRUE;
        iPressCyl.CmdStop();
        _eState := E_DL_TabBendState.eFault;
    ELSIF ABS(_rErr) <= fAngleTolDeg THEN
        bInTolerance := TRUE;                   // 收敛：容差内
        _uInfo := 16#0003_0113;                 // 信息级：迭代收敛
        iPressCyl.CmdRetract();     // 单发缩回（批次收尾）
        _eState := E_DL_TabBendState.eDone;     // 进完成相
    ELSIF nIteration >= nMaxIteration THEN
        _bExhaust := TRUE;                      // 判废锁存（不静默当作 OK）
        _uFault := 16#0003_0413;                // 故障级：迭代耗尽
        _bFault := TRUE;
        bInTolerance := FALSE;                  // 强制 FALSE（规格强制）
        iPressCyl.CmdRetract();
        _eState := E_DL_TabBendState.eDone;     // 进完成相（判废落定）
    ELSE
        _eState := E_DL_TabBendState.eCorrect;  // 未收敛未耗尽：进修正相
    END_IF

E_DL_TabBendState.eCorrect:
    IF fLearnGain > 0.0 THEN
        _rLearn := MAX(0.0, MIN(_rLearn + _rErr * fLearnGain, fSpringbackMaxDeg));   // 学习值修正并限幅
    END_IF
    nIteration := nIteration + 1;               // 迭代计数（上限守卫在 Measure 相判定）
    iPressCyl.CmdExtend();          // 单发再弯（单向逼近）
    _eState := E_DL_TabBendState.eApproach;     // 回逼近相

E_DL_TabBendState.eDone:
    IF NOT iPressCyl.bExtended THEN
        IF NOT _bExhaust THEN
            _eState := E_DL_TabBendState.eIdle;     // 缩回完成且非判废：回空闲
        ELSE
            _eState := E_DL_TabBendState.eIdle;     // 判废也回空闲（bReset 沿清判废锁存）
        END_IF
    END_IF

E_DL_TabBendState.eFault:
    IF rtReset.Q THEN                           // 迁出边：bReset 上升沿（R228-B：输入引脚，恒可达）
        _bFault := FALSE;                       // 清故障锁存位
        _uFault := 16#0000_0000;                // 清锁存码
        _bExhaust := FALSE;                     // 判废锁存清零（迁出统一清账）
        _eState := E_DL_TabBendState.eIdle;     // 迁出：回空闲（Idle 可达路径：故障迁出边）
    END_IF

ELSE
    _uFault := 16#0003_0513;                    // 故障级：非法相位 ID 兜底
    _bFault := TRUE;                            // 锁存
    _eState := E_DL_TabBendState.eFault;        // 强制回故障相

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
bIterationExhausted := _bExhaust;               // 判废出口 = 锁存量（置位同拍不被抹）
IF _bFault THEN
    nErrId := _uFault;              // 故障锁存码回放
    bInTolerance := FALSE;          // 故障相收敛出口强制 FALSE（安全侧）
ELSE
    nErrId := _uInfo;               // 信息码
END_IF
eState := _eState;                  // 状态出口单点映射

END_FUNCTION_BLOCK
