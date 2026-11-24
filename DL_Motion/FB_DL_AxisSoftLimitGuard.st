(*
    FB_DL_AxisSoftLimitGuard —— 轴软限位守卫（位置 + 速度前馈预判减速请求）
    ------------------------------------------------------------------
    组件名称  : FB_DL_AxisSoftLimitGuard
    分类      : DL_Motion / LimitGuard
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : 借鉴点 —— 运动控制领域「软限位 + 提前减速（预判停距）」的通行语义：
                仅用位置比较只能撞限位后才发现（已超程），故必须用当前速度按
                允许减速度反算停距，把「当前位置 + 本周期位移 + 停距」作为预判
                可达位置，与限位比较后提前发出减速请求；越限后锁存并禁止该方向
                运动（方向互锁）。该语义与 PLCopen Motion Control 公开规范中
                「软限位监视 / 方向禁止」的功能描述一致。
                clean-room 声明 —— 零代码行复制；本件不含任何厂商运动指令
                （不调用 MC_* 功能块、不使用任何厂商专有数据类型），停距预判、
                方向互锁、闸门、码位与双语文档全部自有。
                许可证 —— 本件 MIT；来源标签 s7motion 仅指该语义在公开厂商文档
                中的功能描述，文档不属代码，无许可继承。
    平台      : 纯 IEC 61131-3，CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R70 构建轮 · 批 3 · N8）
    ------------------------------------------------------------------
    功能说明  : 预判模型（逐项写清，便于现场复核）：
                  fSpan := ABS(fVel) * fScanSec               本周期位移（速度前馈项，[mm]）
                  fStop := fVel * fVel / (2 * fDecel)         停距（等减速度制动距离，[mm]）
                  fPred := fPos + fVel * fScanSec + 符号(fVel) * fStop   预判可达位置 [mm]
                判据：
                  正向减速请求 bDecelPos := fVel > 0 且 fPred > (fPosMax - fMargin)
                  负向减速请求 bDecelNeg := fVel < 0 且 fPred < (fPosMin + fMargin)
                  正向禁止 bInhibitPos := 越限锁存 或 fPos >= fPosMax
                  负向禁止 bInhibitNeg := 越限锁存 或 fPos <= fPosMin
                除法面（唯一除法）：除子为 (2 * fDecel)，进入除法前经**两道结构闸**
                校验 fDecel > 0 与 (2 * fDecel) > 0，两者同时成立才落除法；
                闸不成立时整个预判段被跳过（不落除法、不发减速请求、不写
                fPredPos），并由组态闸在段 4 置 0501 锁存。
                其余算式一律用乘加（余量比较改写为 fMargin * 2 >= 行程），
                故本件全部代码中只有一个除法点。
                越限锁存：fPos 越过任一限位即锁存 0503，bReset 上升沿解除；
                锁存期内两个禁止方向位**恒为 TRUE**（双方向全禁，因为越限后
                任何方向都可能加剧超程，需人工确认后复位）。
    错误码    : 16#0002_0501 组态非法（限位反置 / 减速度非正 / 回退余量为负 / 非有限），锁存 —— 故障级
                16#0002_0502 位置或速度非有限，锁存 —— 故障级
                16#0002_0503 越限（位置越过软限位），锁存 —— 故障级
    码位总账  : 0501 / 0502 / 0503 用（均故障级）；无信息级码（减速请求与禁止位已可观测）
    状态机    : N/A —— 无顺序相（逐拍组合判据 + 越限锁存），无 ENUM / CASE
    边界与披露: 一 组态闸（R272 逐项点名）：fPosMax > fPosMin；fDecel > 0；
                   fMargin >= 0 且 fMargin < (fPosMax - fPosMin) / 2（余量不得吞没
                   整个行程）；fScanSec > 0；上述量与 fPos / fVel 全部纳入
                   NaN 自反判 + Inf 差值自反判 + 幅值 1E9 上界筛查；
                二 定时器 / 沿实例：仅 _rtReset 一个沿实例，在段 2 无条件调用；
                   本件不含 TON / TOF / TP，故无定时器跳过风险；
                三 出口语义（R191）：bDecelPos / bDecelNeg 为**逐拍重算**的请求位，
                   bInhibitPos / bInhibitNeg 为组合位（越限锁存 或 位置到限），
                   bBeyond 为越限锁存镜像；三者名实同源、无混用；
                四 失能（bEn = FALSE）：减速请求清零、禁止位**保持有效**
                   （安全方向：失能不得放开方向禁止），bBusy 清零，锁存位不被清除；
                五 本件不做任何运动指令下发，只输出布尔许可 / 请求位，由上层
                   运动层转换为 MC_Halt / 减速倍率等动作 —— 保持硬件与厂商无关；
                六 零全局变量、零 VAR_EXTERNAL、零物理地址、零数组下标。
    修订记录  : 2026-11-22 v1.0.0 首次入库（R70 构建轮 · 批 3 · N8）
*)
FUNCTION_BLOCK FB_DL_AxisSoftLimitGuard
VAR_INPUT
    bEn       : BOOL := TRUE;              (* 使能，[标志] / the enable *)
    bReset    : BOOL := FALSE;             (* 越限复位（上升沿有效），[标志] / the overrun reset, rising edge *)
    fPos      : LREAL := 0.0;              (* 轴当前位置（编码器反馈），[mm] / the axis position feedback *)
    fVel      : LREAL := 0.0;              (* 轴当前速度（反馈或指令前馈），[mm/s] / the axis velocity *)
    fPosMax   : LREAL := 1000.0;           (* 正向软限位，[mm]，须 > fPosMin / the positive soft limit *)
    fPosMin   : LREAL := 0.0;              (* 负向软限位，[mm]，须 < fPosMax / the negative soft limit *)
    fDecel    : LREAL := 1000.0;           (* 允许减速度幅值，[mm/s^2]，须 > 0 / the allowed deceleration magnitude *)
    fScanSec  : LREAL := 0.004;            (* 任务周期折算秒数，[s]，须 > 0 / the task period in seconds *)
    fMargin   : LREAL := 20.0;             (* 提前减速余量，[mm]，须 >= 0 / the early deceleration margin *)
