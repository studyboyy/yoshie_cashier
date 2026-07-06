class OutletInfo {
  const OutletInfo({
    required this.id,
    required this.name,
    required this.code,
    this.phone,
    this.address,
  });

  final int id;
  final String name;
  final String code;
  final String? phone;
  final String? address;

  factory OutletInfo.fromJson(Map<String, dynamic> json) {
    return OutletInfo(
      id: _asInt(json['id']),
      name: json['name'] as String? ?? '-',
      code: json['code'] as String? ?? '-',
      phone: json['phone'] as String?,
      address: json['address'] as String?,
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
    required this.receiptProfile,
    this.receiptLogoPath,
  });

  final OutletInfo outlet;
  final List<PaymentMethod> paymentMethods;
  final List<StockAlert> stockAlerts;
  final ReceiptProfile receiptProfile;

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
      receiptProfile: ReceiptProfile.fromJson(
        json['receipt_profile'] as Map<String, dynamic>? ?? const {},
      ),
      receiptLogoPath: json['receipt_logo_path'] as String?,
    );
  }
}

class ReceiptProfile {
  const ReceiptProfile({
    required this.storeName,
    required this.storePhone,
    required this.storeFooter,
    required this.headerNote,
    required this.paperWidth,
    required this.showCashier,
    required this.showOutlet,
    required this.showCustomer,
    required this.storeAlign,
    required this.headerAlign,
    required this.footerAlign,
    required this.topText,
    required this.bottomText,
    required this.lineStyle,
    required this.itemNameWrap,
    required this.spacingHeader,
    required this.spacingItems,
    required this.spacingFooter,
  });

  final String storeName;
  final String storePhone;
  final String storeFooter;
  final String headerNote;
  final String paperWidth;
  final bool showCashier;
  final bool showOutlet;
  final bool showCustomer;
  final String storeAlign;
  final String headerAlign;
  final String footerAlign;
  final String topText;
  final String bottomText;
  final String lineStyle;
  final bool itemNameWrap;
  final int spacingHeader;
  final int spacingItems;
  final int spacingFooter;

  factory ReceiptProfile.fromJson(Map<String, dynamic> json) {
    return ReceiptProfile(
      storeName: json['store_name'] as String? ?? 'Yosy Group',
      storePhone: json['store_phone'] as String? ?? '',
      storeFooter:
          json['store_footer'] as String? ?? 'Terima kasih sudah berbelanja!',
      headerNote: json['receipt_header_note'] as String? ?? '',
      paperWidth: json['receipt_paper_width'] as String? ?? '58',
      showCashier: json['receipt_show_cashier'] as bool? ?? true,
      showOutlet: json['receipt_show_outlet'] as bool? ?? true,
      showCustomer: json['receipt_show_customer'] as bool? ?? true,
      storeAlign: _receiptAlign(json['receipt_store_align']),
      headerAlign: _receiptAlign(json['receipt_header_align']),
      footerAlign: _receiptAlign(json['receipt_footer_align']),
      topText: json['receipt_top_text'] as String? ?? '',
      bottomText: json['receipt_bottom_text'] as String? ?? '',
      lineStyle: json['receipt_line_style'] as String? ?? 'solid',
      itemNameWrap: json['receipt_item_name_wrap'] as bool? ?? true,
      spacingHeader: _asInt(json['receipt_spacing_header']).clamp(0, 3).toInt(),
      spacingItems: _asInt(json['receipt_spacing_items']).clamp(0, 3).toInt(),
      spacingFooter: _asInt(json['receipt_spacing_footer']).clamp(0, 3).toInt(),
    );
  }

  static String _receiptAlign(dynamic value) {
    return switch (value) {
      'left' || 'right' || 'center' => value as String,
      _ => 'center',
    };
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
    this.productType = 'general',
    this.color,
    this.size,
    this.variantName,
    this.canNegotiate = false,
  });

  final int id;
  final String name;
  final String sku;
  final String? barcode;
  final String productType;
  final String? color;
  final String? size;
  final String? variantName;
  final bool canNegotiate;
  final String unit;
  final double price;
  final String priceText;
  final int stock;

  bool get isFashion => productType == 'fashion';

  String get variantText {
    final explicit = (variantName ?? '').trim();
    if (explicit.isNotEmpty) {
      return explicit;
    }

    final parts = [
      if ((color ?? '').trim().isNotEmpty) color!.trim(),
      if ((size ?? '').trim().isNotEmpty) size!.trim(),
    ];

    return parts.join(' / ');
  }

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
      productType: json['product_type'] as String? ?? 'general',
      color: json['color'] as String?,
      size: json['size'] as String?,
      variantName: json['variant_name'] as String?,
      canNegotiate: json['can_negotiate'] as bool? ?? false,
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
      'product_type': productType,
      'color': color,
      'size': size,
      'variant_name': variantName,
      'can_negotiate': canNegotiate,
      'unit': unit,
      'price': price,
      'price_fmt': priceText,
      'stock': stock,
    };
  }
}

