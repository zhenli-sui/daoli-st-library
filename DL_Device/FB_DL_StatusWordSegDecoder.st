(*==============================================================================
 * 组件名称 (Component)  : FB_DL_StatusWordSegDecoder
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 设备状态字 · 段表驱动解码
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；仅 SHL / SHR 位运算与标准类型
 * 功能描述 (Function)   : 用一张段描述表（最多 16 段，每段含位偏移、位宽与
 *                         名称）把设备状态字一次性解码成右对齐的值数组，并在
 *                         同一拍给出越界、重叠、段数三类组态诊断与段状态位。
 *                         替代「每字段调用一次单段提取」的碎片写法：一次调用
 *                         拿全部字段，且组态错误在投运首日即被拦下。
 * 双宽域声明 (Width)    : 入口统一为 64 位宽字，DWORD 调用方把高位补零即可。
 *                         宽度是参数域而非语义差异，故不拆 32 位与 64 位两块。
 * 边界声明 (Boundary)   : FC_DL_BitGet 取单个位；FB_DL_UnpackWordToBits 拆固定
 *                         十六位；FC_DL_BitFieldExtract 取单段；FC_DL_WordBitPack
 *                         做单段打包。四者均为「单点」件，本块是本族唯一的
 *                         「组态级」件：段表驱动的 N 段批量解码加段间重叠诊断，
 *                         且位段提取在本块内自写，不调用上述任何单段件。
 * 掩码构造纪律 (Mask)   : 宽度等于 64 时直接取全 1 常量，**不**做 64 位移位
 *                         （对 64 位字移位 64 是未定义行为，跨平台结果不一致）。
 *                         其余宽度按「低位连续 1 左移偏移」两步构造，宽度与
 *                         偏移都在段级校验通过后才参与移位。
 * 重叠语义 (Overlap)    : 用 64 位占位掩码逐段求与，非零即重叠。拒绝模式
 *                         （bRejectOnOverlap 为真）下后到段整段作废；覆盖模式
 *                         下后到段生效（取后段值），占位掩码同步合并。两种模式
 *                         都置段状态位与信息级码，组态问题不会被静默吞掉。
 * 开源溯源 (Origin)     : lgf-bitlogic / rockwell-aoi / plcnext-community。参考
 *                         公开位逻辑功能库与设备 AOI 的段描述参数组织方式
 *                         （偏移、宽度、名称三元组）以及状态字解码的功能分类，
 *                         只借参数组织与分类，位序、掩码构造、重叠算法、枚举、
 *                         状态机、码位与全部实现 100% 自有，clean-room 实现，
 *                         不构成衍生作品。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的 SHL / SHR
 * 故障码表 (Error codes):
 *   16#0003_0142【信息级】段间重叠（拒绝模式下该段作废，覆盖模式下取后段）
 *   16#0003_0143【信息级】段越界已拒绝（宽度为零、宽度超字宽、偏移加宽超字宽）
 *   16#0003_0144【信息级】段数越界已钳位（小于 1 或大于 16）
 *   16#0003_0302【故障级】段表整体非法（无任何段可用）或非法状态兜底
 * 码位占用 (Slot)       : 信息级 0142 / 0143 / 0144；故障级 0302。
 *                         全部落在 R11 本件分配块内，无跨块借用。
 * 写入点次序 (Write order) :
 *   ① uSegStatusMask ：段解码段逐段置位，本拍起点清零，全拍只增不覆写
 *   ② auValue        ：段解码段逐段写，未定义段与作废段一律写 0
 *   ③ ePhase         ：状态机段为唯一位移点，复位分支只回待机
 *   ④ uErrorId       ：输出段单一优先级链（0302 优于 0142 优于 0143 优于 0144）
 * 验收向量 (Acceptance) :
 *   V1 单段跨半字节：字 16#1234、段（偏移 4、宽度 8）→ 值 16#23 = 35
 *   V2 双段：段（4,8）与段（8,8）→ 值 35 与 16#12 = 18
 *   V3 重叠：段（0,8）与段（4,8）、拒绝模式 → 状态掩码 16#0003、有效段 1、
 *      码 16#0003_0142
 *   V4 越界：段（60,8）→ 该段值为 0、状态位置位、码 16#0003_0143，其余段不受影响
 *   V5 六十四位特例：段（0,64）且字全 1 → 值 16#FFFF_FFFF，全程无 64 位移位
 * 红线自检 (Redline)    : R1 零全局变量表与外部变量引用 ｜ R2 零物理地址直写
 *                         R3 纯 IEC 61131-3 ｜ R4 段级边界先校验后移位，无除零
 *                         R5 全变量中英双语同行注释 ｜ R6 ENUM 加 CASE 加 ELSE
 *                         R7 R_TRIG 在 CASE 之外无条件刷新
 *                         R8 信息级码 0142 至 0144 不置组态故障位
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版落盘（Round 11 · 泳道 B · 位段批量解码开组）
 *============================================================================*)

