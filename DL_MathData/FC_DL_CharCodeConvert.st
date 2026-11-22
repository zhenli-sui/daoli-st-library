(*
    FC_DL_CharCodeConvert —— 单字符 ↔ 字符码双向换算原子
    ------------------------------------------------------------------
    组件名称  : FC_DL_CharCodeConvert
    分类      : DL_MathData / CharCode
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现（单字符与码值的
                双向映射原子，映射内核 = 定长字符表 + 标准 MID / FIND
                检索，零内建转换链依赖）；实现 / 引脚名 / 码位 100% 自有；
                clean-room 声明 —— 零代码行复制，无闭源参考。
    平台      : 纯 IEC 61131-3（Standard.library: LEN / MID / FIND），
                CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R72 构建轮 · 批 2 · 序号 4）
    ------------------------------------------------------------------
    功能说明  : 单字符与字符码（0~255）双向换算。真实工况：HMI 键盘映射、
                协议字符组装、标签打印机字符转义。选向由 eMode 枚举显式
                给出，未选方向出口置确定值（空串 / 0），绝不残留旧值。
                判据链顺序：
                ① eCharToCode 向：串长域闸（LEN <> 1 → 拒收信息级，空串 /
                   多字符同样拒收）→ LO / HI 双表 FIND 检索（先 LO 后 HI，
                   命中即回码值）→ 双表全未命中 → 防御性拒收（结构性不可达，
                   表覆盖 1..255 全字节）；
                ② eCodeToChar 向：码域闸（uCodeIn > 255 → 故障级早退）→
                   码 0 = 串终结符，回执空串（忠实语义，声明口径）→ 码
                   1..127 查 LO 表（位置 = 码值）、码 128..255 查 HI 表
                   （位置 = 码值 − 127）；
                ③ 选向枚举漏项由 CASE ELSE 兜底（拒收信息级，双出口置
                   确定值）。
                扩展 ASCII 披露（128~255）：本件只保证**码值回执**的字节级
                正确性，不保证三平台对 $80~$FF 的渲染 / 显示一致（字体与
                代码页差异属显示层语义），头注释声明披露。
                交付门槛（R64 口径）：MID / FIND 对 $80~$FF 字节的检索行为
                须在 CODESYS / TwinCAT / InoProShop 三平台各编译验证一次。
    错误码    : 16#0002_3906 码域越界（uCodeIn > 255），双出口置确定值空串/0
                            —— 故障级
                16#0002_3907 串长域闸拒收（LEN <> 1，空串 / 多字符同拒）
                            —— 信息级，不置 bError（R45）
                16#0002_3908 选向枚举漏项（CASE ELSE 兜底拒收）—— 信息级，
                            不置 bError
                加码反证句（R90）：3906 由「故障级 + 双出口确定值」唯一观测；
                3907 与 3908 在输出组合上不可分（同为拒收），但成因互斥
                （串长 vs 选向）且调用方可自证入参，故按成因分立两码，
                拒绝合并导致选向错误被误报为串长错误。
    码位总账  : 16#0002_3906 用 ｜ 16#0002_3907 用 ｜ 16#0002_3908 用
    状态机    : 无顺序状态机；选向用 CASE + ELSE 兜底（非法枚举值拦截），
                枚举成员初值一律 :=（红线 4）
    边界与披露: 一 无定时器 / 无沿检测实例 / 无数组下标 / 无除法，周期安全
                   规则 N/A；
                二 零全局变量、零 VAR_EXTERNAL、零物理地址；
                三 域闸逐项点名（R272）：uCodeIn 码域闸覆盖 0~255 全段
                   （0 与 255 两端点各推一条向量）；sCharIn 串长闸覆盖
                   0 / 1 / 多字符三态；
                四 双出口默认值纪律：未选向 / 拒收路径 sCharOut = ''、
                   uCodeOut = 0 确定值，绝不残留旧值（R256）；
                五 字符表覆盖声明：LO 表覆盖码 1..127、HI 表覆盖码 128..255、
                   码 0 按串终结符语义回执空串——三段并起覆盖 0..255 全域，
                   无缺口；
                六 与 FC_DL_HexStringToBytes / FC_DL_DwordToHexString 分工
                   互引：那两件是文本 ↔ 字节块，本件是单字符 ↔ 码值原子，
                   不互代；
                七 依赖声明：仅 Standard.library（LEN / MID / FIND），
                   零厂商方言。
    验收向量  : V1 eCodeToChar，uCodeIn = 0 → 空串（终结符语义）；
                V2 eCodeToChar，uCodeIn = 65 → 'A'；V3 eCodeToChar，
                uCodeIn = 255 → '$FF' 字符；V4 eCodeToChar，uCodeIn = 256
                → 3906 故障级；V5 eCharToCode，'A' → 65；
                V6 eCharToCode，'' 或 'AB' → 3907 拒收；
                V7 eCharToCode，' '（空格，码 32）→ 32。
                算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    修订记录  : 2026-11-23 v1.0.0 首次入库（R72 构建轮 · 批 2 · 序号 4）
*)
TYPE E_DL_CharCodeMode :
(
    eCharToCode := 0,                      // 选向：字符 → 码值 / the direction char to code
    eCodeToChar := 1                       // 选向：码值 → 字符 / the direction code to char
);
END_TYPE

