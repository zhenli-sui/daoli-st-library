(*
  ==================================================================
  组件名 Component  : FB_DL_LotGenealogyLink
  分类   Category   : DL_Process
  复杂度 Complexity  : 中
  版本   Version    : 1.0.0
  功能   Purpose    : 批次谱系链接（ISA-88 批次谱系公开模型）。64 槽注册表：
                      登记批次（bRegReq）→ 建父子链（bLinkReq，环检测 + 深度
                      上限 16）→ 解链（bUnlinkReq）；nDepth 实时输出 nLotId
                      批次谱系深度；拒绝类结果 bRefused 单脉冲并区分成因
                      bCycleDetected / bDepthExceeded。与
                      FB_DL_TrackBarcodeTrace 单件追踪分工。
  来源   Source     : T2-8-isa-88（ISA-88 批次谱系公开模型）
  溯源   Origin     : ISA-88 批次父子谱系为公开模型语义，clean-room 自研实
                      现，未复制任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
  分工声明 Split     : 与 FB_DL_TrackBarcodeTrace 分工——后者做单件条码追踪，
                      本件做批次级父子谱系链维护。
  作者   Author     : 道莅代码库 · PLC 编程专家（R59）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 操作闸：登记重号 / 注册表满 / 链接任一批次未登记 /
                         解链批次未登记 → bRefused 单脉冲（信息级拒绝，非故
                         障）；环检出 bCycleDetected / 深度超限 bDepthExceeded
                         为独立成因独立标志（R190）；
                      二 深度上限 16：链上行遍历以深度限为界（兼作有界环终
                         止条件），超限拒绝建链；
                      三 环检测：从父批沿父链上行，命中子批即判环，拒绝；
                      四 bLinked / bRefused / bCycleDetected / bDepthExceeded
                         均单拍脉冲，每拍前置清零（纪律③）；
                      五 无除法无浮点（纯整数与数组操作，无除零风险）；无全
                         局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R59 首版（批 4 · 序号 20）
  ==================================================================
*)

FUNCTION_BLOCK FB_DL_LotGenealogyLink
VAR_INPUT
    nLotId       : DINT := 0;  // 操作批次号（登记 / 链接子批 / 解链对象）[-] / the operated lot id
    nParentLotId : DINT := 0;  // 父批次号（bLinkReq 方向使用）[-] / the parent lot id
    bRegReq      : BOOL := FALSE; // 登记请求，上升沿生效 [-] / the register request, rising edge
    bLinkReq     : BOOL := FALSE; // 建链请求（nLotId 挂 nParentLotId 下），上升沿生效 [-] / the link request, rising edge
    bUnlinkReq   : BOOL := FALSE; // 解链请求，上升沿生效 [-] / the unlink request, rising edge
END_VAR
VAR_OUTPUT
    bLinked        : BOOL := FALSE; // 建链成功单脉冲（单拍）[-] / the linked one shot pulse
    bRefused       : BOOL := FALSE; // 操作拒绝单脉冲（单拍，成因见独立标志）[-] / the refused one shot pulse
    bCycleDetected : BOOL := FALSE; // 环检出单脉冲（单拍，独立成因）[-] / the cycle detected pulse
    bDepthExceeded : BOOL := FALSE; // 深度超限单脉冲（单拍，独立成因）[-] / the depth exceeded pulse
    nDepth         : INT  := 0;   // nLotId 批次当前谱系深度（根 = 0）[层] / the current depth of the operated lot, the root is zero
    nLinkCnt       : DINT := 0;   // 在册建链总数 [条] / the total link count
    nUsedCnt       : DINT := 0;   // 注册表已用槽数 [槽] / the used slot count
END_VAR
VAR CONSTANT
    DL_LGL_SLOTS  : DINT := 64; // 注册表槽数 [槽] / the registry slot count
    DL_LGL_DEPTH  : INT  := 16; // 谱系深度上限 [层]（兼作上行遍历环界）/ the depth bound, also the walk loop bound
