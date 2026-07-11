import '../models/cashier_models.dart';
import '../services/api_client.dart';
import '../services/offline_return_queue.dart';
import '../services/offline_sale_queue.dart';

class OfflineSyncResult {
  const OfflineSyncResult({
    required this.pendingBeforeSync,
    required this.syncedCount,
    this.syncedReferences = const <String>[],
    this.failedReferences = const <String, String>{},
  });

  final int pendingBeforeSync;
  final int syncedCount;
  final List<String> syncedReferences;
  final Map<String, String> failedReferences;

  bool get hasPending => pendingBeforeSync > 0;
  int get failedCount => failedReferences.length;
  int get remainingCount => pendingBeforeSync - syncedCount;
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
    final failedReferences = <String, String>{};

    for (final draft in drafts) {
      try {
        await offlineQueue.markAttempt(draft.localReference);
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
        if (syncedSale.invoiceNumber.trim().isNotEmpty) {
          syncedReferences.add(syncedSale.invoiceNumber.toUpperCase());
        }
      } on NetworkException {
        await offlineQueue.markPending(draft.localReference);
        rethrow;
      } on UnauthorizedException {
        await offlineQueue.markPending(draft.localReference);
        rethrow;
      } on ForbiddenException {
        await offlineQueue.markPending(draft.localReference);
        rethrow;
      } catch (error) {
        final message = error.toString().replaceFirst('Exception: ', '');
        await offlineQueue.markFailed(draft.localReference, message);
        failedReferences[draft.localReference.toUpperCase()] = message;
      }
    }

    return OfflineSyncResult(
      pendingBeforeSync: drafts.length,
      syncedCount: synced,
      syncedReferences: syncedReferences,
      failedReferences: failedReferences,
    );
  }
}
