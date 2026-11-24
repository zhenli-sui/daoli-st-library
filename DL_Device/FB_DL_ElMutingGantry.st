(*
  FB_DL_ElMutingGantry  —  EL 检测龙门进出光幕屏蔽（muting）/ EL gantry light-curtain muting arbitration
  分类 Category : DL_Device
  码位 Code     : 16#03_2_19
  段位说明      : 03_2 段低半字节已满，1x 段续号，18 格由 DoorInterlockHvac 启用，本件启用 19 格（R192）
  版本 Version  : 1.0.0
  来源 Source   : t1-5-tcopen — EL 检测龙门屏蔽时序仲裁待挖项
  溯源 Origin   : clean-room 实现，2+2 传感器 muting 为公开标准时序语义，未复制任何源码行
  功能 Function : 1) 四传感器（进向 S1/S2，出向 S3/S4）2+2 时序判进/出方向：
                  进向对 S1 先 S2 后激活 → 进向屏蔽；出向对 S3 先 S4 后激活 → 出向屏蔽；
                  2) 屏蔽窗超时 tonMuteIn/tonMuteOut 强制退出屏蔽并锁故障（防遮蔽卡死常屏蔽）；
                  3) 安全事件不受屏蔽约束之外的部分：光幕触发位仅在无屏蔽时升级为安全停止；
                  屏蔽有效期间光幕触发按正常穿越处理（标准 muting 语义）；
                  4) bMuteLamp 屏蔽指示灯出口（标准 muting 联锁灯）。
  边界 Boundary : ① 本件只做屏蔽时序仲裁，光幕本体语义由 FB_DL_SafetyLightCurtain 承载
                  （本件仅接收其触发位，不实例化、不替代）；
                  ② 双向对同时激活判组态矛盾（故障级锁存）；
                  ③ R228-A 达标声明：tonMuteIn/tonMuteOut 各自单相独占（IN 为单相等式），跨相迁移拍 IN 必断；
                  ④ R228-B 达标声明：eFault 迁出 = rtReset.Q AND NOT 双向矛盾 AND NOT 超时残留，
                  三条件均为可满足输入（矛盾解除、复位给沿后），无恒假子式，逐字写于此；
                  ⑤ 传感器经 4 只 FB_DL_SignalDebounce 消抖（主体首部无条件刷新）。
  依赖 Depends  : FB_DL_SignalDebounce（实例化 ×4）；FB_DL_SafetyLightCurtain（语义对齐，不实例化）
  码表 Error codes（本件格 03_2_19，子码步进 +0x100）:
    16#0003_0119 信息级：屏蔽窗正常退出（穿越完成）
    16#0003_0219 故障级：屏蔽窗超时强制退出（防遮蔽卡死），锁存至复位
    16#0003_0319 故障级：双向对同拍激活（组态/传感器矛盾），锁存至复位
    16#0003_0419 故障级：状态机落 ELSE 兜底（非法相位 ID），锁存至复位
    16#0003_0519 信息级：光幕触发且无屏蔽（安全停止有效，本件只透传不仲裁）

  修订历史 Revision :
    2026-11-19  v1.0.0  R39 首版（批次 3 · 序号 11）
*)