END_VAR
VAR_OUTPUT
    bDecelPos   : BOOL;                    (* 正向减速请求，[标志] / the positive direction deceleration request *)
    bDecelNeg   : BOOL;                    (* 负向减速请求，[标志] / the negative direction deceleration request *)
    bInhibitPos : BOOL;                    (* 正向运动禁止，[标志] / the positive direction inhibited *)
    bInhibitNeg : BOOL;                    (* 负向运动禁止，[标志] / the negative direction inhibited *)
    bBeyond     : BOOL;                    (* 越限锁存镜像，[标志] / the overrun latch image *)
    fPredPos    : LREAL;                   (* 预判可达位置（供诊断），[mm] / the predicted reachable position *)
    bBusy       : BOOL;                    (* 减速请求有效（占用中），[标志] / a deceleration request is active *)
    bValid      : BOOL;                    (* 出口可信（无锁存故障），[标志] / the outlets are trustworthy *)
    bError      : BOOL;                    (* 故障标志，锁存故障时为 TRUE / the fault flag, raised while latched *)
    nErrCode    : UDINT;                   (* 错误码，0 = 正常，锁存回放 / the error id, 0 = ok, replayed *)
END_VAR
VAR
    _rtReset    : R_TRIG;                  (* 复位上升沿实例（无条件调用）/ the reset rising edge instance *)
    _bFault     : BOOL;                    (* 组态 / 输入故障锁存位 / the configuration and input fault latch *)
    _bBeyond    : BOOL;                    (* 越限保持量，仅 bReset 上升沿解除 / the overrun hold *)
    _nCodeLatch : UDINT;                   (* 故障锁存码（0501 / 0502 / 0503）/ the fault code latch *)
    _bCfgBad    : BOOL;                    (* 组态非法标志（逐拍重算）/ the configuration fault flag *)
    _bInBad     : BOOL;                    (* 位置或速度非有限标志（逐拍重算）/ the input fault flag *)
    _fSpan      : LREAL;                   (* 本周期位移，[mm] / the travel within one period *)
    _fStop      : LREAL;                   (* 制动停距，[mm] / the braking distance *)
    _fPred      : LREAL;                   (* 预判可达位置（内部），[mm] / the predicted reachable position, internal *)
    _fSign      : LREAL;                   (* 速度符号的实数形式（1.0 / 0.0 / -1.0），[无量纲] / the velocity sign as a real *)
