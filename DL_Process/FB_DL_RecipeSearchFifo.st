(*
  FB_DL_RecipeSearchFifo  —  配方请求 FIFO 排队（队列 + 校验链） / Recipe request FIFO queue with checksum chain
  分类 Category : DL_Process
  版本 Version  : 1.0.0
  来源 Source   : t1-4-codesys-forge — 队列/调度族零检索深化（与 RecipeManager 配方主件分工：那件管配方存取，本件管请求排队）
  溯源 Origin   : clean-room 实现，未复制任何源码行
  功能 Function : 1) 深度 8 固定 FIFO：bEnqCmd 沿入队（uReqId 入栈，异或校验链
                  uChecksum := uReqId XOR 16#A5A5_A5A5 入栈承载），bDeqCmd 沿
                  出队并校验链复核（uReqId XOR 16#A5A5_A5A5 = uChecksum 才放行）；
                  2) 故障级三码独立：038B 队满入队拒收锁存 / 038C 出队校验链
                  失败锁存（数据完整性违约，R190 归因唯一）/ 038D 空队出队违约
                  锁存 + ELSE 兜底归并（码表声明）；
                  3) 信息级三码：入队成功 / 出队成功 / 校验链复核通过（单拍沿）；
                  4) 首尾游标 MOD 8 回绕（除数 8 为常量无除零），计满/排空两端
                  边界即整数进位点验收向量（R28-2：count=8 与 count=0 两点）；
                  5) 解除式全当拍量（R240 落地），逐 BOOL 标注见段 4。
  边界 Boundary : ① 游标域 0..7 由常量 8 的 MOD 结构性限定，无越界路径；
                  ② 队列内容快照仅在命令沿承载（锁存量），每拍不重扫；
                  ③ 校验链为完整性哨兵非加密（头注释声明，防误读）；
                  ④ 无 GVL 依赖：纯引脚输入输出，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : Standard.library（R_TRIG）
  码表 Error codes（Process 段 0005，窗口 038B~038D / 04B3~04B5）:
    16#0005_038B 故障级：队满入队拒收锁存（count = 8 仍入队），锁存至 bReset
    16#0005_038C 故障级：出队校验链失败锁存（异或复核不匹配），锁存至 bReset
    16#0005_038D 故障级：空队出队违约或相位落 ELSE 兜底（归并声明），锁存至 bReset
    16#0005_04B3 信息级：入队成功沿
    16#0005_04B4 信息级：出队成功沿
    16#0005_04B5 信息级：出队校验链复核通过沿
  修订历史 Revision :
    2026-11-19  v1.0.0  R42 首版（批次 2 · 序号 5）
*)

TYPE ST_DL_RqEntry :
STRUCT
    uReqId    : UDINT;              // 请求配方号 [-] / Requested recipe ID
    uChecksum : UDINT;              // 入队校验链（uReqId 异或哨兵）[-] / Enqueue checksum chain
END_STRUCT
END_TYPE

