import '../models/cashier_models.dart';
import '../services/api_client.dart';
import '../services/offline_sale_queue.dart';

enum CashierCheckoutMode { online, offline }

class CashierCheckoutOutcome {
  const CashierCheckoutOutcome._({required this.mode, this.result, this.draft});

  const CashierCheckoutOutcome.online(CheckoutResult result)
    : this._(mode: CashierCheckoutMode.online, result: result);

  const CashierCheckoutOutcome.offline(OfflineSaleDraft draft)
    : this._(mode: CashierCheckoutMode.offline, draft: draft);

  final CashierCheckoutMode mode;
  final CheckoutResult? result;
  final OfflineSaleDraft? draft;
}

class CashierCheckoutController {
  const CashierCheckoutController({
    required this.api,
    required this.offlineQueue,
  });

  final ApiClient api;
  final OfflineSaleQueue offlineQueue;

  Future<CashierCheckoutOutcome> submit({
    required List<CartItem> items,
    required PaymentMethod paymentMethod,
    required double amount,
    required String referenceNumber,
    required int? customerId,
    required int redeemPoints,
    required int receiptColumns,
  }) async {
    try {
      final result = await api.checkout(
        items: items,
        paymentMethodId: paymentMethod.id,
        amount: amount,
        referenceNumber: referenceNumber,
        customerId: customerId,
        redeemPoints: redeemPoints,
        receiptColumns: receiptColumns,
      );

      return CashierCheckoutOutcome.online(result);
    } on NetworkException {
      final draft = OfflineSaleDraft.fromCart(
        cart: items,
        paymentMethodId: paymentMethod.id,
        amount: amount,
        referenceNumber: referenceNumber,
        customerId: customerId,
        redeemPoints: redeemPoints,
      );

      await offlineQueue.enqueue(draft);

      return CashierCheckoutOutcome.offline(draft);
    }
  }
}
