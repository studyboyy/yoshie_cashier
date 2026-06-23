class OutletInfo {
  const OutletInfo({required this.id, required this.name, required this.code});

  final int id;
  final String name;
  final String code;

  factory OutletInfo.fromJson(Map<String, dynamic> json) {
    return OutletInfo(
      id: _asInt(json['id']),
      name: json['name'] as String? ?? '-',
      code: json['code'] as String? ?? '-',
    );
  }
}

class PaymentMethod {
  const PaymentMethod({
    required this.id,
    required this.name,
    required this.code,
  });

  final int id;
  final String name;
  final String code;

  factory PaymentMethod.fromJson(Map<String, dynamic> json) {
    return PaymentMethod(
      id: _asInt(json['id']),
      name: json['name'] as String? ?? '-',
      code: json['code'] as String? ?? '',
    );
  }
}

class StockAlert {
  const StockAlert({
    required this.productId,
    required this.productName,
    required this.unit,
    required this.quantity,
    required this.minimumStock,
  });

  final int productId;
  final String productName;
  final String unit;
  final int quantity;
  final int minimumStock;

  bool get isLow => quantity <= minimumStock;

  factory StockAlert.fromJson(Map<String, dynamic> json) {
    return StockAlert(
      productId: _asInt(json['product_id']),
      productName: json['product_name'] as String? ?? '-',
      unit: json['unit'] as String? ?? 'pcs',
      quantity: _asInt(json['quantity']),
      minimumStock: _asInt(json['minimum_stock']),
    );
  }
}

class CashierCustomer {
  const CashierCustomer({
    required this.id,
    required this.name,
    required this.memberCode,
    required this.points,
    this.phone,
  });

  final int id;
  final String name;
  final String memberCode;
  final String? phone;
  final int points;

  factory CashierCustomer.fromJson(Map<String, dynamic> json) {
    return CashierCustomer(
      id: _asInt(json['id']),
      name: json['name'] as String? ?? '-',
      memberCode: json['member_code'] as String? ?? '',
      phone: json['phone'] as String?,
      points: _asInt(json['points']),
    );
  }
}

class CashierBootstrap {
  const CashierBootstrap({
    required this.outlet,
    required this.paymentMethods,
    required this.stockAlerts,
    this.receiptLogoPath,
  });

  final OutletInfo outlet;
  final List<PaymentMethod> paymentMethods;
  final List<StockAlert> stockAlerts;

  /// Path logo struk di server storage, misal "receipt-logo.png".
  /// Null berarti gunakan logo default (brand.png).
  final String? receiptLogoPath;

