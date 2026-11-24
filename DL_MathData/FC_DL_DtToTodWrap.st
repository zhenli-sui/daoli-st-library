(*
  ==================================================================
  组件名 Component  : FC_DL_DtToTodWrap
  分类   Category   : DL_MathData
  前缀   Naming     : FC_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  码位   Code ID    : 16#0001_0652（信息级）
  版本   Version    : 1.0.0
  复杂度 Complexity  : 低
  功能   Purpose    : 从 DT 提取当日秒数（0..86399）与 TOD，日模 86400 显式化。
  开源溯源 Origin    : IEC 61131-3 标准语义的道莅防御性实现（clean-room，无第三方代码行）
  许可证 License    : MIT
  参考   Reference  : IEC 61131-3:2013 §6.4.3 日期时间类型（DT / TOD）与 §6.5.1 时长域语义
  平台   Platform   : 纯 IEC 61131-3（MOD / 委托 / TOD 类型），三平台通用
  依赖   Depends    : FC_DL_DtToDintEpoch（时刻→纪元秒属主，其内部委托 FC_DL_DateToDintDays
                      完成天序数换算）；FC_DL_DintMsToTod（毫秒→TOD 还原属主）。
                      本件全程委托，不内联任何历法算法（R140 / R216）。
  分工声明 Split     : FC_DL_TodAddWrap / FC_DL_TodDiffWrap 为 TOD 运算属主；
                      FC_DL_TimeToDintMs 为 TIME 域属主；FC_DL_DtToDintEpoch 为绝对纪元秒属主；
                      本件为「DT → 当日秒 / TOD 提取」，四件边界写死（R216 双向互引）。
  归属 Ownership     : 本件无 TYPE 声明；引用件的码位随其属主回传（R66）。
  编译门槛 Gate      : 交付门槛：主路径委托 FC_DL_DtToDintEpoch（其内含 DT_TO_DINT 内建链）
                      与 FC_DL_DintMsToTod（内含 DINT_TO_TOD 内建链），须在 CODESYS /
                      TwinCAT 3 / InoProShop 三平台各编译验证一次（R64）。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 基准无效闸：dtIn 早于 DT#1970-01-01-00:00:00 视为未初始化或非法
                         时间戳，返回哨兵零点 + 信息级码 + bValid = FALSE，禁止把负天数
                         MOD 成一个看似合法的时刻（还原方向不饱和，R81：返回哨兵零点）；
                      二 日模 86400 显式化：diSecOfDay = ((纪元秒 MOD 86400) + 86400) MOD 86400，
                         双 MOD 保证负数路径也不落到负值域（域外不可达，证明在注释内）；
                      三 todOut 经 FC_DL_DintMsToTod 还原（毫秒域 × 1000），不自行拼 TOD 位型；
                      四 委托件的返回值与 bValid 由两个独立变量承接（R62-D5 教训：禁双写）；
                      五 纯函数：无记忆量、无定时器、无边沿实例，每调用重算。
  错误码 Codes      :
    16#0001_0652【信息级】输入时刻早于纪元基准，已返哨兵零点（bValid = FALSE，不置 bError）
    委托件故障码（16#0001_0330 / 0331 等）按「码随属主」原样回传（R66），本件不另立码。
  码位反证 Note     :
    本件唯一自有码 0652 不可省略：「早于基准」与「委托件进位失败」在出口上都是 bValid = FALSE
    且 todOut = 零点，但两者的处置主体与责任方不同（调用方时间戳未初始化 vs 平台位型承载异常），
    合并会让现场把「未初始化」误判为平台缺陷（R90 反证句）。
  验收 Acceptance   :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 DT#1970-01-01-00:00:00 → 0 秒、todOut = 00:00:00、bValid = TRUE
    V2 DT#2024-02-29-23:59:59 → 86399 秒（闰日不计日差，只取当日秒）
    V3 DT#2024-03-01-00:00:00 → 0 秒（日推进不残留）
    V4 DT#1970-01-01-00:00:00 之前的时刻 → bValid = FALSE + 码 0652 + 哨兵零点
    V5 DT#2106-02-07-06:28:15 → 23295 秒（6×3600 + 28×60 + 15，当日秒，跨 32 位不溢出）
    V6 DT#1970-01-02-00:00:00 → 0 秒（日推进归零）
  修订记录 Revision  :
    2026-11-21  v1.0.0  R62 首版（批 3 · 序号 7）
  ==================================================================
*)
FUNCTION FC_DL_DtToTodWrap : BOOL
VAR_INPUT
    dtIn : DT := DT#1970-01-01-00:00:00; // 输入时刻 [日期时间]，有效域自 1970-01-01-00:00:00 起 / the input instant, the domain starts at the epoch
