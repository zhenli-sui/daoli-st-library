(*
  Name: FB_DL_RoMembraneFlushSeq
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 RO/NF 膜法水处理，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) RO 停机冲洗序状态机，五相推进：待机 → 低压冲洗 → 浸泡 → 排放 → 完成。
           待机相等待 xStart 上升沿（必须边沿，防止上电即在启动位自动启动）；
           低压冲洗相开冲洗阀与浓水阀，按 tFlushS 定时并以冲洗流量监督为前置放行条件；
           浸泡相全阀关闭让药液/水在膜面停留 tSoakS；排放相只开浓水阀排空残液 DL_DRAIN_S；
           完成相置 xDone 并保持，直到 xStart 撤下才回待机（为下一次冲洗重新武装边沿）。
        2) 每相独立超时 + 整序总超时：相定时器给出正常推进点，相超时定时器给出
           「定时 + DL_OVER_MARGIN」的越限点，整序总超时由 tonTotal 兜底，
           三者并发监视，任一命中立即进故障相并锁存码值。
        3) 低液位双语义：待机相低液位只拦启动并置信息级码（不置故障位，允许液位恢复后直接启动）；
           冲洗过程中低液位判故障（泵空转保护）。
  边界条件：1) 非有限值闸：冲洗流量入参过 NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf；
           命中即判流量监督不通过（_bFlowOk := FALSE），由流量宽限定时器升级为故障，
           绝不把 NaN 直接与 DL_FLOW_MIN 比较（NaN 比较恒假会伪装成「流量正常」，R19）。
        2) 时间参数零闸：tFlushS / tSoakS <= T#0S 时对应相定时器立即置 Q，等价于该相跳过；
           这是合法组态（调试用），不判无效，但语义在此声明，禁止下游按「必有停留」假设。
        3) 流量下限零闸：DL_FLOW_MIN > DL_EPS，且流量监督只在低压冲洗相生效（其余相无流量要求）。
        4) 饱和与钳制：冲洗流量不做数值钳制（只做比较，不参与运算），避免掩盖超量程故障；
           所有相迁移均以定时器 Q 位与状态量为门控，不以单拍布尔标志门控（R274）。
        5) 故障解除路径：故障相内 (NOT xStart) AND (NOT xFault) 成立即清锁存回待机；
           回待机后必须重新给 xStart 上升沿才能再启动（rtStart 已被清，不会自恢复）。
        6) 状态机兜底：CASE 全态覆盖 + ELSE 强制回故障相并清全部输出。
        7) FB 主体不使用 RETURN，统一单出口（跨平台可移植性）。
  量纲自证：fFlushFlowM3h 为体积流量 [m3/h]，仅与同量纲的 DL_FLOW_MIN [m3/h] 比较；
           tFlushS / tSoakS / DL_DRAIN_S / DL_OVER_MARGIN / DL_TOTAL_MAX 全部为 [TIME]，
           相超时点 = [TIME] + [TIME] = [TIME]，与 TON 的 PT 同量纲；
           本件不出现跨量纲相加（无功率/温度/压力混合运算）。
  码表 Error codes（本件格 0090_03xx，故障级一律 3 行内置 _uFault/_bFault/_eState）:
    16#0090_0301 信息级：低液位，禁止启动冲洗（不置故障位）
    16#0090_0302 故障级：低压冲洗相冲洗流量不足（宽限窗超时）
    16#0090_0303 故障级：低压冲洗相超时（定时已到但放行条件不满足）
    16#0090_0304 故障级：浸泡相超时
    16#0090_0305 故障级：排放相超时
    16#0090_0306 故障级：整序总超时
    16#0090_0307 故障级：外部故障输入 xFault
    16#0090_0308 故障级：冲洗过程中低液位（泵空转保护）
    16#0090_0309 故障级：状态机落 ELSE 兜底（非法相位 ID）

  修订历史 Revision :
    2026-11-25  v1.0.0  R90 首版
*)

TYPE E_DL_RoFlushState :
(
    eRoFlushIdle     := 0,    // 待机：等启动上升沿 / Idle, awaiting start rising edge
    eRoFlushLowPress := 10,   // 低压冲洗：冲洗阀 + 浓水阀开 / Low-pressure flush, both valves open
    eRoFlushSoak     := 20,   // 浸泡：全阀关闭保持 / Soak, all valves closed
    eRoFlushDrain    := 30,   // 排放：仅浓水阀开排空 / Drain, concentrate valve only
    eRoFlushDone     := 40,   // 完成：xDone 保持至撤令 / Done, held until start released
    eRoFlushFault    := 90    // 故障：锁存待解除 / Fault, latched awaiting release
);
END_TYPE

