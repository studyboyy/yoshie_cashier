import 'package:flutter_cashier/controllers/cashier_offline_sync_controller.dart';
import 'package:flutter_cashier/models/cashier_models.dart';
import 'package:flutter_cashier/services/api_client.dart';
import 'package:flutter_cashier/services/offline_return_queue.dart';
import 'package:flutter_cashier/services/offline_sale_queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('syncs all pending offline sales and removes them from queue', () async {
    final queue = OfflineSaleQueue();
    await queue.enqueue(
      OfflineSaleDraft.fromCart(
        cart: [_cartItem()],
        paymentMethodId: 1,
        amount: 10000,
        referenceNumber: null,
        customerId: null,
        redeemPoints: 0,
      ),
    );

    final api = _SyncApiClient();
    final controller = CashierOfflineSyncController(
      api: api,
      offlineQueue: queue,
      offlineReturnQueue: const OfflineReturnQueue(),
    );

    final result = await controller.syncPending();

    expect(result.pendingBeforeSync, 1);
    expect(result.syncedCount, 1);
    expect(api.syncedReferences, hasLength(1));
    expect(await queue.count(), 0);
  });

  test('does not sync duplicate local references twice', () async {
    final queue = OfflineSaleQueue();
    final draft = OfflineSaleDraft(
      localReference: 'LOCAL-DUPLICATE-001',
      createdAt: DateTime(2026, 6, 22, 10),
      cartItems: [_cartItem().toOfflineJson()],
      payment: {'payment_method_id': 1, 'amount': 10000},
    );

    await queue.enqueue(draft);
    await queue.enqueue(draft);

    expect(await queue.count(), 1);

    final api = _SyncApiClient();
    final controller = CashierOfflineSyncController(
      api: api,
      offlineQueue: queue,
      offlineReturnQueue: const OfflineReturnQueue(),
    );

    final result = await controller.syncPending();

    expect(result.pendingBeforeSync, 1);
    expect(result.syncedCount, 1);
    expect(api.syncedReferences, ['LOCAL-DUPLICATE-001']);
    expect(await queue.count(), 0);
  });

  test('reports pending count before and after manual sync', () async {
    final queue = OfflineSaleQueue();
    final controller = CashierOfflineSyncController(
      api: _SyncApiClient(),
      offlineQueue: queue,
      offlineReturnQueue: const OfflineReturnQueue(),
    );

    expect(await controller.pendingCount(), 0);

    await queue.enqueue(
      OfflineSaleDraft.fromCart(
        cart: [_cartItem()],
        paymentMethodId: 1,
        amount: 10000,
        referenceNumber: null,
        customerId: null,
        redeemPoints: 0,
      ),
    );

    expect(await controller.pendingCount(), 1);

    final result = await controller.syncPending();

    expect(result.hasPending, isTrue);
    expect(result.syncedCount, 1);
    expect(await controller.pendingCount(), 0);
  });

  test(
    'continues syncing next drafts when one draft fails validation',
    () async {
      final queue = OfflineSaleQueue();
      final failedDraft = OfflineSaleDraft(
        localReference: 'LOCAL-FAILED-001',
        createdAt: DateTime(2026, 6, 22, 10),
        cartItems: [_cartItem().toOfflineJson()],
        payment: {'payment_method_id': 1, 'amount': 10000},
      );
      final validDraft = OfflineSaleDraft(
        localReference: 'LOCAL-OK-001',
        createdAt: DateTime(2026, 6, 22, 10, 1),
        cartItems: [_cartItem().toOfflineJson()],
        payment: {'payment_method_id': 1, 'amount': 10000},
      );

      await queue.enqueue(failedDraft);
      await queue.enqueue(validDraft);

      final api = _SyncApiClient(failReferences: {'LOCAL-FAILED-001'});
      final controller = CashierOfflineSyncController(
        api: api,
        offlineQueue: queue,
        offlineReturnQueue: const OfflineReturnQueue(),
      );

      final result = await controller.syncPending();
      final remaining = await queue.all();

      expect(result.pendingBeforeSync, 2);
      expect(result.syncedCount, 1);
      expect(result.failedCount, 1);
      expect(result.failedReferences.keys, contains('LOCAL-FAILED-001'));
      expect(api.syncedReferences, ['LOCAL-FAILED-001', 'LOCAL-OK-001']);
      expect(remaining.map((draft) => draft.localReference), [
        'LOCAL-FAILED-001',
      ]);
    },
  );
}

class _SyncApiClient extends ApiClient {
  _SyncApiClient({this.failReferences = const <String>{}});

  final Set<String> failReferences;
  final syncedReferences = <String>[];

  @override
  Future<SyncedOfflineSale> syncOfflineSale(OfflineSaleDraft draft) async {
    syncedReferences.add(draft.localReference);
    if (failReferences.contains(draft.localReference)) {
      throw const ApiException('Stok produk tidak cukup.');
    }

    return const SyncedOfflineSale(saleId: 1, invoiceNumber: 'INV-SYNC');
  }
}

CartItem _cartItem() {
  return CartItem(
    product: const CashierProduct(
      id: 1,
      name: 'Gelang',
      sku: 'GLG',
      unit: 'pcs',
      price: 10000,
      priceText: 'Rp 10.000',
      stock: 10,
    ),
  );
}
