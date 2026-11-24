(*
    FB_DL_BlinkOutput —— 方波闪烁输出（tOn / tOff 独立交替两相 TON）
    ------------------------------------------------------------------
    组件名称  : FB_DL_BlinkOutput
    分类      : DL_Base / SignalGeneration
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : 借鉴组织 —— T1-1 OSCAT Basic（矩阵行 170）：仅借鉴 BLINK 的
                **公开行为定义**（tOn / tOff 独立交替两相 + 使能撤除冻结输出
                与相位），OSCAT 许可免费、按 EPL-2.0 类比先例（R25）致谢；
                clean-room 声明 —— **零代码行复制**，实现 / 引脚名 / 码位 /
                组态锁存口径 100% 自有。
    平台      : 纯 IEC 61131-3（双 TON 交替），CODESYS 3.5 / TwinCAT 3 /
                InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R72 构建轮 · 批 3 · 序号 8）
    ------------------------------------------------------------------
    功能说明  : 秒级方波闪烁：tOn 相（bOut = TRUE）计时满 tOn → 切 tOff 相
                （bOut = FALSE）→ 计满 tOff 回切开相，如此交替。真实工况：
                塔灯辅闪、报警闪烁、待机呼吸灯。
                相机制（两相判据链，无顺序状态机 CASE）：
                ① 双 TON 实例按当前相择一计时，IN 为显式条件变量；
                ② bEn = FALSE 冻结 bOut 与相位**计数值**（失能不清相位，恢复
                   时从冻结点续走——相位保持，定时清零重启，OSCAT BLINK 行为
                   定义口径）；失能期间双 TON 的 IN 强制 FALSE（计时同步冻结），
                   R191 失能语义声明：**冻结保持末值**（bOut 不清零）；
                ③ tOn = 0 或 tOff = 0（TIME 无负值路径）→ **组态锁存码**
                   （防全灭 / 全亮静默——fGain = 0 报警静默教训 R386 同型），
                   锁存至 bReset 上升沿唯一解除（R188，解除路径恒可达自证）；
                   锁存相 bOut 强制 FALSE、周期计数冻结（故障可见性靠码位 +
                   bError，不靠灯）；
                ④ 周期计数口径：每完成一个完整 on + off 周期（关相计满回切
                   开相瞬间）uCycleCount + 1，UDINT 饱和上限 16#FFFF_FFFF。
                段序口径：锁存（含解除与首次成因登记）先于定时器调用——
                消灭「零组态拍定时器先跑一拍」的伪切换伪影；双 TON 与
                R_TRIG 仍为每拍无条件调用（IN 显式条件，选相不进可跳过分支）。
                TON 极性声明（R319 复核）：双 TON 的 IN = 相内剩余条件
                （_bRun AND 相标志），**非**被监视正常电平——本件是相驱动
                而非监视件，极性合规。
    错误码    : 16#0001_0752 组态非法：tOn = 0 或 tOff = 0（零时长相会退化
                            为全灭或全亮静默），锁存至复位沿 —— 故障级
                加码反证句（R90）：该场景无法由「正常闪烁输出 + bValid」
                观测——正常相 bOut 在闪烁、锁存相 bOut 恒 FALSE + bError =
                TRUE + 码位回放，输出组合不可互换，故立独立码。
    码位总账  : 16#0001_0752 用（同段 16#0001_0753 已由 FC_DL_DaysInMonthChk
                占用，本件不占）
    状态机    : 无顺序状态机 CASE——两相判据链 + 双 TON 自持；非法状态不可能
                出现（_bPhaseOn 为 BOOL，无非法值域）
    边界与披露: 一 双 TON（tonOn / tonOff）与 R_TRIG（rtReset）每拍
                   **无条件调用**（规则 ⑦），IN 为显式条件变量；
                二 零全局变量、零 VAR_EXTERNAL、零物理地址；
                三 组态域闸逐项点名（R272）：tOn / tOff 双引脚全部纳入零值
                   锁存闸；
                四 验收向量：tOn = tOff 恰等（对称方波）→ 正常 50% 占空比；
                   tOn / tOff 极端幅值 T#1E9MS（约 11.6 天）→ 正常慢闪
                   （TIME 32 位 ms 域内可表，无溢出面）；tOn = T#0MS →
                   0752 锁存；V5 失能 → bOut 冻结、相位保持、计数冻结；
                   V6 复位沿解除锁存后恢复闪烁；
                五 同拍双窗配比约束（R100）：双相独立计时无窗间依赖约束
                （tOn / tOff 各自独立，无先后门槛），配比约束句豁免声明；
                六 输出语义：uCycleCount 饱和口径（16#FFFF_FFFF 封顶不再
                   累加，防回绕）；
                七 依赖声明：仅 Standard.library（TON / R_TRIG），零厂商方言。
    验收向量  : V1 tOn = T#1S，tOff = T#1S → 50% 对称方波；
                V2 tOn = T#0MS → 0752 锁存 + bError；V3 tOff = T#0MS →
                0752 锁存；V4 tOn = T#500MS，tOff = T#2S → 20% 占空比；
                V5 bEn 置 FALSE → bOut 与 _bPhaseOn 冻结；V6 bReset 上升沿
                → 解锁恢复；V7 一个完整周期后 uCycleCount = 1。
                算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    修订记录  : 2026-11-23 v1.0.0 首次入库（R72 构建轮 · 批 3 · 序号 8）
*)
FUNCTION_BLOCK FB_DL_BlinkOutput
VAR_INPUT
    bEn    : BOOL := FALSE;                (* 使能，[标志]，FALSE 冻结输出与相位（R191 冻结保持声明）/ the enable, FALSE freezes the output and the phase *)
    tOn    : TIME := T#500MS;              (* 开相时长，[ms]，禁 0（零值锁存 0752）/ the on phase duration, must not be zero *)
    tOff   : TIME := T#500MS;              (* 关相时长，[ms]，禁 0（零值锁存 0752）/ the off phase duration, must not be zero *)
    bReset : BOOL := FALSE;                (* 组态故障复位，[标志]，上升沿唯一解除（R188）/ the configuration fault reset, its rising edge is the only release *)
