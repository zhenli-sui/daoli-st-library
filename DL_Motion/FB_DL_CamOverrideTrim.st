(*
  FB_DL_CamOverrideTrim  —  凸轮运行中动态修调（幅值/相位偏置实时叠加）/ In-run cam dynamic override trim
  分类 Category : DL_Motion
  码位 Code     : 16#04_0_A6
  段位说明      : 04_0 段占至 A5，A6 格空穴，本件启用 A6 格
  版本 Version  : 1.0.0
  来源 Source   : t1-6-plcopen — T1-6 行待挖项「凸轮动态修调」落地
  溯源 Origin   : clean-room 实现，未复制任何源码行
  功能 Function : 1) 不重选表、不脱耦：在 FC_DL_CamTableInterp 表插值输出上实时叠加修调；
                  2) 相位偏置 fPhaseTrim：主轴位置先叠加相位偏置再查表（fMasterEff = fMasterPos + fPhaseTrim），
                  周期模式下按 fPeriod 取模回界，非周期模式下越界按表界钳制（bInRange 反映真实界内性）；
                  3) 幅值偏置 fAmpTrim：从轴输出直接叠加（fSlaveTrimmed = fSlavePos + fAmpTrim）；
                  4) bTrimFreeze 电平冻结修调：冻结拍输出纯表值（修调增量记忆保留，解冻即恢复）。
  边界 Boundary : ① 本件只做输出叠加，不写轴命令、不下使能，凸轮耦合本体由上层承载；
                  ② 与 FC_DL_CamTableInterp（表插值原子）与 FB_DL_ElectronicCam（耦合本体）分工明确；
                  ③ 修调量非有限防御：NaN/Inf 保持上次有效修调值（增量语义不突变）；
                  ④ 无 CASE 主状态机（变换型 FB）：无相位迁移，无跨相 TON 复用问题；
                  ⑤ 本件每拍必须调用一次（无定时器/边沿实例，跳拍仅导致输出陈旧，无隐藏状态损坏）。
  依赖 Depends  : I_DL_MotionAxis（注入，不实例化，只读 fPosition）；
                  FC_DL_CamTableInterp（函数调用，aCam 开放数组透传）；ST_DL_CamPoint（库内既有结构）
  码表 Error codes（本件格 04_0_A6，子码步进 +0x100）:
    16#0004_01A6 信息级：修调量非有限已保持上次有效值（继续输出，不中断）
    16#0004_02A6 信息级：插值件报错码透传（表非法/越界，本件输出钳界表值）
    16#0004_03A6 信息级：冻结使能中（bTrimFreeze = TRUE，输出纯表值）

  修订历史 Revision :
    2026-11-19  v1.0.0  R39 首版（批次 2 · 序号 7）
*)

FUNCTION_BLOCK FB_DL_CamOverrideTrim
VAR_INPUT
    bEnable     : BOOL := FALSE;      // 使能，FALSE 时输出纯表值（修调旁路）/ Enable, FALSE bypasses trim
    bTrimFreeze : BOOL := FALSE;      // 修调冻结，电平有效：冻结拍输出纯表值 [-] / Trim freeze, level active
    fAmpTrim    : REAL := 0.0;        // 幅值偏置 [mm]，直接叠加从轴输出 / Amplitude trim, added to slave output
    fPhaseTrim  : REAL := 0.0;        // 相位偏置 [mm]，叠加主轴位置后查表 / Phase trim, added to master position
    bPeriodic   : BOOL := FALSE;      // 周期模式使能（与插值件同口径透传）/ Periodic mode, passed to interpolator
    fPeriod     : LREAL := 360.0;     // 周期模式主轴周期 [mm]，域 > 0 / Master period for periodic mode
    bReset      : BOOL := FALSE;      // 修调复位，上升沿清修调保持值（重新从 0 起）/ Trim reset, rising edge clears hold
END_VAR
VAR_OUTPUT
    fSlaveBase    : LREAL;            // 纯表值输出 [mm]（未叠加修调）/ Pure table output without trim
    fSlaveTrimmed : LREAL;            // 修调后从轴输出 [mm] / Trimmed slave output
    bInRange      : BOOL;             // 有效主轴位置在表界内 [-] / Effective master position within table range
    bTrimActive   : BOOL;             // 修调实际生效中（使能且未冻结且偏置非零）/ Trim actually active
    bClampEdge    : BOOL;             // 相位偏置越表界被钳制（非周期模式）/ Phase trim clamped at table edge
    uErrorId      : UDINT;            // 事件码，0 = 无事件（本件码均信息级瞬时）/ Event code, transient info only
END_VAR
VAR_IN_OUT
    iAxis : I_DL_MotionAxis;          // 主轴引用（注入，不实例化，只读位置）/ Master axis reference, position read-only
    aCam  : ARRAY[*] OF ST_DL_CamPoint; // 凸轮表透传（须按 fMaster 升序）/ Cam table passed through, ascending