FUNCTION_BLOCK FB_DL_RoMembraneFlushSeq
VAR_INPUT
    xStart        : BOOL;    // 冲洗启动指令（上升沿有效）[bool] / Flush start command, edge triggered [bool]
    xFault        : BOOL;    // 外部故障汇总 [bool] / External fault aggregate [bool]
    xLowLevel     : BOOL;    // 水箱低液位开关 [bool] / Tank low level switch [bool]
    fFlushFlowM3h : REAL;    // 冲洗水实测体积流量 [m3/h] / Measured flush water flow [m3/h]
    tFlushS       : TIME;    // 低压冲洗设定时长 [TIME] / Low-pressure flush duration [TIME]
    tSoakS        : TIME;    // 浸泡设定时长 [TIME] / Soak duration [TIME]
END_VAR
VAR_OUTPUT
    xFlushValve   : BOOL;    // 冲洗进水阀指令（安全侧：故障时关）[bool] / Flush inlet valve command [bool]
    xBrineValve   : BOOL;    // 浓水排放阀指令（安全侧：故障时关）[bool] / Brine discharge valve command [bool]
    xDone         : BOOL;    // 冲洗完成保持位 [bool] / Flush complete held flag [bool]
    xBusy         : BOOL;    // 冲洗进行中 [bool] / Flush sequence busy [bool]
    xFlowOk       : BOOL;    // 冲洗流量监督通过 [bool] / Flush flow supervision passed [bool]
    eState        : E_DL_RoFlushState;   // 状态出口，段尾单点映射 / State outlet, single-point mapped
    nErrId        : UDINT;   // 事件码，0 = 无事件 / Event code, 0 = none
END_VAR
VAR
    tonFlush      : TON;     // 低压冲洗相正常定时 [TIME] / Low-pressure flush phase timer
    tonFlushOv    : TON;     // 低压冲洗相超时定时 [TIME] / Low-pressure flush overrun timer
    tonSoak       : TON;     // 浸泡相正常定时 [TIME] / Soak phase timer
    tonSoakOv     : TON;     // 浸泡相超时定时 [TIME] / Soak overrun timer
    tonDrain      : TON;     // 排放相正常定时 [TIME] / Drain phase timer
    tonDrainOv    : TON;     // 排放相超时定时 [TIME] / Drain overrun timer
    tonTotal      : TON;     // 整序总超时定时 [TIME] / Whole-sequence total timeout timer
    tonFlowG      : TON;     // 冲洗流量宽限定时 [TIME] / Flush flow grace timer
    rtStart       : R_TRIG;  // 启动上升沿检测 [bool] / Start rising edge detector
    _eState       : E_DL_RoFlushState := E_DL_RoFlushState.eRoFlushIdle;   // 内部相位（CASE 唯一写入目标）
    _eStatePrev   : E_DL_RoFlushState := E_DL_RoFlushState.eRoFlushIdle;   // 上一拍相位快照（周期末更新）
    _bFlowOk      : BOOL;    // 冲洗流量监督结果 [bool] / Flush flow supervision result [bool]
    _bActive      : BOOL;    // 序激活（三执行相之一）[bool] / Sequence active flag [bool]
    _bDoneL       : BOOL;    // 完成位锁存（跨相保持）[bool] / Done latch held across phases [bool]
    _bFault       : BOOL;    // 故障锁存位 [bool] / Latched fault flag [bool]
    _uInfo        : UDINT;   // 信息码，每拍重算 / Info code, recomputed every cycle
    _uFault       : UDINT;   // 故障码锁存 / Latched fault code
    _iPhaseChg    : INT;     // 本拍相位切换计数（观测用）[-] / Phase-change count this cycle [-]
END_VAR
VAR CONSTANT
    DL_EPS        : REAL := 1.0E-9;      // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_BIG        : REAL := 1.0E12;      // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_FLOW_MIN   : REAL := 0.50;        // 冲洗流量监督下限 [m3/h] / Flush flow supervision low [m3/h]
    DL_DRAIN_S    : TIME := T#20S;       // 排放相设定时长 [TIME] / Drain phase duration [TIME]
    DL_OVER_MARGIN: TIME := T#30S;       // 相超时相对正常定时的裕量 [TIME] / Phase overrun margin [TIME]
    DL_TOTAL_MAX  : TIME := T#2H;        // 整序总超时上限 [TIME] / Whole-sequence total timeout [TIME]
    DL_FLOW_GRACE : TIME := T#10S;       // 冲洗流量不足宽限窗 [TIME] / Flow-shortage grace window [TIME]