END_VAR
VAR_OUTPUT
    bOut        : BOOL := FALSE;           (* 方波输出，[标志]，失能冻结保持末值 / the square wave output, frozen on disable *)
    uCycleCount : UDINT := 0;              (* 完整周期计数（on + off 计满一回切加一），饱和上限 16#FFFF_FFFF [次] / the complete cycle count, saturated *)
    bValid      : BOOL := FALSE;           (* 出口可用标志，锁存故障为 FALSE / the outlets usable flag *)
    bError      : BOOL := FALSE;           (* 故障标志，与锁存同源（R191）/ the fault flag from the latch *)
    nErrCode    : UDINT := 16#0000_0000;   (* 错误码，0 = 正常，锁存回放（R187）/ the error id, replayed from the latch *)
END_VAR
VAR
    _bPhaseOn  : BOOL := TRUE;             (* 相位寄存器：TRUE = 开相（上电首拍从开相起走）/ the phase register, TRUE for the on phase *)
    _bFault    : BOOL := FALSE;            (* 组态故障锁存副本，仅复位沿解除 / the config fault latch copy *)
    _nCodeLatch: UDINT := 0;               (* 锁存成因码，故障期回放 / the latched cause code *)
    _bRun      : BOOL := FALSE;            (* 运行许可 = 使能 且 无锁存故障 / the run permit *)
    tonOn      : TON;                      (* 开相计时实例，每拍无条件调用 / the on phase timer *)
    tonOff     : TON;                      (* 关相计时实例，每拍无条件调用 / the off phase timer *)
    rtReset    : R_TRIG;                   (* 复位沿实例，每拍无条件调用 / the reset edge instance *)
END_VAR
VAR CONSTANT
    DL_BLO_TZERO  : TIME := T#0S;          (* 零时长哨兵（组态锁存闸）[ms] / the zero duration sentinel *)
    DL_BLO_CYCMAX : UDINT := 16#FFFF_FFFF; (* 周期计数饱和上限 [次] / the cycle count saturation cap *)
    DL_BLO_CODE   : UDINT := 16#0001_0752; (* 组态非法锁存码 [码] / the illegal configuration latch code *)
    DL_BLO_ZERO   : UDINT := 0;            (* 无符号零哨兵 [码] / the unsigned zero sentinel *)
    DL_BLO_ONE    : UDINT := 1;            (* 计数步进 [次] / the count step *)
END_VAR

// 段 0｜复位沿无条件调用（规则 ⑦）/ segment 0, the unconditional reset edge refresh
rtReset(CLK := bReset);                    // 每拍无条件刷新 / refreshed every scan without exception

// 段 1｜锁存解除与首次成因登记（先锁存后计时，消灭零组态拍伪切换伪影）/ segment 1, the latch release and the first cause registration
IF rtReset.Q THEN                          // 复位上升沿 / the reset rising edge
    _bFault := FALSE;                      // 解除锁存（唯一解除边，R188，恒可达 R152 自证）/ release the latch
    _nCodeLatch := DL_BLO_ZERO;            // 清锁存码（作用域声明 R311：仅清锁存与码，不清相位与计数）/ clear the latched code
END_IF
IF (NOT _bFault) AND ((tOn = DL_BLO_TZERO) OR (tOff = DL_BLO_TZERO)) THEN // 零时长相组态命中 / a zero duration configuration hit
    _bFault := TRUE;                       // 置锁存（防全灭 / 全亮静默，R386 同型）/ latch the fault
    _nCodeLatch := DL_BLO_CODE;            // 登记成因码（首次成因锁存，故障期不重推断 R189）/ register the cause code
END_IF

// 段 2｜运行许可与双 TON 无条件调用（IN 为显式条件变量，选相不进可跳过分支）/ segment 2, the run permit and the unconditional timer calls
_bRun := bEn AND (NOT _bFault);            // 运行许可（锁存已定，无伪影）/ the run permit
tonOn(IN := _bRun AND _bPhaseOn, PT := tOn);         // 开相计时（失能 / 关相时 IN FALSE 冻结）/ the on timer
tonOff(IN := _bRun AND (NOT _bPhaseOn), PT := tOff); // 关相计时 / the off timer

// 段 3｜两相交替推进（运行许可内；失能 / 故障相不动相位与计数）/ segment 3, the two phase progression
IF _bRun THEN                              // 运行许可成立 / the run permit holds
    IF _bPhaseOn THEN                      // 开相 / the on phase
        bOut := TRUE;                      // 输出亮 / the output on
        IF tonOn.Q THEN                    // 开相计满 / the on phase timed out
            _bPhaseOn := FALSE;            // 切关相 / switch to the off phase
        END_IF
    ELSE                                   // 关相 / the off phase
        bOut := FALSE;                     // 输出灭 / the output off
        IF tonOff.Q THEN                   // 关相计满（完整 on + off 周期完成）/ the off phase timed out
            _bPhaseOn := TRUE;             // 回切开相 / back to the on phase
            IF uCycleCount < DL_BLO_CYCMAX THEN // 饱和上限闸（防回绕）/ the saturation cap
                uCycleCount := uCycleCount + DL_BLO_ONE; // 周期计数 + 1 / count one cycle
            END_IF
        END_IF
    END_IF
ELSIF _bFault THEN                         // 锁存故障相（故障可见性靠码位与 bError）/ the latched fault phase
    bOut := FALSE;                         // 故障相强制灭（不冻结残留亮态）/ force off in the fault phase
END_IF                                     // 失能相（非故障）：bOut 不触碰，冻结保持（R191 声明）

// 段 4｜统一出口（名实双出口同源，R191）/ segment 4, the unified outlet
bValid := NOT _bFault;                     // 出口可用 = 无锁存 / the usable flag
bError := _bFault;                         // 故障标志与锁存同源 / the flag shares the latch
IF _bFault THEN                            // 锁存回放（R187）/ the latched replay
    nErrCode := _nCodeLatch;               // 回放锁存码 / replay the latched code
ELSE                                       // 正常相 / the normal phase
    nErrCode := DL_BLO_ZERO;               // 无错 / ok
END_IF
END_FUNCTION_BLOCK
