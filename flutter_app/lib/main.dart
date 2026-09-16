import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:ion_nitriding_core/ion_nitriding_core.dart';

import 'src/data/drift_cache.dart';
import 'src/data/local_database.dart';
import 'src/ui/batch_list_page.dart';

void main() {
  // 生产环境应使用 NativeDatabase.createInBackground(应用目录/xxx.db);
  // 此处给出显式装配点, 便于平板部署时替换。
  final db = LocalDatabase(NativeDatabase.memory());
  final api = ApiClient('http://10.0.2.2:8000');
  final controller = BatchController(api: api, cache: DriftBatchCache(db));
  runApp(IonNitridingApp(controller: controller));
}

class IonNitridingApp extends StatelessWidget {
  const IonNitridingApp({required this.controller, super.key});

  final BatchController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '离子氮化批次',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: BatchListPage(controller: controller),
    );
  }
}
