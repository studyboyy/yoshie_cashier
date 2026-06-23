import 'package:flutter_cashier/models/cashier_models.dart';
import 'package:flutter_cashier/services/cart_draft_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('saves and loads cart draft items', () async {
    const store = CartDraftStore();
    final item = CartItem(product: _product(id: 7, stock: 4), quantity: 2);

    await store.save([item]);

    final loaded = await store.load();

    expect(loaded, hasLength(1));
    expect(loaded.single.product.id, 7);
    expect(loaded.single.product.name, 'Produk 7');
    expect(loaded.single.quantity, 2);
  });

  test('empty cart clears saved draft', () async {
    const store = CartDraftStore();

    await store.save([CartItem(product: _product(id: 1, stock: 3))]);
    expect(await store.load(), hasLength(1));

    await store.save([]);

    expect(await store.load(), isEmpty);
  });

  test('invalid draft is ignored and cleared', () async {
    SharedPreferences.setMockInitialValues({
      'yosy_group.cashier.cart_draft': '{broken',
    });

    const store = CartDraftStore();

    expect(await store.load(), isEmpty);
  });
}

CashierProduct _product({required int id, required int stock}) {
  return CashierProduct(
    id: id,
    name: 'Produk $id',
    sku: 'SKU-$id',
    unit: 'pcs',
    price: 10000,
    priceText: 'Rp 10.000',
    stock: stock,
  );
}
