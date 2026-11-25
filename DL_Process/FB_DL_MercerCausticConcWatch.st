(*
  Name: FB_DL_MercerCausticConcWatch
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 间歇式溢流染色与丝光整理，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 丝光碱浓度双向监视，超限判据各自去抖后锁存：
           低于 fConcLoGpl 进低浓相并置补碱请求（xMakeupReq），丝光不足会导致纤维膨化不够；
           高于 fConcHiGpl 进高浓相并置稀释请求（xDiluteReq），碱浓过高会损伤纤维并增加中和负荷。
        2) 连续失效计数：每次「去抖确认的越限」使 nFailCount 加一，回到带内即清零；
           计数达到 fFailMax（INT 引脚）时升级为故障锁存（码 0415）——
           这是「反复越限、补液联动无效」的累积证据，比单次越限更值得停机处理。
        3) 三级语义：带内正常（信息级码 0414）→ 越限锁存（故障级 0412 / 0413）→ 累计失效（0415）。
           任一故障级锁存均不直接停设备，由上层决定是否停止进布（本件只监视不驱动工艺阀）。
  边界条件：1) 非有限值闸：浓度与两个阈值先过 NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf；
           命中即锁码 0417 进故障相 —— 绝不把 NaN 拿去与浓度阈比较
           （NaN 比较恒假会把「碱浓电极断线」伪装成「浓度正常」，R19）。
        2) 阈值域闸：须满足 0.0 < fConcLoGpl < fConcHiGpl <= DL_CONC_HI，越域锁码 0417
           （两级判据重叠会让某向永不触发）；tDebounce 必须 > T#0S（零窗使判据无滞后直达停机）。
        3) 计数域闸：fFailMax 必须 >= 1（为 0 会使累计判据恒真，一上电就报 0415）。
        4) 浓度量级闸：实测浓度须落在 [0.0, DL_CONC_HI] 内，越域锁码 0417（电极标定丢失）。
        5) 定时器周期刷新（R7）：两个去抖 TON 与复位边沿全部在 CASE 之外无条件调用。
        6) 故障解除路径：低浓/高浓相内 xReset 上升沿即清锁存回正常（可达）；
           故障相内还必须同时满足 NOT xFault 且入参/组态合法才可解除（不自恢复）。
        7) 状态机兜底：CASE 全态覆盖 + ELSE 强制回故障相并置码 0418、清全部输出。
        8) 输出安全初值（R25）：两个报警位、两个请求位初值 FALSE，nFailCount 初值 0，
           正常相显式赋值，防「上电未初始化直穿」。
  量纲自证：fConcGpl 与 fConcLoGpl / fConcHiGpl 全为质量浓度 [g/L]，比较两侧同量纲；
           nFailCount / fFailMax 为计数 [count]，无因次。
  码表 Error codes（本件子带 0091_041x，故障级一律 3 行内置 _uFault/_bFault/_eState）:
    16#0091_0411 信息级：碱浓度接近下限，尚在去抖窗内（不置故障位）
    16#0091_0412 故障级：碱浓度低于下限（去抖确认，请求补碱）
    16#0091_0413 故障级：碱浓度高于上限（去抖确认，请求稀释）
    16#0091_0414 信息级：碱浓度在工艺带内（不置故障位）
    16#0091_0415 故障级：连续失效计数达上限（补液联动无效）
    16#0091_0416 故障级：外部故障输入 xFault
    16#0091_0417 故障级：入参非有限，或阈值/计数/去抖窗组态越域
    16#0091_0418 故障级：状态机落 ELSE 兜底（非法相位 ID）

  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

TYPE E_DL_JbsCausticConcState :
(
    eJbsConcNormal := 0,    // 正常：浓度在工艺带内 / Normal, concentration within the process band
    eJbsConcLow    := 10,   // 低浓：去抖确认后锁存，请求补碱 / Low, latched after debounce, make-up requested
    eJbsConcHigh   := 20,   // 高浓：去抖确认后锁存，请求稀释 / High, latched after debounce, dilution requested
    eJbsConcFault  := 90    // 故障：入参/组态非法或累计失效，锁存待解除 / Fault, invalid input or repeated failures
);
END_TYPE

