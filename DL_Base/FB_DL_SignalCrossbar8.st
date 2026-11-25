// FB_DL_SignalCrossbar8 v1.0.0
// 开源溯源：self-cleanroom / 信号路由族
(*
  道莅工业代码库 | DL_Base | FB_DL_SignalCrossbar8
  版本: 1.0.0 | 日期: 2026-11-23 | 轮次: R75
  功能: 8×8 信号交叉开关矩阵：8 路输入经路由表任意分配至 8 路输出
        （每输出独立选源 0..8，0=无源置零），同源多投允许（广播路由）
  邻件关系: 与 Mux2Ex / Mux4Ex（单选多路器）同族 —— 差异点：多路器为
            单输出 N 选 1，本件为 8 输出各 9 选 1 全交叉矩阵（含广播），
            路由自由度扩展非同义替换
  路由契约: aRoute[j] = 输出 j 的源号（0=无源/1..8=输入号），每拍执行
            刷新；越界源号按无源处理并置组态码
*)
FUNCTION_BLOCK FB_DL_SignalCrossbar8
VAR_INPUT
    aIn     : ARRAY[1..8] OF REAL;               // 8 路输入 [工程单位] / 8 inputs
    aRoute  : ARRAY[1..8] OF INT;                // 路由表（输出 j 的源号 0..8）[1] / Route table, source per output
END_VAR
VAR_OUTPUT
    aOut       : ARRAY[1..8] OF REAL;            // 8 路输出 [工程单位] / 8 outputs
    aRouteEcho : ARRAY[1..8] OF INT;             // 生效路由回显（钳位后）[1] / Effective route echo
    bValid     : BOOL;                           // 组态有效回执 [-] / Config validity receipt
    bError     : BOOL;                           // 故障标志（任一路由越界）/ Fault flag (any route out of range)
    uErrorId   : UDINT;                          // 事件码，0 = 无事件；16#0002_2201 = 路由越界 / Event code
END_VAR
VAR
    j          : INT;                            // 输出通道索引 [路] / Output channel index
    nSrc       : INT;                            // 当前源号 [1] / Current source index
END_VAR

// —— 段 0：全路径缺省 —— //
bValid := TRUE;                                  // 组态回执预置（越界路径降级）/ Validity preset
bError := FALSE;                                 // 故障预清 / Fault preset
uErrorId := 16#0000;                             // 事件码预清 / Event code preset

// —— 段 1：逐输出路由执行（源号越界按无源降级，不中断矩阵） —— //
FOR j := 1 TO 8 DO                                // 8 路输出逐一派发 / Per-output dispatch
    nSrc := aRoute[j];                            // 取该输出源号 / Source for this output
    IF (nSrc < 0) OR (nSrc > 8) THEN              // 越界源号（下标判界，R4）/ Source out of range
        aOut[j] := 0.0;                           // 无效路由输出置零（安全侧）/ Invalid route outputs zero
        aRouteEcho[j] := 0;                       // 回显钳位无源 / Echo clamped to none
        bError := TRUE;                           // 故障标志（保持型，恢复合法自动清）/ Fault flag, self-clears on valid route
        uErrorId := 16#0002_2201;                 // 信息级：路由越界 / Info level: route out of range
        bValid := FALSE;                          // 组态回执降级 / Validity degraded
    ELSIF nSrc = 0 THEN                           // 无源：输出零 / No source: zero output
        aOut[j] := 0.0;
        aRouteEcho[j] := 0;
    ELSE                                          // 合法源号 1..8：直通复制（下标判界安全）/ Valid source: pass-through
        aOut[j] := aIn[nSrc];
        aRouteEcho[j] := nSrc;
    END_IF
END_FOR
END_FUNCTION_BLOCK
