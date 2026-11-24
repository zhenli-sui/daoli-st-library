(*
  FB_DL_FiringFurnaceZone  —  烧结炉多温区峰值温度跟随（链速联动前馈） / Firing furnace multi-zone peak tracking with chain-speed feedforward
  分类 Category : DL_Process
  码位 Code     : 16#06_0_97
  版本 Version  : 1.0.0
  溯源 Source   : LGF Technology 语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码
  功能 Function : 1) 各温区设定 = 目标峰值温度 + 链速前馈重置量（重置量限幅防阶跃）；
                  2) 峰值窗判定多拍确认（连续 N 拍在窗才置区合格）；
                  3) 链速为 0 用最后有效链速并置 bHold（禁外推）。
  边界 Boundary : ① 链速为 0：保持末次有效链速参与前馈折算并置 bHold，禁外推；
                  ② 前馈系数与链速量纲配比（[%/mm per s] × [mm/s] → [%]）在头注释写死；
                  ③ 峰值窗判定需多拍确认（单拍在窗不置合格）；
                  ④ 区无效冻结该区判定并置码；
                  ⑤ 输出三行同向：区设定 → 区合格 → 前馈重置量。
  依赖 Depends  : 无实例依赖（前馈折算与多拍确认自含实现）

  码表 Error codes（本件子码步进 16#30 · 本格 97 与既有 9X 子码段冲突，错位至 C7/D7 避让）:
    16#0002_06C7 故障级：组态非法（前馈系数或确认拍数 <= 0 / 窗半宽 <= 0 / 重置限幅 <= 0 / 目标温度非有限）
    16#0002_06D7 故障级：相 ID 越界（枚举兜底路径）
    16#0002_06B7 信息级：链速为 0 保持 / 温区无效判定冻结（不置 bError）
*)