class CartItem {
  CartItem({
    required this.product,
    this.quantity = 1,
    double? negotiatedUnitPrice,
  }) : negotiatedUnitPrice = negotiatedUnitPrice ?? product.price;

  final CashierProduct product;
  int quantity;
  double negotiatedUnitPrice;

  double get unitDiscount {
    final discount = product.price - negotiatedUnitPrice;
    return discount > 0 ? discount : 0;
  }

  double get discountAmount => unitDiscount * quantity;

  bool get hasNegotiation => discountAmount > 0;

  double get subtotal => negotiatedUnitPrice * quantity;

  double get grossSubtotal => product.price * quantity;

  Map<String, dynamic> toCheckoutJson() {
    return {
      'product_id': product.id,
      'quantity': quantity,
      if (product.canNegotiate && hasNegotiation)
        'negotiated_unit_price': negotiatedUnitPrice,
    };
  }

  Map<String, dynamic> toOfflineJson() {
    final discount = product.canNegotiate ? discountAmount : 0.0;
    final finalUnitPrice = product.canNegotiate
        ? negotiatedUnitPrice
        : product.price;

    return {
      'product_id': product.id,
      'product_name': product.name,
      'product_sku': product.sku,
      'quantity': quantity,
      'unit_price': product.price,
      'negotiated_unit_price': finalUnitPrice,
      'discount_amount': discount,
      'subtotal': finalUnitPrice * quantity,
    };
  }

  Map<String, dynamic> toDraftJson() {
    return {
      'product': product.toJson(),
      'quantity': quantity,
      'negotiated_unit_price': negotiatedUnitPrice,
    };
  }

  factory CartItem.fromDraftJson(Map<String, dynamic> json) {
    final product = CashierProduct.fromJson(
      json['product'] as Map<String, dynamic>? ?? {},
    );
    final negotiatedUnitPrice = _asDouble(
      json['negotiated_unit_price'] ?? product.price,
    ).clamp(0, product.price).toDouble();

    return CartItem(
      product: product,
      quantity: _asInt(json['quantity']).clamp(1, 999999).toInt(),
      negotiatedUnitPrice: negotiatedUnitPrice,
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
    this.items = const <RecentSaleItem>[],
  });

  final int id;
  final String invoiceNumber;
  final DateTime? paidAt;
  final String? customer;
  final double grandTotal;
  final double paidAmount;
  final double changeAmount;
  final String? paymentMethod;
  final List<RecentSaleItem> items;

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
      items: (json['items'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(RecentSaleItem.fromJson)
          .toList(),
    );
  }
}

class RecentSaleItem {
  const RecentSaleItem({
    required this.id,
    required this.productId,
    required this.productName,
    required this.productSku,
    required this.quantity,
    required this.returnedQuantity,
    required this.returnableQuantity,
    required this.unitPrice,
    required this.discountAmount,
    required this.subtotal,
  });

  final int id;
  final int productId;
  final String productName;
  final String productSku;
  final int quantity;
  final int returnedQuantity;
  final int returnableQuantity;
  final double unitPrice;
  final double discountAmount;
  final double subtotal;

  bool get canReturn => id > 0 && returnableQuantity > 0;

  double get finalUnitPrice => quantity <= 0 ? unitPrice : subtotal / quantity;

  factory RecentSaleItem.fromJson(Map<String, dynamic> json) {
    return RecentSaleItem(
      id: _asInt(json['id']),
      productId: _asInt(json['product_id']),
      productName: json['product_name'] as String? ?? '-',
      productSku: json['product_sku'] as String? ?? '-',
      quantity: _asInt(json['quantity']),
      returnedQuantity: _asInt(json['returned_quantity']),
      returnableQuantity: _asInt(json['returnable_quantity']),
      unitPrice: _asDouble(json['unit_price']),
      discountAmount: _asDouble(json['discount_amount']),
      subtotal: _asDouble(json['subtotal']),
    );
  }
}

class SaleReturnItemRequest {
  const SaleReturnItemRequest({
    required this.saleItemId,
    required this.qty,
    required this.condition,
  });

  final int saleItemId;
  final int qty;
  final String condition;

  Map<String, dynamic> toJson() => {
    'sale_item_id': saleItemId,
    'qty': qty,
    'condition': condition,
  };
}

class SaleReturnResult {
  const SaleReturnResult({
    required this.returnNumber,
    required this.refundAmount,
    this.message,
    this.sale,
  });

  final String returnNumber;
  final double refundAmount;
  final String? message;
  final RecentSale? sale;

  factory SaleReturnResult.fromJson(Map<String, dynamic> json) {
    final data = json['return'] as Map<String, dynamic>? ?? {};
    final sale = json['sale'] as Map<String, dynamic>?;

    return SaleReturnResult(
      returnNumber: data['return_number'] as String? ?? '-',
      refundAmount: _asDouble(data['refund_amount']),
      message: json['message'] as String?,
      sale: sale == null ? null : RecentSale.fromJson(sale),
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
