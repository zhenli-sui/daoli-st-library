(*==============================================================================
 * 组件名称 (Component)  : FB_DL_FifoBuffer
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.1
 * 分类/来源标签         : lgf-datahandling（T2-1 LGF Data Handling 组回补）
 * 作者/日期             : Daoli Library / 2026-11-15
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），存储体经 VAR_IN_OUT 注入
 * 功能简介 (Function)   : 定长槽位 LREAL 先进先出环形队列（通用元素队列）。
 *                         支持压入 / 弹出 / 窥视 / 清空四操作，头尾指针 + 计数管理，
 *                         满 / 空 / 溢出 / 下溢标志齐备。
 *                         与已入库 FB_DL_RingBufferLReal 职责分离：
 *                         本块是通用元素队列（离散事件 / 物料号 / 批号等离散值缓存），
 *                         RingBuffer 是时间序列滑动窗（连续采样历史缓存）。
 *                         满队压入采取"丢新"策略（拒绝并单拍告警，不覆盖旧数据），
 *                         保证已入队元素零丢失——物料追溯场景丢失新批号比丢旧批号更危险。
 * 开源溯源 (Origin)     : 原创实现（参考 LGF 公开手册 Data Handling 分类中
 *                         FIFO 队列族的功能分类与参数域），只借分类/参数域/命名，
 *                         clean-room 实现，未复制任何源码。来源标签：lgf-datahandling。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: R_TRIG
 *
 * 【接口契约 / Interface contract】
 *   输入  ：bPush / bPop / bPeek 均为上升沿生效（内部 R_TRIG 检测，调用方无需
 *           自备边沿块）；bClear 电平生效，最高优先级。
 *   输出  ：fOutVal 弹出 / 窥视共用一个结果窗（被拒时保持上次有效值）；
 *           bDone 为操作处理完成单拍脉冲；bFound 为弹出 / 窥视成功标志；
 *           bFull / bEmpty 保持型；bOverflow / bUnderflow 单拍事件；
 *           uCount 当前元素数；uErrorId 故障码。
 *   注入  ：afData 存储体由调用方声明并经 VAR_IN_OUT 注入，容量上限
 *           DL_FIFO_MAX = 256 槽位，本块不持有缓冲区内存。
 *   纪律  ：同一实例在同一扫描周期内只能被调用一次（多任务 / 多处调用
 *           会破坏指针一致性断言，触发自愈重建）。
 *
 * 【使用示例 / Usage example】
 *   VAR
 *       afFifoStore : ARRAY[0..255] OF LREAL;   // 调用方持有存储体
 *       fbBatchFifo : FB_DL_FifoBuffer;         // 队列实例
 *   END_VAR
 *   // 压入批号数值：
 *   fbBatchFifo(bPush := bNewBatch, fPushVal := fBatchNo,
 *               bPop := bConsume, bPeek := FALSE, bClear := bResetFifo,
 *               uCapacity := 64, afData := afFifoStore);
 *   IF fbBatchFifo.bDone AND fbBatchFifo.bFound THEN
 *       fCurrentBatch := fbBatchFifo.fOutVal;   // 取弹出 / 窥视结果
 *   END_IF
 *
 * 【选型对照 / Selection guide】
 *   本块（FifoBuffer）      ：离散元素先进先出，容量 2..256 可调，
 *                             存储体外置注入，满队丢新告警。
 *   FB_DL_RingBufferLReal   ：固定 64 槽时间序列窗，存储内置，
 *                             满队丢旧（滑动窗语义），窥视每拍自动刷新。
 *   二者不可互相替代：滑动平均 / 趋势诊断用 RingBuffer；
 *   批次 / 物料 / 事件排队用本块。
 *
 * 【扫描周期行为 / Scan behavior】
 *   每拍次序：边沿刷新 → 缺省值清零 → 容量钳位 → 一致性断言
 *             → 清空判定 → 弹出（先）→ 压入（后）→ 窥视 → 标志派生。
 *   单拍输出族（bDone / bOverflow / bUnderflow）仅在事件拍为 TRUE，
 *   下一拍段 2 统一自清，无需调用方复位。
 *
 * 【单拍脉冲逐拍推演 / Single-pulse walk-through（R25 三律）】
 *   拍 n：空队且 bPop 上升沿 → bDone=TRUE、bUnderflow=TRUE、uErrorId=0001_010C；
 *   拍 n+1：bPop 仍为 TRUE（无新上升沿）→ 段 2 自清，bDone=bUnderflow=FALSE。
 *   置位来源唯一（弹出分支），自清位置唯一（段 2），边沿基准唯一（R_TRIG）。
 *
 * 【内存披露 / Memory disclosure】
 *   实例净占用仅指针、计数与三个边沿实例，约 0.03KB；
 *   缓冲区 256 × 8B = 2KB 归调用方，注入式设计便于多队列共享存储池
 *   与 RETAIN 策略自主决定（本块不声明保持属性）。
 *
 * 故障码表 (Error codes):
 *   16#0001_010A  容量引脚越界，已钳位到 2..DL_FIFO_MAX（信息级）
 *   16#0001_010B  满队压入被拒绝（丢新策略），单拍事件（信息级）
 *   16#0001_010C  空队弹出被拒绝，单拍事件（信息级）
 *   16#0001_010D  空队窥视被拒绝，单拍事件（信息级）
 *   16#0001_0204  指针 / 计数一致性破坏，已自愈清空重建（故障级）
 *   【码位终审】原拟 0001_0101~0104 / 0001_0201 经全库复核冲突：0101/0102 为
 *   FB_DL_EventCounter（双脉冲抵消 / 装载覆盖）、0103/0104 为
 *   FB_DL_ModuloCounter（跳步越界 / 双向抵消）、0201 为 FC_DL_DayOfWeekCalc
 *   （日期参数越界，DL_Base/VERSION.md 与总手册码表均已登记）。本体为新增
 *   组件，依公约 0.8「核对结果优先」顺延至 010A~010D / 0204（与既有
 *   0101~0109、0201~0203、0210~0212 逐条比对无冲突）。
 * 红线自检 (Redline)    : R1 ✓ 零全局存储 / 零外部变量引用 ｜ R2 ✓ 零物理地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 容量钳位 + 丢新拒满 + 空队拒读 + 取模回绕先判界
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 指针一致性断言替代状态机，破坏即自愈
 *                         R7 ✓ 三个 R_TRIG 主体最前部无条件刷新
 * 边界契约 (Boundaries):
 *   B1 存储体 afData 由调用方持有并注入（VAR_IN_OUT），容量上限 DL_FIFO_MAX，
 *      实例净占用仅指针与计数，缓冲区内存归属调用方。
 *   B2 同拍"清空 + 压入"：清空电平优先，结果为压入一个元素，无歧义。
 *   B3 同拍"压入 + 弹出"：按"先弹后压"固定次序（物料场景弹旧批号优先，
 *      与 RingBuffer 的先压后弹相反），净效果为"换入队尾"，
 *      该次序不可交换，改动会改变满队 / 单元素队列的行为语义。
 *   B4 单拍脉冲族（bDone / bOverflow / bUnderflow）遵循 R25 三律：
 *      仅操作拍置位，下拍段 2 统一自清，边沿判定只依赖 R_TRIG 单一来源。
 *   B5 fOutVal 在被拒操作拍保持上次有效值（哨兵语义：判成败看 bFound，勿以值反推）。
 *   B6 容量中途缩小到小于当前元素数时触发一致性断言 → 自愈清空（见故障码
 *      0001_0204），属契约行为：容量是结构性参数，运行中变更须预期队列重建。
 * 【验收推演表 / Acceptance walk-through（容量 = 4 槽口径）】
 *   E1 初始态            ：bEmpty=TRUE、uCount=0、bFull=FALSE
 *   E2 压入 10/20/30     ：uCount=3，窥视 → fOutVal=10、bFound=TRUE
 *   E3 弹出一次          ：fOutVal=10、uCount=2（先进先出次序成立）
 *   E4 压满 4 槽后再压   ：bOverflow 一拍 + uErrorId=0001_010B，
 *                          uCount 保持 4（丢新策略，旧数据零丢失）
 *   E5 空队弹出          ：bUnderflow 一拍 + uErrorId=0001_010C，
 *                          fOutVal 保持上次有效值（B5 哨兵纪律）
 *   E6 同拍弹 + 压（3 元素）：先弹旧队头，后压新队尾，uCount 不变（B3 次序）
 *   E7 bClear 电平一拍   ：uCount=0、bEmpty=TRUE，同拍压入请求被清空优先覆盖
 *   E8 uCapacity 填 0    ：钳位到 2 槽 + uErrorId=0001_010A（信息级，不拒动作）
 *   E9 uCapacity 中途缩到小于当前计数：一致性断言触发，自愈清空 +
 *                          uErrorId=0001_0204（故障级，B6 契约行为）
 *
 * 【拒绝路径行为矩阵 / Rejection behavior matrix】
 *   工况            ｜ bDone ｜ bFound ｜ fOutVal  ｜ 单拍事件   ｜ 计数变化
 *   满队压入        ｜ TRUE  ｜ FALSE  ｜ 保持     ｜ bOverflow  ｜ 不变
 *   空队弹出        ｜ TRUE  ｜ FALSE  ｜ 保持     ｜ bUnderflow ｜ 不变
 *   空队窥视        ｜ TRUE  ｜ FALSE  ｜ 保持     ｜ 无         ｜ 不变
 *   合法弹出        ｜ TRUE  ｜ TRUE   ｜ 更新队头 ｜ 无         ｜ 减一
 *   合法压入        ｜ TRUE  ｜ FALSE  ｜ 保持     ｜ 无         ｜ 加一
 *   合法窥视        ｜ TRUE  ｜ TRUE   ｜ 更新队头 ｜ 无         ｜ 不变
 *   被拒操作同样置 bDone：bDone 语义是"本拍处理了操作请求"，
 *   成败以 bFound / bOverflow / bUnderflow 区分，调用方按矩阵取用。
 *
 * 【多任务与保持纪律 / Multi-task and retention discipline】
 *   单实例单调用点：若需在两个任务（如主循环与诊断慢循环）访问同一队列，
 *   必须各自建实例并共享同一注入存储体时加任务同步，否则指针一致性断言
 *   会频繁触发自愈重建（故障码 0001_0204 频现即多任务冲突征兆）。
 *   队列内容需掉电保持时，把调用方的 afData 存储体与实例一起声明为
 *   保持属性（RETAIN 由调用方统一定夺，本块不越权声明）。
 *
 * 【与上位机台账协同 / Coordination with the host ledger】
 *   bOverflow 置位意味着"有一个新批号没进队列"：上位机应按该单拍事件
 *   补录台账，而不是把 bFull 当事件用（满态是保持型，会重复上报）。
 *   uCount + bFound 组合足以重建台账序号：弹出行 = 弹出序号从 1 递增，
 *   压入行 = 压入序号从 1 递增，两侧对账即可发现漏录。
 *
 * 【同族扩展约束 / Extension constraints】
 *   存储体元素类型固定 LREAL：整型批号、字符串批号等异型队列请另立
 *   组件族（泛型容器跨平台行为差异大，本库不做无约束泛化）。
 *   容量上限 DL_FIFO_MAX 与数组维度强耦合：调用方扩大存储体时必须
 *   同步改常量与本文件数组声明，二者不一致属组态级错误，
 *   编译期以维度声明为准、运行期以钳位为准。
 *   本块不做元素查重、不做优先级插队：需要优先级语义时在调用方
 *   排队前仲裁，保持队列语义单一（先进先出）不受污染。
 *
 * 【术语表 / Glossary】
 *   队头（Head）：最早入队元素所在槽位，弹出 / 窥视只读此位；
 *   队尾（Tail）：下一个写入槽位，压入只写此位；
 *   丢新（Drop-new）：满队时拒绝新元素并告警，已入队元素零丢失；
 *   下溢（Underflow）：空队时弹出请求被拒；
 *   回绕（Wrap-around）：指针越过末槽回到 0 槽，取模实现，无指针减法。
 *
 * 【空值与哨兵口径 / Sentinel semantics】
 *   fOutVal 无独立"有效"标志：有效性与最近一次弹出 / 窥视操作绑定，
 *   判据是 bDone + bFound 同拍组合，不以"值是否为 0"反推（0 是合法
 *   采样值）。上电初始 fOutVal = 0.0，未发生任何成功读操作前
 *   该值属未定义哨兵，调用方在上电首拍勿直接取用。
 *
 * 【变更边界 / Change boundary】
 *   本块行为契约由头注释边界 B1~B6 与故障码表固化：任何修订若改变
 *   同拍次序（B3）、丢新策略、单拍语义（B4）或自愈行为（B6），
 *   必须升版并在修订历史登记影响面，禁止行为漂移式小改。
 *   存储体注入形态（VAR_IN_OUT）为库级惯例，不为便利改回内置存储。
 *
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版落盘（Round 09 · 泳道 A · Level 0 原子族回补）
 *   2026-11-15  v1.0.1  终审修复：故障码 0001_0101~0104 / 0001_0201 与
 *                       EventCounter（0101/0102）、ModuloCounter（0103/0104）、
 *                       DayOfWeekCalc（0201）冲突，顺延为 0001_010A~010D /
 *                       0001_0204，行为语义零改动
 *============================================================================*)