TYPE E_DL_ElMuteState :
(
    eIdle    := 0,    // 无屏蔽：等传感器时序 / Idle, no muting active
    eMuteIn  := 10,   // 进向屏蔽：S1→S2 时序命中 / Entry muting, S1 then S2 sequence
    eMuteOut := 20,   // 出向屏蔽：S3→S4 时序命中 / Exit muting, S3 then S4 sequence
    eFault   := 90    // 故障：超时/矛盾锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_ElMutingGantry
VAR_INPUT
    bS1       : BOOL := FALSE;        // 进向传感器 1（外沿）/ Entry sensor 1, outer
    bS2       : BOOL := FALSE;        // 进向传感器 2（内沿）/ Entry sensor 2, inner
    bS3       : BOOL := FALSE;        // 出向传感器 1（内沿）/ Exit sensor 1, inner
    bS4       : BOOL := FALSE;        // 出向传感器 2（外沿）/ Exit sensor 2, outer
    bCurtainTrip : BOOL := FALSE;     // 光幕触发位（FB_DL_SafetyLightCurtain 输出透传）/ Light curtain tripped passthrough
    tDebounce : TIME := T#10MS;       // 传感器消抖延时 [ms] / Sensor debounce delay
    tMuteMax  : TIME := T#10S;        // 屏蔽窗上限 [ms]，域 > 0 / Maximum muting window
    bReset    : BOOL := FALSE;        // 故障复位，上升沿生效 / Fault reset, rising edge
END_VAR
VAR_OUTPUT
    eMuteDir    : E_DL_ElMuteState;   // 屏蔽方向出口（Idle = 无屏蔽）/ Muting direction outlet
    bMuteActive : BOOL;               // 屏蔽生效中（进向或出向）[-] / Muting active flag
    bMuteLamp   : BOOL;               // 屏蔽指示灯出口（与 bMuteActive 同源）[-] / Muting lamp output
    bSafetyStop : BOOL;               // 安全停止出口：光幕触发且无屏蔽（电平，每拍重算）[-] / Safety stop output
    bError      : BOOL;               // 故障锁存，仅故障级码置位，bReset 清除 [-] / Fault latch
    uErrorId    : UDINT;              // 事件码，0 = 无事件（故障级锁存回放）/ Event code
END_VAR
VAR
    afbDeb     : ARRAY[0..3] OF FB_DL_SignalDebounce;   // 四传感器消抖实例，主体首部无条件刷新 / Sensor debounce instances
    tonMuteIn  : TON;                 // 进向屏蔽窗计时（单相独占，R228-A）/ Entry mute window timer, single phase
    tonMuteOut : TON;                 // 出向屏蔽窗计时（单相独占，R228-A）/ Exit mute window timer, single phase
    rtReset    : R_TRIG;              // 复位上升沿 / Reset rising edge
    rtS1       : R_TRIG;              // 进向 S1 上升沿（时序判向基准）/ S1 rising edge, sequence basis
    rtS3       : R_TRIG;              // 出向 S3 上升沿（时序判向基准）/ S3 rising edge, sequence basis
    i0         : INT;                 // 消抖阵列遍历索引 [0..3] / Debounce array loop index
    _eState    : E_DL_ElMuteState := E_DL_ElMuteState.eIdle;  // 内部相位（CASE 唯一写入目标）/ Internal phase
    _bS1St     : BOOL;                // S1 消抖稳定镜像 / S1 debounced mirror
    _bS2St     : BOOL;                // S2 消抖稳定镜像 / S2 debounced mirror
    _bS3St     : BOOL;                // S3 消抖稳定镜像 / S3 debounced mirror
    _bS4St     : BOOL;                // S4 消抖稳定镜像 / S4 debounced mirror
    _bSeqIn    : BOOL;                // 进向时序命中记忆（S1 沿后 S2 激活）/ Entry sequence memory
    _bSeqOut   : BOOL;                // 出向时序命中记忆（S3 沿后 S4 激活）/ Exit sequence memory
    _bFault    : BOOL;                // 故障锁存位 / Latched fault bit
    _uFault    : UDINT;               // 故障码锁存寄存 / Latched fault code register
    _uInfo     : UDINT;               // 信息码，每拍重算 / Info code
    _bConflict : BOOL;                // 双向矛盾聚合 / Bidirectional conflict aggregate
END_VAR

(* —— 段 0：定时器与边沿实例无条件周期刷新（R182：调用语句不得置于 IF/CASE 内） —— *)
FOR i0 := 0 TO 3 DO                                          // 消抖阵列每拍全量刷新（等效无条件域）
    afbDeb[i0](bRawInput := bS1 AND (i0 = 0)                 // 位选：0=S1 1=S2 2=S3 3=S4
                            OR (bS2 AND (i0 = 1))
                            OR (bS3 AND (i0 = 2))
                            OR (bS4 AND (i0 = 3)),
               tRiseDelay := tDebounce,                      // 消抖延时（组态透传）
               tFallDelay := tDebounce,
               bEnable := TRUE);
END_FOR
rtS1(CLK := afbDeb[0].bStable);                              // S1 沿（消抖后取沿）
rtS3(CLK := afbDeb[2].bStable);                              // S3 沿（消抖后取沿）
rtReset(CLK := bReset);                                      // 复位沿刷新，每拍必调
tonMuteIn(IN := (_eState = E_DL_ElMuteState.eMuteIn), PT := tMuteMax);    // 进向屏蔽窗（单相独占）
tonMuteOut(IN := (_eState = E_DL_ElMuteState.eMuteOut), PT := tMuteMax);  // 出向屏蔽窗（单相独占）

(* —— 段 1：单拍量预清零（锁存量 _uFault/_bFault/_bSeqIn/_bSeqOut 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
_bConflict := FALSE;                // 双向矛盾预清零（段 3 单点聚合）
uErrorId := 16#0000_0000;           // 事件码缺省无事件

(* —— 段 2：消抖镜像采集 —— *)
_bS1St := afbDeb[0].bStable;        // S1 稳定值
_bS2St := afbDeb[1].bStable;        // S2 稳定值
_bS3St := afbDeb[2].bStable;        // S3 稳定值
_bS4St := afbDeb[3].bStable;        // S4 稳定值

(* —— 段 3：双向矛盾与故障聚合 —— *)
IF _bS1St AND _bS2St AND _bS3St AND _bS4St THEN
    _bConflict := TRUE;             // 四传感器全亮：双向矛盾（组态/遮蔽异常）
END_IF
IF _bConflict AND (NOT _bFault) THEN
    _uFault := 16#0003_0319;        // 故障级：双向同拍激活
    _bFault := TRUE;
END_IF

(* —— 段 4：时序判向记忆（进向：S1 沿先行，S2 激活命中；出向同构） —— *)
IF rtS1.Q THEN
    _bSeqIn := TRUE;                // S1 沿：进向时序开窗（由 S2 激活或对释放关闭）
END_IF
IF _bS2St AND _bSeqIn THEN
    ;                               // S2 激活且时序开窗：进向屏蔽请求在相位机判定
ELSIF (NOT _bS1St) AND (NOT _bS2St) THEN
    _bSeqIn := FALSE;               // 进向对全释放：时序记忆关闭
END_IF
IF rtS3.Q THEN
    _bSeqOut := TRUE;               // S3 沿：出向时序开窗
END_IF
IF (NOT _bS3St) AND (NOT _bS4St) THEN
    _bSeqOut := FALSE;              // 出向对全释放：时序记忆关闭
END_IF

(* —— 段 5：相位机（屏蔽仲裁；出口在段 7） —— *)
CASE _eState OF

E_DL_ElMuteState.eIdle:
    IF _bFault THEN
        _eState := E_DL_ElMuteState.eFault;         // 聚合故障直接进故障相
    ELSIF _bS1St AND _bS2St AND _bSeqIn THEN
        _eState := E_DL_ElMuteState.eMuteIn;        // 进向时序命中：进屏蔽相
    ELSIF _bS3St AND _bS4St AND _bSeqOut THEN
        _eState := E_DL_ElMuteState.eMuteOut;       // 出向时序命中：进屏蔽相
    END_IF

E_DL_ElMuteState.eMuteIn:
    IF _bFault THEN
        _eState := E_DL_ElMuteState.eFault;         // 聚合故障直接进故障相
    ELSIF tonMuteIn.Q THEN
        _uFault := 16#0003_0219;                    // 故障级：屏蔽窗超时强制退出
        _bFault := TRUE;
        _bSeqIn := FALSE;                           // 强制退出：时序记忆作废
        _eState := E_DL_ElMuteState.eFault;
    ELSIF (NOT _bS1St) AND (NOT _bS2St) THEN
        _uInfo := 16#0003_0119;                     // 信息级：进向穿越完成正常退出
        _bSeqIn := FALSE;                           // 时序记忆关闭
        _eState := E_DL_ElMuteState.eIdle;          // 回无屏蔽相
    END_IF

E_DL_ElMuteState.eMuteOut:
    IF _bFault THEN
        _eState := E_DL_ElMuteState.eFault;         // 聚合故障直接进故障相
    ELSIF tonMuteOut.Q THEN
        _uFault := 16#0003_0219;                    // 故障级：屏蔽窗超时强制退出
        _bFault := TRUE;
        _bSeqOut := FALSE;                          // 强制退出：时序记忆作废
        _eState := E_DL_ElMuteState.eFault;
    ELSIF (NOT _bS3St) AND (NOT _bS4St) THEN
        _uInfo := 16#0003_0119;                     // 信息级：出向穿越完成正常退出
        _bSeqOut := FALSE;                          // 时序记忆关闭
        _eState := E_DL_ElMuteState.eIdle;          // 回无屏蔽相
    END_IF

E_DL_ElMuteState.eFault:
    ;                               // 故障相：等复位沿（段 6 承载迁出）

ELSE
    _uFault := 16#0003_0419;        // 故障级：非法相位 ID 兜底
    _bFault := TRUE;
    _eState := E_DL_ElMuteState.eFault;             // 强制回故障相

END_CASE

(* —— 段 6：eFault 迁出沿（R228-B：rtReset.Q AND NOT 矛盾 AND NOT 超时残留，逐字自证见头注释④） —— *)
IF rtReset.Q AND (NOT _bConflict) THEN
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;
    IF _eState = E_DL_ElMuteState.eFault THEN
        _eState := E_DL_ElMuteState.eIdle;          // 故障相迁出：回无屏蔽相
    END_IF
END_IF

(* —— 段 7：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
bMuteActive := (_eState = E_DL_ElMuteState.eMuteIn) OR (_eState = E_DL_ElMuteState.eMuteOut);   // 屏蔽生效中
bMuteLamp := bMuteActive;           // 指示灯同源镜像
bSafetyStop := bCurtainTrip AND (NOT bMuteActive);   // 安全停止：光幕触发且无屏蔽（电平每拍重算）
IF bSafetyStop THEN
    _uInfo := 16#0003_0519;         // 信息级：安全停止有效（覆盖正常退出码，安全信息优先）
END_IF
IF _bFault THEN
    uErrorId := _uFault;            // 故障锁存码回放
    bError := TRUE;
ELSE
    uErrorId := _uInfo;             // 信息码
    bError := FALSE;
END_IF
eMuteDir := _eState;                // 方向出口单点映射

END_FUNCTION_BLOCK
