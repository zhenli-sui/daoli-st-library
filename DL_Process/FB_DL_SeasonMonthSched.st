(*
  FB_DL_SeasonMonthSched  —  供暖/制冷季月度切换窗（月位图 + 切换滞回确认） / Season month schedule: heating/cooling bitmap with changeover hysteresis
  分类 Category : DL_Process
  版本 Version  : 1.0.0
  来源 Source   : t1-2-oscat-building — 楼宇季节切换族零检索深化
  溯源 Origin   : clean-room 实现，月位图语义公开借鉴 OSCAT 惯例，未复制任何源码行
  功能 Function : 1) 月度季节判据：uMonth（1..12）索引两幅 12 位月位图
                  （wHeatBmp 位 n-1 = 月 n 供暖 / wCoolBmp 位 n-1 = 月 n 制冷），
                  两位图均未命中 → 过渡季；
                  2) 切换滞回：目标季与当前季不一致 → eChgWait 相 tHyst 确认窗，
                  窗满提交切换，窗内目标季回撤即取消（eWait 相双出口，R98）；
                  3) 故障级三码独立：0382 位图交叠（同月双季，组态级锁存）/
                  0383 月值越界（uMonth > 12 判据不可信）/ 0384 ELSE 兜底；
                  4) 信息级三码：切供暖沿 / 切制冷沿 / 进过渡季沿；
                  5) 解除式全当拍量（R240 落地），逐 BOOL 标注见段 4。
  边界 Boundary : ① 位图判读前先做 uMonth 域闸（1..12），越界月不进移位判读
                  （移位量归一先于判据，R48 落地）；掩码用 SHL(WORD#1, 0..11)，
                  量域 0..11 < 16 结构性安全；
                  ② 位图交叠属静态组态错：锁存后季节出口保持当前季（冻结声明），
                  不随越界月漂移；
                  ③ 无 GVL 依赖：纯引脚输入输出，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : Standard.library（TON / R_TRIG）
  码表 Error codes（Process 段 0005，窗口 0382~0384 / 04AA~04AC）:
    16#0005_0382 故障级：月位图交叠锁存（同月既供暖又制冷），锁存至 bReset
    16#0005_0383 故障级：月值越界锁存（uMonth > 12 判据不可信），锁存至 bReset
    16#0005_0384 故障级：相位落 ELSE 兜底或滞回窗域非法（tHyst <= 0，归并声明），锁存至 bReset
    16#0005_04AA 信息级：切换至供暖季沿
    16#0005_04AB 信息级：切换至制冷季沿
    16#0005_04AC 信息级：进入过渡季沿
  修订历史 Revision :
    2026-11-19  v1.0.0  R42 首版（批次 2 · 序号 2）
*)

TYPE E_DL_SmsSeason :
(
    eTrans  := 0,    // 过渡季：位图未命中 / Transition season
    eHeat   := 10,   // 供暖季 / Heating season
    eCool   := 20    // 制冷季 / Cooling season
);
END_TYPE

