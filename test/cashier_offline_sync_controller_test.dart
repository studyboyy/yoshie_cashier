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
}

class _SyncApiClient extends ApiClient {
  final syncedReferences = <String>[];

  @override
  Future<SyncedOfflineSale> syncOfflineSale(OfflineSaleDraft draft) async {
    syncedReferences.add(draft.localReference);
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
