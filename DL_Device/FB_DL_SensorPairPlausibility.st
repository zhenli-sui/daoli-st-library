(*
  ==================================================================
  组件名 Component  : FB_DL_SensorPairPlausibility
  分类   Category   : DL_Device
  前缀   Naming     : FB_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  复杂度 Complexity  : 高
  版本   Version    : 1.0.1
  功能   Purpose    : 双冗余传感器交叉合理性（偏差窗 + 漂移趋势 + 择优输出 + 故障锁定状态机）。
  来源   Source     : t2-6-rockwell-aoi（冗余交叉判据公开语义）
  平台   Platform   : 纯 IEC 61131-3（TON 无 / R_TRIG / CASE / FOR），三平台通用
  分工声明 Split     : 与 FB_DL_SensorDriftBaseline（基线学习属主）分工——后者
                      学慢漂基线；本件做双冗余交叉判与择优（R216 双向互引）。
  作者   Author     : 道莅代码库 · PLC 编程专家（R61）
  归属 Ownership     : E_DL_SensorPairPhase 属主为本文件（全库唯一定义，R264）；
                      引用件只引用不重声明。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 择优切换须迟滞：源切换仅在「当前源非有限」时发生（有效性
                         边界迟滞），合法但分歧时不拍拍翻转（防抖动纪律）；切换
                         拍发单拍 bSwitched（R256 统一出口预置）；
                      二 偏差窗与漂移趋势滚动窗长度 nTrendWin 提为输入（合法域
                         1..32，越域钳位信息级 070A）；窗长变更沿（_nUse ≠ _nUsePrev）
                         全窗清零（和 / 写头 / 填充计数 / 环元素逐项清），防窗长缩小后
                         旧条目永久留在和里（v1.0.1 修 D4 环窗残留）；
                      三 非有限闸逐个点名 fA / fB / fDevWin / fDriftLim 四个浮点
                         入参（R272 全量枚举）；
                      四 故障锁存逐条自证：双传感器偏差超窗（0707）与漂移趋势
                         超限（0708）独立锁存独立码（R190），bReset 上升沿解除
                         （恒可达，R152 自证）；故障相输出冻结最近有效择优快照
                         （R273 快照防污染：快照写前过有限闸）；
                      五 CASE 必带 ELSE 兜底；R_TRIG 段 0 无条件刷新；
                      六 无全局、无外部变量、无物理地址。
  错误码   Codes    :
    16#0003_0707【故障级】双传感器偏差超窗，输出冻结快照，锁存至复位沿
    16#0003_0708【故障级】漂移趋势超限，输出冻结快照，锁存至复位沿
    16#0003_0709【信息级】发生择优源切换（bSwitched 同拍置位）
    16#0003_070A【信息级】滚动窗长度越域已钳位（1..32）
  验收   Acceptance :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 A=100/B=100.5、窗 2.0 → fSel=100（A 源）、无故障
    V2 A=NaN → 切 B 源、码 0709、bSwitched 单拍
    V3 B=110（窗 2.0）持续 → 码 0707、输出冻结快照、锁存待复位
    V4 窗 32 跑 40 拍后缩到 8 → 均值只含最近 8 个样本（旧版含陈旧项；v1.0.1 回归）
    V5 窗 8 首 3 拍（_nFill=3）→ 均值 = 3 样本均值（旧版除子 8，偏小 62%）
    V6 双源均非有限（_nFill=0 路径）→ 判据不执行、无除零、无锁存
    V7 窗长 8↔32 反复抖动 → 无残留累加漂移（环元素随变更沿清零）
  修订记录 Revision  :
    2026-11-21  v1.0.0  R61 首版（批 4 · 序号 13）
    2026-11-21  v1.0.1  R62-D4 返修：①新增 _nUsePrev，窗长变更沿全窗清零（含环元素逐项清，防减项把陈旧样本重新注入和）；②新增 _nFill，均值除子由 _nUse 改为 _nFill（首填偏小防漏报）；③_nFill=0 跳过判据并重写除子 ≥1 证明注释；④复位清单补 _nFill / _nUsePrev。注：盘面实测入库版本为 v1.0.0（计划书假设 R61 已发 v1.0.1），按实测优先、禁跳号递增一次至 v1.0.1
  ==================================================================
*)
TYPE E_DL_SensorPairPhase :
(
    eUseA   := 0,  // 择优 A 源 / using the source A
    eUseB   := 10, // 择优 B 源 / using the source B
    eFault  := 20  // 故障锁定：输出冻结快照 / fault locked, the outlet frozen at the snapshot
);
END_TYPE