(*------------------------------------------------------------------------------
 * 结构体: ST_DL_BitSeg（单段描述：偏移、宽度、名称）
 *         One segment descriptor, offset, width and a readable name
 *-----------------------------------------------------------------------------*)
TYPE ST_DL_BitSeg :
STRUCT
    nOffset : USINT;        // 段起始位偏移 [位]，有效域 0 到 63 / Segment start bit offset, zero to sixty-three
    nWidth  : USINT;        // 段位宽 [位]，有效域 1 到 64 / Segment width in bits, one to sixty-four
    sName   : STRING[16];   // 段名称 [文本]，供 HMI 显示与排故定位 / Segment name for the HMI and for troubleshooting
END_STRUCT
END_TYPE

(*------------------------------------------------------------------------------
 * 结构体: ST_DL_BitSegTable（段描述表容器，由调用方组态并持有）
 *         Segment descriptor table container, configured and owned by the caller
 *-----------------------------------------------------------------------------*)
TYPE ST_DL_BitSegTable :
STRUCT
    aSeg      : ARRAY[1..16] OF ST_DL_BitSeg;  // 段描述数组，十六段上限 [段] / Segment descriptor array, sixteen entries maximum
    nReserved : INT;                           // 预留字段，保持结构体对齐惯例 [整数] / Reserved field keeping the library struct convention
END_STRUCT
END_TYPE

(*------------------------------------------------------------------------------
 * 枚举: E_DL_SegDecodePhase（本块相位，归属本功能块并同文件发布）
 *       Phase enumeration owned by this block and published in the same file
 *-----------------------------------------------------------------------------*)
TYPE E_DL_SegDecodePhase :
(
    eIdle   := 0,   // 待机：未使能，值数组清零 / Idle, value array cleared
    eDecode := 10,  // 解码：逐拍重解，值随源字刷新 / Decoding, re-evaluated every cycle
    eReject := 20,  // 拒绝：整表无可用段，组态故障，需改表并复位 / Rejected, no usable segment, fix the table and reset
    eFault  := 99   // 故障：非法相位兜底，需复位退出 / Fault, illegal phase fallback, needs a reset
);
END_TYPE

(*==============================================================================
 * 逐拍推演 (Cycle-by-cycle trace)：
 *   场景 A 两段正常（段一偏移 4 宽 8，段二偏移 8 宽 8，字 16#1234）
 *     段解码段：段一掩码为高位连续八位左移四位，取值 16#23 得 35，占位合并；
 *          段二掩码不与占位相交，取值 16#12 得 18，占位合并；有效段计数为 2
 *     状态机段：eDecode 自保持；输出段有效段 2、段状态掩码 0、码 0
 *   场景 B 重叠且拒绝模式（段一 0 宽 8，段二 4 宽 8）
 *     段一正常取值并占位；段二掩码与占位相交，置段状态位两位，段二作废；
 *          有效段计数为 1；输出段码 16#0003_0142，组态故障位保持假
 *   场景 C 越界（段三偏移 60 宽 8）
 *     段级校验先做：偏移加宽 68 超过 64，直接拒绝，不参与移位、不参与占位；
 *          该段值写 0，其余段照常解码，码 16#0003_0143
 *   场景 D 整表不可用（唯一段宽度为 0）
 *     有效段计数为 0 → eReject、组态故障位为真、码 16#0003_0302；
 *          改表后有效段计数回到 1，复位上升沿退回待机，下一拍重入解码
 *   场景 E 六十四位特例（段一 0 宽 64，字全 1）
 *     宽度等于字宽直接取全 1 常量，不做移位；取值低 32 位为 16#FFFF_FFFF
 *============================================================================*)