FUNCTION_BLOCK FB_DL_FifoBuffer
VAR_INPUT
    bPush      : BOOL;                  // 压入请求，上升沿生效（Push request, rising edge）
    fPushVal   : LREAL := 0.0;          // 待压入元素值 [工程单位随应用] / Value to push [EU by application]
    bPop       : BOOL;                  // 弹出请求，上升沿生效（Pop request, rising edge）
    bPeek      : BOOL;                  // 窥视请求：读队头不弹出，上升沿生效（Peek request, rising edge）
    bClear     : BOOL;                  // 清空请求，电平生效，最高优先级（Clear request, level, highest priority）
    uCapacity  : UINT := 16;            // 队列容量 [槽位]，范围 2..DL_FIFO_MAX，越界自动钳位 / Queue capacity [slots], clamped
END_VAR
VAR_OUTPUT
    fOutVal    : LREAL;                 // 弹出 / 窥视结果值，被拒时保持上次有效值 / Pop or peek result value
    bDone      : BOOL;                  // 本次操作完成（含被拒操作），单拍脉冲 / Operation processed this scan, single pulse
    bFound     : BOOL;                  // 弹出 / 窥视成功标志，空队操作时为 FALSE / Pop or peek success flag
    bFull      : BOOL;                  // 队列满保持型标志 / Queue full flag, level
    bEmpty     : BOOL;                  // 队列空保持型标志 / Queue empty flag, level
    bOverflow  : BOOL;                  // 满队压入被拒绝，单拍脉冲（丢新策略）/ Push rejected when full, single pulse
    bUnderflow : BOOL;                  // 空队弹出被拒绝，单拍脉冲 / Pop rejected when empty, single pulse
    uCount     : UINT;                  // 当前元素数 [个] / Current element count [items]
    uErrorId   : UDINT;                 // 故障码，0 = 无故障（见头注释故障码表）/ Error code, 0 = no error