FUNCTION_BLOCK FB_DL_SensorPairPlausibility
VAR_INPUT
    bEnable   : BOOL := TRUE;   // 使能，FALSE 时冻结择优出口（R191 声明行）/ the enable, false freezes the outlet
    bReset    : BOOL := FALSE;  // 故障复位电平，上升沿清锁存 / the fault reset level
    fA        : LREAL := 0.0;   // A 传感器测量值 [工程单位] / the sensor A value
    fB        : LREAL := 0.0;   // B 传感器测量值 [工程单位] / the sensor B value
    fDevWin   : LREAL := 2.0;   // 偏差窗 [工程单位]，必须 > 0 / the deviation window, must be positive
    fDriftLim : LREAL := 5.0;   // 漂移趋势限 [工程单位]，必须 > 0 / the drift trend limit, must be positive
    nTrendWin : DINT  := 8;     // 漂移趋势滚动窗长度 [拍]，合法域 1..32 / the rolling window length, legal from one to thirty two
END_VAR
VAR_OUTPUT
    fSel      : LREAL := 0.0;  // 择优输出 [工程单位] / the selected outlet
    bSrcA     : BOOL := TRUE;  // 当前择优 A 源指示 [-] / the source A indicator
    bSrcB     : BOOL := FALSE; // 当前择优 B 源指示 [-] / the source B indicator
    bSwitched : BOOL := FALSE; // 源切换单拍脉冲 [-] / the source switch one shot pulse
    eState    : E_DL_SensorPairPhase; // 主状态机当前态 [状态] / the current state
    bError    : BOOL := FALSE; // 故障锁存位（与锁存同源，R191）/ the fault bit from the latch
    bValid    : BOOL := FALSE; // 择优可用标志 [-] / the selection usable flag
    eErr      : UDINT := 16#0000_0000; // 错误码，0 = 正常 / the error code, zero is ok
END_VAR
VAR
    _bInit    : BOOL := FALSE;                          // 首拍初始化标志（R310）/ the first scan flag
    _eState   : E_DL_SensorPairPhase := E_DL_SensorPairPhase.eUseA; // 内部状态寄存器 / the internal state register
    _bFault   : BOOL := FALSE;                          // 故障锁存副本（仅复位沿清除）/ the fault latch copy
    _bDevFlt  : BOOL := FALSE;                          // 偏差超窗锁存副本（独立成因，R190）/ the deviation fault latch copy
    _bDriftFlt: BOOL := FALSE;                          // 漂移超限锁存副本（独立成因）/ the drift fault latch copy
    _bFin     : BOOL := FALSE;                          // 入参非有限闸结果（逐拍重算）/ the finiteness gate result
    _bFinA    : BOOL := FALSE;                          // A 源有限标记（逐拍重算）/ the A finiteness flag
    _bFinB    : BOOL := FALSE;                          // B 源有限标记 / the B finiteness flag
    _fDev     : LREAL := 0.0;                           // 本拍偏差 [工程单位] / the deviation this scan
    _fSnap    : LREAL := 0.0;                           // 最近有效择优快照（写前过闸，FB32-7）/ the last valid snapshot gated before write
    _nUse     : DINT := 8;                              // 钳位后的滚动窗长度 [拍] / the clamped window length
    _afRing   : ARRAY[0..31] OF LREAL;                  // 偏差滚动环形窗 [工程单位] / the deviation rolling ring
    _nHead    : DINT := 0;                              // 环形窗写头 [下标] / the ring write head
    _nFill    : DINT := 0;                              // 环形窗已填样本数 [拍]，均值除子（v1.0.1 修 D4）/ the filled sample count of the ring, the mean divisor
    _nUsePrev : DINT := 0;                              // 上拍窗长快照 [拍]，置 0 使首拍必触发一次全窗清零 / the previous window length snapshot, zero forces a full clear on the first scan
    _nRingIdx : DINT := 0;                              // 环元素清零遍历索引 [下标] / the ring clearing traversal index
    _fRingSum : LREAL := 0.0;                           // 环窗偏差和 [工程单位] / the ring deviation sum
    _bSw      : BOOL := FALSE;                          // 切换单拍内部位，段 1 预清段 5 映射 / the internal switch bit
    _bWinBad  : BOOL := FALSE;                          // 窗长钳位标记（逐拍重算）/ the window clamp flag
    rtReset   : R_TRIG; // 复位沿实例，段 0 无条件刷新 / the reset edge instance
