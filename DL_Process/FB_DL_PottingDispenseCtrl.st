(*
  FB_DL_PottingDispenseCtrl  —  接线盒灌胶定量控制 / Junction-box potting dispense control
  分类 Category : DL_Process
  码位 Code     : 16#06_0_8F
  版本 Version  : 1.0.0
  溯源 Source   : LBP（Lediberg Process Library）语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码
  功能 Function : 1) 称重减量法计量：灌注前后称重差折算实际灌注重量；
                  2) 双组份 A/B 混合比闭环：按设定比例分配比例输出，偏差超窗先停 A 侧（安全侧）；
                  3) 目标重量到达 + 去抖确认后置 bDoseDone（禁单拍判完成）。
  边界 Boundary : ① 称重非有限或 < 0 判 NE43 无效：冻结计量并禁止泵使能；
                  ② 混合比偏差窗上下限倒置出厂报码不运行；
                  ③ 灌注中称重回升（回流/抖动）需连续 N 拍去抖确认才判完成；
                  ④ 目标重量 <= 0 拒启动并置码；
                  ⑤ 输出三行同向：泵使能 → 比例输出 → 完成标志。
  依赖 Depends  : 无实例依赖（称重去抖自实现，避免跨件调用首拍跟踪债）

  码表 Error codes（本件子码步进 16#10，避让邻件码位）:
    16#0002_068F 故障级：组态非法（目标重量 <= 0 / 比例 <= 0 / 偏差窗倒置 / 去抖拍数 < 1）
    16#0002_069F 故障级：混合比偏差持续超窗已停 A 侧（锁存需复位）
    16#0002_06AF 信息级：称重无效计量冻结 / 目标已到去抖确认中（不置 bError）
*)

