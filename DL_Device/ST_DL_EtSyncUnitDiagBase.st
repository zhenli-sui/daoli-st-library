// ST_DL_EtSyncUnitDiagBase v1.0.0
// 开源溯源：TcOpen / URL https://github.com/TcOpenGroup / 许可证 MIT / 借鉴 SyncUnitsBase 结构语义（同步单元诊断基），clean-room 重写
(*
  道莅工业代码库 | DL_Device | ST_DL_EtSyncUnitDiagBase
  版本: 1.0.0 | 日期: 2026-11-23 | 轮次: R75
  功能: EtherCAT 同步单元（Sync Unit）诊断基结构（单元号/参考时钟/成员
        从站索引表/同步质量聚合），供任务级同步诊断 FB 组合扩展
  邻件关系: 与 ST_DL_EtSlaveDiagBase（本批 S10）同族 —— 差异点：从站件为
            单站设备级字段，本件为多站单元级聚合（成员索引表 + 单元级
            同步质量），两件互不嵌套、平级组合
  命名声明: clean-room 重构，不含厂商库哈希后缀名（原队列条目
            SyncUnitsBase_AD6C35CE 语义对标）
*)
TYPE ST_DL_EtSyncUnitDiagBase :
STRUCT
    uSyncUnitId     : UINT;      // 同步单元编号 [单元号] / Sync unit identifier
    bUnitActive     : BOOL;      // 单元激活标志 [-] / Unit active flag
    bRefClockOk     : BOOL;      // 参考时钟锁定 [-] / Reference clock locked
    bAllInSync      : BOOL;      // 全成员同步合格 [-] / All members in sync
    nMemberCnt      : INT;       // 成员从站数 [个]，域 0..8 / Member slave count, domain 0..8
    aMemberAddr     : ARRAY[1..8] OF UINT;   // 成员从站地址表 [站号] / Member slave address table
    nWorstDiffUs    : DINT;      // 成员最大 DC 偏差 [微秒 us] / Worst member DC deviation [us]
    uSyncErrCnt     : UDINT;     // 单元同步错误累计 [次] / Unit sync error cumulative count
    uCycleMissCnt   : UDINT;     // 周期帧丢失累计 [次] / Cycle frame miss cumulative count
    bDiagStale      : BOOL;      // 诊断数据过期（看门狗超时）[-] / Diagnostic data stale flag
END_STRUCT
END_TYPE