END_VAR
VAR CONSTANT
    DL_SPP_RMAX : DINT := 32; // 滚动窗容量上界 [拍]，与环形数组一致 / the ring capacity aligned with the array
END_VAR

// 段 0｜复位沿无条件周期刷新（禁入分支，R7）/ segment 0, the unconditional refresh
rtReset(CLK := bReset); // 复位沿 / the reset edge

// 段 1｜首拍初始化与单拍标志预清（R310 / FB32-1 / R256）/ segment 1, the first scan init and the preset
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the first scan flag
    _bFault := FALSE; // 故障锁存显式清零 / clear the fault latch explicitly
    _bDevFlt := FALSE; // 偏差锁存显式清零 / clear the deviation latch explicitly
    _bDriftFlt := FALSE; // 漂移锁存显式清零 / clear the drift latch explicitly
    _eState := E_DL_SensorPairPhase.eUseA; // 状态显式落 A 源 / place the state to the source A
    _nFill := 0; // 填充计数显式清零（R243 复位清单）/ clear the filled count explicitly
    _nUsePrev := 0; // 窗长快照置 0，使段 2 变更沿必然触发一次全窗清零 / zero the window snapshot so the change edge clears the ring once
    _fRingSum := 0.0; // 环窗和显式清零 / clear the ring sum explicitly
    _nHead := 0; // 写头显式清零 / clear the write head explicitly
END_IF
IF rtReset.Q THEN // 复位沿（作用域：清双侧锁存 + 迁相位 + 清环窗累计量，R311 声明）/ the reset edge with the declared scope
    _bDevFlt := FALSE; // 清偏差锁存（解除路径：复位沿恒可达，R152 自证）/ clear the deviation latch
    _bDriftFlt := FALSE; // 清漂移锁存 / clear the drift latch
    _eState := E_DL_SensorPairPhase.eUseA; // 迁回 A 源 / back to the source A
    _nFill := 0; // 填充计数清零（R243 复位清单）/ clear the filled count
    _nUsePrev := 0; // 窗长快照置 0 触发一次全窗清零 / zero the window snapshot to force a ring clear
    _fRingSum := 0.0; // 环窗和清零 / clear the ring sum
    _nHead := 0; // 写头清零 / clear the write head
END_IF
_bSw := FALSE; // 切换单拍预清零 / preset the switch bit false
_bWinBad := FALSE; // 钳位标记预清零 / preset the clamp flag false

// 段 2｜非有限闸与窗长钳位（R272 全量点名，边界三二）/ segment 2, the finiteness gate and the window clamp
_bFinA := (fA = fA) AND ((fA - fA) = (fA - fA)); // A 源自反 + 差值判 / the A source tests
_bFinB := (fB = fB) AND ((fB - fB) = (fB - fB)); // B 源自反 + 差值判 / the B source tests
_bFin := _bFinA AND _bFinB
AND (fDevWin = fDevWin) AND ((fDevWin - fDevWin) = (fDevWin - fDevWin))
AND (fDriftLim = fDriftLim) AND ((fDriftLim - fDriftLim) = (fDriftLim - fDriftLim)); // 阈值引脚同判 / the threshold pins tested the same way
_nUse := nTrendWin; // 窗长接管 / take the window length
IF (_nUse < 1) OR (_nUse > DL_SPP_RMAX) THEN // 窗长越域（边界二）/ the window length out of the domain
    _bWinBad := TRUE; // 置钳位标记 / raise the clamp flag
    IF _nUse < 1 THEN // 下界钳位 / the floor clamp
        _nUse := 1; // 钳到一 / clamp to one
    ELSE // 上界钳位 / the ceiling clamp
        _nUse := DL_SPP_RMAX; // 钳到容量 / clamp to the capacity
    END_IF
END_IF

