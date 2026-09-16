import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ion_nitriding_core/ion_nitriding_core.dart';
import 'package:test/test.dart';

const batchJson = {
  'batch_id': 'BN-1',
  'furnace_id': 'LD-50',
  'operator': 'zhang.wei',
  'procedure_id': 'PN-X',
  'status': 'DRAFT',
  'parts': [
    {
      'part_no': 'GEAR-001',
      'material': '42CrMo',
      'pretreatment': '调质+除油',
      'fixture_position': '上层A1',
    }
  ],
  'witness_samples': [
    {'sample_no': 'WS-01', 'material': '42CrMo', 'fixture_position': 'B1'},
    {'sample_no': 'WS-02', 'material': '42CrMo', 'fixture_position': 'C2'},
  ],
  'loaded_witness': <dynamic>[],
  'checklist': {
    'gas_line_confirmed': false,
    'insulation_confirmed': false,
    'gas_channel_mapping': <String, String>{},
  },
  'created_ts': 1.0,
  'started_ts': null,
  'completed_ts': null,
};

http.Response jsonResp(Object body, int code) => http.Response(
      jsonEncode(body),
      code,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  test('登记 -> 漏装客户端拦截 -> 补装 -> 清单 -> 启动 (MockClient)', () async {
    final requests = <http.Request>[];
    final current = Map<String, dynamic>.from(batchJson);

    final mock = MockClient((req) async {
      requests.add(req);
      final body = req.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(req.body) as Map<String, dynamic>;
      if (req.method == 'POST' && req.url.path.endsWith('/batches')) {
        return jsonResp(current, 201);
      }
      if (req.url.path.endsWith('/loading')) {
        current['loaded_witness'] = body['loaded_witness'];
        return jsonResp(current, 200);
      }
      if (req.url.path.endsWith('/checklist')) {
        current['status'] = 'CHECKED';
        current['checklist'] = body;
        return jsonResp(current, 200);
      }
      if (req.url.path.endsWith('/start')) {
        current['status'] = 'RUNNING';
        return jsonResp(current, 200);
      }
      return jsonResp({}, 404);
    });

    final cache = InMemoryBatchCache();
    final ctl = BatchController(
      api: ApiClient('http://x', client: mock),
      cache: cache,
    );

    final b = await ctl.registerBatch(
      furnaceId: 'LD-50',
      operator: 'zhang.wei',
      procedureId: 'PN-X',
      parts: const [
        Part(
          partNo: 'GEAR-001',
          material: '42CrMo',
          pretreatment: '调质+除油',
          fixturePosition: '上层A1',
        ),
      ],
      witnessSamples: const [
        WitnessSample(sampleNo: 'WS-01', material: '42CrMo', fixturePosition: 'B1'),
        WitnessSample(sampleNo: 'WS-02', material: '42CrMo', fixturePosition: 'C2'),
      ],
    );
    expect(b.status, BatchStatus.draft);

    // 场景5: 漏装 WS-02 客户端先拦截, 不发请求
    final before = requests.length;
    await expectLater(
      ctl.confirmLoading(b.batchId, const [
        LoadedWitness(sampleNo: 'WS-01', fixturePosition: 'B1'),
      ]),
      throwsA(isA<LoadingMismatch>()
          .having((e) => e.missing, 'missing', ['WS-02'])),
    );
    expect(requests.length, before);

    // 补齐后通过并缓存
    final loaded = await ctl.confirmLoading(b.batchId, const [
      LoadedWitness(sampleNo: 'WS-01', fixturePosition: 'B1'),
      LoadedWitness(sampleNo: 'WS-02', fixturePosition: 'C2'),
    ]);
    expect(loaded.loadingConfirmed, isTrue);
    expect((await cache.getBatch('BN-1'))!.loadedWitness.length, 2);

    // 清单未确认时拒绝启动
    expect(
      () => ctl.confirmChecklist(
        b.batchId,
        const Checklist(gasLineConfirmed: true),
      ),
      throwsA(isA<StateError>()),
    );

    await ctl.confirmChecklist(
      b.batchId,
      const Checklist(
        gasLineConfirmed: true,
        insulationConfirmed: true,
        gasChannelMapping: {'MFC1': 'N2', 'MFC2': 'H2', 'MFC3': 'Ar'},
      ),
    );
    final running = await ctl.start(b.batchId);
    expect(running.status, BatchStatus.running);
  });

  test('ApiException 解析后端错误码 (409 WITNESS_MISSING)', () async {
    final mock = MockClient(
      (req) async => jsonResp(
        {'code': 'WITNESS_MISSING', 'detail': '见证样漏装: WS-02'},
        409,
      ),
    );
    final api = ApiClient('http://x', client: mock);
    try {
      await api.confirmLoading('BN-1', {'loaded_witness': []});
      fail('should throw');
    } on ApiException catch (e) {
      expect(e.statusCode, 409);
      expect(e.code, 'WITNESS_MISSING');
    }
  });
}