FUNCTION_BLOCK FB_DL_MercerCausticConcWatch
VAR_INPUT
    xEnable      : BOOL;    // 监视使能 [bool] / Monitoring enable [bool]
    xReset       : BOOL;    // 报警/故障复位（上升沿有效）[bool] / Alarm and fault reset, rising edge [bool]
    xFault       : BOOL;    // 外部故障汇总 [bool] / External fault aggregate [bool]
    fConcGpl     : REAL;    // 实测碱质量浓度 [g/L] / Measured caustic concentration [g/L]
    fConcLoGpl   : REAL;    // 浓度工艺下限 [g/L] / Concentration process low limit [g/L]
    fConcHiGpl   : REAL;    // 浓度工艺上限 [g/L] / Concentration process high limit [g/L]
    tDebounce    : TIME;    // 判据去抖窗 [TIME] / Criteria debounce window [TIME]
    fFailMax     : INT;     // 连续失效计数上限 [count] / Consecutive failure count limit [count]
END_VAR
VAR_OUTPUT
    xLowAlarm    : BOOL;    // 低浓报警（锁存）[bool] / Low concentration alarm, latched [bool]
    xHighAlarm   : BOOL;    // 高浓报警（锁存）[bool] / High concentration alarm, latched [bool]
    xMakeupReq   : BOOL;    // 补碱（补液）联动请求 [bool] / Caustic make-up request [bool]
    xDiluteReq   : BOOL;    // 稀释（补水）联动请求 [bool] / Dilution water request [bool]
    nFailCount   : INT;     // 连续失效计数 [count] / Consecutive failure count [count]
    eState       : E_DL_JbsCausticConcState;   // 状态出口，段尾单点映射 / State outlet, single-point mapped
    nErrId       : UDINT;   // 事件码，0 = 无事件 / Event code, 0 = none
END_VAR
VAR
    tonLow       : TON;     // 低浓去抖定时 [TIME] / Low concentration debounce timer
    tonHigh      : TON;     // 高浓去抖定时 [TIME] / High concentration debounce timer
    rtReset      : R_TRIG;  // 复位上升沿检测 [bool] / Reset rising edge detector
    _eState      : E_DL_JbsCausticConcState := E_DL_JbsCausticConcState.eJbsConcNormal;   // 内部相位（CASE 唯一写入目标）
    _iFailCnt    : INT := 0;        // 内部连续失效计数 [count] / Internal consecutive failure count [count]
    _bFinOk      : BOOL := FALSE;   // 实值入参有限性总闸结果 / Finiteness gate aggregate result
    _bCfgOk      : BOOL := FALSE;   // 阈值与计数组态域闸结果 / Threshold and count domain gate result
    _bLowRaw     : BOOL := FALSE;   // 低浓原始判据 [bool] / Raw low concentration criterion
    _bHighRaw    : BOOL := FALSE;   // 高浓原始判据 [bool] / Raw high concentration criterion
    _bLowL       : BOOL := FALSE;   // 低浓锁存位 [bool] / Latched low alarm flag
    _bHighL      : BOOL := FALSE;   // 高浓锁存位 [bool] / Latched high alarm flag
    _bFault      : BOOL := FALSE;   // 故障锁存位 [bool] / Latched fault flag
    _uInfo       : UDINT := 16#0000_0000;   // 信息码，每拍重算 / Info code, recomputed every cycle
    _uFault      : UDINT := 16#0000_0000;   // 故障码锁存 / Latched fault code
END_VAR
VAR CONSTANT
    DL_EPS       : REAL := 1.0E-9;      // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_BIG       : REAL := 1.0E12;      // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_CONC_HI   : REAL := 1000.0;      // 浓度量级闸上限 [g/L] / Concentration magnitude upper bound [g/L]
    DL_CNT_HI    : INT := 10000;        // 计数显示上限 [count] / Count display upper bound [count]
END_VAR

