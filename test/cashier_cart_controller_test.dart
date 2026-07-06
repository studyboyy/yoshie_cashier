import 'package:flutter_cashier/controllers/cashier_cart_controller.dart';
import 'package:flutter_cashier/models/cashier_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new product scan adds item with quantity one', () {
    final controller = CashierCartController();
    final product = _product(id: 1, stock: 5);

    expect(controller.addProduct(product), AddCartResult.added);
    expect(controller.items, hasLength(1));
    expect(controller.items.single.product.id, product.id);
    expect(controller.items.single.quantity, 1);
  });

  test('duplicate product scan does not change cart quantity', () {
    final controller = CashierCartController();
    final product = _product(id: 1, stock: 5);

    expect(controller.addProduct(product), AddCartResult.added);
    expect(controller.count, 1);

    expect(controller.addProduct(product), AddCartResult.duplicate);
    expect(controller.count, 1);
    expect(controller.items.single.quantity, 1);
  });

  test('zero stock product scan is rejected', () {
    final controller = CashierCartController();
    final product = _product(id: 1, stock: 0);

    expect(controller.addProduct(product), AddCartResult.outOfStock);
    expect(controller.items, isEmpty);
    expect(controller.count, 0);
  });

  test('manual increment still changes quantity up to available stock', () {
    final controller = CashierCartController();
    final product = _product(id: 1, stock: 2);

    controller.addProduct(product);

    expect(controller.increment(controller.items.single), isTrue);
    expect(controller.count, 2);
    expect(controller.increment(controller.items.single), isFalse);
    expect(controller.count, 2);
  });

  test('restores saved cart draft and skips empty stock products', () {
    final controller = CashierCartController();

    controller.restore([
      CartItem(product: _product(id: 1, stock: 5), quantity: 2),
      CartItem(product: _product(id: 2, stock: 0), quantity: 1),
    ]);

    expect(controller.items, hasLength(1));
    expect(controller.items.single.product.id, 1);
    expect(controller.count, 2);
  });

  test('negotiation is only allowed for fashion products', () {
    final controller = CashierCartController();
    final general = _product(id: 1, stock: 5);
    final fashion = _product(
      id: 2,
      stock: 5,
      productType: 'fashion',
      canNegotiate: true,
    );

    controller.addProduct(general);
    controller.addProduct(fashion);

    expect(
      controller.updateNegotiatedUnitPrice(controller.items[0], 8000),
      isFalse,
    );
    expect(controller.items[0].negotiatedUnitPrice, 10000);

    expect(
      controller.updateNegotiatedUnitPrice(controller.items[1], 8000),
      isTrue,
    );
    expect(controller.items[1].negotiatedUnitPrice, 8000);
  });
}

CashierProduct _product({
  required int id,
  required int stock,
  String productType = 'general',
  bool canNegotiate = false,
}) {
  return CashierProduct(
    id: id,
    name: 'Produk $id',
    sku: 'SKU-$id',
    unit: 'pcs',
    price: 10000,
    priceText: 'Rp 10.000',
    stock: stock,
    productType: productType,
    canNegotiate: canNegotiate,
  );
}
