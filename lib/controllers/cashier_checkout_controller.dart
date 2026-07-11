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
    required this.profile,
    this.outletPhone,
    this.outletAddress,
    this.customerName,
  });

  final String outletName;
  final String cashierName;
  final ReceiptProfile profile;
  final String? outletPhone;
  final String? outletAddress;
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
    final localReference = OfflineSaleDraft.nextLocalReference();

    try {
      final result = await api.checkout(
        items: items,
        paymentMethodId: paymentMethod.id,
        amount: amount,
        localReference: localReference,
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
        localReference: localReference,
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
    final grossTotal = draft.cartItems.fold<double>(
      0,
      (total, item) =>
          total + (_asDouble(item['unit_price']) * _asInt(item['quantity'])),
    );
    final negotiationDiscount = draft.cartItems.fold<double>(
      0,
      (total, item) => total + _asDouble(item['discount_amount']),
    );
    final paidAmount = _asDouble(draft.payment['amount']);
    final changeAmount = (paidAmount - grandTotal).clamp(0, double.infinity);
    final invoiceNumber = draft.localReference.toUpperCase();
    final receiptText = _offlineReceiptText(
      draft: draft,
      paymentMethod: paymentMethod,
      invoiceNumber: invoiceNumber,
      grandTotal: grandTotal,
      grossTotal: grossTotal,
      negotiationDiscount: negotiationDiscount,
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
    required double grossTotal,
    required double negotiationDiscount,
    required double paidAmount,
    required double changeAmount,
    required int receiptColumns,
    required OfflineReceiptContext context,
  }) {
    final width = receiptColumns == 42 ? 42 : 32;
    final profile = context.profile;
    final line = _receiptLine(width, profile.lineStyle);
    final rows = <String>[_align(profile.storeName, width, profile.storeAlign)];

    _addBlankRows(rows, profile.spacingHeader);

    if (profile.topText.trim().isNotEmpty) {
      for (final text in _wrap(profile.topText, width)) {
        rows.add(_align(text, width, profile.headerAlign));
      }
    }

    rows.add(_align('STRUK OFFLINE', width, profile.headerAlign));

    final outletAddress = (context.outletAddress ?? '').trim();
    if (outletAddress.isNotEmpty) {
      for (final part in outletAddress.split(',')) {
        final text = part.trim();
        if (text.isNotEmpty) {
          for (final line in _wrap(text, width)) {
            rows.add(_align(line, width, profile.headerAlign));
          }
        }
      }
    }

    if (profile.headerNote.trim().isNotEmpty) {
      for (final text in _wrap(profile.headerNote, width)) {
        rows.add(_align(text, width, profile.headerAlign));
      }
    }

    final receiptPhone = (context.outletPhone ?? '').trim().isNotEmpty
        ? context.outletPhone!.trim()
        : profile.storePhone.trim();
    if (receiptPhone.isNotEmpty) {
      rows.add(_align('Telp: $receiptPhone', width, profile.headerAlign));
    }

    rows.addAll([
      line,
      _infoLine('Tgl', receiptDateTime(draft.createdAt), width),
      if (profile.showCashier) _infoLine('Kasir', context.cashierName, width),
      if (profile.showOutlet) _infoLine('Cabang', context.outletName, width),
      if (profile.showCustomer &&
          (context.customerName ?? '').trim().isNotEmpty)
        _infoLine('Member', context.customerName!.trim(), width),
      line,
    ]);

    _addBlankRows(rows, profile.spacingItems);

    for (final item in draft.cartItems) {
      final name = item['product_name'] as String? ?? '-';
      final quantity = _asInt(item['quantity']);
      final unitPrice = _asDouble(item['unit_price']);
      final subtotal = _asDouble(item['subtotal']);
      final discount = _asDouble(item['discount_amount']);
      rows.addAll(
        profile.itemNameWrap ? _wrap(name, width) : [_trim(name, width)],
      );
      rows.add(_itemLine(quantity, unitPrice, subtotal, width));
      if (discount > 0) {
        rows.add(_signedAmountLine('Nego', -discount, width));
      }
    }

    rows
      ..add(line)
      ..add(_amountLine('Subtotal', grossTotal, width));

    if (negotiationDiscount > 0) {
      rows.add(_signedAmountLine('Potongan Nego', -negotiationDiscount, width));
    }

    rows
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
      ..add(line);

    _addBlankRows(rows, profile.spacingFooter);

    if (profile.bottomText.trim().isNotEmpty) {
      for (final text in _wrap(profile.bottomText, width)) {
        rows.add(_align(text, width, profile.footerAlign));
      }
    }

    rows
      ..add(_align('Transaksi offline tersimpan.', width, profile.footerAlign))
      ..add(_align('Sync saat internet tersedia.', width, profile.footerAlign))
      ..add(_align(profile.storeFooter, width, profile.footerAlign))
      ..add(_align(invoiceNumber, width, 'center'));

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

  String _infoLine(String label, String value, int width) {
    final labelWidth = width >= 42 ? 10 : 7;
    final safeLabel = _trim(label, labelWidth).padRight(labelWidth);
    final valueWidth = (width - labelWidth).clamp(8, width).toInt();
    final safeValue = _trim(value, valueWidth);

    return safeLabel + safeValue.padLeft(valueWidth);
  }

  String _itemLine(int quantity, double unitPrice, double subtotal, int width) {
    final qtyWidth = width >= 42 ? 6 : 5;
    final priceWidth = width >= 42 ? 14 : 11;
    final subtotalWidth = width - qtyWidth - priceWidth;
    final qty = '${quantity}x'.padRight(qtyWidth);
    final price = _trim(_money(unitPrice), priceWidth).padLeft(priceWidth);
    final total = _trim(_money(subtotal), subtotalWidth).padLeft(subtotalWidth);

    return '$qty$price$total';
  }

  String _amountLine(String label, double value, int width) {
    final amount = _money(value);
    final safeLabel = _trim(label, width - 9);
    final spaces = width - safeLabel.length - amount.length;

    return spaces > 0
        ? '$safeLabel${' ' * spaces}$amount'
        : '$safeLabel $amount';
  }

  String _signedAmountLine(String label, double value, int width) {
    final amount = value < 0 ? '-${_money(value.abs())}' : _money(value);
    final safeLabel = _trim(label, width - 10);
    final spaces = width - safeLabel.length - amount.length;

    return spaces > 0
        ? '$safeLabel${' ' * spaces}$amount'
        : '$safeLabel $amount';
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

  String _align(String text, int width, String align) {
    final trimmed = _trim(text, width);
    if (align == 'left') {
      return trimmed;
    }

    final padding = width - trimmed.length;
    if (padding <= 0) {
      return trimmed;
    }

    if (align == 'right') {
      return ' ' * padding + trimmed;
    }

    return ' ' * (padding ~/ 2) + trimmed;
  }

  String _receiptLine(int width, String style) {
    return switch (style) {
      'dot' => '.' * width,
      _ => '-' * width,
    };
  }

  void _addBlankRows(List<String> rows, int count) {
    for (var index = 0; index < count; index++) {
      rows.add('');
    }
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
