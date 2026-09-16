/// FastAPI 批次接口客户端 (后端 InfluxDB 时序由服务端接入, 平板只读/登记)。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.statusCode, this.code, this.message);

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => 'ApiException($statusCode, $code): $message';
}

class ApiClient {
  ApiClient(this._baseUrl, {http.Client? client})
      : _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  Uri _u(String path) => Uri.parse('$_baseUrl$path');

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Object? body,
    int? expect,
  }) async {
    final req = http.Request(method, _u(path))
      ..headers['Content-Type'] = 'application/json';
    if (body != null) req.body = jsonEncode(body);
    final res = await http.Response.fromStream(await _client.send(req));
    final decoded =
        res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body);
    if (res.statusCode >= 400) {
      throw ApiException(
        res.statusCode,
        (decoded is Map && decoded['code'] != null)
            ? decoded['code'].toString()
            : 'HTTP_${res.statusCode}',
        (decoded is Map && decoded['detail'] != null)
            ? decoded['detail'].toString()
            : res.reasonPhrase ?? '',
      );
    }
    if (expect != null && res.statusCode != expect) {
      throw ApiException(res.statusCode, 'UNEXPECTED_STATUS', res.body);
    }
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  Future<List<dynamic>> _sendList(String method, String path) async {
    final req = http.Request(method, _u(path));
    final streamed = await _client.send(req);
    final res = await http.Response.fromStream(streamed);
    final decoded = res.body.isEmpty ? const [] : jsonDecode(res.body);
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, 'HTTP_${res.statusCode}', res.body);
    }
    return decoded as List<dynamic>;
  }

  Future<Map<String, dynamic>> registerProcedure(Map<String, dynamic> p) =>
      _send('POST', '/api/v1/procedures', body: p, expect: 201);

  Future<Map<String, dynamic>> createBatch(Map<String, dynamic> b) =>
      _send('POST', '/api/v1/batches', body: b, expect: 201);

  Future<Map<String, dynamic>> getBatch(String id) =>
      _send('GET', '/api/v1/batches/$id');

  Future<Map<String, dynamic>> confirmLoading(
    String id,
    Map<String, dynamic> body,
  ) =>
      _send('POST', '/api/v1/batches/$id/loading', body: body, expect: 200);

  Future<Map<String, dynamic>> confirmChecklist(
    String id,
    Map<String, dynamic> body,
  ) =>
      _send('POST', '/api/v1/batches/$id/checklist', body: body, expect: 200);

  Future<Map<String, dynamic>> start(String id) =>
      _send('POST', '/api/v1/batches/$id/start', expect: 200);

  Future<Map<String, dynamic>> complete(String id) =>
      _send('POST', '/api/v1/batches/$id/complete', expect: 200);

  Future<void> postTelemetry(String id, Map<String, dynamic> body) =>
      _send('POST', '/api/v1/batches/$id/telemetry', body: body, expect: 202);

  /// 打弧事件 (微弧/硬弧)。后端写入独立无限保留 bucket, 永不清理。
  Future<Map<String, dynamic>> postArc(String id, Map<String, dynamic> body) =>
      _send('POST', '/api/v1/batches/$id/arcs', body: body, expect: 202);

  /// 辉光图像仅登记元数据 + 过曝标记; 图像仅供人工观察均匀性。
  Future<Map<String, dynamic>> postGlowImage(
    String id,
    Map<String, dynamic> body,
  ) =>
      _send('POST', '/api/v1/batches/$id/glow-images',
          body: body, expect: 202);

  Future<List<dynamic>> stageSeries(String id, int seq) =>
      _sendList('GET', '/api/v1/batches/$id/stages/$seq/series');

  Future<List<dynamic>> arcEvents(String id, {int? stageSeq}) =>
      _sendList(
        'GET',
        '/api/v1/batches/$id/arcs${stageSeq == null ? '' : '?stage_seq=$stageSeq'}',
      );

  Future<List<dynamic>> glowImages(String id, {int? stageSeq}) =>
      _sendList(
        'GET',
        '/api/v1/batches/$id/glow-images${stageSeq == null ? '' : '?stage_seq=$stageSeq'}',
      );

  Future<Map<String, dynamic>> runStageChecks(String id, int seq) =>
      _send('POST', '/api/v1/batches/$id/stages/$seq/checks', expect: 200);

  Future<Map<String, dynamic>> backfillLab(
    String id,
    Map<String, dynamic> body,
  ) =>
      _send('POST', '/api/v1/batches/$id/lab-results', body: body, expect: 201);

  Future<List<dynamic>> anomalies(String id) =>
      _sendList('GET', '/api/v1/batches/$id/anomalies');

  Future<Map<String, dynamic>> dispositionAnomaly(
    String anomalyId,
    Map<String, dynamic> body,
  ) =>
      _send('POST', '/api/v1/anomalies/$anomalyId/disposition',
          body: body, expect: 200);

  Future<Map<String, dynamic>> release(String id, Map<String, dynamic> body) =>
      _send('POST', '/api/v1/batches/$id/release', body: body, expect: 200);

  Future<Map<String, dynamic>> correlation(String id) =>
      _send('GET', '/api/v1/batches/$id/correlation');
}
