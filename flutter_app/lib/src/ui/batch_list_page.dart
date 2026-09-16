import 'package:flutter/material.dart';
import 'package:ion_nitriding_core/ion_nitriding_core.dart';

import 'register_batch_page.dart';
import 'batch_detail_page.dart';

class BatchListPage extends StatefulWidget {
  const BatchListPage({required this.controller, super.key});

  final BatchController controller;

  @override
  State<BatchListPage> createState() => _BatchListPageState();
}

class _BatchListPageState extends State<BatchListPage> {
  late Future<List<BatchRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.controller.cache.listBatches();
  }

  void _refresh() {
    setState(() => _future = widget.controller.cache.listBatches());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('离子氮化批次')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => RegisterBatchPage(controller: widget.controller),
            ),
          );
          _refresh();
        },
        icon: const Icon(Icons.add),
        label: const Text('登记批次'),
      ),
      body: FutureBuilder<List<BatchRecord>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final batches = snap.data!;
          if (batches.isEmpty) {
            return const Center(child: Text('暂无缓存批次, 点击"登记批次"开始'));
          }
          return ListView(
            children: [
              for (final b in batches)
                ListTile(
                  leading: _StatusChip(status: b.status),
                  title: Text('${b.batchId} · 炉 ${b.furnaceId} · ${b.operator}'),
                  subtitle: Text(
                    '程序 ${b.procedureId} · 工件 ${b.parts.length} · '
                    '见证样 ${b.loadedWitness.length}/${b.witnessSamples.length}',
                  ),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            BatchDetailPage(controller: widget.controller, batch: b),
                      ),
                    );
                    _refresh();
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final BatchStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      BatchStatus.released => Colors.green,
      BatchStatus.rejected => Colors.red,
      BatchStatus.hold => Colors.orange,
      BatchStatus.running => Colors.blue,
      _ => Colors.grey,
    };
    return CircleAvatar(backgroundColor: color, radius: 8);
  }
}