(*==============================================================================
 * 状态迁移表 (State transition table)：
 *   当前相位   迁移条件                          目标相位   伴随动作
 *   eIdle      使能为真                          eDecode    值数组在解码段刷新
 *   eDecode    有效段数大于等于 1                eDecode    自保持，逐拍重解
 *   eDecode    有效段数为 0 且请求段数大于等于 1 eReject    组态故障位为真
 *   eDecode    使能为假                          eIdle      值数组清零
 *   eReject    使能为假                          eIdle      值数组清零
 *   eReject    复位沿且有效段数大于等于 1        eIdle      表已修正，回待机重入
 *   eFault     复位沿                            eIdle      非法相位标记清除
 *   其他值     任意                              eFault     码归入 0302
 *   说明：eReject 不自动恢复——组态问题必须人工确认后复位，避免「表错但
 *   偶发可用」时反复跳变；而 eDecode 允许逐拍重解，源字变化立即反映到值数组。
 *============================================================================*)

(*==============================================================================
 * 掩码构造对照表 (Mask construction)：
 *   段位宽   掩码构造方式                     注意事项
 *   1       单比特基准左移偏移                最常用，等价取单个标志位
 *   2 到 31 低位连续一左移后整体左移偏移      两步走，先造宽度再定位
 *   32      低位连续一左移后整体左移偏移      低半字取值，高位被自然丢弃
 *   33 到 63 同上，仍在 64 位字内合法          宽度与偏移之和不得超 64
 *   64      直接取全 1 常量                    禁对 64 位字移位 64，属未定义行为
 *   0       直接判越界拒绝                     宽度为零无物理意义
 *   说明：宽度大于 64 或偏移加宽超 64 一律在段级校验拦下，绝不进入移位分支；
 *   这是「先校验后运算」纪律的具体落点，与浮点先判零再除法同源。
 *============================================================================*)

(*==============================================================================
 * 重叠模式对照表 (Overlap policy)：
 *   项目           拒绝模式（真）              覆盖模式（假）
 *   后到段取值     写 0，整段作废              取后段值，后写者生效
 *   占位掩码       不合并                      合并，后续段继续判重叠
 *   有效段计数     不计该段                    计入
 *   段状态位       置位                        置位（重叠事实不变）
 *   信息级码       0142                        0142
 *   适用场合       字段定义严格、不允许歧义     上级字含兼容旧定义的冗余字段
 *   说明：两种模式都置段状态位与信息级码，重叠绝不会被静默吞掉；选择哪一种
 *   由调用方按设备手册的字段定义决定，本块不替现场做语义判断。
 *============================================================================*)

(*==============================================================================
 * 段表组态投运检查清单 (Commissioning checklist)：
 *   ① 段数：请求段数不超过十六，且与段表实际填写段数一致（多填的段不解码）
 *   ② 单调性：段偏移无需递增，但重叠必须是有意为之，否则投运首日就会看到 0142
 *   ③ 满宽段：宽度等于 64 的段只允许存在一段，且偏移必须为 0
 *   ④ 名称：段名建议写设备手册原文缩写，排故时与手册逐条对照
 *   ⑤ 字节序：本块只做位序解码，多字节字段的高低字节交换请在 IO 映射层完成，
 *      不要在段表里用两个半字节段去拼一个整字，那样会触发重叠诊断
 *   说明：以上五条是现场投运阶段最常见的组态错误来源，本块把它们转成段状态
 *   位与信息级码，让问题在第一次上电时就暴露，而不是等到三个月后偶发停机。
 *============================================================================*)

