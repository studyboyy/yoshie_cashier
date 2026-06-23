import 'package:flutter/material.dart';

import '../../services/offline_catalog_store.dart';
import '../../services/offline_sale_queue.dart';
import '../../utils/formatters.dart';
import '../common/app_ui.dart';

class OfflineCenterPage extends StatefulWidget {
  const OfflineCenterPage({
    super.key,
    required this.offlineQueue,
    required this.catalogStore,
    required this.syncing,
    required this.onSyncOffline,
    required this.onRefreshCatalog,
  });

  final OfflineSaleQueue offlineQueue;
  final OfflineCatalogStore catalogStore;
  final bool syncing;
  final Future<void> Function() onSyncOffline;
  final Future<void> Function() onRefreshCatalog;

  @override
  State<OfflineCenterPage> createState() => _OfflineCenterPageState();
}

class _OfflineCenterPageState extends State<OfflineCenterPage> {
  late Future<_OfflineCenterData> _future;
  bool _refreshingCatalog = false;
  bool _syncingOffline = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_OfflineCenterData> _load() async {
    final drafts = await widget.offlineQueue.all();
    final catalog = await widget.catalogStore.snapshot();

    return _OfflineCenterData(drafts: drafts, catalog: catalog);
  }

  Future<void> _reload() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _syncOffline() async {
    setState(() => _syncingOffline = true);
    try {
      await widget.onSyncOffline();
      if (mounted) {
        await _reload();
      }
    } finally {
      if (mounted) {
        setState(() => _syncingOffline = false);
      }
    }
  }

  Future<void> _refreshCatalog() async {
    setState(() => _refreshingCatalog = true);
    try {
      await widget.onRefreshCatalog();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Katalog offline berhasil diperbarui.')),
        );
        await _reload();
      }
    } finally {
      if (mounted) {
        setState(() => _refreshingCatalog = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Offline Center'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        surfaceTintColor: Colors.white,
        elevation: 0,
      ),
      body: FutureBuilder<_OfflineCenterData>(
        future: _future,
        builder: (context, snapshot) {
          final data = snapshot.data;

          if (snapshot.connectionState == ConnectionState.waiting &&
              data == null) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return EmptyState(
              text: 'Gagal membaca data offline: ${snapshot.error}',
            );
          }

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _StatusGrid(
                  pendingCount: data?.drafts.length ?? 0,
                  productCount: data?.catalog.productCount ?? 0,
                  updatedAt: data?.catalog.updatedAt,
                  syncing: _syncingOffline || widget.syncing,
                ),
                const SizedBox(height: 12),
                AppSurface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Aksi Offline',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed:
                            _syncingOffline ||
                                widget.syncing ||
                                (data?.drafts.isEmpty ?? true)
                            ? null
                            : _syncOffline,
                        icon: _syncingOffline || widget.syncing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.sync),
                        label: Text(
                          _syncingOffline || widget.syncing
                              ? 'Menyinkronkan...'
                              : 'Sync Transaksi Pending',
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _refreshingCatalog ? null : _refreshCatalog,
                        icon: _refreshingCatalog
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.cloud_download_outlined),
                        label: const Text('Sync Katalog Produk'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _PendingDraftList(drafts: data?.drafts ?? const []),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatusGrid extends StatelessWidget {
  const _StatusGrid({
    required this.pendingCount,
    required this.productCount,
    required this.updatedAt,
    required this.syncing,
  });

  final int pendingCount;
  final int productCount;
  final DateTime? updatedAt;
  final bool syncing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620 ? 3 : 1;
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: columns == 1 ? 3.4 : 1.6,
          children: [
            _StatusCard(
              icon: Icons.receipt_long_outlined,
              label: 'Transaksi pending',
              value: '$pendingCount',
              color: pendingCount > 0
                  ? const Color(0xFFF59E0B)
                  : const Color(0xFF10B981),
            ),
            _StatusCard(
              icon: Icons.inventory_2_outlined,
              label: 'Produk offline',
              value: '$productCount',
              color: const Color(0xFF4F46E5),
            ),
            _StatusCard(
              icon: syncing ? Icons.sync : Icons.schedule_outlined,
              label: 'Katalog terakhir',
              value: updatedAt == null
                  ? 'Belum ada'
                  : receiptDateTime(updatedAt!),
              color: const Color(0xFF0EA5E9),
            ),
          ],
        );
      },
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingDraftList extends StatelessWidget {
  const _PendingDraftList({required this.drafts});

  final List<OfflineSaleDraft> drafts;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Text(
              'Transaksi Pending',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ),
          if (drafts.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 8, 14, 16),
              child: Text(
                'Tidak ada transaksi offline pending.',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            ...drafts.map((draft) => _DraftTile(draft: draft)),
        ],
      ),
    );
  }
}

class _DraftTile extends StatelessWidget {
  const _DraftTile({required this.draft});

  final OfflineSaleDraft draft;

  double get _total {
    var total = 0.0;
    for (final item in draft.cartItems) {
      final subtotal = item['subtotal'];
      if (subtotal is num) {
        total += subtotal.toDouble();
      } else {
        total += double.tryParse(subtotal?.toString() ?? '') ?? 0;
      }
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.pending_actions_outlined,
              color: Color(0xFFD97706),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  draft.localReference,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  '${draft.cartItems.length} item • ${receiptDateTime(draft.createdAt)}',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: draft.cartItems.take(3).map((item) {
                    final name = item['product_name']?.toString() ?? 'Produk';
                    final quantity = item['quantity']?.toString() ?? '1';
                    return AppPill('$name x$quantity');
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            rupiah(_total),
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineCenterData {
  const _OfflineCenterData({required this.drafts, required this.catalog});

  final List<OfflineSaleDraft> drafts;
  final OfflineCatalogSnapshot catalog;
}
