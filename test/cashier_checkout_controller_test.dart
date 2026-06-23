import 'package:flutter_cashier/controllers/cashier_checkout_controller.dart';
import 'package:flutter_cashier/models/cashier_models.dart';
import 'package:flutter_cashier/services/api_client.dart';
import 'package:flutter_cashier/services/offline_sale_queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('returns online outcome when checkout succeeds', () async {
    final controller = CashierCheckoutController(
      api: _CheckoutApiClient(),
      offlineQueue: OfflineSaleQueue(),
    );

    final outcome = await controller.submit(
      items: [_cartItem()],
      paymentMethod: _paymentMethod(),
      amount: 10000,
      referenceNumber: '',
      customerId: null,
      redeemPoints: 0,
      receiptColumns: 32,
    );

    expect(outcome.mode, CashierCheckoutMode.online);
    expect(outcome.result?.invoiceNumber, 'INV-TEST');
  });

  test('queues offline draft when checkout hits network error', () async {
    final queue = OfflineSaleQueue();
    final controller = CashierCheckoutController(
      api: _CheckoutApiClient(throwNetwork: true),
      offlineQueue: queue,
    );

    final outcome = await controller.submit(
      items: [_cartItem()],
      paymentMethod: _paymentMethod(),
      amount: 10000,
      referenceNumber: 'REF-1',
      customerId: 7,
      redeemPoints: 2,
      receiptColumns: 32,
    );

    final queued = await queue.all();

    expect(outcome.mode, CashierCheckoutMode.offline);
    expect(queued, hasLength(1));
    expect(outcome.draft?.localReference, queued.single.localReference);
    expect(queued.single.cartItems, hasLength(1));
    expect(queued.single.cartItems.single['product_id'], 1);
    expect(queued.single.payment['payment_method_id'], 1);
    expect(queued.single.payment['amount'], 10000);
    expect(queued.single.payment['reference_number'], 'REF-1');
    expect(queued.single.payment['customer_id'], 7);
    expect(queued.single.payment['redeem_points'], 2);
  });
}

class _CheckoutApiClient extends ApiClient {
  _CheckoutApiClient({this.throwNetwork = false});

  final bool throwNetwork;

  @override
  Future<CheckoutResult> checkout({
    required List<CartItem> items,
    required int paymentMethodId,
    required double amount,
    String? referenceNumber,
    int? customerId,
    int redeemPoints = 0,
    int receiptColumns = 32,
  }) async {
    if (throwNetwork) {
      throw const NetworkException('offline');
    }

    return const CheckoutResult(
      invoiceNumber: 'INV-TEST',
      receiptText: 'receipt',
      grandTotal: 10000,
      paidAmount: 10000,
      changeAmount: 0,
    );
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

PaymentMethod _paymentMethod() {
  return const PaymentMethod(id: 1, name: 'Cash', code: 'cash');
}