END_VAR

(* —— 段 0：单拍量预清零（锁存量 _uFault/_bFault/_bDoneL/_eStatePrev 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;                     // 信息码每拍重算 / Info code recomputed
_iPhaseChg := 0;                            // 相位切换计数每拍重算 / Phase-change counter recomputed
nErrId := 16#0000_0000;                     // 事件码缺省无事件 / Event code defaults to none

(* —— 段 1：非有限值闸（R19：流量不参与运算，但必须拦住 NaN 比较的伪装成真） —— *)
IF NOT (fFlushFlowM3h > -DL_BIG AND fFlushFlowM3h < DL_BIG) THEN
    _bFlowOk := FALSE;                      // 非有限一律判流量不通过（不是运算符，是安全侧）
ELSE
    _bFlowOk := (fFlushFlowM3h >= DL_FLOW_MIN);   // 与同量纲下限比较 [m3/h] vs [m3/h]
END_IF

(* —— 段 2：状态派生量（本拍相位为上一拍末值，标准 FB 周期语义） —— *)
_bActive := (_eState = E_DL_RoFlushState.eRoFlushLowPress)
            OR (_eState = E_DL_RoFlushState.eRoFlushSoak)
            OR (_eState = E_DL_RoFlushState.eRoFlushDrain);

(* —— 段 3：定时器与边沿无条件周期刷新（R7：调用语句不得置于 IF/CASE 内） —— *)
rtStart(CLK := xStart);                                                      // 启动上升沿，每拍必调
tonFlush(IN := (_eState = E_DL_RoFlushState.eRoFlushLowPress), PT := tFlushS);            // 冲洗相正常定时
tonFlushOv(IN := (_eState = E_DL_RoFlushState.eRoFlushLowPress),
           PT := tFlushS + DL_OVER_MARGIN);                                  // 冲洗相超时点 = 定时 + 裕量
tonSoak(IN := (_eState = E_DL_RoFlushState.eRoFlushSoak), PT := tSoakS);                  // 浸泡相正常定时
tonSoakOv(IN := (_eState = E_DL_RoFlushState.eRoFlushSoak),
          PT := tSoakS + DL_OVER_MARGIN);                                    // 浸泡相超时点
tonDrain(IN := (_eState = E_DL_RoFlushState.eRoFlushDrain), PT := DL_DRAIN_S);            // 排放相正常定时
tonDrainOv(IN := (_eState = E_DL_RoFlushState.eRoFlushDrain),
           PT := DL_DRAIN_S + DL_OVER_MARGIN);                               // 排放相超时点
tonTotal(IN := _bActive, PT := DL_TOTAL_MAX);                                // 整序总超时，自复位由相位驱动
tonFlowG(IN := (_eState = E_DL_RoFlushState.eRoFlushLowPress) AND (NOT _bFlowOk),
         PT := DL_FLOW_GRACE);                                               // 流量不足宽限窗

(* —— 段 4：全局故障拦截（优先级最高；已锁存则不再改写码值，禁同拍抹除） —— *)
IF xFault AND (NOT _bFault) THEN
    _uFault := 16#0090_0307;                // 故障级：外部故障输入
    _bFault := TRUE;                        // 锁存（3 行内置，R45 配对）
    _eState := E_DL_RoFlushState.eRoFlushFault;
END_IF
IF tonTotal.Q AND _bActive AND (NOT _bFault) THEN
    _uFault := 16#0090_0306;                // 故障级：整序总超时
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_RoFlushState.eRoFlushFault;
END_IF

(* —— 段 5：相位机（只做迁移；出口在段 7 单点映射） —— *)
CASE _eState OF

E_DL_RoFlushState.eRoFlushIdle:
    IF NOT xStart THEN
        _bDoneL := FALSE;                   // 撤令即清完成位，为下次冲洗重新武装
    ELSIF xLowLevel THEN
        _uInfo := 16#0090_0301;             // 信息级：低液位禁止启动（不置故障位）
    ELSIF rtStart.Q THEN
        _bDoneL := FALSE;                   // 新序开始：清完成位（迁移前一次性清）
        _eState := E_DL_RoFlushState.eRoFlushLowPress;   // 进低压冲洗相
    END_IF

E_DL_RoFlushState.eRoFlushLowPress:
    IF xLowLevel THEN
        _uFault := 16#0090_0308;            // 故障级：冲洗中低液位（泵空转保护）
        _bFault := TRUE;
        _eState := E_DL_RoFlushState.eRoFlushFault;
    ELSIF tonFlush.Q AND _bFlowOk THEN
        _eState := E_DL_RoFlushState.eRoFlushSoak;       // 本拍合法事件优先于超时迁移（R275）
    ELSIF tonFlowG.Q THEN
        _uFault := 16#0090_0302;            // 故障级：冲洗流量不足
        _bFault := TRUE;
        _eState := E_DL_RoFlushState.eRoFlushFault;
    ELSIF tonFlushOv.Q THEN
        _uFault := 16#0090_0303;            // 故障级：低压冲洗相超时
        _bFault := TRUE;
        _eState := E_DL_RoFlushState.eRoFlushFault;
    END_IF

E_DL_RoFlushState.eRoFlushSoak:
    IF xLowLevel THEN
        _uFault := 16#0090_0308;            // 故障级：浸泡中低液位
        _bFault := TRUE;
        _eState := E_DL_RoFlushState.eRoFlushFault;
    ELSIF tonSoak.Q THEN
        _eState := E_DL_RoFlushState.eRoFlushDrain;      // 浸泡到点：进排放相
    ELSIF tonSoakOv.Q THEN
        _uFault := 16#0090_0304;            // 故障级：浸泡相超时
        _bFault := TRUE;
        _eState := E_DL_RoFlushState.eRoFlushFault;
    END_IF

E_DL_RoFlushState.eRoFlushDrain:
    IF xLowLevel THEN
        _uFault := 16#0090_0308;            // 故障级：排放中低液位
        _bFault := TRUE;
        _eState := E_DL_RoFlushState.eRoFlushFault;
    ELSIF tonDrain.Q THEN
        _bDoneL := TRUE;                    // 完成位锁存（跨相保持，段 7 单点映射）
        _eState := E_DL_RoFlushState.eRoFlushDone;       // 进完成相
    ELSIF tonDrainOv.Q THEN
        _uFault := 16#0090_0305;            // 故障级：排放相超时
        _bFault := TRUE;
        _eState := E_DL_RoFlushState.eRoFlushFault;
    END_IF

E_DL_RoFlushState.eRoFlushDone:
    IF xFault THEN
        _uFault := 16#0090_0307;            // 故障级：完成后外部故障（段 4 已拦，此处兜底同码）
        _bFault := TRUE;
        _eState := E_DL_RoFlushState.eRoFlushFault;
    ELSIF NOT xStart THEN
        _bDoneL := FALSE;                   // 撤令：清完成位并回待机
        _eState := E_DL_RoFlushState.eRoFlushIdle;
    END_IF

E_DL_RoFlushState.eRoFlushFault:
    IF (NOT xStart) AND (NOT xFault) THEN
        _bFault := FALSE;                   // 解除路径：撤令 AND 外部故障消失（可达）
        _uFault := 16#0000_0000;            // 清锁存码
        _bDoneL := FALSE;                   // 完成位一并清，避免故障后误报完成
        _eState := E_DL_RoFlushState.eRoFlushIdle;       // 回待机，需新上升沿才可再启动
    END_IF

ELSE
    _uFault := 16#0090_0309;                // 故障级：非法相位 ID 兜底
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_RoFlushState.eRoFlushFault;          // 强制回故障相

END_CASE

(* —— 段 6：后置段（R23：相位切换后的清计数与快照统一放在迁移判断之后） —— *)
IF _eState <> _eStatePrev THEN
    _iPhaseChg := _iPhaseChg + 1;           // 相位已切换：记一拍切换事件（观测用）
END_IF
_eStatePrev := _eState;                     // 快照在周期末尾统一更新，禁跨相重试预算不清零

(* —— 段 7：出口单点映射（名实同源；阀门由状态导出，不在多分支各写一遍，故障侧一律关） —— *)
xFlushValve := (_eState = E_DL_RoFlushState.eRoFlushLowPress) AND (NOT _bFault);      // 仅冲洗相开
xBrineValve := ((_eState = E_DL_RoFlushState.eRoFlushLowPress)
                OR (_eState = E_DL_RoFlushState.eRoFlushDrain)) AND (NOT _bFault);    // 冲洗/排放相开
xDone := _bDoneL AND (NOT _bFault);                                                      // 完成位出口
xBusy := _bActive AND (NOT _bFault);                                                     // 进行中出口
xFlowOk := _bFlowOk;                                                                     // 流量监督出口
eState := _eState;                                                                       // 状态出口单点映射
IF _bFault THEN
    nErrId := _uFault;                      // 故障锁存码回放（不在故障相按当下输入重推断）
ELSE
    nErrId := _uInfo;                       // 信息码
END_IF

END_FUNCTION_BLOCK