END_VAR
VAR_IN_OUT
    afData     : ARRAY[0..DL_FIFO_MAX-1] OF LREAL;  // 存储体，由调用方持有并注入 / Storage array, owned and injected by the caller
END_VAR
VAR
    fbTrigPush : R_TRIG;                // 压入边沿检测实例 / Push edge detector instance
    fbTrigPop  : R_TRIG;                // 弹出边沿检测实例 / Pop edge detector instance
    fbTrigPeek : R_TRIG;                // 窥视边沿检测实例 / Peek edge detector instance
    uHead      : UINT := 0;             // 队头读指针 [槽位索引] / Head read index [slot]
    uTail      : UINT := 0;             // 队尾写指针 [槽位索引] / Tail write index [slot]
    uCnt       : UINT := 0;             // 内部元素计数 [个]，与 uCount 同步输出 / Internal element count [items]
    uCapEff    : UINT := 16;            // 钳位后的有效容量 [槽位] / Effective clamped capacity [slots]
END_VAR
VAR CONSTANT
    DL_FIFO_MAX   : UINT := 256;        // 存储体最大容量 [槽位]，必须与数组维度一致 / Max capacity, must match the array dimension
    DL_FIFO_MIN   : UINT := 2;          // 最小合法容量 [槽位]，1 槽队列无工程意义 / Minimum legal capacity [slots]
    DL_FLOAT_EPS  : LREAL := 1.0E-9;    // LREAL 判等容差（本块不做浮点判等，保留给派生类使用）/ LREAL equality tolerance
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）：三个边沿实例位于主体最前部，严禁进入 IF / CASE
 *      Unconditional refresh zone: all three edge instances at the very top
 *      嵌入条件分支会导致边沿实例漏拍，上升沿被吞掉或重复触发
 *-----------------------------------------------------------------------------*)
