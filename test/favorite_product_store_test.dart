import 'package:flutter_cashier/services/favorite_product_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('toggles favorite product ids', () async {
    const store = FavoriteProductStore();

    expect(await store.toggle(10), {10});
    expect(await store.toggle(20), {10, 20});
    expect(await store.toggle(10), {20});
  });

  test('limits favorites to five products', () async {
    const store = FavoriteProductStore();

    for (var id = 1; id <= FavoriteProductStore.maxFavorites; id++) {
      await store.toggle(id);
    }

    expect(
      () => store.toggle(99),
      throwsA(isA<FavoriteProductLimitException>()),
    );
  });

  test('prunes favorites that are no longer available', () async {
    const store = FavoriteProductStore();
    await store.toggle(1);
    await store.toggle(2);
    await store.toggle(3);

    await store.prune({1, 3});

    expect(await store.ids(), {1, 3});
  });
}
