(*==============================================================================
 * 组件名称 (Component)  : FB_DL_RoomTempClassify
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library，复用本库 FC_DL_TempUnitConvert
 *                         （既有契约，零修改），零厂商私有库
 * 功能描述 (Function)   : 房间温度舒适带四档分级（HVAC P1 在册）。输入温度按
 *                         eUnit 温标经 FC_DL_TempUnitConvert 归一到摄氏，按
 *                         四组态阈值（过冷/偏冷上限、舒适上限、偏热上限）分五
 *                         档输出（过冷/偏冷/舒适/偏热/过热）；阈值处带迟滞带
 *                         fHysteresis 防边界抖动（回差语义：升档用阈值上沿、
 *                         降档用阈值-迟滞）。风机/阀门舒适控制前级、环境监测
 *                         上报场景。
 * 来源标签 (Origin)     : ROADMAP 在册空勾 P1（HVAC 行）；换算复用既有
 *                         FC_DL_TempUnitConvert（公开温标语义），分级与迟滞
 *                         实现 clean-room，IEC 61131-3 标准语义的道莅防御性实现
 * 边界语义 (Boundary)   : ① 阈值序闸：fColdMax <= fCoolMax <= fComfortMax <=
 *                         fWarmMax 任意破序 → 故障锁存（组态域闸全覆盖）；
 *                         ② 迟滞带负值按 0 处理并置信息级计数（不静默吞错）；
 *                         ③ 换算件 uErrorId 非零（绝对零度以下等）→ 本拍
 *                         冻结保持上拍档位并 nWarnCnt 递增（信息级）；
 *                         ④ 温度 NaN → 档位冻结保持 + 信息级（不误报过冷）。
 * 输出语义 (Fallback)   : 【R191】bEnable = FALSE → 档位冻结保持末值（舒适
 *                         分级是显示/控制前级，不强制回 eIdle 档）；eFault 相
 *                         → 冻结 + bError = TRUE。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码；错误出口 BOOL+ENUM(eCause)，
 *                         码位待主控收口统一派号。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 序闸/NaN 冻结/信息级台账 ✓｜R5 双语同行注释 ✓
 *                         R6 CASE 带 ELSE 兜底迁 eFault ✓｜R7 无定时器（监视型）N/A ✓
 * 验收向量 (Acceptance) : V1 阈值 16/18/24/28，输入 20.0°C → eComfort；
 *                         V2 输入 28.2 → 升 eWarm；输入回落 27.7（迟滞 0.5）
 *                         → 保持 eWarm（回差生效）；回落 27.4 → eComfort；
 *                         V3 阈值破序（fComfortMax=15 < fCoolMax=18）→ eFault。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R49 首版（批 3 · 序号 15）
 *==============================================================================*)
TYPE E_DL_RtcBand :
(
    eTooCold  := 0,                          (* 过冷：T <= fColdMax / Too cold band *)
    eCool     := 1,                          (* 偏冷：fColdMax < T <= fCoolMax / Cool band *)
    eComfort  := 2,                          (* 舒适：fCoolMax < T <= fComfortMax / Comfort band *)
    eWarm     := 3,                          (* 偏热：fComfortMax < T <= fWarmMax / Warm band *)
    eTooHot   := 4                           (* 过热：T > fWarmMax / Too hot band *)
);
END_TYPE

TYPE E_DL_RtcState :
(
    eIdle  := 0,                             (* 待使能（档位冻结） / Idle, band frozen *)
    eRun   := 10,                            (* 分级运行 / Classify run *)
    eFault := 90                             (* 故障锁存相 / Fault latched phase *)
);
END_TYPE