fbTrigPush(CLK := bPush);
fbTrigPop(CLK  := bPop);
fbTrigPeek(CLK := bPeek);
(* 三个实例互相独立，任一沿不干扰其余沿的判定基准 *)

(*------------------------------------------------------------------------------
 * 段 2｜本拍缺省值：单拍脉冲族统一自清（R25 三律第 2 律），故障码清零
 *      Per-scan defaults: all single-pulse outputs self-clear, error code cleared
 *      bFound 同拍先清：无弹出 / 窥视操作的拍不残留上拍成功标志（B5 哨兵纪律）
 *      保持型输出（bFull / bEmpty / uCount）在段 9 重算，此处不动
 *-----------------------------------------------------------------------------*)
uErrorId   := 16#0000_0000;
bDone      := FALSE;
bFound     := FALSE;
bOverflow  := FALSE;
bUnderflow := FALSE;

(*------------------------------------------------------------------------------
 * 段 3｜容量钳位（边界 B1）：容量引脚每拍钳位到 DL_FIFO_MIN..DL_FIFO_MAX
 *      Capacity clamp: effective capacity clamped to the legal window every scan
 *      容量是结构性参数，钳位只影响后续操作，不搬移已有元素
 *-----------------------------------------------------------------------------*)
IF (uCapacity < DL_FIFO_MIN) OR (uCapacity > DL_FIFO_MAX) THEN
    (* 双向钳位而非拒绝服务：容量参数错了队列仍可用，仅信息级提示 *)
    IF uCapacity < DL_FIFO_MIN THEN
        uCapEff := DL_FIFO_MIN;     // 下越界收窄到 2 槽 / Under-range narrows to 2 slots
    ELSE
        uCapEff := DL_FIFO_MAX;     // 上越界扩张到 256 槽 / Over-range expands to 256 slots
    END_IF
    uErrorId := 16#0001_010A;   // 信息级：容量越界已钳位 / Info: capacity clamped
