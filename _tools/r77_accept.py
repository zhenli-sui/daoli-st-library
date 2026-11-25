# -*- coding: utf-8 -*-
"""由 R77 规划生成 _r77_accept.json 骨架（注册候选），闸/审校后由主控勾除拒收件再喂 closeout。"""
import json, os, importlib.util, sys

spec = importlib.util.spec_from_file_location('p77', r'C:\Library\_tools\r77_plan.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
rows = m.rows

TAGS = {
 'FC_DL_StringPadLeftZeros': ['string','pad','fixed-width','format'], 'FC_DL_StringTruncEllipsis': ['string','truncate','ellipsis','display'],
 'FC_DL_StringCountChar': ['string','count','delimiter','parse'], 'FC_DL_StringReverse': ['string','reverse','palindrome'],
 'FC_DL_StringIsNumeric': ['string','validate','numeric','parse'], 'FC_DL_StringRemoveWhitespace': ['string','whitespace','compact'],
 'FC_DL_StringSplitPair': ['string','key-value','split','parse'], 'FC_DL_StringRepeat': ['string','repeat','concat','buffer-guard'],
 'FC_DL_StringCompareNatural': ['string','natural-sort','compare'], 'FC_DL_StringCsvFieldEscape': ['string','csv','escape','quote'],
 'FC_DL_LengthUnitConvert': ['unit-conversion','length','si','imperial'], 'FC_DL_MassUnitConvert': ['unit-conversion','mass','si','imperial'],
 'FC_DL_VolumeUnitConvert': ['unit-conversion','volume','si','imperial'], 'FC_DL_AreaUnitConvert': ['unit-conversion','area','si','imperial'],
 'FC_DL_DensityUnitConvert': ['unit-conversion','density','si','imperial'], 'FC_DL_ViscosityUnitConvert': ['unit-conversion','viscosity','kinematic'],
 'FC_DL_EnergyUnitConvert': ['unit-conversion','energy','kwh','btu'], 'FC_DL_PowerUnitConvert': ['unit-conversion','power','kw','hp'],
 'FC_DL_HumidityUnitConvert': ['unit-conversion','humidity','relative','absolute'],
 'FC_DL_ConcentrationUnitConvert': ['unit-conversion','concentration','ppm','gas'],
 'FC_DL_TableLookupDescending': ['table','lookup','descending','interpolate'], 'FC_DL_TableLookupNearestIndex': ['table','lookup','nearest-node'],
 'FC_DL_InterpLogLinear': ['interpolation','log-linear','decay-curve'], 'FC_DL_InterpTwoPointSlope': ['interpolation','slope','extrapolation'],
 'FC_DL_TableIndexBinarySearch': ['table','binary-search','index'], 'FC_DL_InterpHoldLast': ['interpolation','hold-last','clamp'],
 'FC_DL_TableReverseLookupX': ['table','reverse-lookup','monotonic'], 'FC_DL_InterpSegmentWeight': ['interpolation','weight','segment'],
 'FB_DL_RunningAverageN': ['filter','moving-average','ring-buffer'], 'FB_DL_PeakHoldFilter': ['filter','peak-hold','reset'],
 'FB_DL_RateOfChangeFilter': ['filter','rate-limit','slew'], 'FB_DL_GatedUpdateFilter': ['filter','gated','sample-window'],
 'FB_DL_HoldLastGoodFilter': ['filter','hold-last-good','validity'], 'FB_DL_DeadbandFilter': ['filter','deadband','stateful','hold'],
 'FB_DL_QuantizeFilter': ['filter','quantize','hysteresis'],
 'FC_DL_StatsMeanStdDev': ['statistics','mean','stddev','welford'], 'FC_DL_StatsMinMaxWindow': ['statistics','min-max','window'],
 'FC_DL_StatsPercentile': ['statistics','percentile','rank'], 'FC_DL_StatsRmsCalc': ['statistics','rms','ac-signal'],
 'FC_DL_StatsZeroCrossRate': ['statistics','zero-crossing','vibration'], 'FC_DL_StatsOutlierCount': ['statistics','outlier','3-sigma'],
 'FB_DL_DualEncoderDeviationWatch': ['motion','dual-encoder','deviation','alarm','state-machine'],
 'FB_DL_MoldCoolingZoneSeq': ['process','mold-cooling','zone-seq','interlock'],
 'FB_DL_AnalogInputRedundancySel': ['device','analog','redundancy','bumpless','validity'],
 'FC_DL_ModbusRtuFrameBuild': ['algo','modbus','rtu','frame','crc16'],
}

out = []
for n, cat, f, tag, cx, batch, tier, src in rows:
    out.append({'name': n, 'category': cat, 'type': 'FB' if n.startswith('FB_') else 'FC',
                'complexity': int(cx[1]), 'tags': TAGS.get(n, ['industrial']),
                'origin': src if '自研' in src else '道莅原创（自研线）', 'license': 'MIT'})
p = r'C:\Library\_Staging_Raw\2026-11-23\_r77_accept.json'
json.dump(out, open(p, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print('accept骨架', len(out), '→', p)
