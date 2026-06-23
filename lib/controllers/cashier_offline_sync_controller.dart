import '../services/api_client.dart';
import '../services/offline_sale_queue.dart';

class OfflineSyncResult {
  const OfflineSyncResult({
    required this.pendingBeforeSync,
    required this.syncedCount,
  });

  final int pendingBeforeSync;
  final int syncedCount;

  bool get hasPending => pendingBeforeSync > 0;
}

class CashierOfflineSyncController {
  const CashierOfflineSyncController({
    required this.api,
    required this.offlineQueue,
  });

  final ApiClient api;
  final OfflineSaleQueue offlineQueue;

  Future<int> pendingCount() {
    return offlineQueue.count();
  }

  Future<OfflineSyncResult> syncPending() async {
    final drafts = await offlineQueue.all();
    var synced = 0;

    for (final draft in drafts) {
      await api.syncOfflineSale(draft);
      await offlineQueue.remove(draft.localReference);
      synced++;
    }

    return OfflineSyncResult(
      pendingBeforeSync: drafts.length,
      syncedCount: synced,
    );
  }
}