END_VAR
VAR_OUTPUT
    todOut     : TOD;   // 当日时刻 [时刻]，00:00:00 ~ 23:59:59 / the time of day
    diSecOfDay : DINT;  // 当日秒数 [秒]，0..86399 / the second of the day
    bValid     : BOOL;  // 输出可用（早于基准与委托故障为 FALSE）[-] / the output is usable
    eErr       : UDINT; // 错误码，0 = 正常 / the error code, zero is ok
    bError     : BOOL;  // 故障标志，故障级码同拍置位（R45 配对）；信息级恒 FALSE / the fault flag, raised with a fault level code only
END_VAR
VAR
    _nEpochSec   : DINT := 0;                // 委托返回的纪元秒 [秒] / the epoch second returned by the delegate
    _bEpochValid : BOOL := FALSE;            // 委托 bValid 承接量（独立承接，禁双写）/ the delegate valid holder, never double written
    _bEpochErr   : BOOL := FALSE;            // 委托 bError 承接量（独立承接）/ the delegate fault holder, never double written
    _uEpochErr   : UDINT := 16#0000_0000;    // 委托错误码承接量 [码] / the delegate error code holder
    _nMsOfDay    : DINT := 0;                // 当日毫秒偏移 [毫秒] / the millisecond offset inside the day
    _todWork     : TOD := TOD#00:00:00;      // 委托 TOD 返回值承接量 [时刻] / the delegate time of day holder
    _bTodValid   : BOOL := FALSE;            // 委托 TOD 可用位承接量 / the delegate time of day usable holder
    _bTodErr     : BOOL := FALSE;            // 委托 TOD 故障位承接量 / the delegate time of day fault holder
    _uTodErr     : UDINT := 16#0000_0000;    // 委托 TOD 错误码承接量 [码] / the delegate time of day error code holder
    _bTodClamped : BOOL := FALSE;            // 委托 TOD 钳位位承接量（仅留档，不参与分级）/ the delegate clamp holder, recorded only
END_VAR  // R64 结构补齐：VAR 段缺失的 END_VAR（门禁机械修复）
VAR CONSTANT
    DL_DTT_SEC_PER_DAY : DINT := 86400;      // 每日秒数（日模）[秒] / the seconds of one day, the day modulus
    DL_DTT_MS_PER_SEC : DINT := 1000;        // 每秒毫秒数（毫秒域换算）[毫秒] / the milliseconds of one second
    DL_DTT_DINT_ZERO : DINT := 0;             // 整型零常量 [秒] / the integer zero constant
    DL_DTT_TOD_ZERO : TOD := TOD#00:00:00;   // 时刻哨兵零点 [时刻] / the sentinel midnight
    DL_DTT_EPOCH : DT := DT#1970-01-01-00:00:00; // 纪元基准时刻 [日期时间] / the epoch baseline instant
END_VAR

// 段 1｜返回值与全部出口预置安全值（R45 四段式第一段）/ segment 1, preset every outlet to its safe value
FC_DL_DtToTodWrap := FALSE; // 返回值预置假 / preset the return false
todOut := DL_DTT_TOD_ZERO; // 时刻预置哨兵零点 [时刻] / preset the sentinel midnight
diSecOfDay := DL_DTT_DINT_ZERO; // 当日秒数预置零 [秒] / preset the second of the day zero
bValid := FALSE; // 可用标志预置假，过闸后置位 / preset the validity false, raised after the gates
eErr := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 故障标志预置假 / preset the fault flag false
_nEpochSec := DL_DTT_DINT_ZERO; // 纪元秒承接量清零 [秒] / clear the epoch second holder
_bEpochValid := FALSE; // 委托可用位承接量清零 / clear the delegate usable holder
_bEpochErr := FALSE; // 委托故障位承接量清零 / clear the delegate fault holder
_uEpochErr := 16#0000_0000; // 委托码承接量清零 [码] / clear the delegate code holder
_nMsOfDay := DL_DTT_DINT_ZERO; // 当日毫秒清零 [毫秒] / clear the millisecond offset
_todWork := DL_DTT_TOD_ZERO; // 时刻承接量清零 [时刻] / clear the time of day holder
_bTodValid := FALSE; // 委托 TOD 可用位清零 / clear the time of day usable holder
_bTodErr := FALSE; // 委托 TOD 故障位清零 / clear the time of day fault holder
_uTodErr := 16#0000_0000; // 委托 TOD 码清零 [码] / clear the time of day code
_bTodClamped := FALSE; // 委托钳位位清零 / clear the delegate clamp holder