TYPE E_DL_SmsState :
(
    eIdle    := 0,   // 季节稳态：按当前季输出 / Steady season state
    eChgWait := 10,  // 切换确认：滞回窗计时 / Changeover confirm window
    eFault   := 90   // 故障：组态或月值锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_SeasonMonthSched
VAR_INPUT
    uMonth       : USINT := 1;        // 当前月 [1..12]，越界判 0383 / Current month
    wHeatBmp     : WORD := 16#0FC0;   // 供暖月位图，位 n-1 = 月 n 供暖 / Heating month bitmap
    wCoolBmp     : WORD := 16#003C;   // 制冷月位图，位 n-1 = 月 n 制冷 / Cooling month bitmap
    tHyst        : TIME := T#10M;     // 切换滞回确认窗 [ms]，域 > 0 / Changeover hysteresis window
    bReset       : BOOL := FALSE;     // 复位，上升沿清故障锁存 / Reset edge clears fault latch
END_VAR
VAR_OUTPUT
    eState       : E_DL_SmsState;     // 相位出口，段尾单点映射 / State outlet
    eSeason      : E_DL_SmsSeason;    // 当前季出口 / Current season outlet
    bHeatDemand  : BOOL;              // 供暖需求出口（供暖季电平）[-] / Heating demand outlet
    bCoolDemand  : BOOL;              // 制冷需求出口（制冷季电平）[-] / Cooling demand outlet
    bError       : BOOL;              // 故障锁存标志 / Fault latch flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    tonHyst      : TON;               // 切换滞回确认窗（eChgWait 相独占），无条件刷新 / Hysteresis timer
    rtReset      : R_TRIG;            // 复位沿实例，无条件刷新 / Reset edge instance
    _eSeason     : E_DL_SmsSeason := E_DL_SmsSeason.eTrans;  // 内部季（CASE 唯一写入目标）/ Internal season
    _eTgtSeason  : E_DL_SmsSeason;    // 月位图判出目标季 / Bitmap-derived target season
    _wMask       : WORD;              // 当月掩码（SHL 结果）/ Current month mask
    _bHeatHit    : BOOL;              // 供暖位命中当拍量 [-] / Heating-bit hit flag
    _bCoolHit    : BOOL;              // 制冷位命中当拍量 [-] / Cooling-bit hit flag
    _bMonthBad   : BOOL;              // 月值越界当拍量 [-] / Month-out-of-range flag
    _bBmpOvl     : BOOL;              // 位图交叠当拍量（静态组态错逐月判出）[-] / Bitmap overlap flag
    _bFault      : BOOL;              // 故障锁存位（锁存量）/ Latched fault bit
    _uFault      : UDINT;             // 故障码锁存（锁存量）/ Latched fault code
    _uInfo       : UDINT;             // 信息码，每拍重算 / Transient info code
END_VAR

(* —— 段 0：定时器与沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
_bMonthBad := (uMonth = 0) OR (uMonth > 12);             // 月值越界（当拍量）
IF NOT _bMonthBad THEN               // 域内才进移位判读（移位量 0..11 结构性安全）
    _wMask := SHL(WORD#1, UINT(uMonth) - UINT#1);        // 当月掩码（移位量归一后合法域）
    _bHeatHit := (wHeatBmp AND _wMask) <> WORD#0;        // 供暖位命中（当拍量）
    _bCoolHit := (wCoolBmp AND _wMask) <> WORD#0;        // 制冷位命中（当拍量）
    _bBmpOvl := _bHeatHit AND _bCoolHit;                 // 位图交叠（当拍量）
    IF _bHeatHit THEN
        _eTgtSeason := E_DL_SmsSeason.eHeat;             // 目标季：供暖
    ELSIF _bCoolHit THEN
        _eTgtSeason := E_DL_SmsSeason.eCool;             // 目标季：制冷
    ELSE
        _eTgtSeason := E_DL_SmsSeason.eTrans;            // 目标季：过渡
    END_IF
END_IF
rtReset(CLK := bReset);              // 复位沿（每拍必调）
tonHyst(IN := (_eState = E_DL_SmsState.eChgWait), PT := tHyst);  // 滞回窗（确认相独占）

(* —— 段 1：单拍量预清零（锁存量 _bFault/_uFault 不入清单，禁同拍抹除） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 2：复位沿 + 域闸锁存（判据当拍量） —— *)
IF rtReset.Q THEN                   // rtReset.Q = 当拍量
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;        // 清故障锁存码
END_IF
IF _bBmpOvl THEN                    // 位图交叠（当拍量，静态组态错）
    _uFault := 16#0005_0382;        // 故障级：位图交叠锁存
    _bFault := TRUE;                // 故障标志与码位配对（R45）
END_IF
IF _bMonthBad THEN                  // 月值越界（当拍量）
    _uFault := 16#0005_0383;        // 故障级：月值越界锁存
    _bFault := TRUE;
END_IF
IF TIME_TO_DINT(tHyst) <= 0 THEN    // 滞回窗域闸（当拍量）
    _uFault := 16#0005_0384;        // 故障级：组态非法（归并 0384，码表声明）
    _bFault := TRUE;
END_IF

(* —— 段 3：故障解除式（R240 落地，逐 BOOL 标注）：
     rtReset.Q = 当拍量；NOT _bBmpOvl = 当拍量；NOT _bMonthBad = 当拍量。
     均不含锁存量（_bFault/_uFault），解除边真实可达（组态修正 + 月值恢复 + 复位沿）。 —— *)
IF rtReset.Q AND (NOT _bBmpOvl) AND (NOT _bMonthBad) THEN
    _bFault := FALSE;               // 清故障锁存位（锁存量，仅此当拍量解除沿可清）
    _uFault := 16#0000_0000;        // 清故障锁存码（锁存量，仅本当拍量解除沿可清）
    IF _eState = E_DL_SmsState.eFault THEN
        _eState := E_DL_SmsState.eIdle;     // 故障相迁出：回稳态
    END_IF
END_IF

(* —— 段 4：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_SmsState.eIdle:
    IF (NOT _bFault) AND (_eTgtSeason <> _eSeason) THEN
        _eState := E_DL_SmsState.eChgWait;      // 目标季变更：进切换确认相
    END_IF

E_DL_SmsState.eChgWait:
    IF tonHyst.Q THEN                           // 出口 1：滞回窗满（事件量）
        CASE _eTgtSeason OF                     // 切换提交拍按目标季发信息沿（码表声明逐分支对齐）
            E_DL_SmsSeason.eHeat:
                _uInfo := 16#0005_04AA;         // 信息级：切换至供暖季沿
            E_DL_SmsSeason.eCool:
                _uInfo := 16#0005_04AB;         // 信息级：切换至制冷季沿
            E_DL_SmsSeason.eTrans:
                _uInfo := 16#0005_04AC;         // 信息级：进入过渡季沿
        END_CASE
        _eSeason := _eTgtSeason;                // 提交切换（锁存量级提交）
        _eState := E_DL_SmsState.eIdle;         // 回稳态相
    ELSIF _eTgtSeason = _eSeason THEN           // 出口 2：目标季回撤（前置条件消失，R98 双出口）
        _eState := E_DL_SmsState.eIdle;         // 取消切换：回稳态相
    END_IF

E_DL_SmsState.eFault:
    ;                                           // 故障相：季节出口冻结当前季（头注释②声明）
    (* 解除迁出在段 3 承载 *)

ELSE
    _uFault := 16#0005_0384;                // 故障级：非法相位兜底
    _bFault := TRUE;
    _eState := E_DL_SmsState.eFault;        // 强制回故障相

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
IF (_eSeason = E_DL_SmsSeason.eHeat) AND (NOT _bFault) THEN
    bHeatDemand := TRUE;            // 供暖需求（电平）
ELSE
    bHeatDemand := FALSE;           // 非供暖季强制 FALSE
END_IF
IF (_eSeason = E_DL_SmsSeason.eCool) AND (NOT _bFault) THEN
    bCoolDemand := TRUE;            // 制冷需求（电平）
ELSE
    bCoolDemand := FALSE;           // 非制冷季强制 FALSE
END_IF
IF _bFault THEN
    nErrId := _uFault;              // 故障锁存码回放
ELSE
    nErrId := _uInfo;               // 信息码
END_IF
bError := _bFault;                  // 故障标志与锁存位同源
eSeason := _eSeason;                // 季节出口单点映射
eState := _eState;                  // 相位出口单点映射

END_FUNCTION_BLOCK