TYPE E_DL_PdcPhase :
(
    eIdle    := 0,   // 空闲待启动 / Idle
    eDose    := 10,  // 灌注计量中 / Dispensing
    eConfirm := 20,  // 目标到达去抖确认 / Target-reached debounce confirm
    eDone    := 30,  // 计量完成 / Dose done
    eFrozen  := 40,  // 称重无效冻结 / Frozen by invalid scale
    eFault   := 90   // 故障锁定 / Fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_PottingDispenseCtrl
VAR_INPUT
    bStart        : BOOL;                           // 启动指令，上升沿生效 / Dose start, edge
    bAbort        : BOOL;                           // 中止指令，电平生效回空闲 / Abort, level
    bReset        : BOOL;                           // 复位，上升沿清故障 / Reset, clears fault
    fTargetG      : REAL := 120.0;                  // 目标灌注重量 [g]，域 > 0 / Target dose weight [g]
    fWeightAG     : REAL;                           // A 组份称重读数 [g] / Component A scale reading [g]
    fWeightBG     : REAL;                           // B 组份称重读数 [g] / Component B scale reading [g]
    fWeightStartG : REAL;                           // 灌注前称重基准 [g]（启动拍锁存）/ Pre-dose tare snapshot [g]
    fMixRatio     : REAL := 2.0;                    // A:B 混合比设定 [1]，A 份额 / Mix ratio A share [1]
    fRatioTolHi   : REAL := 10.0;                   // 比例偏差窗上限 [%]，域 > 0 / Ratio deviation window high [%]
    fRatioTolLo   : REAL := 10.0;                   // 比例偏差窗下限 [%]，域 >= 0 / Ratio deviation window low [%]
    uConfirmScans : UINT := 5;                      // 完成去抖确认拍数 [拍] / Done debounce confirm scans
    fEps          : REAL := 1.0E-6;                 // 浮点判零容差 [1] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    bPumpEnable   : BOOL;                           // 计量泵使能出口 / Metering pump enable output
    fRatioOutA    : REAL;                           // A 侧比例输出 [0..1] / Component A ratio output [0..1]
    fRatioOutB    : REAL;                           // B 侧比例输出 [0..1] / Component B ratio output [0..1]
    bDoseDone     : BOOL;                           // 计量完成标志（保持型）/ Dose done flag, held
    fDosedG       : REAL;                           // 实际灌注重量 [g] = 基准 − 当前 / Actual dosed weight [g]
    bError        : BOOL;                           // 故障标志，与故障级码配对 / Fault flag
    uErrorId      : UDINT;                          // 事件码，0 = 无事件 / Event code
    eStateOut     : E_DL_PdcPhase;                  // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState       : E_DL_PdcPhase := E_DL_PdcPhase.eIdle;  // 内部状态 / Internal state
    rtrStart      : R_TRIG;                         // 启动沿 / Start edge
    rtrReset      : R_TRIG;                         // 复位沿 / Reset edge
    bCfgOk        : BOOL;                           // 组态合法标志 / Configuration valid
    bScaleOkA     : BOOL;                           // A 称重本拍有效 / Scale A valid this scan
    bScaleOkB     : BOOL;                           // B 称重本拍有效 / Scale B valid this scan
    bScaleOk      : BOOL;                           // 双路称重综合有效 / Both scales valid
    fDoseAG       : REAL;                           // A 侧减量计量 [g] / A-side loss-in-weight [g]
    fDoseBG       : REAL;                           // B 侧减量计量 [g] / B-side loss-in-weight [g]
    fRatioAct     : REAL;                           // 实际混合比 [1] / Actual mix ratio [1]
    fRatioDevPct  : REAL;                           // 比例偏差 [%] / Ratio deviation [%]
    bRatioOut     : BOOL;                           // 比例超窗（电平）/ Ratio out of window
    uConfirmCnt   : UINT;                           // 完成去抖计数 [拍] / Done debounce counter
    uFault        : UDINT;                          // 锁存故障码 / Latched fault code
    uInfo         : UDINT;                          // 信息级码 / Information code
END_VAR
VAR CONSTANT
    DL_PDC_INFMAX : REAL := 1.0E30;                 // 称重有限值幅值上限 [g] / Scale finite bound [g]
END_VAR

(* === 段 0 · 实例刷新 === *)
rtrStart(CLK := bStart);                          // 每拍刷新启动沿
rtrReset(CLK := bReset);                          // 每拍刷新复位沿

(* === 段 1 · 组态闸与称重域闸 === *)
bCfgOk := (fTargetG > fEps)                       // 目标重量正域（<= 0 拒启动）
          AND (fMixRatio > fEps)                  // 比例正域
          AND (fRatioTolHi > fEps) AND (fRatioTolLo >= 0.0)   // 偏差窗不倒置且上限为正
          AND (uConfirmScans >= UINT#1)           // 去抖拍数下限
          AND (fTargetG = fTargetG) AND (fMixRatio = fMixRatio);  // NaN 自反
IF NOT bCfgOk THEN
    uFault := 16#0002_068F;                       // 故障级：组态非法
END_IF
IF rtrReset.Q AND bCfgOk THEN
    uFault := 16#0000;                            // 复位沿清锁存（解除路径可达）
END_IF
uInfo := 16#0000;                                 // 信息码每拍清零
bScaleOkA := (fWeightAG = fWeightAG) AND (fWeightAG >= 0.0) AND (fWeightAG < DL_PDC_INFMAX);  // A 路域闸
bScaleOkB := (fWeightBG = fWeightBG) AND (fWeightBG >= 0.0) AND (fWeightBG < DL_PDC_INFMAX);  // B 路域闸
bScaleOk := bScaleOkA AND bScaleOkB;              // 双路综合有效
fDosedG := 0.0;                                   // 计量值本拍重算
IF bScaleOk AND (_eState <> E_DL_PdcPhase.eIdle) THEN
    fDoseAG := fWeightStartG - fWeightAG;         // A 侧减量（基准 − 当前，回升为负）
    fDoseBG := fWeightStartG - fWeightBG;         // B 侧减量
    IF fDoseAG < 0.0 THEN
        fDoseAG := 0.0;                           // 称重回升不外推负计量（去抖确认承担）
    END_IF
    IF fDoseBG < 0.0 THEN
        fDoseBG := 0.0;                           // 同上 B 侧
    END_IF
    fDosedG := fDoseAG + fDoseBG;                 // 实际灌注 = 双侧减量和
END_IF

(* === 段 2 · 混合比闭环判据（本拍重算）=== *)
fRatioAct := 1.0;                                 // 实际比缺省 1（防除零哨兵）
fRatioDevPct := 0.0;                              // 偏差缺省 0
bRatioOut := FALSE;                               // 超窗标志本拍重算
IF bScaleOk AND (fDoseBG > fEps) THEN
    fRatioAct := fDoseAG / fDoseBG;               // A/B 实际比（分母已判零）
    fRatioDevPct := ABS(fRatioAct - fMixRatio) / fMixRatio * 100.0;   // 相对偏差 [%]（分母组态闸已保证 > 0）
    bRatioOut := (fRatioDevPct > fRatioTolHi + fEps) OR (fRatioDevPct < -fRatioTolLo - fEps);  // 超窗判定
END_IF

(* === 段 3 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_PdcPhase.eIdle :
    bPumpEnable := FALSE;                         // 空闲泵停
    fRatioOutA := 0.0;                            // 比例输出清零
    fRatioOutB := 0.0;
    IF uFault <> 16#0000 THEN
        _eState := E_DL_PdcPhase.eFault;          // 故障优先
    ELSIF NOT bScaleOk THEN
        _eState := E_DL_PdcPhase.eFrozen;         // 称重无效进冻结
    ELSIF rtrStart.Q AND bCfgOk THEN
        _eState := E_DL_PdcPhase.eDose;           // 启动沿进灌注相
    END_IF

E_DL_PdcPhase.eDose :
    bPumpEnable := bScaleOk AND (uFault = 16#0000);   // 称重无效/故障即停泵（安全侧）
    fRatioOutA := fMixRatio / (fMixRatio + 1.0);  // A 份额按设定比分配（分母 > 0 组态闸保证）
    fRatioOutB := 1.0 - fRatioOutA;               // B 份额互补
    IF bRatioOut THEN
        fRatioOutA := 0.0;                        // 比例超窗先停 A 侧（安全侧）
        uFault := 16#0002_069F;                   // 故障级：混合比偏差持续超窗停 A 侧（锁存）
        _eState := E_DL_PdcPhase.eFault;          // 转故障相
    ELSIF NOT bScaleOk THEN
        uInfo := 16#0002_06AF;                    // 信息级：称重无效计量冻结
        _eState := E_DL_PdcPhase.eFrozen;         // 转冻结相
    ELSIF bAbort THEN
        _eState := E_DL_PdcPhase.eIdle;           // 中止回空闲
    ELSIF fDosedG >= fTargetG THEN
        uInfo := 16#0002_06AF;                    // 信息级：目标已到去抖确认中
        uConfirmCnt := UINT#0;                    // 确认计数从 0 起算
        _eState := E_DL_PdcPhase.eConfirm;        // 进确认相（禁单拍判完成）
    END_IF

E_DL_PdcPhase.eConfirm :
    bPumpEnable := FALSE;                         // 确认相泵已停（目标到即停）
    IF bScaleOk AND (fDosedG >= fTargetG - fEps) THEN
        uConfirmCnt := uConfirmCnt + UINT#1;      // 稳定保持计数累加
        IF uConfirmCnt >= uConfirmScans THEN
            bDoseDone := TRUE;                    // 连续 N 拍稳定在目标域：完成
            _eState := E_DL_PdcPhase.eDone;       // 转完成相
        END_IF
    ELSE
        uConfirmCnt := UINT#0;                    // 回落：计数清零重计
        IF bScaleOk THEN
            _eState := E_DL_PdcPhase.eDose;       // 未达稳态回灌注相（欠量补灌）
        ELSE
            _eState := E_DL_PdcPhase.eFrozen;     // 称重丢失转冻结
        END_IF
    END_IF

E_DL_PdcPhase.eDone :
    bPumpEnable := FALSE;                         // 完成相泵停
    bDoseDone := TRUE;                            // 完成保持（防同拍抹除）
    IF rtrStart.Q AND bScaleOk THEN
        bDoseDone := FALSE;                       // 新启动沿重开计量
        _eState := E_DL_PdcPhase.eDose;           // 回灌注相
    ELSIF NOT bScaleOk THEN
        _eState := E_DL_PdcPhase.eFrozen;         // 称重丢失转冻结（完成标志保持）
    END_IF

E_DL_PdcPhase.eFrozen :
    bPumpEnable := FALSE;                         // 冻结相禁泵使能（计量冻结）
    IF bScaleOk AND (uFault = 16#0000) THEN
        _eState := E_DL_PdcPhase.eDose;           // 称重恢复回灌注（解除路径可达，欠量续灌）
    END_IF

E_DL_PdcPhase.eFault :
    bPumpEnable := FALSE;                         // 故障相禁泵
    IF uFault = 16#0000 THEN
        _eState := E_DL_PdcPhase.eIdle;           // 解锁回空闲
    END_IF

ELSE
    _eState := E_DL_PdcPhase.eFault;              // 非法状态拦截
    uFault := 16#0002_068F;                       // 故障级：相 ID 越界复用组态码段
END_CASE

(* === 段 4 · 输出映射 === *)
bError := (uFault <> 16#0000);                    // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                           // 故障级优先上报
ELSE
    uErrorId := uInfo;                            // 否则上报信息级码
END_IF
eStateOut := _eState;                             // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
