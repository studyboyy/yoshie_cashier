import '../models/cashier_models.dart';
import '../services/api_client.dart';
import '../services/offline_sale_queue.dart';
import '../utils/formatters.dart';

enum CashierCheckoutMode { online, offline }

class CashierCheckoutOutcome {
  const CashierCheckoutOutcome._({required this.mode, this.result, this.draft});

  const CashierCheckoutOutcome.online(CheckoutResult result)
    : this._(mode: CashierCheckoutMode.online, result: result);

  const CashierCheckoutOutcome.offline(
    OfflineSaleDraft draft,
    CheckoutResult result,
  ) : this._(mode: CashierCheckoutMode.offline, draft: draft, result: result);

  final CashierCheckoutMode mode;
  final CheckoutResult? result;
  final OfflineSaleDraft? draft;
}

class OfflineReceiptContext {
  const OfflineReceiptContext({
    required this.outletName,
    required this.cashierName,
    this.customerName,
  });

  final String outletName;
  final String cashierName;
  final String? customerName;
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
    required OfflineReceiptContext offlineReceiptContext,
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
      final result = offlineResultFromDraft(
        draft: draft,
        paymentMethod: paymentMethod,
        receiptColumns: receiptColumns,
        context: offlineReceiptContext,
      );

      return CashierCheckoutOutcome.offline(draft, result);
    }
  }

  CheckoutResult offlineResultFromDraft({
    required OfflineSaleDraft draft,
    required PaymentMethod paymentMethod,
    required int receiptColumns,
    required OfflineReceiptContext context,
  }) {
    final grandTotal = draft.cartItems.fold<double>(
      0,
      (total, item) => total + _asDouble(item['subtotal']),
    );
    final paidAmount = _asDouble(draft.payment['amount']);
    final changeAmount = (paidAmount - grandTotal).clamp(0, double.infinity);
    final invoiceNumber = draft.localReference.toUpperCase();
    final receiptText = _offlineReceiptText(
      draft: draft,
      paymentMethod: paymentMethod,
      invoiceNumber: invoiceNumber,
      grandTotal: grandTotal,
      paidAmount: paidAmount,
      changeAmount: changeAmount.toDouble(),
      receiptColumns: receiptColumns,
      context: context,
    );

    return CheckoutResult(
      invoiceNumber: invoiceNumber,
      receiptText: receiptText,
      grandTotal: grandTotal,
      paidAmount: paidAmount,
      changeAmount: changeAmount.toDouble(),
    );
  }

  String _offlineReceiptText({
    required OfflineSaleDraft draft,
    required PaymentMethod paymentMethod,
    required String invoiceNumber,
    required double grandTotal,
    required double paidAmount,
    required double changeAmount,
    required int receiptColumns,
    required OfflineReceiptContext context,
  }) {
    final width = receiptColumns == 42 ? 42 : 32;
    final line = '-' * width;
    final rows = <String>[
      centerReceiptText('Yosy Group', width),
      centerReceiptText('STRUK OFFLINE', width),
      line,
      _kv('No', invoiceNumber, width),
      _kv('Tgl', receiptDateTime(draft.createdAt), width),
      _kv('Kasir', context.cashierName, width),
      _kv('Cabang', context.outletName, width),
      if ((context.customerName ?? '').trim().isNotEmpty)
        _kv('Member', context.customerName!.trim(), width),
      line,
    ];

    for (final item in draft.cartItems) {
      final name = item['product_name'] as String? ?? '-';
      final quantity = _asInt(item['quantity']);
      final unitPrice = _asDouble(item['unit_price']);
      final subtotal = _asDouble(item['subtotal']);
      rows
        ..addAll(_wrap(name, width))
        ..add(_itemLine(quantity, unitPrice, subtotal, width));
    }

    rows
      ..add(line)
      ..add(_amountLine('Subtotal', grandTotal, width))
      ..add(line)
      ..add(_amountLine('TOTAL', grandTotal, width))
      ..add(_amountLine(paymentMethod.name, paidAmount, width));

    final referenceNumber =
        (draft.payment['reference_number']?.toString() ?? '').trim();
    if (referenceNumber.isNotEmpty) {
      rows.add(_kv('Ref', referenceNumber, width));
    }

    rows
      ..add(_amountLine('Kembali', changeAmount, width))
      ..add(line)
      ..add(centerReceiptText('Transaksi offline tersimpan.', width))
      ..add(centerReceiptText('Sync saat internet tersedia.', width))
      ..add(invoiceNumber);

    return rows.join('\n');
  }

  String _kv(String label, String value, int width) {
    final prefix = '$label : ';
    final available = width - prefix.length;
    if (available <= 0) {
      return '$label: $value';
    }

    return prefix + _trim(value, available);
  }

  String _itemLine(int quantity, double unitPrice, double subtotal, int width) {
    final left = '${quantity}x ${_money(unitPrice)}';
    final right = _money(subtotal);
    final spaces = width - left.length - right.length;

    return spaces > 0 ? '$left${' ' * spaces}$right' : '$left $right';
  }

  String _amountLine(String label, double value, int width) {
    final amount = _money(value);
    final spaces = width - label.length - amount.length;

    return spaces > 0 ? '$label${' ' * spaces}$amount' : '$label $amount';
  }

  List<String> _wrap(String text, int width) {
    final words = text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final lines = <String>[];
    var current = '';

    for (final word in words) {
      if (word.length > width) {
        if (current.isNotEmpty) {
          lines.add(current);
          current = '';
        }
        lines.add(_trim(word, width));
      } else if (current.isEmpty) {
        current = word;
      } else if ('$current $word'.length <= width) {
        current = '$current $word';
      } else {
        lines.add(current);
        current = word;
      }
    }

    if (current.isNotEmpty) {
      lines.add(current);
    }

    return lines.isEmpty ? ['-'] : lines;
  }

  String _money(double value) => value.round().toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );

  String _trim(String value, int maxLength) {
    if (value.length <= maxLength) {
      return value;
    }

    return value.substring(0, maxLength);
  }

  double _asDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _asInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