TYPE E_DL_RsfState :
(
    eIdle   := 0,    // 空闲：队列待命 / Idle, queue standing by
    eFault  := 90    // 故障：契约违约锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_RecipeSearchFifo
VAR_INPUT
    bEnqCmd      : BOOL := FALSE;     // 入队命令，上升沿承载 [-] / Enqueue command edge
    uReqId       : UDINT := 0;        // 入队请求配方号（bEnqCmd 沿采信）[-] / Enqueue recipe ID
    bDeqCmd      : BOOL := FALSE;     // 出队命令，上升沿承载 [-] / Dequeue command edge
    bReset       : BOOL := FALSE;     // 复位，上升沿清故障锁存与队列 / Reset edge clears fault and queue
END_VAR
VAR_OUTPUT
    eState       : E_DL_RsfState;     // 状态出口，段尾单点映射 / State outlet
    nCount       : DINT;              // 当前队列深度 [0..8] / Current queue depth
    uDeqId       : UDINT;             // 出队配方号（校验通过后有效）[-] / Dequeued recipe ID
    bDeqValid    : BOOL;              // 出队有效单拍镜像 [-] / Dequeue valid one-shot mirror
    bQueueFull   : BOOL;              // 队满镜像（count = 8）[-] / Queue-full mirror
    bError       : BOOL;              // 故障锁存标志 / Fault latch flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    a_stQueue    : ARRAY[0..7] OF ST_DL_RqEntry;  // 8 深度队列存储 / Queue storage
    rtEnq        : R_TRIG;            // 入队沿实例，无条件刷新 / Enqueue edge instance
    rtDeq        : R_TRIG;            // 出队沿实例，无条件刷新 / Dequeue edge instance
    rtReset      : R_TRIG;            // 复位沿实例，无条件刷新 / Reset edge instance
    _nHead       : DINT := 0;         // 队头游标 [0..7]（出队位置）/ Head cursor
    _nTail       : DINT := 0;         // 队尾游标 [0..7]（入队位置）/ Tail cursor
    _nCnt        : DINT := 0;         // 队列深度计数 [0..8] / Depth counter
    _bFault      : BOOL;              // 故障锁存位（锁存量）/ Latched fault bit
    _uFault      : UDINT;             // 故障码锁存（锁存量）/ Latched fault code
    _uInfo       : UDINT;             // 信息码，每拍重算 / Transient info code
END_VAR

(* —— 段 0：沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
rtEnq(CLK := bEnqCmd);               // 入队沿（每拍必调）
rtDeq(CLK := bDeqCmd);               // 出队沿（每拍必调）
rtReset(CLK := bReset);              // 复位沿（每拍必调）

(* —— 段 1：单拍量预清零（锁存量 _bFault/_uFault 与游标/队列不入清单，禁同拍抹除） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
bDeqValid := FALSE;                 // 出队有效镜像缺省 FALSE（单拍）
uDeqId := 16#0000_0000;             // 出队号缺省 0
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 2：复位沿（判据当拍量；清锁存与全队列） —— *)
IF rtReset.Q THEN                   // rtReset.Q = 当拍量
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;        // 清故障锁存码
    _nHead := 0;                    // 队头游标清零
    _nTail := 0;                    // 队尾游标清零
    _nCnt := 0;                     // 深度计数清零
END_IF

(* —— 段 3：入队承载（判据当拍量沿；count = 8 满界为进位点验收向量之一） —— *)
IF rtEnq.Q AND (NOT _bFault) THEN
    IF _nCnt >= 8 THEN              // 队满（上界进位点）
        _uFault := 16#0005_038B;    // 故障级：队满入队拒收
        _bFault := TRUE;            // 故障标志与码位配对（R45）
    ELSE
        a_stQueue[_nTail].uReqId := uReqId;             // 请求号入栈
        a_stQueue[_nTail].uChecksum := uReqId XOR 16#A5A5_A5A5;  // 校验链入栈（异或哨兵）
        _nTail := (_nTail + 1) MOD 8;                   // 队尾游标回绕（除数 8 常量无除零）
        _nCnt := _nCnt + 1;                             // 深度递增
        _uInfo := 16#0005_04B3;         // 信息级：入队成功沿
    END_IF
END_IF

(* —— 段 4：出队承载（判据当拍量沿；count = 0 空界为进位点验收向量之一） —— *)
IF rtDeq.Q AND (NOT _bFault) THEN
    IF _nCnt = 0 THEN               // 空队（下界进位点）
        _uFault := 16#0005_038D;    // 故障级：空队出队违约
        _bFault := TRUE;
    ELSE
        IF (a_stQueue[_nHead].uReqId XOR 16#A5A5_A5A5) = a_stQueue[_nHead].uChecksum THEN
            uDeqId := a_stQueue[_nHead].uReqId;         // 校验通过：出队号放行
            bDeqValid := TRUE;      // 出队有效单拍镜像
            _uInfo := 16#0005_04B5; // 信息级：校验链复核通过沿
        ELSE
            _uFault := 16#0005_038C;    // 故障级：校验链失败（数据完整性违约）
            _bFault := TRUE;
        END_IF
        _nHead := (_nHead + 1) MOD 8;                   // 队头游标回绕（除数 8 常量）
        IF NOT _bFault THEN
            _nCnt := _nCnt - 1;     // 深度递减（校验失败拍不递减，保现场）
            _uInfo := 16#0005_04B4; // 信息级：出队成功沿（覆盖通过沿，后到优先声明）
        END_IF
    END_IF
END_IF

(* —— 段 5：故障解除式（R240 落地，逐 BOOL 标注）：
     rtReset.Q = 当拍量；NOT bEnqCmd = 当拍量；NOT bDeqCmd = 当拍量。
     均不含锁存量（_bFault/_uFault），解除边真实可达（命令撤销 + 复位沿）。 —— *)
IF rtReset.Q AND (NOT bEnqCmd) AND (NOT bDeqCmd) THEN
    _bFault := FALSE;               // 清故障锁存位（锁存量，仅此当拍量解除沿可清）
    _uFault := 16#0000_0000;        // 清故障锁存码（锁存量，仅本当拍量解除沿可清）
END_IF

(* —— 段 6：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
IF _bFault THEN
    nErrId := _uFault;              // 故障锁存码回放
    bDeqValid := FALSE;             // 故障拍出队有效镜像强制 FALSE（安全侧）
ELSE
    nErrId := _uInfo;               // 信息码
END_IF
nCount := _nCnt;                    // 深度出口
bQueueFull := (_nCnt >= 8);         // 队满镜像（上界进位点直读）
bError := _bFault;                  // 故障标志与锁存位同源
eState := _eState;                  // 状态出口单点映射

END_FUNCTION_BLOCK