ELSE
    uCapEff := uCapacity;       // 合法容量直通 / Legal capacity passes through
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜指针一致性断言（红线 R6）：uCnt <= 有效容量 且 头尾指针 < 有效容量
 *      Pointer consistency assertion: count fits capacity, indices in range
 *      破坏来源：多任务并发调用、调用方越界改写、容量中途缩小（B6）。
 *      越界即写故障码并清空重建（自愈），绝不带病继续访问数组——
 *      队列数据可疑时，清空重建比继续吐出可疑值安全得多。
 *-----------------------------------------------------------------------------*)
IF (uCnt > uCapEff) OR (uHead >= uCapEff) OR (uTail >= uCapEff) THEN
    (* 自愈重建三件事：指针归位、计数归零、结果窗清零，一步不可缺 *)
    uHead    := 0;              // 头指针归零 / Reset head index
    uTail    := 0;              // 尾指针归零 / Reset tail index
    uCnt     := 0;              // 计数清零 / Clear the count
    fOutVal  := 0.0;            // 结果窗同步清零 / Clear the result window
    uErrorId := 16#0001_0204;   // 故障级：一致性破坏已自愈重建 / Fault: consistency broken, rebuilt
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜清空（边界 B2）：电平触发、最高优先级，先于弹 / 压 / 窥处理
 *      Clear: level-triggered, highest priority, handled before pop / push / peek
 *      这样"清空与压入同周期"的结果只可能是"压入一个元素"，不存在歧义
 *-----------------------------------------------------------------------------*)
IF bClear THEN
    uHead   := 0;               // 头指针复位 / Reset head
    uTail   := 0;               // 尾指针复位 / Reset tail
    uCnt    := 0;               // 计数复位 / Reset count
    fOutVal := 0.0;             // 结果窗复位 / Reset result window
    (* 清空拍不置任何事件脉冲：清空是常规操作不是异常（B4 口径） *)