TYPE E_DL_FfzPhase :
(
    eIdle  := 0,  // 空闲（设定回目标值）/ Idle, setpoint at target
    eRun   := 10, // 峰值跟随运行 / Peak tracking running
    eFault := 90  // 组态故障锁定 / Configuration fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_FiringFurnaceZone
VAR_INPUT
    bEnable       : BOOL;                           // 总使能，FALSE 回空闲 / Master enable
    bReset        : BOOL;                           // 复位，上升沿清组态故障 / Reset, clears fault
    fChainSpd     : REAL;                           // 链速 [mm/s]，0 = 停链 / Chain speed [mm/s]
    fKffPctPerSpd : REAL := 0.5;                    // 前馈系数 [% per (mm/s)]，域 > 0 / Feedforward gain [% per mm/s]
    fFfLimPct     : REAL := 15.0;                   // 前馈重置量限幅 [%]，域 > 0 / Feedforward reset limit [%]
    aZoneTgtC     : ARRAY[1..4] OF REAL;            // 各温区目标峰值温度 [°C] / Zone target peak temperature [degC]
    aZoneActC     : ARRAY[1..4] OF REAL;            // 各温区实测温度 [°C] / Zone measured temperature [degC]
    nZoneCount    : INT := 4;                       // 温区数 [区]，1..4 / Zone count
    fPeakWinK     : REAL := 5.0;                    // 峰值窗半宽 [K]，域 > 0 / Peak window half width [K]
    uPeakConfirm  : UINT := 8;                      // 峰值合格确认拍数 [拍] / Peak confirm scans
    fEps          : REAL := 1.0E-6;                 // 浮点判零容差 [1] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    afZoneSpC     : ARRAY[1..4] OF REAL;            // 各温区设定输出 [°C]（目标 + 前馈折算）/ Zone setpoint output [degC]
    abZoneOk      : ARRAY[1..4] OF BOOL;            // 各温区峰值合格（多拍确认）/ Zone peak in-window confirmed
    fFfResetPct   : REAL;                           // 前馈重置量输出 [%]，已限幅 / Feedforward reset output [%]
    bHold         : BOOL;                           // 链速为 0 保持标志 / Zero-speed hold flag
    bError        : BOOL;                           // 故障标志，与故障级码配对 / Fault flag
    uErrorId      : UDINT;                          // 事件码，0 = 无事件 / Event code
    eStateOut     : E_DL_FfzPhase;                  // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState       : E_DL_FfzPhase := E_DL_FfzPhase.eIdle;  // 内部状态 / Internal state
    rtrReset      : R_TRIG;                         // 复位沿 / Reset edge
    abZoneValid   : ARRAY[1..4] OF BOOL;            // 温区有效掩码 / Zone validity mask
    abZoneInWin   : ARRAY[1..4] OF BOOL;            // 温区本拍在窗 / Zone in-window this scan
    auConfirmCnt  : ARRAY[1..4] OF UINT;            // 温区合格确认计数 [拍] / Zone confirm counters
    bCfgOk        : BOOL;                           // 组态合法标志 / Configuration valid
    bSpdOk        : BOOL;                           // 链速本拍有效（非有限/负拒绝）/ Chain speed valid
    fChainEff     : REAL;                           // 生效链速 [mm/s]（0 速保持末次有效）/ Effective chain speed [mm/s]
    fFfRawPct     : REAL;                           // 前馈折算原始量 [%] / Raw feedforward [%]
    nZ            : INT;                            // 温区遍历索引 / Zone loop index
    uFault        : UDINT;                          // 锁存故障码 / Latched fault code
    uInfo         : UDINT;                          // 信息级码 / Information code
END_VAR
VAR CONSTANT
    DL_FFZ_ZMAX   : INT := 4;                       // 温区数上限 [区] / Zone count upper bound
    DL_FFZ_INFMAX : REAL := 1.0E30;                 // 温度/速度有限值幅值上限 / Finite magnitude bound
END_VAR

(* === 段 0 · 实例刷新 === *)
rtrReset(CLK := bReset);                          // 每拍刷新复位沿

(* === 段 1 · 组态闸 === *)
bCfgOk := (nZoneCount >= 1) AND (nZoneCount <= DL_FFZ_ZMAX)    // 温区数域闸
          AND (fKffPctPerSpd > fEps) AND (fFfLimPct > fEps)    // 前馈系数与限幅正域
          AND (fPeakWinK > fEps) AND (uPeakConfirm >= UINT#1)  // 窗半宽与确认拍数下限
          AND (fKffPctPerSpd = fKffPctPerSpd);                 // NaN 自反
FOR nZ := 1 TO DL_FFZ_ZMAX DO
    bCfgOk := bCfgOk AND (aZoneTgtC[nZ] = aZoneTgtC[nZ])       // 目标 NaN 自反
              AND (ABS(aZoneTgtC[nZ]) < DL_FFZ_INFMAX);        // 目标幅值域
END_FOR
IF NOT bCfgOk THEN
    uFault := 16#0002_06C7;                       // 故障级：组态非法
END_IF
IF rtrReset.Q AND bCfgOk THEN
    uFault := 16#0000;                            // 复位沿清锁存（解除路径可达）
    FOR nZ := 1 TO DL_FFZ_ZMAX DO
        auConfirmCnt[nZ] := UINT#0;               // 确认计数复位
    END_FOR
END_IF
uInfo := 16#0000;                                 // 信息码每拍清零

(* === 段 2 · 链速域闸与 0 速保持（禁外推）=== *)
bSpdOk := (fChainSpd = fChainSpd) AND (fChainSpd >= 0.0) AND (fChainSpd < DL_FFZ_INFMAX);  // 链速 NaN 自反 + 非负域
IF bSpdOk AND (fChainSpd > fEps) THEN
    fChainEff := fChainSpd;                       // 有效链速直通
    bHold := FALSE;                               // 保持解除（路径可达）
ELSIF bSpdOk AND (fChainSpd <= fEps) THEN
    bHold := TRUE;                                // 0 速：保持末次有效链速并置 bHold（禁外推）
    uInfo := 16#0002_06B7;                        // 信息级：链速为 0 保持
ELSE
    bHold := TRUE;                                // 链速无效同样保持（不更新生效值）
    uInfo := 16#0002_06B7;                        // 信息级：链速无效保持
END_IF

(* === 段 3 · 前馈折算与限幅（量纲配比：[%/mm每s] × [mm/s] → [%]，头注释写死）=== *)
fFfRawPct := fKffPctPerSpd * fChainEff;           // 前馈重置量 = 系数 × 生效链速 [%]
IF fFfRawPct > fFfLimPct THEN
    fFfRawPct := fFfLimPct;                       // 重置量上限限幅（防阶跃）
END_IF
IF fFfRawPct < -fFfLimPct THEN
    fFfRawPct := -fFfLimPct;                      // 重置量下限限幅
END_IF
fFfResetPct := fFfRawPct;                         // 前馈重置量输出

(* === 段 4 · 逐温区设定与峰值窗多拍确认 === *)
FOR nZ := 1 TO DL_FFZ_ZMAX DO
    abZoneValid[nZ] := (nZ <= nZoneCount)
                       AND (aZoneActC[nZ] = aZoneActC[nZ])
                       AND (ABS(aZoneActC[nZ]) < DL_FFZ_INFMAX);  // NaN 自反 + 幅值闸
    abZoneOk[nZ] := FALSE;                        // 合格标志先清（多拍确认后重置）
    IF nZ <= nZoneCount THEN
        afZoneSpC[nZ] := aZoneTgtC[nZ] + fFfRawPct;   // 区设定 = 目标 + 前馈折算
    ELSE
        afZoneSpC[nZ] := 0.0;                     // 超组态区设定回零
    END_IF
    IF abZoneValid[nZ] THEN
        abZoneInWin[nZ] := ABS(aZoneActC[nZ] - aZoneTgtC[nZ]) <= fPeakWinK + fEps;  // 本拍在窗（对目标判定）
        IF abZoneInWin[nZ] THEN
            IF auConfirmCnt[nZ] < uPeakConfirm THEN
                auConfirmCnt[nZ] := auConfirmCnt[nZ] + UINT#1;  // 确认计数累加
            END_IF
            abZoneOk[nZ] := auConfirmCnt[nZ] >= uPeakConfirm;   // 连续 N 拍在窗才合格
        ELSE
            auConfirmCnt[nZ] := UINT#0;           // 出窗计数归零重计
        END_IF
    ELSE
        auConfirmCnt[nZ] := UINT#0;               // 无效区计数归零（判定冻结，不塞伪值）
        IF nZ <= nZoneCount THEN
            uInfo := 16#0002_06B7;                // 信息级：温区无效判定冻结
        END_IF
    END_IF
END_FOR

(* === 段 5 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_FfzPhase.eIdle :
    IF uFault <> 16#0000 THEN
        _eState := E_DL_FfzPhase.eFault;          // 故障优先
    ELSIF bEnable AND bCfgOk THEN
        _eState := E_DL_FfzPhase.eRun;            // 进运行相
    END_IF

E_DL_FfzPhase.eRun :
    IF (uFault <> 16#0000) OR (NOT bEnable) THEN
        _eState := E_DL_FfzPhase.eFault;          // 故障/失能转出
    END_IF

E_DL_FfzPhase.eFault :
    IF uFault = 16#0000 THEN
        _eState := E_DL_FfzPhase.eIdle;           // 解锁回空闲
    END_IF

ELSE
    _eState := E_DL_FfzPhase.eFault;              // 非法状态拦截
    uFault := 16#0002_06D7;                       // 故障级：相 ID 越界
END_CASE

(* === 段 6 · 输出映射 === *)
bError := (uFault <> 16#0000);                    // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                           // 故障级优先上报
ELSE
    uErrorId := uInfo;                            // 否则上报信息级码
END_IF
eStateOut := _eState;                             // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
