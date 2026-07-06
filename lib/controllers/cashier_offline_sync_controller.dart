import '../models/cashier_models.dart';
import '../services/api_client.dart';
import '../services/offline_return_queue.dart';
import '../services/offline_sale_queue.dart';

class OfflineSyncResult {
  const OfflineSyncResult({
    required this.pendingBeforeSync,
    required this.syncedCount,
    this.syncedReferences = const <String>[],
  });

  final int pendingBeforeSync;
  final int syncedCount;
  final List<String> syncedReferences;

  bool get hasPending => pendingBeforeSync > 0;
}

class CashierOfflineSyncController {
  const CashierOfflineSyncController({
    required this.api,
    required this.offlineQueue,
    required this.offlineReturnQueue,
  });

  final ApiClient api;
  final OfflineSaleQueue offlineQueue;
  final OfflineReturnQueue offlineReturnQueue;

  Future<int> pendingCount() {
    return offlineQueue.count();
  }

  Future<OfflineSyncResult> syncPending() async {
    final drafts = await offlineQueue.all();
    var synced = 0;
    final syncedReferences = <String>[];

    for (final draft in drafts) {
      final syncedSale = await api.syncOfflineSale(draft);
      final returnDrafts = await offlineReturnQueue.forReference(
        draft.localReference,
      );

      if (returnDrafts.isNotEmpty) {
        for (final returnDraft in returnDrafts) {
          final serverSale = await api.returnPreview(syncedSale.saleId);
          final serverItemsByProduct = {
            for (final item in serverSale.items) item.productId: item,
          };
          final mappedItems = returnDraft.items
              .map((item) {
                final serverItem = serverItemsByProduct[item.productId];
                if (serverItem == null) {
                  return null;
                }

                return SaleReturnItemRequest(
                  saleItemId: serverItem.id,
                  productId: serverItem.productId,
                  qty: item.qty,
                  condition: item.condition,
                );
              })
              .whereType<SaleReturnItemRequest>()
              .toList();

          if (mappedItems.isNotEmpty) {
            await api.createSaleReturn(
              saleId: syncedSale.saleId,
              items: mappedItems,
              reason: returnDraft.reason,
            );
          }
        }

        await offlineReturnQueue.removeForReference(draft.localReference);
      }

      await offlineQueue.remove(draft.localReference);
      synced++;
      syncedReferences.add(draft.localReference.toUpperCase());
    }

    return OfflineSyncResult(
      pendingBeforeSync: drafts.length,
      syncedCount: synced,
      syncedReferences: syncedReferences,
    );
  }
}