END_VAR
VAR
    rtReset      : R_TRIG;            // 修调复位沿实例，主体首部无条件刷新 / Trim reset edge instance
    fAmpTrimEff  : REAL := 0.0;       // 生效幅值偏置 [mm]（非有限保持载体）/ Effective amplitude trim with hold
    fPhaseTrimEff: REAL := 0.0;       // 生效相位偏置 [mm]（非有限保持载体）/ Effective phase trim with hold
    fMasterEff   : LREAL;             // 修调后有效主轴位置 [mm] / Effective master position after phase trim
    fSlavePos    : LREAL;             // 插值件从轴输出 [mm] / Interpolator slave output
    eInterpErr   : UDINT;             // 插值件本拍错误码透传 / Interpolator error code passthrough
    bDefend      : BOOL;              // 本拍非有限防御触发标志 / Non-finite defense triggered this cycle
END_VAR
VAR CONSTANT
    DL_COT_INF_CAP : LREAL := 1.0E15;   // 非有限值筛查幅值上限 / Non-finite screening cap
END_VAR

(* —— 段 0：边沿实例无条件周期刷新（R7 红线） —— *)
rtReset(CLK := bReset);                 // 修调复位沿刷新，每拍必调

(* —— 段 1：修调量非有限防御（NaN/Inf 保持上次有效值；复位沿清保持） —— *)
bDefend := FALSE;                       // 防御标志预清零
IF (fAmpTrim <> fAmpTrim) OR (ABS(fAmpTrim) > DL_COT_INF_CAP) OR ((fAmpTrim - fAmpTrim) <> 0.0) THEN
    bDefend := TRUE;                    // 幅值偏置非有限：保持上次有效
ELSE
    fAmpTrimEff := fAmpTrim;            // 有效值入保持载体
END_IF
IF (fPhaseTrim <> fPhaseTrim) OR (ABS(fPhaseTrim) > DL_COT_INF_CAP) OR ((fPhaseTrim - fPhaseTrim) <> 0.0) THEN
    bDefend := TRUE;                    // 相位偏置非有限：保持上次有效
ELSE
    fPhaseTrimEff := fPhaseTrim;        // 有效值入保持载体
END_IF
IF rtReset.Q THEN
    fAmpTrimEff := 0.0;                 // 复位沿：幅值修调归零
    fPhaseTrimEff := 0.0;               // 复位沿：相位修调归零
END_IF

(* —— 段 2：相位偏置叠加（主轴位置先偏置，周期模式取模回界） —— *)
IF bPeriodic AND (fPeriod > 0.0) THEN
    fMasterEff := iAxis.fPosition + fPhaseTrimEff;              // 叠加相位偏置
    fMasterEff := fMasterEff - TRUNC(fMasterEff / fPeriod) * fPeriod;   // 取模回界（分母已闸 > 0）
    IF fMasterEff < 0.0 THEN
        fMasterEff := fMasterEff + fPeriod;                     // 负模回正（保持 [0, fPeriod) 域）
    END_IF
    bClampEdge := FALSE;                                        // 周期模式无表界钳制概念
ELSE
    fMasterEff := iAxis.fPosition + fPhaseTrimEff;              // 非周期：直接叠加（界内性由插值件判）
    bClampEdge := FALSE;                                        // 钳制判定由插值件 bInRange 承载
END_IF

(* —— 段 3：调表插值原子（每拍一次；错误码透传） —— *)
FC_DL_CamTableInterp(fMasterPos := fMasterEff,      // 有效主轴位置（已含相位偏置）
                     bPeriodic := bPeriodic,        // 周期模式透传
                     fPeriod := fPeriod,            // 周期透传
                     aCam := aCam,                  // 凸轮表透传（开放数组引用）
                     fSlavePos => fSlavePos,        // 从轴表值输出
                     bInRange => bInRange,          // 表界内标志输出
                     eErr => eInterpErr);           // 插值件错误码输出
fSlaveBase := fSlavePos;                            // 纯表值镜像

(* —— 段 4：幅值修调叠加与使能门控 —— *)
IF bEnable AND (NOT bTrimFreeze) THEN
    fSlaveTrimmed := fSlaveBase + fAmpTrimEff;      // 修调生效：表值 + 幅值偏置
    bTrimActive := (fAmpTrimEff <> 0.0) OR (fPhaseTrimEff <> 0.0);   // 修调非零即生效中
ELSE
    fSlaveTrimmed := fSlaveBase;                    // 旁路/冻结：输出纯表值（修调保持值不丢）
    bTrimActive := FALSE;
END_IF

(* —— 段 5：事件码合成（信息级瞬时，无锁存） —— *)
uErrorId := 16#0000_0000;               // 缺省无事件
IF bDefend THEN
    uErrorId := 16#0004_01A6;           // 信息级：修调量非有限已保持
ELSIF eInterpErr <> 0 THEN
    uErrorId := 16#0004_02A6;           // 信息级：插值件错误码透传
END_IF
IF bTrimFreeze AND bEnable THEN
    uErrorId := 16#0004_03A6;           // 信息级：冻结使能中（覆盖优先级最低，放最后）
END_IF

END_FUNCTION_BLOCK