END_VAR
VAR CONSTANT
    DL_ASG_FMAX : LREAL := 1.0E9;          (* 非有限筛查幅值上限，[工程单位] / the finiteness screening cap *)
END_VAR

// 段 1｜出口预置（R256 统一出口预置）/ segment 1, preset every outlet
bDecelPos   := FALSE;                      // 正向减速请求预清零 / preset the positive request false
bDecelNeg   := FALSE;                      // 负向减速请求预清零 / preset the negative request false
bInhibitPos := FALSE;                      // 正向禁止预清零（段 7 按安全方向重算）/ preset the positive inhibit false
bInhibitNeg := FALSE;                      // 负向禁止预清零 / preset the negative inhibit false
bBeyond     := FALSE;                      // 越限镜像预清零 / preset the overrun image false
fPredPos    := 0.0;                        // 预判位置预置零 / preset the predicted position
bBusy       := FALSE;                      // 忙碌标志预清零 / preset the busy flag false
bValid      := FALSE;                      // 可用标志预置假，健康路径再置真 / preset valid false
bError      := FALSE;                      // 故障标志预清零 / preset the error flag false
nErrCode    := 0;                          // 错误码预置无错 / preset the code to zero
_fSign      := 0.0;                        // 速度符号预置零 / preset the sign to zero

// 段 2｜沿实例无条件调用（规则 ⑦，本件无 TON / TOF / TP）/ segment 2, the reset edge instance
_rtReset(CLK := bReset);                   // 复位沿，每周期无条件刷新 / the reset edge, refreshed every scan

// 段 3｜越限解除：唯一可到达的清除边（R188）/ segment 3, the only overrun release edge
IF _rtReset.Q THEN                         // 复位上升沿 / the reset rising edge
    _bBeyond := FALSE;                     // 解除越限保持 / release the overrun hold
    IF _nCodeLatch = 16#0002_0503 THEN     // 锁存码为越限时才清码（组态 / 输入码保持到修复）/ clear the code only when it was the overrun
        _nCodeLatch := 0;                  // 清锁存码 / clear the latched code
    END_IF
END_IF

// 段 4｜组态守卫（R272 逐项点名）/ segment 4, the configuration guard
_bCfgBad := (fPosMax <= fPosMin)                                     // 限位反置或重合 / the limits reversed or coincident
         OR (fDecel <= 0.0)                                          // 减速度非正（除子域非法）/ a non positive deceleration
         OR (fScanSec <= 0.0)                                        // 任务周期非正 / a non positive task period
         OR (fMargin < 0.0)                                          // 余量为负 / a negative margin
         OR (fMargin * 2.0 >= (fPosMax - fPosMin))                   // 余量吞没行程（改用乘 2，本式不落除法）/ the margin swallows the stroke, no division here
         OR (fPosMax <> fPosMax) OR ((fPosMax - fPosMax) <> 0.0) OR (ABS(fPosMax) > DL_ASG_FMAX)
         OR (fPosMin <> fPosMin) OR ((fPosMin - fPosMin) <> 0.0) OR (ABS(fPosMin) > DL_ASG_FMAX)
         OR (fDecel <> fDecel) OR ((fDecel - fDecel) <> 0.0) OR (ABS(fDecel) > DL_ASG_FMAX)
         OR (fScanSec <> fScanSec) OR ((fScanSec - fScanSec) <> 0.0) OR (ABS(fScanSec) > DL_ASG_FMAX)
         OR (fMargin <> fMargin) OR ((fMargin - fMargin) <> 0.0) OR (ABS(fMargin) > DL_ASG_FMAX);

// 段 5｜输入守卫：位置与速度非有限 / segment 5, the position and velocity guard
_bInBad := (fPos <> fPos) OR ((fPos - fPos) <> 0.0) OR (ABS(fPos) > (DL_ASG_FMAX * 10.0))
        OR (fVel <> fVel) OR ((fVel - fVel) <> 0.0) OR (ABS(fVel) > (DL_ASG_FMAX * 10.0));

// 段 6｜首次成因锁存（故障期不重推断，R189）/ segment 6, the first cause latch
IF NOT _bFault THEN                        // 未锁存才登记 / register only while healthy
    IF _bCfgBad THEN                       // 组态非法优先 / the configuration first
        _bFault     := TRUE;               // 置锁存 / latch it
        _nCodeLatch := 16#0002_0501;       // 故障级：组态非法 / fault level: an illegal configuration
    ELSIF _bInBad THEN                     // 输入非有限 / an input is non finite
        _bFault     := TRUE;               // 置锁存 / latch it
        _nCodeLatch := 16#0002_0502;       // 故障级：输入非有限 / fault level: an input is non finite
    END_IF
