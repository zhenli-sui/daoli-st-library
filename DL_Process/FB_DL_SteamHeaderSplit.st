(*
  FB_DL_SteamHeaderSplit  —  蒸汽母管多支路分程分配 / Steam header multi-branch split-range allocation
  分类 Category : DL_Process
  码位 Code     : 16#06_0_93
  版本 Version  : 1.0.0
  溯源 Source   : ModPID 分程控制语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码
  功能 Function : 1) 母管压力偏差折算总需水率（P 调节口径），按支路优先级顺序分配到各支路阀位输出域；
                  2) 每支路一个 FB_DL_SplitRangeControl 实例承载本支路输出域映射（复用多实例）；
                  3) 逐支路阀位输出钳到本支路行程域。
  边界 Boundary : ① 支路数为 0 拒运行（组态闸）；
                  ② 优先级重复出厂报码（分配顺序不可定即拒算）；
                  ③ 母管压力无效时全支路回安全位（输出域下限）并冻结；
                  ④ 分程区间必须无缝覆盖且不重叠（重叠/空洞出厂报码）；
                  ⑤ 输出三行同向：总需求 → 逐支路阀位 → 分配完成标志。
  依赖 Depends  : FB_DL_SplitRangeControl × 4（逐支路输出域映射，每拍无条件调用）

  码表 Error codes（本件子码步进 16#30 · 本格 93 与既有 9X 子码段冲突，错位至 C3/D3 避让）:
    16#0002_06C3 故障级：组态非法（支路数越界 / 优先级重复 / 分程区间重叠或空洞 / 压力设定 <= 0）
    16#0002_06D3 故障级：相 ID 越界（枚举兜底路径）
    16#0002_06B3 信息级：母管压力无效全支路回安全位冻结（不置 bError）
*)