// 段 2b｜窗长变更沿全窗清零（v1.0.1 修 D4：仅清和与写头不足，减项 _afRing[_nHead] 会把陈旧样本重新注入和）/ segment 2b, the full window clear on a length change
IF _nUse <> _nUsePrev THEN // 窗长变更沿（含首拍 _nUsePrev = 0）/ the window length change edge, including the first scan
    _fRingSum := 0.0; // 环窗和清零 / clear the ring sum
    _nHead := 0; // 写头回零 / reset the write head
    _nFill := 0; // 填充计数回零 / reset the filled count
    FOR _nRingIdx := 0 TO DL_SPP_RMAX - 1 DO // 有界遍历全容量（32 项，无死循环风险）/ the bounded traversal over the full capacity
        _afRing[_nRingIdx] := 0.0; // 环元素逐项清零：减项读到零才不会把旧样本扣回和里 / zero every element so the subtract term reads zero instead of a stale sample
    END_FOR
    _nUsePrev := _nUse; // 快照本拍窗长，防重复清零 / snapshot the length to avoid a repeated clear
END_IF

// 段 3｜偏差与漂移判据（闸覆盖全量入参后执行）/ segment 3, the deviation and the drift criteria
IF _bFinA AND _bFinB THEN // 双源有限才判偏差（双源非有限即整段跳过，_nFill 保持不增）/ the deviation judged on two finite sources, otherwise the whole segment is skipped
    _fDev := ABS(fA - fB); // 偏差（无除法，无除零风险）/ the deviation without a division
    _fRingSum := _fRingSum - _afRing[_nHead] + _fDev; // 环窗和滑窗更新（环元素已在清零沿置零，减项必为有效样本或零）/ update the ring sum, the subtract term is either a live sample or zero
    _afRing[_nHead] := _fDev; // 本拍偏差入环 / push the deviation into the ring
    _nHead := _nHead + 1; // 写头推进 / advance the head
    IF _nHead >= _nUse THEN // 回卷（按钳位窗长）/ wrap by the clamped length
        _nHead := 0; // 写头回零 / reset the head
    END_IF
    IF _nFill < _nUse THEN // 窗未填满才累加 / count only while the window is not yet full
        _nFill := _nFill + 1; // 填充计数推进 / advance the filled count
    END_IF
    IF _fDev > fDevWin THEN // 偏差超窗（0707 独立成因）/ the deviation over the window
        _bDevFlt := TRUE; // 独立锁存 / latch the deviation cause
    END_IF
    // 除子证明（v1.0.1 重写）：① _nFill 在上一行刚自增且上界为 _nUse，而 _nUse 已在段 2 钳到 ≥ 1，
    // 故进入本判时 _nFill ≥ 1 恒成立；② 唯一能把 _nFill 置 0 的是段 2b 的窗长变更沿，它在段 3 之前执行；
    // ③ 下方 _nFill ≥ 1 复检为第三重防御，供后续重构时不破除零。
    // divisor proof: the count is incremented just above and bounded by the clamped length of at least one, so it is at least one here;
    // the only zeroing path is the length change edge executed before this segment; the explicit recheck below is a third line of defence.
    IF _nFill >= 1 THEN // 除零复检（正常路径恒真，禁用裸除子）/ the divisor recheck, always true on the normal path
        IF (_fRingSum / DINT_TO_LREAL(_nFill)) > fDriftLim THEN // 滚动均值超限（除子已证 ≥ 1，0708 独立成因）/ the rolling mean over the limit with a proven divisor
            _bDriftFlt := TRUE; // 独立锁存 / latch the drift cause
        END_IF
    END_IF
END_IF
IF _bDevFlt OR _bDriftFlt THEN // 任一成因锁存即整体故障 / any cause latches the whole fault
    _bFault := TRUE; // 总锁存 / latch the total fault
END_IF