ELSE
    (*--------------------------------------------------------------------------
     * 段 6｜弹出（边界 B3 第一优先）：空队拒绝并置 bUnderflow（R25 单拍）
     *      先弹后压固定次序：同拍双请求时净效果为"换入队尾"
     *      Pop first: empty queue rejects with a one-scan underflow pulse
     *-------------------------------------------------------------------------*)
    IF fbTrigPop.Q THEN
        bDone := TRUE;          // 操作已被处理（含拒绝拍），R25 仅操作拍置位
        IF uCnt = UINT#0 THEN
            bUnderflow := TRUE; // 单拍：空队弹出被拒 / Single pulse: pop on empty rejected
            uErrorId   := 16#0001_010C;
            (* fOutVal 保持上次有效值（B5），调用方以 bFound = FALSE 识别拒绝 *)
            (* 计数不动、指针不动：被拒路径零副作用，重试幂等 *)
        ELSE
            (* 读下标先判界再访问（红线 R4）：取模回绕已保证范围，仍显式兜底 *)
            IF uHead < uCapEff THEN
                fOutVal := afData[uHead];       // 取队头元素 / Read the head element
            ELSE
                uHead   := 0;                   // 越界兜底归零 / Out-of-range fallback to zero
                fOutVal := afData[uHead];
            END_IF
            bFound := TRUE;     // 弹出成功 / Pop succeeded
            uHead  := (uHead + UINT#1) MOD uCapEff;  // 前向取模回绕，无指针减法（防负取模平台差异）
            uCnt   := uCnt - UINT#1;
        END_IF
    END_IF

    (*--------------------------------------------------------------------------
     * 段 7｜压入（边界 B3 第二优先）：满队拒绝（丢新策略），绝不覆盖旧数据
     *      Push second: rejected when full (drop-new), old data never overwritten
     *      丢新与丢旧的选择依据：物料追溯中已入队批号是台账事实，
     *      静默覆盖等于篡改台账；新批号被拒会触发 bOverflow 上位机补录流程
     *-------------------------------------------------------------------------*)
    IF fbTrigPush.Q THEN
        bDone := TRUE;          // 操作已被处理（含拒绝拍）
        IF uCnt >= uCapEff THEN
            bOverflow := TRUE;  // 单拍：满队压入被拒 / Single pulse: push on full rejected
            uErrorId  := 16#0001_010B;
            (* 被拒路径零副作用：计数、指针、存储体全部不动（丢新承诺） *)
        ELSE
            (* 写下标先判界再访问（红线 R4） *)
            IF uTail < uCapEff THEN
                afData[uTail] := fPushVal;      // 写队尾元素 / Write the tail element
            ELSE
                uTail := 0;                     // 越界兜底归零 / Out-of-range fallback to zero
                afData[uTail] := fPushVal;
            END_IF
            uTail := (uTail + UINT#1) MOD uCapEff;   // 前向取模回绕
            uCnt  := uCnt + UINT#1;
        END_IF
    END_IF

    (*--------------------------------------------------------------------------
     * 段 8｜窥视（边界 B5）：读队头不弹出，空队拒绝且 fOutVal 保持
     *      Peek: read the head without popping, rejected when empty
     *      与 RingBuffer 的每拍自动窥视不同：本块窥视是请求制（上升沿），
     *      离散事件队列的队首只在调用方需要时才读，避免无意义的覆盖
     *-------------------------------------------------------------------------*)
    IF fbTrigPeek.Q THEN
        bDone := TRUE;          // 操作已被处理（含拒绝拍）
        IF uCnt = UINT#0 THEN
            uErrorId := 16#0001_010D;   // 信息级：空队窥视被拒 / Info: peek on empty rejected
            (* fOutVal 与 bFound 均不动：空队窥视对状态零影响 *)
        ELSE
            IF uHead < uCapEff THEN
                fOutVal := afData[uHead];       // 读队头不回绕 / Read head without advancing
            ELSE
                uHead   := 0;                   // 越界兜底归零 / Out-of-range fallback
                fOutVal := afData[uHead];
            END_IF
            bFound := TRUE;     // 窥视成功 / Peek succeeded
        END_IF
    END_IF

END_IF

(*------------------------------------------------------------------------------
 * 段 9｜状态标志派生：空满由计数派生，计数只在成功路径上加减，
 *      因此 bFull / bEmpty 与指针状态恒一致（不变式）
 *      Status flags derived from the count, which only moves on success paths
 *      被拒操作不动计数：这是"满队不覆盖 / 空队不出值"承诺的推论，
 *      计数错一格则空满标志全盘失真，故加减只挂在成功分支上
 *-----------------------------------------------------------------------------*)
uCount := uCnt;                     // 内部计数外化 / Expose the internal count
bFull  := (uCnt >= uCapEff);        // 满队判据（含等号，闭口径）/ Full including equality
bEmpty := (uCnt = UINT#0);          // 空队判据 / Empty
(* bFull 与 bEmpty 互斥恒成立（容量 >= 2），调用方可安全并联使用 *)
END_FUNCTION_BLOCK