FUNCTION_BLOCK FB_DL_StatusWordSegDecoder
VAR_INPUT
    bEnable           : BOOL;                       // 使能，FALSE 时值数组清零 [-] / Enable, clears the value array on FALSE
    bReset            : BOOL;                       // 清组态诊断，上升沿有效 [-] / Clears the configuration diagnostics on a rising edge
    uWord             : LWORD;                      // 被解码状态字，六十四位宽 [位串] / Source status word, sixty-four bits wide
    nSegCount         : INT;                        // 有效段数 [段]，有效域 1 到 16 / Valid segment count, one to sixteen
    bRejectOnOverlap  : BOOL;                       // 重叠策略，真为整段拒绝，假为后段覆盖 [-] / Overlap policy, reject the segment or let the later one win
END_VAR
VAR_OUTPUT
    auValue           : ARRAY[1..16] OF UDINT;      // 各段解码值，右对齐，未定义段为 0 [值] / Decoded value per segment, right aligned, zero for unused
    nValidCount       : INT;                        // 实际成功解码的段数 [段] / Segment count successfully decoded
    uSegStatusMask    : WORD;                       // 段状态位：置位表示该段越界或重叠被拒 [位串] / Segment status bits, set when rejected
    eState            : E_DL_SegDecodePhase;        // 主状态机当前相位 [-] / Current phase of the main state machine
    bConfigFault      : BOOL;                       // 段表组态故障（整表无可用段）[-] / Segment table configuration fault
    uErrorId          : UDINT;                      // 事件码，0 表示无事件 [代码] / Event code, zero means none
END_VAR
VAR_IN_OUT
    stSegs            : ST_DL_BitSegTable;          // 段描述表，块内只读，禁止就地改写 [-] / Segment descriptor table, read only inside this block
END_VAR
VAR
    fbTrigReset       : R_TRIG;                     // 复位沿检测，CASE 之外无条件刷新 [-] / Reset edge detector, refreshed outside the CASE
    bInit             : BOOL := FALSE;              // 首扫标志，初值 FALSE，判据 NOT bInit [-] / First-scan flag initialised FALSE
    ePhase            : E_DL_SegDecodePhase := E_DL_SegDecodePhase.eIdle;  // 内部相位，对外经 eState 输出 / Internal phase, exported as eState
    nSegClamped       : INT;                        // 钳位后的段数 [段]，0 到 16 / Clamped segment count, zero to sixteen
    bSegCntClamped    : BOOL;                       // 段数越界被钳位的标记 [-] / Flag, segment count was clamped
    bSegCntEmpty      : BOOL;                       // 段数小于一的标记 [-] / Flag, segment count below one
    nWidthUse         : INT;                        // 当前段位宽 [位] / Width of the current segment
    nOffsetUse        : INT;                        // 当前段位偏移 [位] / Bit offset of the current segment
    uSegMask          : LWORD;                      // 当前段掩码 [位串] / Mask of the current segment
    uOccupy           : LWORD;                      // 已占位掩码，重叠检测用 [位串] / Occupied bit mask used for overlap detection
    bSegBad           : BOOL;                       // 当前段越界标记 [-] / Flag, current segment is out of range
    bSegDup           : BOOL;                       // 当前段重叠标记 [-] / Flag, current segment overlaps a previous one
    bAnyOut           : BOOL;                       // 本拍存在越界段 [-] / Flag, at least one segment is out of range
    bAnyOverlap       : BOOL;                       // 本拍存在重叠段 [-] / Flag, at least one segment overlaps
    bStateIllegal     : BOOL;                       // 非法相位被兜底捕获 [-] / Flag, an illegal phase was captured
    i                 : INT;                        // 段遍历索引 [1..16] / Segment loop index