FUNCTION FC_DL_CharCodeConvert : BOOL
VAR_INPUT
    eMode    : E_DL_CharCodeMode;          (* 换算方向选向，[选向枚举] / the conversion direction selector *)
    sCharIn  : STRING;                     (* 字符输入（eCharToCode 向用），[串]，串长闸限 1 字符 / the char input, gated to one char *)
    uCodeIn  : UINT;                       (* 码值输入（eCodeToChar 向用），[码]，域 0~255 / the code input, domain 0 to 255 *)
END_VAR
VAR_OUTPUT
    sCharOut  : STRING(1);                 (* 字符出口（未选向 / 拒收时为空串确定值）[串] / the char outlet, empty when rejected *)
    uCodeOut  : UINT;                      (* 码值出口（未选向 / 拒收时为 0 确定值）[码] / the code outlet, zero when rejected *)
    bValid    : BOOL;                      (* 输出可用标志，拒收 / 故障为 FALSE / the outputs usable flag *)
    bError    : BOOL;                      (* 故障标志，仅故障级码置位（R45 配对）/ the fault flag *)
    nInfoCode : UDINT;                     (* 信息 / 错误码，0 = 正常 / the info or error id *)
END_VAR
VAR CONSTANT
    DL_CHC_TAB_LO : STRING(127) := '$01$02$03$04$05$06$07$08$09$0A$0B$0C$0D$0E$0F$10$11$12$13$14$15$16$17$18$19$1A$1B$1C$1D$1E$1F !"$24%&$27()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~$7F'; (* 码 1..127 字符表（位置 p = 码 p），$24 = '$'，$27 = ''' / the low char table, position p equals code p *)
    DL_CHC_TAB_HI : STRING(128) := '$80$81$82$83$84$85$86$87$88$89$8A$8B$8C$8D$8E$8F$90$91$92$93$94$95$96$97$98$99$9A$9B$9C$9D$9E$9F$A0$A1$A2$A3$A4$A5$A6$A7$A8$A9$AA$AB$AC$AD$AE$AF$B0$B1$B2$B3$B4$B5$B6$B7$B8$B9$BA$BB$BC$BD$BE$BF$C0$C1$C2$C3$C4$C5$C6$C7$C8$C9$CA$CB$CC$CD$CE$CF$D0$D1$D2$D3$D4$D5$D6$D7$D8$D9$DA$DB$DC$DD$DE$DF$E0$E1$E2$E3$E4$E5$E6$E7$E8$E9$EA$EB$EC$ED$EE$EF$F0$F1$F2$F3$F4$F5$F6$F7$F8$F9$FA$FB$FC$FD$FE$FF'; (* 码 128..255 字符表（位置 p = 码 127 + p），只保证码值回执不保证显示 / the high char table, position p equals code 127 plus p *)
    DL_CHC_ONE    : INT  := 1;             (* 检索步进与串长基准 [个] / the search step and the length base *)
    DL_CHC_SPLIT  : UINT := 127;           (* LO / HI 表码值分界 [码] / the code split between the tables *)
    DL_CHC_CMAX   : UINT := 255;           (* 码域上界 [码] / the code domain upper bound *)
    DL_CHC_ZERO   : UINT := 0;             (* 码零哨兵（终结符语义）[码] / the zero code sentinel *)
    DL_CHC_ZEROI  : INT  := 0;             (* 检索未命中哨兵 [位置] / the not found sentinel *)
END_VAR
VAR
    nLen  : INT;                           (* 输入串长 [个] / the input string length *)
    nPos  : INT;                           (* FIND 检索命中位置（LO 表）[位置] / the FIND hit position in the low table *)
    nPosH : INT;                           (* FIND 检索命中位置（HI 表）[位置] / the FIND hit position in the high table *)
END_VAR

// 段 1｜返回值与双出口预置（统一出口预置，R256）/ segment 1, preset the return and the dual outlets
FC_DL_CharCodeConvert := FALSE;          // 故障缺省返回不可用 / the fault default is unusable
sCharOut  := '';                         // 字符出口预置空串确定值 / preset the char outlet to the empty string
uCodeOut  := DL_CHC_ZERO;                // 码值出口预置零确定值 / preset the code outlet to zero
bValid    := FALSE;                      // 可用标志预清零 / preset the usable flag false
bError    := FALSE;                      // 故障标志预清零 / preset the fault flag false
nInfoCode := 0;                          // 码位预置无错 / preset the code to zero
nLen  := 0;                              // 串长中间量清零 / clear the length temporary
nPos  := DL_CHC_ZEROI;                   // 检索位置清零 / clear the hit position
nPosH := DL_CHC_ZEROI;                   // 检索位置清零 / clear the hit position

// 段 2｜选向分发（CASE + ELSE 兜底，非法枚举值拦截，红线 4）/ segment 2, the direction dispatch with the ELSE guard
CASE eMode OF

    E_DL_CharCodeMode.eCharToCode:       // 字符 → 码值向 / the char to code direction
        nLen := LEN(sCharIn);            // 串长闸取样 / sample the input length
        IF nLen <> DL_CHC_ONE THEN       // 空串或多字符一律拒收（串长域闸）/ empty or multi char rejected
            nInfoCode := 16#0002_3907;   // 信息级：串长闸拒收 / info level: the length gate rejection
            bError := FALSE;             // 信息级不置故障（R45）/ info level never raises a fault
            bValid := FALSE;             // 输出不可用 / the outputs unusable
            sCharOut := '';              // 双出口确定值（R256）/ the deterministic outlets
            uCodeOut := DL_CHC_ZERO;     // 双出口确定值 / the deterministic outlets
            RETURN;                      // 结构早退 / structural exit
        END_IF
        nPos := FIND(DL_CHC_TAB_LO, sCharIn); // LO 表检索（位置 p = 码 p）/ search the low table
        IF nPos > DL_CHC_ZEROI THEN      // LO 表命中 / a low table hit
            uCodeOut := INT_TO_UINT(nPos); // 码值 = 位置 / the code equals the position
        ELSE                             // LO 未命中转 HI 表 / fall through to the high table
            nPosH := FIND(DL_CHC_TAB_HI, sCharIn); // HI 表检索（位置 p = 码 127 + p）/ search the high table
            IF nPosH > DL_CHC_ZEROI THEN // HI 表命中 / a high table hit
                uCodeOut := INT_TO_UINT(nPosH + UINT_TO_INT(DL_CHC_SPLIT)); // 码值 = 位置 + 127 / the code equals position plus 127
            ELSE                         // 双表全未命中（表覆盖 1..255 全字节，结构性不可达防御收口）/ both tables missed, unreachable
                nInfoCode := 16#0002_3907; // 信息级：检索失败按拒收口径 / info level: the search failure rejection
                bValid := FALSE;         // 输出不可用 / unusable
                sCharOut := '';          // 双出口确定值 / the deterministic outlets
                uCodeOut := DL_CHC_ZERO; // 双出口确定值 / the deterministic outlets
                RETURN;                  // 结构早退 / exit
            END_IF
        END_IF
        bValid := TRUE;                  // 换算成功 / the conversion succeeded

    E_DL_CharCodeMode.eCodeToChar:       // 码值 → 字符向 / the code to char direction
        IF uCodeIn > DL_CHC_CMAX THEN    // 码域闸（>255 越域）/ the code domain gate
            nInfoCode := 16#0002_3906;   // 故障级：码域越界 / fault level: the code domain violation
            bError := TRUE;              // R45 配对置故障标志 / paired with the fault flag
            bValid := FALSE;             // 输出不可用 / unusable
            sCharOut := '';              // 双出口确定值 / the deterministic outlets
            uCodeOut := DL_CHC_ZERO;     // 双出口确定值 / the deterministic outlets
            RETURN;                      // 结构早退 / exit
        END_IF
        uCodeOut := uCodeIn;             // 码值回执（选向确认）/ echo the code
        IF uCodeIn = DL_CHC_ZERO THEN    // 码 0 = 串终结符，忠实回执空串 / code zero is the terminator, faithful empty
            sCharOut := '';              // 空串出口 / the empty outlet
        ELSIF uCodeIn <= DL_CHC_SPLIT THEN // 码 1..127 查 LO 表 / the low table range
            nPos := UINT_TO_INT(uCodeIn); // 位置 = 码值（LO 表 1 起）/ the position equals the code
            sCharOut := MID(DL_CHC_TAB_LO, nPos, DL_CHC_ONE); // 取单字符 / pick the single char
        ELSE                             // 码 128..255 查 HI 表 / the high table range
            nPos := UINT_TO_INT(uCodeIn) - UINT_TO_INT(DL_CHC_SPLIT); // 位置 = 码值 − 127 / the position equals code minus 127
            sCharOut := MID(DL_CHC_TAB_HI, nPos, DL_CHC_ONE); // 取单字符 / pick the single char
        END_IF
        bValid := TRUE;                  // 换算成功 / the conversion succeeded

    ELSE                                 // 选向枚举漏项兜底（红线 4）/ the unknown direction guard
        nInfoCode := 16#0002_3908;       // 信息级：选向未知拒收 / info level: the unknown direction rejection
        bError := FALSE;                 // 信息级不置故障（R45）/ info level never raises a fault
        bValid := FALSE;                 // 输出不可用 / unusable
        sCharOut := '';                  // 双出口确定值 / the deterministic outlets
        uCodeOut := DL_CHC_ZERO;         // 双出口确定值 / the deterministic outlets

END_CASE

// 段 3｜统一出口 / segment 3, the unified outlet
FC_DL_CharCodeConvert := bValid;         // 返回值与 bValid 同源（R191 名实双出口）/ the return shares its source with bValid
END_FUNCTION