// 段 2｜基准无效闸：早于纪元的时刻不交给委托件（边界一，还原方向不饱和，R81）/ segment 2, the epoch baseline gate
IF dtIn < DL_DTT_EPOCH THEN // 未初始化或非法时间戳 / an uninitialised or illegal timestamp
    todOut := DL_DTT_TOD_ZERO; // 哨兵零点 [时刻] / the sentinel midnight
    diSecOfDay := DL_DTT_DINT_ZERO; // 哨兵零秒 [秒] / the sentinel zero second
    bValid := FALSE; // 输出不可用 / the output is not usable
    eErr := 16#0001_0652; // 信息级：输入早于纪元基准 / informational, the input precedes the epoch baseline
    bError := FALSE; // 明确不置故障标志（信息级，R285）/ keep the fault flag false, this is informational
    RETURN; // 早退，绝不把负天数交给委托件 / early return, a negative day count never reaches the delegate
END_IF

// 段 3｜委托时刻→纪元秒（R140 委托优先；返回值与可用位分承）/ segment 3, delegate the instant to the epoch second
_nEpochSec := FC_DL_DtToDintEpoch(dtIn := dtIn, eErr => _uEpochErr, bError => _bEpochErr, bValid => _bEpochValid); // 委托纪元秒换算 [秒] / delegate the epoch conversion
IF (NOT _bEpochValid) OR _bEpochErr THEN // 委托失败：码随属主回传（R66）/ the delegate failed, the code follows its owner
    eErr := _uEpochErr; // 原样回传委托码 [码] / replay the delegate code as is
    bError := _bEpochErr; // 原样回传委托故障位 / replay the delegate fault bit as is
    bValid := FALSE; // 输出不可用 / the output is not usable
    todOut := DL_DTT_TOD_ZERO; // 哨兵零点 [时刻] / the sentinel midnight
    diSecOfDay := DL_DTT_DINT_ZERO; // 哨兵零秒 [秒] / the sentinel zero second
    RETURN; // 早退 / early return
END_IF

// 段 4｜日模 86400 抽取当日秒（边界二：双 MOD 保证任何输入都落 0..86399）/ segment 4, the day modulus extraction
// 域外不可达证明：段 2 已证 dtIn ≥ 纪元，委托件已证返回值非负，故首层 MOD 的结果已在 [0, 86399]；
// 第二次「+ 86400 再 MOD」为结构对称的二重防御，保证任何未来改动都不会引入负值域出口。
// domain proof: the gate above guarantees a non negative epoch second, so the first modulus already lands inside the day;
// the second fold is a structural second line of defence against any future refactor.
diSecOfDay := ((_nEpochSec MOD DL_DTT_SEC_PER_DAY) + DL_DTT_SEC_PER_DAY) MOD DL_DTT_SEC_PER_DAY; // 当日秒数 [秒] / the second of the day

// 段 5｜委托毫秒→TOD 还原（边界三：不自行拼 TOD 位型）/ segment 5, delegate the millisecond offset back to a time of day
_nMsOfDay := diSecOfDay * DL_DTT_MS_PER_SEC; // 当日毫秒偏移（上界 86399000，DINT 内不溢出）[毫秒] / the millisecond offset, bounded by eighty six million four hundred thousand
_todWork := FC_DL_DintMsToTod(nMsOfDay := _nMsOfDay, bClampSilently := TRUE, eErr => _uTodErr, bError => _bTodErr, bValid => _bTodValid, bClamped => _bTodClamped); // 委托还原 [时刻] / delegate the restoration
IF (NOT _bTodValid) OR _bTodErr THEN // 委托失败：码随属主回传 / the delegate failed, the code follows its owner
    eErr := _uTodErr; // 原样回传委托码 [码] / replay the delegate code as is
    bError := _bTodErr; // 原样回传委托故障位 / replay the delegate fault bit as is
    bValid := FALSE; // 输出不可用 / the output is not usable
    todOut := DL_DTT_TOD_ZERO; // 哨兵零点 [时刻] / the sentinel midnight
    RETURN; // 早退 / early return
END_IF

// 段 6｜统一出口 / segment 6, the unified outlet
todOut := _todWork; // 时刻出口 [时刻] / the time of day outlet
bValid := TRUE; // 域内输出可用 / the in-domain output is usable
FC_DL_DtToTodWrap := TRUE; // 返回成功 / return success
END_FUNCTION