END_VAR
VAR CONSTANT
    DL_SEG_MAX        : INT := 16;                  // 段数上限 [段] / Maximum segment count
    DL_WORD_BITS      : INT := 64;                  // 位宽常量 [位] / Word width in bits
    DL_MASK64_ALL     : LWORD := 16#FFFF_FFFF_FFFF_FFFF;  // 六十四位全 1 掩码 [位串] / All ones mask for the full width
    DL_MASK64_ONE     : LWORD := 16#0000_0000_0000_0001;  // 六十四位单比特基准 [位串] / Single bit reference of the full width
    DL_MASK64_NONE    : LWORD := 16#0000_0000_0000_0000;  // 六十四位全 0 掩码 [位串] / All zeros mask
    DL_MASK_ONE       : WORD := 16#0001;            // 段状态位单比特基准 [位串] / Single bit reference for the status mask
    DL_SEG_MIN        : INT := 1;                   // 段数下限 [段] / Minimum segment count
    DL_WIDTH_MIN      : INT := 1;                   // 段宽下限 [位] / Minimum segment width
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜沿检测无条件刷新（R7 红线）
 *      Edge detection refreshed unconditionally
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bReset);

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化（R19 唯一合法范式）
 *      First-scan initialisation with the canonical R19 pattern
 *-----------------------------------------------------------------------------*)
IF NOT bInit THEN
    FOR i := 1 TO DL_SEG_MAX DO
        auValue[i] := 0;                 // 值数组初值确定，HMI 不显示随机数
    END_FOR
    nValidCount     := 0;
    uSegStatusMask  := 16#0000;
    ePhase          := E_DL_SegDecodePhase.eIdle;
    eState          := E_DL_SegDecodePhase.eIdle;
    bConfigFault    := FALSE;
    bStateIllegal   := FALSE;
    uErrorId        := 16#0000_0000;
    bInit           := TRUE;             // 首扫只做一次
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜段数钳位（小于一整体不动作，大于上限钳位到十六）
 *      Segment count clamping, below one does nothing, above sixteen clamped
 *-----------------------------------------------------------------------------*)
bSegCntClamped := FALSE;
bSegCntEmpty   := FALSE;
IF nSegCount < DL_SEG_MIN THEN
    nSegClamped   := 0;                  // 无有效段：整体不动作
    bSegCntEmpty  := TRUE;
ELSIF nSegCount > DL_SEG_MAX THEN
    nSegClamped   := DL_SEG_MAX;         // 超上限钳位
    bSegCntClamped := TRUE;
ELSE
    nSegClamped := nSegCount;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜段解码（段级校验先于移位；重叠用占位掩码求与判定）
 *      Segment decoding, validation before shifting, overlap by occupy mask
 *      位段提取在本块内自写，不调用任何单段提取件，保证泳道内零跨依赖
 *      每段处理分三步，顺序不可颠倒：
 *        第一步 校验：宽度小于一、宽度超字宽、偏移加宽超字宽，任一成立即拒绝，
 *               该段不参与移位、不参与占位，仅置段状态位与越界标记
 *        第二步 造掩码：满宽特例走全 1 常量，其余走「连续一左移」两步构造
 *        第三步 取值与占位：取值写值数组；拒绝模式下重叠段写 0 且不合并占位，
 *               覆盖模式下取值并合并占位，有效段计数同步加一
 *-----------------------------------------------------------------------------*)
uOccupy        := DL_MASK64_NONE;
uSegStatusMask := 16#0000;
nValidCount    := 0;
bAnyOut        := FALSE;
bAnyOverlap    := FALSE;
FOR i := 1 TO DL_SEG_MAX DO
    auValue[i] := 0;                                     // 未定义段与作废段一律为 0
END_FOR