(* —— 段 0：单拍量预清零（锁存量 _uFault/_bFault/_bLowL/_bHighL/_iFailCnt 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;                     // 信息码每拍重算 / Info code recomputed
nErrId := 16#0000_0000;                     // 事件码缺省无事件 / Event code defaults to none

(* —— 段 1：非有限值闸与组态域闸（R19：不拿 NaN 去比较浓度阈） —— *)
_bFinOk := (fConcGpl > -DL_BIG) AND (fConcGpl < DL_BIG)
           AND (fConcLoGpl > -DL_BIG) AND (fConcLoGpl < DL_BIG)
           AND (fConcHiGpl > -DL_BIG) AND (fConcHiGpl < DL_BIG);
_bCfgOk := (fConcLoGpl > DL_EPS)                            // 下限必须为正
           AND (fConcHiGpl > fConcLoGpl)                     // 上限必须严格大于下限
           AND (fConcHiGpl <= DL_CONC_HI)                    // 上限须在量级闸内
           AND (fConcGpl >= 0.0) AND (fConcGpl <= DL_CONC_HI)   // 实测浓度量级闸
           AND (tDebounce > T#0S)                            // 去抖窗必须为正
           AND (fFailMax >= 1);                              // 计数上限至少为 1

(* —— 段 2：原始判据（取未钳制的实测浓度，禁先夹后判，R24） —— *)
_bLowRaw := _bFinOk AND _bCfgOk AND (fConcGpl < fConcLoGpl);             // 低浓原始判据
_bHighRaw := _bFinOk AND _bCfgOk AND (fConcGpl > fConcHiGpl);            // 高浓原始判据

(* —— 段 3：定时器与边沿无条件周期刷新（R7：调用语句不得置于 IF/CASE 内） —— *)
rtReset(CLK := xReset);                                                     // 复位上升沿，每拍必调
tonLow(IN := _bLowRaw AND (NOT _bFault), PT := tDebounce);                  // 低浓去抖
tonHigh(IN := _bHighRaw AND (NOT _bFault), PT := tDebounce);                // 高浓去抖

(* —— 段 4：全局故障拦截（优先级最高；已锁存则不再改写码值，禁同拍抹除） —— *)
IF xFault AND (NOT _bFault) THEN
    _uFault := 16#0091_0416;                // 故障级：外部故障输入
    _bFault := TRUE;                        // 锁存（3 行内置，R45 配对）
    _eState := E_DL_JbsCausticConcState.eJbsConcFault;
END_IF
IF ((NOT _bFinOk) OR (NOT _bCfgOk)) AND (NOT _bFault) THEN
    _uFault := 16#0091_0417;                // 故障级：入参非有限或组态越域（内部成员已分离）
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_JbsCausticConcState.eJbsConcFault;
END_IF

(* —— 段 5：相位机（只做迁移与锁存；出口在段 7 单点映射） —— *)
CASE _eState OF

E_DL_JbsCausticConcState.eJbsConcNormal:
    IF NOT xEnable THEN
        _uInfo := 16#0091_0414;             // 信息级：监视关闭，浓度保持上拍结论（不置故障位）
    ELSIF tonLow.Q THEN
        _uFault := 16#0091_0412;            // 故障级：碱浓度低于下限（去抖确认）
        _bLowL := TRUE;                     // 低浓锁存
        _iFailCnt := _iFailCnt + 1;         // 连续失效计数加一
        _eState := E_DL_JbsCausticConcState.eJbsConcLow;
    ELSIF tonHigh.Q THEN
        _uFault := 16#0091_0413;            // 故障级：碱浓度高于上限（去抖确认）
        _bHighL := TRUE;                    // 高浓锁存
        _iFailCnt := _iFailCnt + 1;         // 连续失效计数加一
        _eState := E_DL_JbsCausticConcState.eJbsConcHigh;
    ELSIF _bLowRaw THEN
        _uInfo := 16#0091_0411;             // 信息级：接近下限但尚在去抖窗内
    ELSE
        _uInfo := 16#0091_0414;             // 信息级：浓度合格
        _iFailCnt := 0;                     // 回到带内即清连续失效计数
    END_IF

E_DL_JbsCausticConcState.eJbsConcLow:
    IF _iFailCnt >= fFailMax THEN
        _uFault := 16#0091_0415;            // 故障级：连续失效计数达上限（联动无效）
        _bLowL := FALSE;                    // 低浓锁存升格为故障，避免双码并存
        _bFault := TRUE;                    // 故障锁存
        _eState := E_DL_JbsCausticConcState.eJbsConcFault;
    ELSIF rtReset.Q THEN
        _bLowL := FALSE;                    // 解除路径：复位上升沿（可达，R188）
        _uFault := 16#0000_0000;            // 清锁存码
        _eState := E_DL_JbsCausticConcState.eJbsConcNormal;
    ELSIF NOT _bLowRaw AND NOT _bHighRaw THEN
        _bLowL := FALSE;                    // 浓度自行回到带内：清锁存（保留计数供累计判据）
        _eState := E_DL_JbsCausticConcState.eJbsConcNormal;
    END_IF

E_DL_JbsCausticConcState.eJbsConcHigh:
    IF _iFailCnt >= fFailMax THEN
        _uFault := 16#0091_0415;            // 故障级：连续失效计数达上限（联动无效）
        _bHighL := FALSE;                   // 高浓锁存升格为故障，避免双码并存
        _bFault := TRUE;                    // 故障锁存
        _eState := E_DL_JbsCausticConcState.eJbsConcFault;
    ELSIF rtReset.Q THEN
        _bHighL := FALSE;                   // 解除路径：复位上升沿（可达，R188）
        _uFault := 16#0000_0000;            // 清锁存码
        _eState := E_DL_JbsCausticConcState.eJbsConcNormal;
    ELSIF NOT _bLowRaw AND NOT _bHighRaw THEN
        _bHighL := FALSE;                   // 浓度自行回到带内：清锁存（保留计数供累计判据）
        _eState := E_DL_JbsCausticConcState.eJbsConcNormal;
    END_IF

E_DL_JbsCausticConcState.eJbsConcFault:
    IF rtReset.Q AND (NOT xFault) AND _bFinOk AND _bCfgOk THEN
        _bFault := FALSE;                   // 解除路径：复位沿 + 外部故障消失 + 入参/组态合法（可达，R188）
        _uFault := 16#0000_0000;            // 清锁存码
        _iFailCnt := 0;                     // 累计计数一并清（故障已人工确认）
        _eState := E_DL_JbsCausticConcState.eJbsConcNormal;
    END_IF

ELSE
    _uFault := 16#0091_0418;                // 故障级：非法相位 ID 兜底
    _bFault := TRUE;                        // 锁存
    _bLowL := FALSE;                        // 各级锁存清
    _bHighL := FALSE;
    _eState := E_DL_JbsCausticConcState.eJbsConcFault;        // 强制回故障相

END_CASE

(* —— 段 6：后置段（计数器域兜底：负值归零、越上限钳制，防整型溢出） —— *)
IF _iFailCnt < 0 THEN
    _iFailCnt := 0;                         // 负计数属异常，归零
END_IF
IF _iFailCnt > DL_CNT_HI THEN
    _iFailCnt := DL_CNT_HI;                 // 越上限钳制
END_IF

(* —— 段 7：出口单点映射（名实同源；请求位由状态导出，故障侧全清） —— *)
xLowAlarm := _bLowL AND (NOT _bFault);                                     // 低浓报警出口
xHighAlarm := _bHighL AND (NOT _bFault);                                   // 高浓报警出口
xMakeupReq := (_eState = E_DL_JbsCausticConcState.eJbsConcLow) AND (NOT _bFault);    // 补碱请求
xDiluteReq := (_eState = E_DL_JbsCausticConcState.eJbsConcHigh) AND (NOT _bFault);   // 稀释请求
nFailCount := _iFailCnt;                                                   // 计数出口
eState := _eState;                                                         // 状态出口单点映射
IF _bFault OR _bLowL OR _bHighL THEN
    nErrId := _uFault;                      // 故障码锁存回放（不在故障相按当下输入重推断）
ELSE
    nErrId := _uInfo;                       // 信息码
END_IF

END_FUNCTION_BLOCK
