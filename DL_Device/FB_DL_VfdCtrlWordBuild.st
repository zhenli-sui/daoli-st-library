(*
  道莅工业代码库 | DL_Device | FB_DL_VfdCtrlWordBuild
  版本: 1.0.0 | 日期: 2026-11-23 | 轮次: R75
  开源溯源: brOscatLib (github.com/brOscatLib) / MIT / 借鉴 CtrlWordBuild 的语义，代码为 clean-room 重写
  功能: 变频器控制字编码——目标状态号（bit0..3）+ 命令位（运行/自由停车/直流
        制动/快速停止/反转/复位脉冲）按固定位图组装控制字；与 FB_DL_VfdStateWordMatch
        成对（编码/判码）。变换型 FB：无相位机，每拍独立全量重算。
  兼容性: CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop；仅依赖标准 R_TRIG，零厂商私有库
  接口: 输入 bEn/uStateNo（0..15，越界钳 15 并置信息码）/六命令位；输出
        wCtrlWord/uStateEff（钳位后状态号）/bRangeInfo/bError/nErrId。
  位图定义（bit0..3 = 目标状态号，与 C04 判码件低 4 位状态号口径一致）:
    bit4 = 运行命令 bRunCmd            bit5 = 非自由停车（1=斜坡停车可用）
    bit6 = 直流制动 bDCBrake           bit7 = 复位脉冲（R_TRIG 单拍）
    bit11 = 反转 bReverse              bit13 = 快速停止 bQuickStop
  码表: 16#0003_040F 信息级：目标状态号越域钳 15（每拍重算，非锁存）
        码段说明：0003 段信息子带 04xx，槽位经全库实扫空闲。
  边界: ① uStateNo > 15 → 钳 15 + bRangeInfo（本件无故障级路径，bError 恒 FALSE）；
        ② bit7 复位脉冲由 R_TRIG 单拍化（不复位脉冲不驻留控制字）；
        ③ bEn = FALSE 时控制字输出 16#0000（全零安全侧）；
        ④ R_TRIG 段 0 无条件周期刷新；⑤ 零全局耦合。
  邻件比对: StatusWordSegDecoder（通用分段译码 vs 本件变频器控制字编码组装）。
  修订历史: 2026-11-23 v1.0.0 R75 首版（复杂件批 B2 · C10）
*)

FUNCTION_BLOCK FB_DL_VfdCtrlWordBuild
VAR_INPUT
    bEn         : BOOL := FALSE;    // 编码使能（FALSE 输出全零控制字）[-] | Build enable, FALSE outputs zero word
    uStateNo    : UINT := 0;        // 目标状态号，域 [0, 15]，越界钳 15 [号] | Target state number, clamped to 15
    bRunCmd     : BOOL := FALSE;    // 运行命令（bit4）[-] | Run command bit
    bCoastStop  : BOOL := FALSE;    // 自由停车选择（TRUE 时 bit5=0）[-] | Coast stop select, TRUE clears bit5
    bDCBrake    : BOOL := FALSE;    // 直流制动（bit6）[-] | DC brake bit
    bQuickStop  : BOOL := FALSE;    // 快速停止（bit13）[-] | Quick stop bit
    bReverse    : BOOL := FALSE;    // 反转（bit11）[-] | Reverse bit
    bResetCmd   : BOOL := FALSE;    // 故障复位命令（bit7，沿触发单拍）[-] | Fault reset command, edge one-shot
END_VAR
VAR_OUTPUT
    wCtrlWord  : WORD;              // 组装控制字出口（bEn=FALSE 时全零）[-] | Built control word outlet
    uStateEff  : UINT;              // 钳位后状态号出口 [号] | Clamped state number outlet
    bRangeInfo : BOOL;              // 状态号越域钳位当拍信息 [-] | Range clamp info this scan
    bError     : BOOL;              // 故障标志（本件无故障路径，恒 FALSE）[-] | Error flag, no fault paths
    nErrId     : UDINT;             // 事件码，0 = 无事件 | Event code, 0 = none
END_VAR
VAR
    _uStateEff : UINT := 0;         // 钳位状态号内部镜像 [号] | Clamped state number mirror
    _wOut      : WORD := 16#0000;   // 组装暂存字 [-] | Build staging word
    _bRange    : BOOL;              // 越域当拍量 [-] | Range violation this scan
    rtResetCmd : R_TRIG;            // 复位脉冲沿实例，段 0 无条件刷新 | Reset pulse edge instance
END_VAR

(* —— 段 0：沿实例无条件周期刷新（R7 红线） —— *)
rtResetCmd(CLK := bResetCmd);                 // 复位脉冲沿每拍必调 / Reset pulse edge every scan

(* —— 段 1：状态号钳位（越域置当拍信息量） —— *)
_uStateEff := uStateNo;                       // 状态号暂存 / State number staging
_bRange := FALSE;                             // 越域当拍量预清 / Range flag preset
IF _uStateEff > 15 THEN
    _uStateEff := 15;                         // 越域钳 15 / Clamp to 15
    _bRange := TRUE;                          // 置越域信息量 / Set range info
END_IF

(* —— 段 2：控制字位图组装（bit0..3 状态号） —— *)
_wOut := INT_TO_WORD(UINT_TO_INT(_uStateEff)) AND 16#000F;    // 状态号入低 4 位（掩码兜底）/ State number to low nibble
IF bRunCmd THEN
    _wOut := _wOut OR 16#0010;                // bit4 运行命令 / Run command bit
END_IF
IF NOT bCoastStop THEN
    _wOut := _wOut OR 16#0020;                // bit5 斜坡停车可用（非自由停车）/ Ramp stop available bit
END_IF
IF bDCBrake THEN
    _wOut := _wOut OR 16#0040;                // bit6 直流制动 / DC brake bit
END_IF
IF rtResetCmd.Q THEN
    _wOut := _wOut OR 16#0080;                // bit7 复位脉冲（仅沿当拍驻留）/ Reset pulse bit, one scan only
END_IF
IF bReverse THEN
    _wOut := _wOut OR 16#0800;                // bit11 反转 / Reverse bit
END_IF
IF bQuickStop THEN
    _wOut := _wOut OR 16#2000;                // bit13 快速停止 / Quick stop bit
END_IF

(* —— 段 3：出口单点映射（名实同源；信息码每拍重算） —— *)
IF bEn THEN
    wCtrlWord := _wOut;                       // 使能输出组装字 / Enabled, output built word
ELSE
    wCtrlWord := 16#0000;                     // 未使能输出全零（安全侧） / Disabled, output zero word
END_IF
uStateEff := _uStateEff;                      // 钳位状态号出口 / Clamped state outlet
bRangeInfo := _bRange;                        // 越域信息出口 / Range info outlet
bError := FALSE;                              // 本件无故障级路径（头注释声明）/ No fault paths by design
IF _bRange THEN
    nErrId := 16#0003_040F;                   // 信息级：状态号越域钳位 / Info: state number clamped
ELSE
    nErrId := 16#0000_0000;                   // 无事件 / No event
END_IF

END_FUNCTION_BLOCK