END_IF

// 段 7｜越限判定与方向禁止（安全方向：越限后双向全禁）/ segment 7, the overrun verdict and the direction inhibits
IF bEn AND NOT _bFault THEN                // 使能与无故障才判越限 / judge the overrun only while enabled and healthy
    IF (fPos > fPosMax) OR (fPos < fPosMin) THEN   // 位置越过任一软限位 / the position passed a soft limit
        IF NOT _bBeyond THEN               // 首次越限才登记码（不重推断）/ register the code once
            _bBeyond    := TRUE;           // 置越限保持 / hold the overrun
            _nCodeLatch := 16#0002_0503;   // 故障级：越限 / fault level: an overrun
        END_IF
    END_IF
    bInhibitPos := _bBeyond OR (fPos >= fPosMax);  // 正向禁止：越限锁存 或 位置到正限 / the positive inhibit
    bInhibitNeg := _bBeyond OR (fPos <= fPosMin);  // 负向禁止：越限锁存 或 位置到负限 / the negative inhibit
ELSE                                       // 失能或故障：禁止位保持安全侧（不放开）/ disabled or faulted, keep the inhibits safe
    bInhibitPos := TRUE;                   // 正向保持禁止 / keep the positive direction inhibited
    bInhibitNeg := TRUE;                   // 负向保持禁止 / keep the negative direction inhibited
END_IF

// 段 8｜预判停距与减速请求（唯一除法，除子先经结构闸）/ segment 8, the predictive request
IF bEn AND NOT _bFault AND NOT _bBeyond THEN   // 健康且未越限才做预判 / predict only while healthy and inside the limits
    IF fDecel > 0.0 THEN                       // 结构闸一：减速度为正 / gate one, the deceleration is positive
        IF (2.0 * fDecel) > 0.0 THEN           // 结构闸二：除子为正（禁除零，规则 ④）/ gate two, the divisor is positive
            _fSpan := ABS(fVel) * fScanSec;    // 本周期位移（速度前馈项）/ the travel within one period
            _fStop := (fVel * fVel) / (2.0 * fDecel); // 制动停距（唯一除法）/ the braking distance, the only division
            IF fVel > 0.0 THEN                 // 正向运动 / moving in the positive direction
                _fSign := 1.0;                 // 符号为正 / the sign is positive
            ELSIF fVel < 0.0 THEN              // 负向运动 / moving in the negative direction
                _fSign := -1.0;                // 符号为负 / the sign is negative
            ELSE                               // 静止 / at standstill
                _fSign := 0.0;                 // 符号为零（停距不计方向）/ the sign is zero
            END_IF
            _fPred := fPos + (fVel * fScanSec) + (_fSign * _fStop); // 预判可达位置 / the predicted reachable position
            fPredPos := _fPred;                // 预判位置出口（诊断用）/ the predicted position outlet
            bDecelPos := (fVel > 0.0) AND (_fPred > (fPosMax - fMargin));  // 正向提前减速请求 / the positive early request
            bDecelNeg := (fVel < 0.0) AND (_fPred < (fPosMin + fMargin));  // 负向提前减速请求 / the negative early request
        END_IF
    END_IF
END_IF

// 段 9｜出口映射（名实双出口同源，R191）/ segment 9, the outlet mapping
bBeyond  := _bBeyond;                      // 越限镜像 = 保持量 / the overrun image mirrors the hold
bBusy    := bDecelPos OR bDecelNeg;        // 减速请求有效即占用 / a request is active
bError   := _bFault OR _bBeyond;           // 故障标志 = 锁存故障 或 越限 / the fault flag, the latch or the overrun
bValid   := bEn AND NOT bError;            // 出口可信条件 / the outlets are trustworthy
IF _bBeyond THEN                           // 越限优先归因 / the overrun takes precedence
    nErrCode := 16#0002_0503;              // 故障级：越限 / fault level: an overrun
ELSE                                       // 非越限 / no overrun
    nErrCode := _nCodeLatch;               // 回放锁存码 / replay the latched code
END_IF
END_FUNCTION_BLOCK