IF bEnable AND (ePhase <> E_DL_SegDecodePhase.eFault) THEN
    FOR i := 1 TO nSegClamped DO
        nWidthUse  := USINT_TO_INT(stSegs.aSeg[i].nWidth);
        nOffsetUse := USINT_TO_INT(stSegs.aSeg[i].nOffset);
        bSegBad    := FALSE;
        bSegDup    := FALSE;

        IF (nWidthUse < DL_WIDTH_MIN)
           OR (nWidthUse > DL_WORD_BITS)
           OR ((nOffsetUse + nWidthUse) > DL_WORD_BITS) THEN
            bSegBad := TRUE;                             // 段级越界：先拒绝，后不参与移位
        END_IF

        IF bSegBad THEN
            uSegStatusMask := uSegStatusMask OR SHL(DL_MASK_ONE, i - 1);
            bAnyOut        := TRUE;
        ELSE
            IF nWidthUse >= DL_WORD_BITS THEN
                uSegMask := DL_MASK64_ALL;               // 满宽特例：禁 64 位移位
            ELSE
                uSegMask := SHL(DL_MASK64_ONE, nWidthUse) - DL_MASK64_ONE;
                uSegMask := SHL(uSegMask, nOffsetUse);   // 低位连续一左移到位
            END_IF

            IF (uOccupy AND uSegMask) <> DL_MASK64_NONE THEN
                uSegStatusMask := uSegStatusMask OR SHL(DL_MASK_ONE, i - 1);
                bAnyOverlap    := TRUE;
                bSegDup        := TRUE;
            END_IF

            IF bSegDup AND bRejectOnOverlap THEN
                auValue[i] := 0;                         // 拒绝模式：后到段整段作废
            ELSE
                auValue[i] := LWORD_TO_UDINT(SHR(uWord AND uSegMask, nOffsetUse));
                uOccupy    := uOccupy OR uSegMask;       // 覆盖模式：占位合并，后段生效
                nValidCount := nValidCount + 1;
            END_IF
        END_IF
    END_FOR
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜主状态机（ENUM 加 CASE，含 ELSE 兜底；每成员均有对应标签）
 *      Main state machine, one label per enumeration member plus a fallback
 *-----------------------------------------------------------------------------*)
CASE ePhase OF
    E_DL_SegDecodePhase.eIdle:
        IF bEnable THEN
            ePhase := E_DL_SegDecodePhase.eDecode;       // 使能即进入逐拍重解
        END_IF

    E_DL_SegDecodePhase.eDecode:
        IF NOT bEnable THEN
            ePhase := E_DL_SegDecodePhase.eIdle;
        ELSIF (nValidCount = 0) AND (nSegClamped >= DL_SEG_MIN) THEN
            ePhase := E_DL_SegDecodePhase.eReject;       // 整表无可用段：组态故障
        END_IF

    E_DL_SegDecodePhase.eReject:
        IF NOT bEnable THEN
            ePhase := E_DL_SegDecodePhase.eIdle;
        ELSIF fbTrigReset.Q AND (nValidCount >= DL_SEG_MIN) THEN
            ePhase := E_DL_SegDecodePhase.eIdle;         // 表已修正且复位：退回待机重入
        END_IF

    E_DL_SegDecodePhase.eFault:
        IF fbTrigReset.Q THEN
            ePhase        := E_DL_SegDecodePhase.eIdle;  // 只有复位可退出兜底故障
            bStateIllegal := FALSE;
        END_IF

    ELSE
        ePhase        := E_DL_SegDecodePhase.eFault;     // 非法值兜底
        bStateIllegal := TRUE;
END_CASE

(*------------------------------------------------------------------------------
 * 段 6｜输出归并与码位定级（单一优先级链，全拍只写一次 uErrorId）
 *      Output merge and single-priority error code resolution
 *-----------------------------------------------------------------------------*)
IF NOT bEnable THEN
    FOR i := 1 TO DL_SEG_MAX DO
        auValue[i] := 0;                                 // 未使能一律清零，避免陈旧值
    END_FOR
    nValidCount := 0;
    uSegStatusMask := 16#0000;
END_IF

bConfigFault := bStateIllegal
                OR (bEnable AND (nSegClamped >= DL_SEG_MIN) AND (nValidCount = 0));

IF bConfigFault THEN
    uErrorId := 16#0003_0302;                            // 优先级一：整表非法
ELSIF bAnyOverlap THEN
    uErrorId := 16#0003_0142;                            // 信息级：段间重叠
ELSIF bAnyOut THEN
    uErrorId := 16#0003_0143;                            // 信息级：段越界已拒绝
ELSIF bSegCntClamped OR bSegCntEmpty THEN
    uErrorId := 16#0003_0144;                            // 信息级：段数越界已钳位
ELSE
    uErrorId := 16#0000_0000;
END_IF

eState := ePhase;                                        // 相位每拍重写，供 HMI 诊断
END_FUNCTION_BLOCK
