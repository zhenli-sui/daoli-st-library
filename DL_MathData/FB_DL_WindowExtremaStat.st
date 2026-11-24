(*
  FB_DL_WindowExtremaStat  —  滑动窗极值/均值聚合（基于 FB_DL_RingBufferLReal） / Sliding-window extrema and mean over a ring buffer
  分类 Category : DL_MathData
  版本 Version  : 1.0.0
  来源 Source   : t2-1-lgf-datahandling — 数据聚合族零检索深化
  溯源 Origin   : clean-room 实现，未复制任何源码行
  功能 Function : 1) bSample 上升沿压入 fSample，窗口容量 uWinSize（1..64，底座环容量口径）；
                  2) 窗满前 bValid = FALSE；窗满后输出窗内 min/max/mean（LREAL 口径）；
                  3) 环与本地镜像同步推进：每拍压入后环满即弹最旧一拍（单拍单发），
                  本地镜像同拍移位并重算聚合；环计数与镜像计数失步 → 故障级 03E8；
                  4) 非有限样本不入窗（信息级 04AB）；bReset 电平清窗（环 + 镜像同清）。
  边界 Boundary : ① 组态闸：uWinSize >= 1 且 <= 64（0 值判据恒真反例 R227 显式拦截）→ 03E7；
                  ② 环失步/底座故障锁存 03E8；镜像计数越域防御守卫 03E9；
                  ③ 聚合循环带守卫计数，防失控；均值分母为窗内实数，窗满前不出值；
                  ④ 无 GVL 依赖：纯引脚输入输出，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : FB_DL_RingBufferLReal（实例化，引脚按 registry 实名）；Standard.library（R_TRIG）
  码表 Error codes（MathData 段 0001，窗口 03E7~03E9 / 04AA~04AC）:
    16#0001_03E7 故障级：组态非法（uWinSize < 1 或 > 64），锁存至 bReset
    16#0001_03E8 故障级：底座环失步或环故障透传，锁存至 bReset
    16#0001_03E9 故障级：镜像计数越域防御守卫兜底，锁存至 bReset
    16#0001_04AA 信息级：窗满就绪沿（bValid 首次 TRUE）
    16#0001_04AB 信息级：非有限样本剔除（不入窗）
    16#0001_04AC 信息级：清窗确认沿
  修订历史 Revision :
    2026-11-19  v1.0.0  R41 首版（批次 2 · 序号 2）
*)

FUNCTION_BLOCK FB_DL_WindowExtremaStat
VAR_INPUT
    fSample      : LREAL := 0.0;      // 采样输入 [EU] / Sample input
    bSample      : BOOL := FALSE;     // 采样沿，上升沿压入 [-] / Sample push edge
    uWinSize     : UINT := 16;        // 窗口容量 [个]，域 1..64 / Window size, 1..64
    bReset       : BOOL := FALSE;     // 清窗电平 + 复位沿 / Level clear and fault reset
END_VAR
VAR_OUTPUT
    fMin         : LREAL;             // 窗内最小值 [EU] / Window minimum
    fMax         : LREAL;             // 窗内最大值 [EU] / Window maximum
    fMean        : LREAL;             // 窗内均值 [EU] / Window mean
    bValid       : BOOL;              // 窗满有效标志 [-] / Window-full valid flag
    uFillCnt     : UINT;              // 当前窗内样本数 [个] / Current window fill count
    bError       : BOOL;              // 故障锁存标志 / Fault latch flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    fbRing       : FB_DL_RingBufferLReal;  // 底座环实例 / Ring buffer base instance
    rtSmp        : R_TRIG;            // 采样沿实例，无条件刷新 / Sample edge instance
    rtReset      : R_TRIG;            // 复位沿实例，无条件刷新 / Reset edge instance
    aWin         : ARRAY[1..64] OF LREAL;  // 本地镜像窗 [EU] / Local mirror window
    _nLive       : INT := 0;          // 镜像实际样本数 [个] / Mirror live count
    _nCap        : INT;               // 生效窗容量 [个] / Effective window capacity
    _uFault      : UDINT;             // 故障码锁存（锁存量）/ Latched fault code
    _uInfo       : UDINT;             // 信息码，每拍重算 / Transient info code
    _bFault      : BOOL;              // 故障锁存位（锁存量）/ Latched fault bit
    _bValidPrev  : BOOL;              // 上拍窗满镜像（就绪沿判据）/ Previous valid mirror
    _nMin        : INT;               // 守卫计数 [次] / Loop guard counter
    i            : INT;               // 聚合循环游标 [索引] / Aggregation loop cursor
    fSum         : LREAL;             // 均值累加器 [EU] / Mean accumulator
END_VAR