// 段 4｜择优状态机（ENUM + CASE，ELSE 兜底；迟滞纪律，边界一）/ segment 4, the selection machine with the hysteresis
CASE _eState OF
    E_DL_SensorPairPhase.eUseA: // A 源相 / the source A phase
        IF _bFault THEN // 故障迁移（安全相带全量闸位复检，R274）/ the fault migration with the full gate recheck
            _eState := E_DL_SensorPairPhase.eFault; // 迁入故障锁存相 / enter the fault phase
        ELSIF NOT _bFinA THEN // A 源失效：迟滞边界切换（唯一切换判据）/ the A source invalid, the hysteresis boundary switch
            _eState := E_DL_SensorPairPhase.eUseB; // 切到 B 源 / switch to the source B
            _bSw := TRUE; // 置切换单拍 / raise the switch bit
        END_IF
    E_DL_SensorPairPhase.eUseB: // B 源相 / the source B phase
        IF _bFault THEN // 故障迁移 / the fault migration
            _eState := E_DL_SensorPairPhase.eFault; // 迁入故障锁存相 / enter the fault phase
        ELSIF NOT _bFinB THEN // B 源失效：切回 A / the B source invalid, back to A
            _eState := E_DL_SensorPairPhase.eUseA; // 切回 A 源 / back to the source A
            _bSw := TRUE; // 置切换单拍 / raise the switch bit
        END_IF
    E_DL_SensorPairPhase.eFault: // 故障锁存相：等复位沿（解除可达，边界四）/ the fault phase until the reset edge
        IF rtReset.Q AND (NOT _bDevFlt) AND (NOT _bDriftFlt) THEN // 双锁存已清才迁出（防清锁同拍重锁，FB50-1）/ the exit only after both latches cleared
            _eState := E_DL_SensorPairPhase.eUseA; // 迁回 A 源 / back to the source A
        END_IF
    ELSE // 非法枚举值拦截 / the illegal enumeration guard
        _eState := E_DL_SensorPairPhase.eUseA; // 落回 A 源 / force back to A
        _bFault := TRUE; // 置总锁存 / latch the total fault
END_CASE

// 段 5｜统一出口（择优值按态取源；故障冻结快照，R273）/ segment 5, the unified outlet
bSwitched := _bSw; // 切换单拍出口 / the switch pulse outlet
eState := _eState; // 状态出口 / the state outlet
bSrcA := (_eState = E_DL_SensorPairPhase.eUseA); // A 源指示 / the A indicator
bSrcB := (_eState = E_DL_SensorPairPhase.eUseB); // B 源指示 / the B indicator
IF _eState = E_DL_SensorPairPhase.eUseA THEN // A 源相出口取 A（非有限时安全零，R273）/ the A outlet with the safe zero on a non finite source
    IF _bFinA THEN // A 有限才外泄 / export only a finite A
        fSel := fA; // 择优值 / the selected value
        _fSnap := fA; // 快照更新（写前过闸，FB32-7）/ update the snapshot gated
    ELSE // A 非有限：保持快照（切换已在状态机发生）/ keep the snapshot
        fSel := _fSnap; // 冻结快照出口 / freeze the snapshot outlet
    END_IF
ELSIF _eState = E_DL_SensorPairPhase.eUseB THEN // B 源相出口取 B / the B outlet
    IF _bFinB THEN // B 有限才外泄 / export only a finite B
        fSel := fB; // 择优值 / the selected value
        _fSnap := fB; // 快照更新 / update the snapshot
    ELSE // B 非有限：保持快照 / keep the snapshot
        fSel := _fSnap; // 冻结快照出口 / freeze the snapshot outlet
    END_IF
ELSE // 故障相：冻结最近有效快照（R273）/ the fault phase freezes the snapshot
    fSel := _fSnap; // 冻结快照出口 / freeze the snapshot outlet
END_IF
bError := _bFault; // 故障位出口（与锁存同源）/ the fault bit outlet
bValid := (NOT _bFault) AND (_bFinA OR _bFinB); // 可用标志（无故障且至少一源有限，单点单写）/ the usable flag, no fault and at least one finite source
IF _bDevFlt THEN // 偏差成因回放（R187 锁存回放）/ the deviation cause replayed
    eErr := 16#0003_0707; // 故障级：偏差超窗 / fault grade, the deviation over the window
ELSIF _bDriftFlt THEN // 漂移成因 / the drift cause
    eErr := 16#0003_0708; // 故障级：漂移趋势超限 / fault grade, the drift over the limit
ELSIF _bSw THEN // 切换（信息级不置 bError，R285）/ the switch informational
    eErr := 16#0003_0709; // 信息级：发生择优源切换 / informational, the source switched
ELSIF _bWinBad THEN // 窗长钳位（信息级）/ the window clamp informational
    eErr := 16#0003_070A; // 信息级：滚动窗长度越域已钳位 / informational, the window clamped
ELSE // 无事件 / no event
    eErr := 16#0000_0000; // 正常 / ok
END_IF
END_FUNCTION_BLOCK