  factory CashierBootstrap.fromJson(Map<String, dynamic> json) {
    return CashierBootstrap(
      outlet: OutletInfo.fromJson(json['outlet'] as Map<String, dynamic>),
      paymentMethods: (json['payment_methods'] as List<dynamic>? ?? [])
          .map((item) => PaymentMethod.fromJson(item as Map<String, dynamic>))
          .toList(),
      stockAlerts: (json['stock_alerts'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(StockAlert.fromJson)
          .toList(),
      receiptLogoPath: json['receipt_logo_path'] as String?,
    );
  }
}

class CashierSummary {
  const CashierSummary({
    required this.todaySalesTotal,
    required this.todaySalesCount,
    required this.todayItemsCount,
    required this.availableProductCount,
    required this.lowStockCount,
  });

  final double todaySalesTotal;
  final int todaySalesCount;
  final int todayItemsCount;
  final int availableProductCount;
  final int lowStockCount;

  factory CashierSummary.fromJson(Map<String, dynamic> json) {
    return CashierSummary(
      todaySalesTotal: _asDouble(json['today_sales_total']),
      todaySalesCount: _asInt(json['today_sales_count']),
      todayItemsCount: _asInt(json['today_items_count']),
      availableProductCount: _asInt(json['available_product_count']),
      lowStockCount: _asInt(json['low_stock_count']),
    );
  }
}

class CashierProduct {
  const CashierProduct({
    required this.id,
    required this.name,
    required this.sku,
    required this.unit,
    required this.price,
    required this.priceText,
    required this.stock,
    this.barcode,
  });

  final int id;
  final String name;
  final String sku;
  final String? barcode;
  final String unit;
  final double price;
  final String priceText;
  final int stock;

  factory CashierProduct.fromJson(Map<String, dynamic> json) {
    final id = json['product_id'] ?? json['id'];
    final name = json['product_name'] ?? json['name'];
    final sku = json['product_sku'] ?? json['sku'];
    final price = json['unit_price'] ?? json['price'];
    final priceText = json['unit_price_fmt'] ?? json['price_fmt'];

    return CashierProduct(
      id: _asInt(id),
      name: name as String? ?? '-',
      sku: sku as String? ?? '',
      barcode: json['barcode'] as String?,
      unit: json['unit'] as String? ?? 'pcs',
      price: _asDouble(price),
      priceText: priceText as String? ?? '',
      stock: _asInt(json['stock']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'sku': sku,
      'barcode': barcode,
      'unit': unit,
      'price': price,
      'price_fmt': priceText,
      'stock': stock,
    };
  }
}

class CartItem {
  CartItem({required this.product, this.quantity = 1});

  final CashierProduct product;
  int quantity;

  double get subtotal => product.price * quantity;

  Map<String, dynamic> toCheckoutJson() {
    return {'product_id': product.id, 'quantity': quantity};
  }

  Map<String, dynamic> toOfflineJson() {
    return {
      'product_id': product.id,
      'product_name': product.name,
      'product_sku': product.sku,
      'quantity': quantity,
      'unit_price': product.price,
      'subtotal': subtotal,
    };
  }

  Map<String, dynamic> toDraftJson() {
    return {'product': product.toJson(), 'quantity': quantity};
  }

  factory CartItem.fromDraftJson(Map<String, dynamic> json) {
    return CartItem(
      product: CashierProduct.fromJson(
        json['product'] as Map<String, dynamic>? ?? {},
      ),
      quantity: _asInt(json['quantity']).clamp(1, 999999).toInt(),
    );
  }
}

class CheckoutResult {
  const CheckoutResult({
    required this.invoiceNumber,
    required this.receiptText,
    required this.grandTotal,
    required this.paidAmount,
    required this.changeAmount,
  });

  final String invoiceNumber;
  final String receiptText;
  final double grandTotal;
  final double paidAmount;
  final double changeAmount;

  factory CheckoutResult.fromJson(Map<String, dynamic> json) {
    final sale = json['sale'] as Map<String, dynamic>? ?? {};

    return CheckoutResult(
      invoiceNumber: sale['invoice_number'] as String? ?? '-',
      receiptText: json['receipt_text'] as String? ?? '',
      grandTotal: _asDouble(sale['grand_total']),
      paidAmount: _asDouble(sale['paid_amount']),
      changeAmount: _asDouble(sale['change_amount']),
    );
  }
}

class RecentSale {
  const RecentSale({
    required this.id,
    required this.invoiceNumber,
    required this.grandTotal,
    required this.paidAmount,
    required this.changeAmount,
    this.paidAt,
    this.customer,
    this.paymentMethod,
  });

  final int id;
  final String invoiceNumber;
  final DateTime? paidAt;
  final String? customer;
  final double grandTotal;
  final double paidAmount;
  final double changeAmount;
  final String? paymentMethod;

  factory RecentSale.fromJson(Map<String, dynamic> json) {
    return RecentSale(
      id: _asInt(json['id']),
      invoiceNumber: json['invoice_number'] as String? ?? '-',
      paidAt: DateTime.tryParse(json['paid_at'] as String? ?? '')?.toLocal(),
      customer: json['customer'] as String?,
      grandTotal: _asDouble(json['grand_total']),
      paidAmount: _asDouble(json['paid_amount']),
      changeAmount: _asDouble(json['change_amount']),
      paymentMethod: json['payment_method'] as String?,
    );
  }
}

class CashierShiftInfo {
  const CashierShiftInfo({
    required this.id,
    required this.shiftNumber,
    required this.status,
    required this.openingCash,
    required this.expectedCash,
    this.openedAt,
    this.closedAt,
    this.closingCash = 0,
    this.cashDifference = 0,
  });

  final int id;
  final String shiftNumber;
  final String status;
  final double openingCash;
  final double expectedCash;
  final double closingCash;
  final double cashDifference;
  final DateTime? openedAt;
  final DateTime? closedAt;

  bool get isOpen => status == 'open';

  factory CashierShiftInfo.fromJson(Map<String, dynamic> json) {
    return CashierShiftInfo(
      id: _asInt(json['id']),
      shiftNumber: json['shift_number'] as String? ?? '-',
      status: json['status'] as String? ?? '-',
      openingCash: _asDouble(json['opening_cash']),
      expectedCash: _asDouble(json['expected_cash']),
      closingCash: _asDouble(json['closing_cash']),
      cashDifference: _asDouble(json['cash_difference']),
      openedAt: DateTime.tryParse(
        json['opened_at'] as String? ?? '',
      )?.toLocal(),
      closedAt: DateTime.tryParse(
        json['closed_at'] as String? ?? '',
      )?.toLocal(),
    );
  }
}

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.toInt();
  }

  if (value is String) {
    return int.tryParse(value) ?? 0;
  }

  return 0;
}

double _asDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }

  if (value is String) {
    return double.tryParse(value) ?? 0;
  }

  return 0;
}
