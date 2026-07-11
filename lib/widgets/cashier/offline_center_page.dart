import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    final backupCount = await widget.offlineQueue.backupCount();
    final backupUpdatedAt = await widget.offlineQueue.backupUpdatedAt();
    final catalog = await widget.catalogStore.snapshot();

    return _OfflineCenterData(
      drafts: drafts,
      catalog: catalog,
      backupCount: backupCount,
      backupUpdatedAt: backupUpdatedAt,
    );
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
                  failedCount:
                      data?.drafts
                          .where((draft) => draft.syncStatus == 'failed')
                          .length ??
                      0,
                  backupCount: data?.backupCount ?? 0,
                  productCount: data?.catalog.productCount ?? 0,
                  syncing: _syncingOffline || widget.syncing,
                ),
                const SizedBox(height: 12),
                _BackupCard(
                  backupCount: data?.backupCount ?? 0,
                  backupUpdatedAt: data?.backupUpdatedAt,
                  onCopyBackup: _copyBackupJson,
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

  Future<void> _copyBackupJson() async {
    final json = await widget.offlineQueue.backupJson();
    if (!mounted) {
      return;
    }

    await Clipboard.setData(ClipboardData(text: json));
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Backup offline disalin ke clipboard.')),
    );
  }
}

class _StatusGrid extends StatelessWidget {
  const _StatusGrid({
    required this.pendingCount,
    required this.failedCount,
    required this.backupCount,
    required this.productCount,
    required this.syncing,
  });

  final int pendingCount;
  final int failedCount;
  final int backupCount;
  final int productCount;
  final bool syncing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760
            ? 4
            : constraints.maxWidth >= 520
            ? 2
            : 1;
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
              icon: Icons.backup_outlined,
              label: 'Backup transaksi',
              value: '$backupCount',
              color: const Color(0xFF4F46E5),
            ),
            _StatusCard(
              icon: Icons.error_outline,
              label: 'Sync gagal',
              value: '$failedCount',
              color: failedCount > 0
                  ? const Color(0xFFEF4444)
                  : const Color(0xFF10B981),
            ),
            _StatusCard(
              icon: syncing ? Icons.sync : Icons.schedule_outlined,
              label: 'Produk offline',
              value: '$productCount produk',
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

class _BackupCard extends StatelessWidget {
  const _BackupCard({
    required this.backupCount,
    required this.backupUpdatedAt,
    required this.onCopyBackup,
  });

  final int backupCount;
  final DateTime? backupUpdatedAt;
  final VoidCallback onCopyBackup;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.cloud_done_outlined,
                  color: Color(0xFF059669),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Backup Offline Otomatis',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      backupUpdatedAt == null
                          ? 'Belum ada backup transaksi.'
                          : 'Terakhir: ${receiptDateTime(backupUpdatedAt!)}',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            backupCount == 0
                ? 'Saat kasir transaksi offline, APK akan menyimpan salinan lokal otomatis sebagai cadangan.'
                : '$backupCount transaksi offline tersimpan sebagai cadangan lokal.',
            style: const TextStyle(
              color: Color(0xFF334155),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: backupCount == 0 ? null : onCopyBackup,
            icon: const Icon(Icons.copy_all_outlined),
            label: const Text('Salin Backup JSON'),
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
    final status = _DraftStatus.fromDraft(draft);

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
              color: status.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(status.icon, color: status.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        draft.localReference,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusChip(status: status),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${draft.cartItems.length} item • ${receiptDateTime(draft.createdAt)}',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (draft.attemptCount > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Percobaan sync: ${draft.attemptCount}${draft.lastAttemptAt == null ? '' : ' • ${receiptDateTime(draft.lastAttemptAt!)}'}',
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
                if ((draft.lastError ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    draft.lastError!.trim(),
                    style: const TextStyle(
                      color: Color(0xFFB91C1C),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ],
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final _DraftStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: status.color,
          fontWeight: FontWeight.w900,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _DraftStatus {
  const _DraftStatus({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  factory _DraftStatus.fromDraft(OfflineSaleDraft draft) {
    return switch (draft.syncStatus) {
      'syncing' => const _DraftStatus(
        label: 'Syncing',
        icon: Icons.sync,
        color: Color(0xFF2563EB),
      ),
      'failed' => const _DraftStatus(
        label: 'Gagal',
        icon: Icons.error_outline,
        color: Color(0xFFDC2626),
      ),
      _ => const _DraftStatus(
        label: 'Pending',
        icon: Icons.pending_actions_outlined,
        color: Color(0xFFD97706),
      ),
    };
  }
}

class _OfflineCenterData {
  const _OfflineCenterData({
    required this.drafts,
    required this.catalog,
    required this.backupCount,
    required this.backupUpdatedAt,
  });

  final List<OfflineSaleDraft> drafts;
  final OfflineCatalogSnapshot catalog;
  final int backupCount;
  final DateTime? backupUpdatedAt;
}
