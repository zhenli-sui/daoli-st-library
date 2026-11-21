(*
  FB_DL_StringCurrentMismatch  —  组串电流失配诊断与遮挡定位 / PV string current mismatch diagnostics and shading localisation
  分类 Category : DL_Process
  码位 Code     : 16#06_0_84
  版本 Version  : 1.0.0
  溯源 Source   : LGF Measurement 语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码
  功能 Function : 1) 剔除无效/停机串后取中位基线（中位数抗单串遮挡污染，优于均值）；
                  2) 按失配率分级，失配率分母（基线）近零时自动切换为绝对差判据，防除零；
                  3) 输出最劣串物理串号（连续编址 1..16，越界钳位并置码）与失配掩码。
  边界 Boundary : ① 中位基线计算前剔除无效/停机串（电流 <= 0 或 NaN），有效样本 < 3 时不出诊断结论；
                  ② 失配率分母近零时改绝对差判据（防除零）；
                  ③ 遮挡定位输出按物理串号连续编址，越界下标钳位并置码；
                  ④ 结论态三行同向：基线值 → 最劣串号 → 失配标志。
  依赖 Depends  : None

  码表 Error codes（本件子码步进 16#10，避让邻件码位）:
    16#0002_0684 故障级：串数配置越界（nStringCount 不在 1..16）
    16#0002_0694 故障级：物理串号越界（枚举兜底路径，索引钳位后仍不可能命中）
    16#0002_06A4 信息级：有效样本不足 3 串，本轮不出诊断结论（不置 bError）
*)