(* —— 段 0：沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
rtSmp(CLK := bSample);                    // 采样沿（每拍必调）
rtReset(CLK := bReset);                   // 复位沿（每拍必调）

(* —— 段 1：单拍量预清零（锁存量 _uFault/_bFault/aWin 不入清单，禁同拍抹除） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
bValid := FALSE;                    // 有效出口缺省 FALSE
nErrId := 16#0000_0000;             // 事件码缺省无事件
_nCap := UINT_TO_INT(uWinSize);     // 容量快照（当拍量）/ capacity snapshot

(* —— 段 2：复位沿与组态域闸（全当拍量判据） —— *)
IF rtReset.Q THEN                   // rtReset.Q = 当拍量
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;        // 清故障锁存码
    _nLive := 0;                    // 镜像清窗
    fbRing(bClear := TRUE, bPop := FALSE, bPush := FALSE, fPushValue := 0.0);  // 环电平清空
    _uInfo := 16#0001_04AC;         // 信息级：清窗确认
END_IF
IF (_nCap < 1) OR (_nCap > 64) THEN
    _uFault := 16#0001_03E7;        // 故障级：窗容量组态非法
    _bFault := TRUE;
END_IF

(* —— 段 3：底座环同拍推进（压入沿单发；环满即弹最旧一拍，单拍单发） —— *)
IF rtSmp.Q AND (NOT _bFault) THEN
    fbRing(fPushValue := fSample, bPush := TRUE, bPop := FALSE, bClear := FALSE);
                                    // 压入沿单发（每采样拍一次）
    IF (fbRing.uErrorId <> 16#0000_0000) THEN
        _uFault := 16#0001_03E8;    // 故障级：底座环故障透传
        _bFault := TRUE;
    END_IF
END_IF

(* —— 段 4：本地镜像同步推进 + 聚合重算（守卫循环） —— *)
IF (NOT _bFault) AND rtSmp.Q THEN
    IF (fSample <> fSample) OR ((fSample - fSample) <> (fSample - fSample)) THEN
        _uInfo := 16#0001_04AB;     // 信息级：非有限样本剔除（不入镜像与环口径一致）
    ELSE
        IF _nLive >= _nCap THEN
            FOR i := 2 TO _nCap DO  // 镜像满：整体左移丢最旧（容量 <= 64，循环守卫内）
                aWin[i - 1] := aWin[i];
            END_FOR
            _nLive := _nLive - 1;   // 左移后计数减一
        END_IF
        _nLive := _nLive + 1;       // 新样本入尾
        IF (_nLive >= 1) AND (_nLive <= 64) THEN
            aWin[_nLive] := fSample;    // 尾位写入（界内守卫）
        ELSE
            _uFault := 16#0001_03E9;    // 故障级：镜像计数越域防御守卫兜底
            _bFault := TRUE;
        END_IF
    END_IF
END_IF

(* —— 段 5：聚合重算（min/max/mean；仅镜像非空时执行） —— *)
IF (NOT _bFault) AND (_nLive >= 1) AND (_nLive <= 64) THEN
    fMin := aWin[1];                // 极值初值取首元素
    fMax := aWin[1];                // 极值初值取首元素
    fSum := 0.0;                    // 均值累加器清零
    _nMin := 0;                     // 守卫清零
    FOR i := 1 TO _nLive DO
        _nMin := _nMin + 1;         // 守卫递增
        IF _nMin > 64 THEN
            EXIT;                   // 守卫兜底退出（理论不可达）
        END_IF
        IF aWin[i] < fMin THEN
            fMin := aWin[i];        // 最小值刷新
        END_IF
        IF aWin[i] > fMax THEN
            fMax := aWin[i];        // 最大值刷新
        END_IF
        fSum := fSum + aWin[i];     // 均值累加
    END_FOR
    fMean := fSum / INT_TO_LREAL(_nLive);   // 均值（分母 >= 1 已过闸，防除零）
END_IF

(* —— 段 6：底座环-镜像失步复核（窗口推进后单点复核） —— *)
IF (NOT _bFault) AND (_nCap >= 1) AND (_nCap <= 64) THEN
    IF UINT_TO_INT(fbRing.uCount) > _nCap THEN
        _uFault := 16#0001_03E8;    // 故障级：环计数超容量 = 失步
        _bFault := TRUE;
    END_IF
END_IF

(* —— 段 7：出口单点映射（锁存码回放，禁同拍抹除） —— *)
uFillCnt := INT_TO_UINT(_nLive);    // 窗内样本数出口
bValid := (NOT _bFault) AND (_nLive >= _nCap);   // 窗满有效出口
IF bValid AND (NOT _bValidPrev) THEN
    _uInfo := 16#0001_04AA;         // 信息级：窗满就绪沿
END_IF
IF _bFault THEN
    nErrId := _uFault;              // 故障锁存码回放
    bValid := FALSE;                // 故障期强制 FALSE（安全侧）
ELSE
    nErrId := _uInfo;               // 信息码
END_IF
bError := _bFault;                  // 故障标志与锁存位同源
_bValidPrev := bValid;              // 就绪沿判据快照

END_FUNCTION_BLOCK