TYPE E_DL_ShsPhase :
(
    eIdle    := 0,   // 空闲（全支路安全位）/ Idle, all branches at safe position
    eSplit   := 10,  // 分程分配中 / Split allocation running
    eFrozen  := 20,  // 压力无效冻结 / Frozen by invalid header pressure
    eFault   := 90   // 组态故障锁定 / Configuration fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_SteamHeaderSplit
VAR_INPUT
    bEnable       : BOOL;                           // 总使能，FALSE 全支路安全位 / Master enable
    bReset        : BOOL;                           // 复位，上升沿清组态故障 / Reset, clears configuration fault
    fHeaderMPa    : REAL;                           // 母管压力实测 [MPa] / Header pressure [MPa]
    fSetMPa       : REAL := 1.0;                    // 母管压力设定 [MPa]，域 > 0 / Header pressure setpoint [MPa]
    fKpPerMPa     : REAL := 100.0;                  // 压力-需求增益 [%/MPa]，域 > 0 / Pressure-to-demand gain [%/MPa]
    nBranchCount  : INT := 3;                       // 支路数 [路]，1..4 / Branch count
    aPriority     : ARRAY[1..4] OF USINT;           // 支路优先级 [1 = 最先分配] / Branch priority, 1 = first
    aDomainLo     : ARRAY[1..4] OF REAL;            // 支路阀位输出域下限 [%] / Branch output domain low [%]
    aDomainHi     : ARRAY[1..4] OF REAL;            // 支路阀位输出域上限 [%] / Branch output domain high [%]
    fSafePosPct   : REAL := 0.0;                    // 安全位阀位 [%] / Safe position [%]
    fEps          : REAL := 1.0E-6;                 // 浮点判零容差 [1] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    afValvePct    : ARRAY[1..4] OF REAL;            // 逐支路分程阀位 [%] / Per-branch split valve position [%]
    bAllocDone    : BOOL;                           // 本拍分配完成标志 / Allocation done this scan
    bFrozen       : BOOL;                           // 压力无效冻结标志 / Frozen by invalid pressure
    bError        : BOOL;                           // 故障标志，与故障级码配对 / Fault flag
    uErrorId      : UDINT;                          // 事件码，0 = 无事件 / Event code
    eStateOut     : E_DL_ShsPhase;                  // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState       : E_DL_ShsPhase := E_DL_ShsPhase.eIdle;  // 内部状态 / Internal state
    afbSplit      : ARRAY[1..4] OF FB_DL_SplitRangeControl;  // 逐支路分程实例（无条件调用）/ Per-branch split-range instance
    rtrReset      : R_TRIG;                         // 复位沿 / Reset edge
    bCfgOk        : BOOL;                           // 组态合法标志 / Configuration valid
    bHdrOk        : BOOL;                           // 母管压力本拍有效 / Header pressure valid
    fDemand       : REAL;                           // 总需求 [%] 0..100 / Total demand [%]
    fRemain       : REAL;                           // 剩余需求 [%] / Remaining demand [%]
    bAllocated    : ARRAY[1..4] OF BOOL;            // 支路已分配掩码 / Branch allocated mask
    afCtrl        : ARRAY[1..4] OF REAL;            // 逐支路需求输入 [%] / Per-branch demand input [%]
    afSpan        : ARRAY[1..4] OF REAL;            // 逐支路域跨度 [%] / Per-branch domain span [%]
    nRank         : USINT;                          // 当前分配序位 / Current allocation rank
    nB            : INT;                            // 支路遍历索引 / Branch loop index
    nFound        : INT;                            // 序位命中支路号 / Branch hit at rank
    uPrioSeen     : ARRAY[1..4] OF USINT;           // 优先级查重表 / Priority duplicate table
    uFault        : UDINT;                          // 锁存故障码 / Latched fault code
    uInfo         : UDINT;                          // 信息级码 / Information code
END_VAR
VAR CONSTANT
    DL_SHS_BMAX   : INT := 4;                       // 支路数上限 [路] / Branch count upper bound
    DL_SHS_INFMAX : REAL := 1.0E30;                 // 压力有限值幅值上限 [MPa] / Pressure finite bound [MPa]
END_VAR

(* === 段 0 · 实例刷新 === *)
rtrReset(CLK := bReset);                          // 每拍刷新复位沿

(* === 段 1 · 组态闸（支路数 / 优先级查重 / 分程区间覆盖性）=== *)
bCfgOk := (nBranchCount >= 1) AND (nBranchCount <= DL_SHS_BMAX)   // 支路数域闸（0 拒运行）
          AND (fSetMPa > fEps) AND (fKpPerMPa > fEps)              // 设定与增益正域
          AND (fSetMPa = fSetMPa) AND (fKpPerMPa = fKpPerMPa);     // NaN 自反
FOR nB := 1 TO DL_SHS_BMAX DO
    uPrioSeen[nB] := 0;                           // 查重表清零
END_FOR
FOR nB := 1 TO nBranchCount DO
    IF (aPriority[nB] >= USINT#1) AND (aPriority[nB] <= USINT#4) THEN
        uPrioSeen[aPriority[nB]] := uPrioSeen[aPriority[nB]] + USINT#1;   // 优先级出现计数（越界优先级按重复计）
    ELSE
        bCfgOk := FALSE;                          // 优先级越域：组态非法
    END_IF
    bCfgOk := bCfgOk AND (aDomainHi[nB] > aDomainLo[nB] + fEps)   // 单支路域不倒置
              AND (aDomainLo[nB] = aDomainLo[nB]) AND (aDomainHi[nB] = aDomainHi[nB]);  // NaN 自反
END_FOR
FOR nB := 1 TO nBranchCount DO
    bCfgOk := bCfgOk AND (uPrioSeen[nB] = USINT#1);   // 每个序位恰好一次（重复/缺位均非法）
END_FOR
FOR nB := 2 TO nBranchCount DO
    bCfgOk := bCfgOk AND (ABS(aDomainLo[nB] - aDomainHi[nB - 1]) < 1.0E-3);  // 相邻域无缝覆盖（容差内贴接）
END_FOR
IF NOT bCfgOk THEN
    uFault := 16#0002_06C3;                       // 故障级：组态非法（含优先级重复与区间重叠/空洞）
END_IF
IF rtrReset.Q AND bCfgOk THEN
    uFault := 16#0000;                            // 复位沿清锁存（解除路径可达）
END_IF
uInfo := 16#0000;                                 // 信息码每拍清零
bHdrOk := (fHeaderMPa = fHeaderMPa) AND (fHeaderMPa >= 0.0) AND (fHeaderMPa < DL_SHS_INFMAX);  // 压力域闸

(* === 段 2 · 总需求折算与按序位残余分配（本拍重算）=== *)
bAllocDone := FALSE;                              // 分配完成本拍重算
fDemand := 0.0;                                   // 需求缺省 0（安全位口径）
FOR nB := 1 TO DL_SHS_BMAX DO
    afCtrl[nB] := 0.0;                            // 支路需求输入清零（安全位口径）
    afSpan[nB] := 0.0;                            // 跨度缺省 0
END_FOR
IF bCfgOk AND bHdrOk AND bEnable THEN
    fDemand := (fSetMPa - fHeaderMPa) * fKpPerMPa;  // 偏差折算需求 [%]（压力低 → 需求大）
    IF fDemand > 100.0 THEN
        fDemand := 100.0;                         // 需求上限钳位
    END_IF
    IF fDemand < 0.0 THEN
        fDemand := 0.0;                           // 需求下限钳位
    END_IF
    fRemain := fDemand;                           // 剩余需求起值
    FOR nRank := 1 TO USINT#4 DO                  // 按优先级序位 1..4 顺序分配（残余递减）
        nFound := 0;                              // 序位命中支路清零
        FOR nB := 1 TO nBranchCount DO
            IF (aPriority[nB] = nRank) AND (nFound = 0) THEN
                nFound := nB;                     // 找到本序位支路
            END_IF
        END_FOR
        bAllocated[nRank] := FALSE;               // 分配掩码先清
        IF nFound > 0 THEN
            bAllocated[nRank] := TRUE;            // 本序位已分配
            afSpan[nFound] := aDomainHi[nFound] - aDomainLo[nFound];   // 本支路域跨度 [%]
            afCtrl[nFound] := fRemain;            // 需求输入 = 当前残余（段 3 内按跨度钳位消化）
            IF fRemain > afSpan[nFound] THEN
                fRemain := fRemain - afSpan[nFound];   // 本支路域已耗尽：残余递减传下序位
            ELSE
                fRemain := 0.0;                   // 残余被本支路消化完
            END_IF
        END_IF
    END_FOR
    bAllocDone := TRUE;                           // 分配完成
ELSIF bCfgOk AND ((NOT bHdrOk) OR (NOT bEnable)) THEN
    uInfo := 16#0002_06B3;                        // 信息级：压力无效/失能全支路安全位冻结
END_IF

(* === 段 3 · 逐支路分程实例（无条件调用）与输出域钳位 === *)
FOR nB := 1 TO DL_SHS_BMAX DO
    afbSplit[nB](bEnable := bCfgOk AND bHdrOk AND bEnable AND bAllocated[nB],   // 本支路参与分配
                 fCtrlIn := afCtrl[nB],             // 本支路需求输入
                 fGap := 0.0,                       // 支路间无中央死区（无缝覆盖组态）
                 rCtrlMax := MAX(afSpan[nB], fEps), // 满量程 = 本支路域跨度（分母防零）
                 rOutHeatMin := aDomainLo[nB],      // 本支路域下限（映射到热通道）
                 rOutHeatMax := aDomainHi[nB],      // 本支路域上限
                 rOutCoolMin := aDomainLo[nB],      // 冷通道复用同域（单通道口径）
                 rOutCoolMax := aDomainHi[nB]);     // 实例每拍无条件调用
    IF bCfgOk AND bHdrOk AND bEnable AND (nB <= nBranchCount) AND afbSplit[nB].bHeatActive THEN
        afValvePct[nB] := afbSplit[nB].fOutHeat;  // 分配中：跟随实例输出
    ELSE
        afValvePct[nB] := fSafePosPct;            // 未参与/冻结/失能：安全位
    END_IF
    IF afValvePct[nB] > aDomainHi[nB] THEN
        afValvePct[nB] := aDomainHi[nB];          // 输出钳到本支路域上限
    END_IF
    IF afValvePct[nB] < aDomainLo[nB] THEN
        afValvePct[nB] := aDomainLo[nB];          // 输出钳到本支路域下限
    END_IF
END_FOR

(* === 段 4 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_ShsPhase.eIdle :
    IF uFault <> 16#0000 THEN
        _eState := E_DL_ShsPhase.eFault;          // 故障优先
    ELSIF bEnable AND bCfgOk AND (NOT bHdrOk) THEN
        _eState := E_DL_ShsPhase.eFrozen;         // 压力无效进冻结
    ELSIF bEnable AND bCfgOk AND bHdrOk THEN
        _eState := E_DL_ShsPhase.eSplit;          // 进分程相
    END_IF

E_DL_ShsPhase.eSplit :
    IF (uFault <> 16#0000) OR (NOT bEnable) THEN
        _eState := E_DL_ShsPhase.eFault;          // 故障/失能转出
    ELSIF NOT bHdrOk THEN
        _eState := E_DL_ShsPhase.eFrozen;         // 压力无效转冻结
    END_IF

E_DL_ShsPhase.eFrozen :
    IF bHdrOk AND bEnable AND (uFault = 16#0000) THEN
        _eState := E_DL_ShsPhase.eSplit;          // 压力恢复回分程（解除路径可达）
    END_IF

E_DL_ShsPhase.eFault :
    IF uFault = 16#0000 THEN
        _eState := E_DL_ShsPhase.eIdle;           // 解锁回空闲
    END_IF

ELSE
    _eState := E_DL_ShsPhase.eFault;              // 非法状态拦截
    uFault := 16#0002_06D3;                       // 故障级：相 ID 越界
END_CASE
bFrozen := (_eState = E_DL_ShsPhase.eFrozen) OR (_eState = E_DL_ShsPhase.eFault);  // 冻结标志段尾单点映射

(* === 段 5 · 输出映射 === *)
bError := (uFault <> 16#0000);                    // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                           // 故障级优先上报
ELSE
    uErrorId := uInfo;                            // 否则上报信息级码
END_IF
eStateOut := _eState;                             // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