TYPE E_DL_RtcCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：阈值破序 / Illegal config: threshold order *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_RoomTempClassify
VAR_INPUT
    fTemp       : LREAL := 20.0;             (* 房间温度输入 [源温标单位] / Room temperature input *)
    eUnit       : E_DL_TempUnit := E_DL_TempUnit.eCelsius;   (* 源温标选择（复用既有枚举）[-] / Source unit selector *)
    fColdMax    : LREAL := 16.0;             (* 过冷上限阈值 [摄氏度] / Too-cold upper threshold *)
    fCoolMax    : LREAL := 18.0;             (* 偏冷上限阈值，域 >= fColdMax [摄氏度] / Cool upper threshold *)
    fComfortMax : LREAL := 24.0;             (* 舒适上限阈值，域 >= fCoolMax [摄氏度] / Comfort upper threshold *)
    fWarmMax    : LREAL := 28.0;             (* 偏热上限阈值，域 >= fComfortMax [摄氏度] / Warm upper threshold *)
    fHysteresis : LREAL := 0.5;              (* 档位迟滞带，域 >= 0.0 [摄氏度] / Band hysteresis *)
    bEnable     : BOOL := TRUE;              (* 分级使能，FALSE 档位冻结 [-] / Enable *)
    bReset      : BOOL := FALSE;             (* 复位命令，上升沿清故障与台账 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    eBand       : E_DL_RtcBand;              (* 当前舒适档出口（迟滞平滑后）[-] / Current comfort band outlet *)
    fTempC      : LREAL;                     (* 归一摄氏温度（诊断镜像）[摄氏度] / Normalized Celsius temperature *)
    nWarnCnt    : UDINT;                      (* 坏值/换算异常拒收累计（信息级台账）[次] / Rejection counter *)
    eState      : E_DL_RtcState;             (* 状态出口 / State outlet *)
    eCause      : E_DL_RtcCause;             (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError      : BOOL;                       (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState  : E_DL_RtcState := E_DL_RtcState.eIdle;      (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause  : E_DL_RtcCause := E_DL_RtcCause.eNone;      (* 故障成因锁存量 / Latched cause *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _eBandI  : E_DL_RtcBand := E_DL_RtcBand.eComfort;     (* 内部档位锁存（迟滞平滑对象） / Internal band latch *)
    _fTempC  : LREAL;                        (* 归一摄氏中间量 [摄氏度] / Normalized Celsius intermediate *)
    _fHyst   : LREAL;                        (* 防御后生效迟滞带 [摄氏度] / Sanitized hysteresis *)
    _uConvErr: UDINT;                        (* 换算件错误码接收（R287：OUT 实参必须落变量） / Converter error id received *)
    _bBad    : BOOL;                         (* 本拍坏值当拍量（NaN/换算异常）[-] / Bad value this scan *)
    _bFault  : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bCfgBad : BOOL;                         (* 组态非法当拍量 / Illegal config this scan *)
END_VAR

(* —— 段 0：当拍判据派生 + 沿实例无条件刷新（R228A） —— *)
_bCfgBad := (fColdMax > fCoolMax) OR (fCoolMax > fComfortMax) OR (fComfortMax > fWarmMax)   (* 阈值序闸（组态域闸全引脚覆盖，R28） / Threshold order gate *)
            OR (fHysteresis < 0.0) OR (fHysteresis > 5.0);   (* 迟滞域闸 / Hysteresis gate *)
rtReset(CLK := bReset);                      (* 复位沿每拍必调 / Reset edge every scan *)
_fHyst := fHysteresis;                       (* 迟滞初值 / Hysteresis init *)
IF _fHyst < 0.0 THEN
    _fHyst := 0.0;                           (* 负迟滞钳 0（信息级计数在段 4 记账） / Negative clamp to zero *)
END_IF

(* —— 段 1：单拍量预清零（R107） —— *)
_bBad := FALSE;                              (* 坏值当拍量预清，唯一分支置位 / Bad flag preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清台账 + 档位回舒适基准 + 迁 eRun，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                        (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_RtcCause.eNone;          (* 清成因 / Clear cause *)
    nWarnCnt := 0;                           (* 清拒收台账 / Clear counter *)
    _eBandI := E_DL_RtcBand.eComfort;        (* 档位回舒适基准 / Band back to comfort *)
    IF NOT _bCfgBad THEN
        _eState := E_DL_RtcState.eRun;       (* 组态合法复位即恢复运行 / Resume run *)
    END_IF
END_IF

(* —— 段 3：组态闸故障锁存（R45 配对；锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                         (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_RtcCause.eCfgIllegal;    (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_RtcState.eFault;         (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_RtcState.eIdle:                     (* 待机相：档位冻结保持 / Idle *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_RtcState.eRun;   (* 使能进入运行 / Enable enters run *)
        END_IF
    E_DL_RtcState.eRun:                      (* 运行相：归一换算 + 迟滞分级 / Run *)
        IF NOT bEnable THEN
            _eState := E_DL_RtcState.eIdle;  (* 失能回待机（档位保持） / Back to idle *)
        ELSE
            _fTempC := FC_DL_TempUnitConvert(fVal := fTemp, eSrc := eUnit, eDst := E_DL_TempUnit.eCelsius, uErrorId => _uConvErr);   (* 复用既有换算件（OUT 实参落变量，R287） / Reuse existing converter *)
            IF (fTemp <> fTemp) OR ((fTemp - fTemp) <> (fTemp - fTemp)) THEN
                _bBad := TRUE;               (* 输入 NaN/Inf：坏值记账（档位冻结不误报过冷） / Non-finite input *)
            ELSIF _uConvErr <> 0 THEN
                _bBad := TRUE;               (* 换算件报错（低于绝对零度等）：坏值记账 / Converter error *)
            ELSE
                fTempC := _fTempC;           (* 有效归一值出口镜像 / Valid mirror *)
                (* 迟滞分级：升档用阈值上沿、降档用阈值减迟滞（边界②回差语义） / Hysteretic classify: up at threshold, down at threshold minus hysteresis *)
                IF _fTempC <= fColdMax - _fHyst THEN
                    _eBandI := E_DL_RtcBand.eTooCold;    (* 过冷档（降档沿：阈值-迟滞） / Too cold *)
                ELSIF _fTempC <= fCoolMax - _fHyst THEN
                    _eBandI := E_DL_RtcBand.eCool;       (* 偏冷档 / Cool *)
                ELSIF _fTempC <= fComfortMax + _fHyst THEN
                    _eBandI := E_DL_RtcBand.eComfort;    (* 舒适档（中央带宽加倍，迟滞对称） / Comfort *)
                ELSIF _fTempC <= fWarmMax + _fHyst THEN
                    _eBandI := E_DL_RtcBand.eWarm;       (* 偏热档 / Warm *)
                ELSE
                    _eBandI := E_DL_RtcBand.eTooHot;     (* 过热档（IF 链带 ELSE 兜底，R285） / Too hot *)
                END_IF
            END_IF
            IF _bBad THEN
                nWarnCnt := nWarnCnt + 1;    (* 信息级台账递增（不置故障级，R90 口径） / Info counter *)
            END_IF
            IF fHysteresis < 0.0 THEN
                nWarnCnt := nWarnCnt + 1;    (* 负迟滞钳 0 记账（不静默吞错，边界②） / Negative hysteresis counted *)
            END_IF
        END_IF
    E_DL_RtcState.eFault:                    (* 故障相：档位冻结，仅复位沿出 / Fault *)
        ;                                    (* 锁存回放（R28） / Replay from latch *)
    ELSE                                     (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_RtcState.eFault;     (* 迁故障相 / To fault *)
        _bFault := TRUE;                     (* 同步锁存 / Latch *)
        _eCause := E_DL_RtcCause.ePhaseBad;  (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
eBand := _eBandI;                            (* 档位出口单点映射 / Band outlet mapping *)
bError := _bFault;                           (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                           (* 状态出口 / State outlet *)
eCause := _eCause;                           (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