END_VAR
VAR
    aLotId    : ARRAY[0..63] OF DINT; // 批次号槽组（0 = 空槽）/ the lot id slots, zero means empty
    aParentIx : ARRAY[0..63] OF DINT; // 父槽索引组（-1 = 无父）/ the parent slot indexes, minus one means no parent
    rtReg     : R_TRIG; // 登记沿，段 0 无条件刷新 / the register edge
    rtLink    : R_TRIG; // 建链沿，段 0 无条件刷新 / the link edge
    rtUnlink  : R_TRIG; // 解链沿，段 0 无条件刷新 / the unlink edge
    _nI       : DINT;  // 槽遍历索引 / the slot loop index
    _nChild   : DINT;  // 子批槽索引工作量 [槽] / the child slot work index
    _nParent  : DINT;  // 父批槽索引工作量 [槽] / the parent slot work index
    _nWalk    : DINT;  // 上行遍历槽索引 [槽] / the walk slot index
    _nDepth   : INT;   // 深度工作量 [层] / the depth work value
    _nFree    : DINT;  // 空槽索引工作量（-1 = 满）/ the free slot index, minus one means full
    _bFound   : BOOL;  // 槽查找命中工作量 [-] / the slot found work flag
END_VAR

// 段 0｜沿检测无条件周期刷新（禁入分支，R7）/ segment 0, the unconditional refresh
rtReg(CLK := bRegReq); // 登记沿 / the register edge
rtLink(CLK := bLinkReq); // 建链沿 / the link edge
rtUnlink(CLK := bUnlinkReq); // 解链沿 / the unlink edge

// 段 1｜单拍脉冲前置清零（边界四，纪律③）/ segment 1, the per scan pulse preset
bLinked := FALSE; // 建链脉冲预清零 / preset the linked false
bRefused := FALSE; // 拒绝脉冲预清零 / preset the refused false
bCycleDetected := FALSE; // 环脉冲预清零 / preset the cycle false
bDepthExceeded := FALSE; // 深度脉冲预清零 / preset the depth false

// 段 2｜登记操作（重号拒 / 表满拒，边界一）/ segment 2, the register operation
IF rtReg.Q THEN // 登记沿 / the register edge
    IF nLotId <> 0 THEN // 零号保留为空槽哨兵，禁登记 / the zero id reserved, refused
        _bFound := FALSE; // 重号查找清 / clear the dup search
        _nFree := -1; // 空槽查找清（-1 = 满）/ clear the free search
        FOR _nI := 0 TO DL_LGL_SLOTS - 1 DO // 全槽扫描 / per slot
            IF aLotId[_nI] = nLotId THEN // 重号命中 / a dup hit
                _bFound := TRUE; // 记重号 / mark the dup
            ELSIF aLotId[_nI] = 0 THEN // 空槽捕获（记首个）/ capture the first free slot
                IF _nFree < 0 THEN // 尚未捕获 / not captured yet
                    _nFree := _nI; // 记空槽 / mark the free slot
                END_IF
            END_IF
        END_FOR
        IF _bFound OR (_nFree < 0) THEN // 重号或表满拒绝（信息级）/ a dup or full, refused
            bRefused := TRUE; // 置拒绝脉冲 / raise the refused pulse
        ELSE // 受理登记 / accept the registration
            aLotId[_nFree] := nLotId; // 批次号入槽 / store the lot id
            aParentIx[_nFree] := -1; // 无父起步 / start without a parent
            nUsedCnt := nUsedCnt + 1; // 用槽计数推进 / advance the used count
        END_IF
    ELSE // 零号登记拒绝 / the zero id refused
        bRefused := TRUE; // 置拒绝脉冲 / raise the refused pulse
    END_IF
END_IF

// 段 3｜槽定位公共步（子批与父批索引查找）/ segment 3, the slot locating common step
_nChild := -1; // 子批索引清（-1 = 未登记）/ clear the child index
_nParent := -1; // 父批索引清 / clear the parent index
FOR _nI := 0 TO DL_LGL_SLOTS - 1 DO // 全槽查找 / per slot search
    IF aLotId[_nI] = nLotId THEN // 子批命中 / the child hit
        _nChild := _nI; // 记子批槽 / mark the child slot
    END_IF
    IF aLotId[_nI] = nParentLotId THEN // 父批命中 / the parent hit
        _nParent := _nI; // 记父批槽 / mark the parent slot
    END_IF