TYPE E_DL_ScmPhase :
(
    eIdle    := 0,   // 空闲 / Idle
    eCollect := 10,  // 采样与剔除 / Sampling and rejection
    eDiagnose:= 20,  // 诊断计算 / Diagnostic computation
    eVerdict := 30,  // 结论输出 / Verdict output
    eFault   := 90   // 故障锁定 / Fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_StringCurrentMismatch
VAR_INPUT
    bEnable       : BOOL;                         // 总使能，FALSE 回空闲 / Master enable
    bSample       : BOOL := TRUE;                 // 采样使能，TRUE 每拍纳入诊断 / Sampling enable
    bReset        : BOOL;                         // 复位，上升沿清故障 / Reset, clears fault
    nStringCount  : INT := 16;                    // 组串总数 [串]，域 1~16 / String count, 1..16
    afCurrentA    : ARRAY[1..16] OF REAL;         // 各串电流 [A]，域 > 0 为有效 / Per-string current [A]
    abStringValid : ARRAY[1..16] OF BOOL;         // 各串通讯/熔断有效标志 / Per-string valid flag
    fMismatchPct  : REAL := 10.0;                 // 失配率告警门限 [%]，域 0~100 / Mismatch rate alarm limit [%]
    fAbsFloorA    : REAL := 0.5;                  // 基线近零时的绝对差门限 [A]，域 > 0 / Absolute-difference limit [A]
    fBaselineEpsA : REAL := 0.1;                  // 基线近零判据容差 [A]，域 > 0 / Baseline near-zero tolerance [A]
    fMinSample    : INT := 3;                     // 最少有效样本数 [串]，常量 3 / Minimum valid sample count
END_VAR
VAR_OUTPUT
    fBaselineA    : REAL;                         // 中位基线电流 [A] / Median baseline current [A]
    nWorstIdx     : INT;                          // 最劣串物理串号 1..16，0 = 无 / Worst string number, 0 = none
    fWorstDevPct  : REAL;                         // 最劣串失配率 [%] / Worst string mismatch rate [%]
    fWorstDevA    : REAL;                         // 最劣串绝对偏差 [A] / Worst string absolute deviation [A]
    abMismatchMask : ARRAY[1..16] OF BOOL;        // 失配掩码 [开关]，索引 = 物理串号 / Mismatch mask per physical string
    nMismatchCount : INT;                         // 失配串数 [串] / Mismatched string count
    bMismatch     : BOOL;                         // 存在失配（保持型）/ Mismatch present, held
    bEnoughSample : BOOL;                         // 样本数满足结论条件 / Enough samples for a verdict
    bError        : BOOL;                         // 故障标志，与故障级码配对 / Fault flag paired with fault codes
    uErrorId      : UDINT;                        // 事件码，0 = 无事件 / Event code, 0 = none
    eStateOut     : E_DL_ScmPhase;                // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState       : E_DL_ScmPhase := E_DL_ScmPhase.eIdle;  // 内部状态 / Internal state
    rtrReset      : R_TRIG;                       // 复位沿 / Reset edge
    nN            : INT;                          // 钳位后串数 [串] / Clamped string count
    nI            : INT;                          // 串循环下标 / String loop index
    nJ            : INT;                          // 排序内层下标 / Sort inner index
    nValid        : INT;                          // 有效串数 [串] / Valid string count
    nClampCode    : INT;                          // 下标钳位次数 [次] / Index clamping count
    afSort        : ARRAY[1..16] OF REAL;         // 有效电流排序缓存 [A] / Sorted valid currents [A]
    fTmp          : REAL;                         // 排序交换暂存 [A] / Sort swap buffer [A]
    fMedian       : REAL;                         // 中位基线暂存 [A] / Median baseline buffer [A]
    fDev          : REAL;                         // 单串偏差暂存 [A] / Single-string deviation [A]
    fRate         : REAL;                         // 单串失配率暂存 [%] / Single-string rate [%]
    fWorst        : REAL;                         // 最劣偏差累计 [A] / Worst deviation accumulator [A]
    bNearZero     : BOOL;                         // 基线近零标志 / Baseline near-zero flag
    uFault        : UDINT;                        // 锁存故障码 / Latched fault code
    uInfo         : UDINT;                        // 信息级码 / Information code
END_VAR
VAR CONSTANT
    DL_SCM_STRMAX : INT := 16;                    // 组串数组上界 [串] / String array upper bound
    DL_SCM_PCTMAX : REAL := 100.0;                // 失配率上限 [%] / Mismatch rate ceiling [%]
END_VAR

(* === 段 0 · 实例刷新（无条件周期调用）=== *)
rtrReset(CLK := bReset);                          // 每拍刷新复位沿

(* === 段 1 · 组态与索引闸 === *)
nN := nStringCount;                               // 串数取用前钳位
IF nN < 1 THEN
    nN := 1;                                      // 下限钳位
END_IF
IF nN > DL_SCM_STRMAX THEN
    nN := DL_SCM_STRMAX;                          // 上限钳位
END_IF
IF (nStringCount < 1) OR (nStringCount > DL_SCM_STRMAX) THEN
    uFault := 16#0002_0684;                       // 故障级：串数配置越界
END_IF
IF rtrReset.Q THEN
    uFault := 16#0000;                            // 复位沿清锁存
    bMismatch := FALSE;                           // 失配标志同步复位
    nWorstIdx := 0;                               // 最劣串号复位
END_IF

(* === 段 2 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_ScmPhase.eIdle :
    bEnoughSample := FALSE;                       // 空闲无结论
    uInfo := 16#0000;                             // 信息码清零
    IF uFault = 16#0002_0684 THEN
        _eState := E_DL_ScmPhase.eFault;          // 组态故障优先
    ELSIF bEnable AND bSample THEN
        _eState := E_DL_ScmPhase.eCollect;        // 本拍进入采样相
    END_IF

E_DL_ScmPhase.eCollect :
    nValid := 0;                                  // 有效串计数清零
    nClampCode := 0;                              // 钳位计数清零
    FOR nI := 1 TO DL_SCM_STRMAX DO
        IF nI <= nN THEN
            IF abStringValid[nI]
               AND (afCurrentA[nI] = afCurrentA[nI])              // NaN 自反判据
               AND (ABS(afCurrentA[nI]) < 1.0E30)                 // Inf 上限兜底
               AND (afCurrentA[nI] > 0.0) THEN                    // 停机串（<= 0）剔除
                nValid := nValid + 1;                             // 有效样本计数
                afSort[nValid] := afCurrentA[nI];                 // 收入排序缓存，nValid 已受 DL_SCM_STRMAX 约束
            END_IF
        END_IF
    END_FOR
    IF fMinSample < 3 THEN
        fMinSample := 3;                          // 最小样本数下限钳位（域 >= 3，防组态放宽到误判）
    END_IF
    bEnoughSample := (nValid >= fMinSample);      // 样本不足不出结论
    IF bEnoughSample THEN
        _eState := E_DL_ScmPhase.eDiagnose;       // 转诊断相
    ELSE
        uInfo := 16#0002_06A4;                    // 信息级：样本不足
        _eState := E_DL_ScmPhase.eVerdict;        // 仍走结论相，但结论为空
    END_IF

E_DL_ScmPhase.eDiagnose :
    FOR nI := 1 TO (nValid - 1) DO                // 插入排序求中位数
        FOR nJ := nI + 1 TO nValid DO
            IF afSort[nJ] < afSort[nI] THEN
                fTmp := afSort[nI];               // 交换暂存
                afSort[nI] := afSort[nJ];
                afSort[nJ] := fTmp;
            END_IF
        END_FOR
    END_FOR
    IF (nValid MOD 2) = 1 THEN
        fMedian := afSort[(nValid + 1) / 2];      // 奇数：取正中样本，下标受 nValid 约束
    ELSE
        fMedian := (afSort[nValid / 2] + afSort[(nValid / 2) + 1]) * 0.5;   // 偶数：取中两样本均值
    END_IF
    fBaselineA := fMedian;                        // 基线输出
    bNearZero := (ABS(fMedian) <= fBaselineEpsA); // 基线近零判据（防除零前置）
    nWorstIdx := 0;                               // 最劣串号先清零
    fWorst := -1.0;                               // 最劣偏差累计初值（负值确保首次必更新）
    fWorstDevPct := 0.0;                          // 最劣失配率初值
    fWorstDevA := 0.0;                            // 最劣绝对偏差初值
    nMismatchCount := 0;                          // 失配串计数清零
    FOR nI := 1 TO DL_SCM_STRMAX DO
        abMismatchMask[nI] := FALSE;              // 掩码逐串先清零
        IF nI <= nN THEN
            IF abStringValid[nI] AND (afCurrentA[nI] = afCurrentA[nI]) AND (afCurrentA[nI] > 0.0) THEN
                fDev := fMedian - afCurrentA[nI];                 // 偏差 = 基线 − 实测（正 = 偏低）
                IF bNearZero THEN
                    fRate := ABS(fDev);                               // 基线近零：改绝对差判据
                ELSE
                    fRate := ABS(fDev) / ABS(fMedian) * DL_SCM_PCTMAX;   // 分母已判非零
                END_IF
                IF fRate > DL_SCM_PCTMAX THEN
                    fRate := DL_SCM_PCTMAX;                       // 失配率饱和，防超界显示
                END_IF
                IF (bNearZero AND (ABS(fDev) > fAbsFloorA))
                   OR ((NOT bNearZero) AND (fRate >= fMismatchPct)) THEN
                    abMismatchMask[nI] := TRUE;                   // 该串判失配
                    nMismatchCount := nMismatchCount + 1;         // 失配计数累加
                END_IF
                IF fDev > fWorst THEN
                    fWorst := fDev;                               // 记录最劣偏差
                    IF (nI >= 1) AND (nI <= DL_SCM_STRMAX) THEN
                        nWorstIdx := nI;                          // 物理串号连续编址
                    ELSE
                        nWorstIdx := 0;                           // 越界下标钳位为 0
                        nClampCode := nClampCode + 1;             // 记录钳位事件
                    END_IF
                    fWorstDevPct := fRate;                        // 最劣串失配率
                    fWorstDevA := ABS(fDev);                      // 最劣串绝对偏差
                END_IF
            END_IF
        END_IF
    END_FOR
    bMismatch := (nMismatchCount > 0);            // 置位型结论：存在失配（段尾不清零）
    IF nClampCode > 0 THEN
        uFault := 16#0002_0694;                   // 故障级：物理串号越界已钳位
    END_IF
    _eState := E_DL_ScmPhase.eVerdict;            // 转结论相

E_DL_ScmPhase.eVerdict :
    IF NOT bEnoughSample THEN
        nWorstIdx := 0;                           // 样本不足：不给定位结论
        nMismatchCount := 0;                      // 失配计数归 0
        fWorstDevPct := 0.0;                      // 失配率归 0，避免误导
    END_IF
    IF (NOT bEnable) OR rtrReset.Q THEN
        _eState := E_DL_ScmPhase.eIdle;           // 失能/复位回空闲
    ELSIF bSample THEN
        _eState := E_DL_ScmPhase.eCollect;        // 连续采样：下一拍重新采集
    END_IF

E_DL_ScmPhase.eFault :
    bEnoughSample := FALSE;                       // 故障态不出结论
    nWorstIdx := 0;                               // 最劣串号 0
    IF uFault = 16#0000 THEN
        _eState := E_DL_ScmPhase.eIdle;           // 解锁后回空闲
    END_IF

ELSE
    _eState := E_DL_ScmPhase.eFault;              // 非法状态拦截
    uFault := 16#0002_0694;                       // 故障级：相 ID 越界（枚举兜底路径）
END_CASE

(* === 段 3 · 输出映射（三行同向：基线 → 最劣串号 → 失配标志）=== *)
IF NOT bEnoughSample THEN
    fBaselineA := fMedian;                        // 基线仍输出（诊断可读）
    bMismatch := nMismatchCount > 0;               // 失配标志与计数严格同源
END_IF
IF NOT bEnable THEN
    bMismatch := FALSE;                           // 失能强制清失配结论
    nWorstIdx := 0;                               // 最劣串号归 0
END_IF
bError := (uFault <> 16#0000);                    // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                           // 故障级优先上报
ELSE
    uErrorId := uInfo;                            // 否则上报信息级码
END_IF
eStateOut := _eState;                             // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
