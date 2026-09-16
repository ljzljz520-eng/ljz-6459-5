# 离子氮化批次管理系统

把**真空(压力)、气体比例、偏压电流、辉光图像、工件温度**等过程数据与最终
**化合物层 / 扩散层**金相结果关联到同一批次; **局部打弧(微弧/硬弧)必须永久保留**,
不允许抑制、去重或随保留期清除。

- **平板交互**: Flutter (`flutter_app/`)
- **业务逻辑**: 平台无关纯 Dart (`core/`, 可独立单测, Flutter 与 Drift 均不参与)
- **车间记录缓存**: Drift (`flutter_app/lib/src/data/local_database.dart`)
- **批次接口**: FastAPI (`backend/`)
- **炉体时序**: InfluxDB (`furnace_telemetry` / `glow_images` / 独立无限保留 `arc_events`)
- **元数据**: SQLite(服务端 stdlib `sqlite3`, 无需 ORM; 生产可换 Postgres)

## 业务流程

1. **登记批次**: 操作员登记工件材质/前处理/装夹位置、计划见证样、炉号、操作员、已批准工艺规程。
2. **装炉确认**: 逐个确认实际装上的见证样 —— 漏装立即 `409 WITNESS_MISSING` 并登记异常;
   未登记编号 `409 WITNESS_UNKNOWN`。
3. **气路/绝缘确认**: 必须勾选气路、绝缘, 并登记物理通道映射 (`MFC1->N2` 等)。
4. **执行批准程序**: `DRAFT -> CHECKED -> RUNNING`; 未完成清单 `409 BAD_STATE`,
   存在未处置的见证样漏装偏差 `409 WITNESS_DEVIATION_OPEN`。
5. **执行中按阶段监视**: 抽真空/升温/辉光清洗/氮化/扩散/冷却 —— 展示压力、气体比例、
   偏压电压电流波动、工件温度、微弧/硬弧事件; 阶段检查给出通道互换、热电偶干扰、频繁微弧结论。
6. **辉光图像仅用于人工观察均匀性**: 系统只登记 URI/平均灰度/过曝标记;
   过曝只提示 `GLOW_OVEREXPOSED`, **不自动停批/判废**。
7. **出炉 -> 实验室回填**金相结论、显微硬度梯度、化合物层厚度、扩散层深度
   (`COMPLETED -> LAB_PARTIAL -> LAB_COMPLETE`); 只能为**实际装炉**的见证样回填。
8. **工艺工程师放行**: 金相层结果超出规程窗口 `409 SPEC_FAILURE`;
   存在未处置异常 `409 ANOMALY_OPEN`; 全部通过才允许 `RELEASED`, 也可 `HOLD/REJECTED`。
9. **追溯关联**: `GET /batches/{id}/correlation` 一次返回每阶段聚合参数、打弧计数、
   辉光 URI、实验室层结果、异常处置记录与放行结论。

## 目录

```
backend/                 FastAPI + SQLite 元数据 + InfluxDB/内存时序
  app/
    main.py              应用装配与 DomainError -> 409/404
    models.py            枚举/状态机/ID
    schemas.py           Pydantic DTO
    db.py                车间元数据 (SQLite)
    influx.py            Point + InfluxDB 实现 + 内存实现(测试)
    services/
      batch_service.py   登记/装炉/清单/执行
      telemetry_service.py 时序/打弧/辉光接入与阶段聚合
      anomaly_service.py 通道互换/热电偶干扰/频繁微弧
      lab_service.py     实验室回填与放行判定
    api/                 batches / telemetry / lab 路由
  tests/                 14 个 pytest (含五个验收场景)
core/                    纯 Dart 业务逻辑 (与后端规则对齐) + http 客户端 + 离线缓存接口
  lib/src/domain/        models / rules / stage_summary
  lib/src/state/         BatchController
  lib/src/data/          ApiClient / BatchCache
  test/                  14 个 dart test
flutter_app/             Flutter 平板应用 + Drift 缓存
  lib/src/data/local_database.dart  Drift 表 (build_runner 生成 _$LocalDatabase)
  lib/src/ui/           批次列表/登记/详情清单/阶段监视/放行
```

## 运行后端

```bash
cd backend
pip install -r requirements.txt
uvicorn app.main:app --reload          # 默认内存时序 + :memory: SQLite
pytest -q                               # 14 passed
```

生产用环境变量切换 InfluxDB 与持久 SQLite:
`NITRIDING_DB`, `INFLUX_URL`, `INFLUX_TOKEN`, `INFLUX_ORG`, `INFLUX_BUCKET`,
`INFLUX_ARC_BUCKET`。也可用 `docker compose up -d`(自动创建无限保留期 `arc-events` bucket)。

## 运行 Dart/Flutter

```bash
cd core && dart pub get && dart test                 # 14 passed, 纯 Dart
cd ../flutter_app
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # 生成 Drift 代码
flutter run -d <tablet>
```

> 注: 本仓库构建环境为 linux-arm64, 无 arm64 官方 Flutter SDK, 故 Flutter UI 未经
> `flutter analyze`; 平台无关逻辑全部在 `core/`, 已用 Dart 3.13 单测覆盖。

## 规则阈值 (后端与 Dart 保持一致)

| 规则 | 阈值 | 位置 |
|---|---|---|
| 气体比例互换容差 | 直接比例偏差 > 0.05 且出现交叉匹配 | anomaly_service / rules.dart |
| 热电偶等离子体干扰 | 偏压 >100V 时, 工件偶-控温偶偏差 >40°C 的点 ≥50% | 同上 |
| 频繁微弧 | 60 s 滑窗峰值 > 6 次/min (可被规程每阶段覆盖) | 同上 |
| 辉光过曝 | 平均灰度 ≥ 220 (0-255), 仅提示 | telemetry_service / rules.dart |
| 打弧保留 | `arc_events` 独立 measurement/bucket, retention=0(无限) | influx.py / docker-compose |

## 需求 -> 测试追溯矩阵

| 需求点 | 后端测试 | Dart 测试 |
|---|---|---|
| 登记材质/前处理/装夹位置/见证样 | test_batch_flow (ready_batch) | batch_controller_test 登记 |
| 气路+绝缘+通道映射确认后才执行 | test_checklist_required_before_start | batch_controller_test 清单拦截 |
| 见证样漏装拦截并留异常 | test_missing_witness_blocks_loading | rules_test LoadingCheck; controller 漏装拦截 |
| 未装见证样不得回填金相 | test_lab_result_rejected_for_unloaded_sample | — |
| 气体流量通道互换 | test_gas_channel_swap_detected / _normal | rules_test 气体通道互换 |
| 辉光图像过曝仅提示不判废 | test_overexposed_glow_image_flagged / _normal | rules_test 辉光过曝 |
| 热电偶受等离子体影响 | test_tc_plasma_interference_detected / _normal | rules_test 热电偶 |
| 频繁微弧报警 | test_frequent_micro_arcs / _sparse | rules_test 频繁微弧 |
| 局部打弧必须保留(不抑制) | 10 个微弧全部可查; HARD_ARC preserved=True | rules_test 保留标志; 计数不删除 |
| 异常未处置禁止放行 | test_release_blocked_until_arc_anomaly_dispositioned | — |
| 化合物层/扩散层超窗禁止 RELEASE | test_release_blocked_when_layer_out_of_spec | — |
| 全过程参数<->层结果关联 | test_full_happy_path correlation 断言 | stage_summary_test 聚合 |
| 状态机/完整放行 | test_full_happy_path | controller 全流程 MockClient |