END_FOR

// 段 4｜谱系深度实时计算（上行遍历以深度限为界，边界二）/ segment 4, the live depth calculation
nDepth := 0; // 深度预置根零 / preset the root zero
IF _nChild >= 0 THEN // 批次在册才算深度 / the depth only for a registered lot
    _nDepth := 0; // 深度清零 / clear the depth
    _nWalk := aParentIx[_nChild]; // 从父槽上行 / walk up from the parent slot
    WHILE (_nWalk >= 0) AND (_nDepth < DL_LGL_DEPTH) DO // 有界上行环 / the bounded walk
        _nDepth := _nDepth + 1; // 深度推进 / advance the depth
        _nWalk := aParentIx[_nWalk]; // 继续上行 / keep walking
    END_WHILE
    nDepth := _nDepth; // 深度出口（超限截断口径）/ the depth outlet, truncated by the bound
END_IF

// 段 5｜建链操作（未登记拒 / 环拒 / 深度超限拒，边界一二三）/ segment 5, the link operation
IF rtLink.Q THEN // 建链沿 / the link edge
    IF (_nChild < 0) OR (_nParent < 0) THEN // 任一批次未登记拒绝 / either unregistered, refused
        bRefused := TRUE; // 置拒绝脉冲 / raise the refused pulse
    ELSE // 双批在册，环与深度闸 / both registered, the cycle and depth gates
        _bFound := FALSE; // 环检出工作量清 / clear the cycle search
        _nDepth := 0; // 深度工作量清 / clear the depth
        _nWalk := _nParent; // 从父批上行 / walk up from the parent
        WHILE (_nWalk >= 0) AND (_nDepth < DL_LGL_DEPTH) DO // 有界上行（深度限兼环界）/ the bounded walk
            IF _nWalk = _nChild THEN // 上行命中子批：环 / the child hit, a cycle
                _bFound := TRUE; // 记环 / mark the cycle
                _nWalk := -1; // 终止遍历 / stop the walk
            ELSE // 未命中继续上行 / not hit, keep walking
                _nWalk := aParentIx[_nWalk]; // 上行一步 / walk one step
                _nDepth := _nDepth + 1; // 深度推进 / advance the depth
            END_IF
        END_WHILE // 环上行结束（R59 修：原误写 END_FOR，编译阻断）/ end of the bounded walk
        IF _bFound THEN // 环检出：拒绝建链（独立成因，R190）/ a cycle detected, refused
            bCycleDetected := TRUE; // 置环脉冲 / raise the cycle pulse
            bRefused := TRUE; // 同步置拒绝脉冲 / raise the refused pulse
        ELSIF (nDepth + 1) > DL_LGL_DEPTH THEN // 子批挂后深度超限：拒绝（独立成因）/ the depth beyond the bound, refused
            bDepthExceeded := TRUE; // 置深度脉冲 / raise the depth pulse
            bRefused := TRUE; // 同步置拒绝脉冲 / raise the refused pulse
        ELSE // 受理建链 / accept the link
            aParentIx[_nChild] := _nParent; // 写父槽索引 / write the parent index
            nLinkCnt := nLinkCnt + 1; // 建链计数推进 / advance the link count
            bLinked := TRUE; // 置建链成功脉冲 / raise the linked pulse
        END_IF
    END_IF
END_IF

// 段 6｜解链操作（未登记拒，成功不脉冲只更新）/ segment 6, the unlink operation
IF rtUnlink.Q THEN // 解链沿 / the unlink edge
    IF _nChild < 0 THEN // 批次未登记拒绝 / unregistered, refused
        bRefused := TRUE; // 置拒绝脉冲 / raise the refused pulse
    ELSIF aParentIx[_nChild] >= 0 THEN // 有父可解 / a parent exists
        aParentIx[_nChild] := -1; // 清父索引 / clear the parent index
        nLinkCnt := nLinkCnt - 1; // 建链计数回落 / drop the link count
        IF nLinkCnt < 0 THEN // 计数防御兜底（不可达分支）/ the unreachable fallback
            nLinkCnt := 0; // 夹回零 / clamp to zero
        END_IF
    END_IF
END_IF
END_FUNCTION_BLOCK
