import 'dart:async';

import 'package:flutter_cashier/controllers/cashier_lookup_controller.dart';
import 'package:flutter_cashier/models/cashier_models.dart';
import 'package:flutter_cashier/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ignores stale product search responses', () async {
    final api = _FakeApiClient();
    final controller = CashierLookupController(api: api);

    final first = Completer<List<CashierProduct>>();
    final second = Completer<List<CashierProduct>>();
    api.productResponses
      ..add(first.future)
      ..add(second.future);

    final firstSearch = controller.searchProducts('gel');
    final secondSearch = controller.searchProducts('gelang');

    second.complete([_product(id: 2, name: 'Gelang Manik')]);
    final secondResult = await secondSearch;

    first.complete([_product(id: 1, name: 'Gelang Lama')]);
    final firstResult = await firstSearch;

    expect(secondResult.isCurrent, isTrue);
    expect(firstResult.isCurrent, isFalse);
    expect(controller.products.map((product) => product.name), [
      'Gelang Manik',
    ]);
    controller.dispose();
  });

  test('clears customer results and guards pending customer search', () async {
    final api = _FakeApiClient();
    final controller = CashierLookupController(api: api);
    final pending = Completer<List<CashierCustomer>>();
    api.customerResponses.add(pending.future);

    final search = controller.searchCustomers('ani');
    controller.clearCustomers();
    pending.complete([_customer(name: 'Ani')]);
    final result = await search;

    expect(result.isCurrent, isFalse);
    expect(controller.customers, isEmpty);
    expect(controller.searchingCustomers, isFalse);
    controller.dispose();
  });
}

class _FakeApiClient extends ApiClient {
  final productResponses = <Future<List<CashierProduct>>>[];
  final customerResponses = <Future<List<CashierCustomer>>>[];

  @override
  Future<List<CashierProduct>> searchProducts(String query) {
    if (productResponses.isEmpty) {
      return Future.value([]);
    }

    return productResponses.removeAt(0);
  }

  @override
  Future<List<CashierCustomer>> searchCustomers(String query) {
    if (customerResponses.isEmpty) {
      return Future.value([]);
    }

    return customerResponses.removeAt(0);
  }
}

CashierProduct _product({required int id, required String name}) {
  return CashierProduct(
    id: id,
    name: name,
    sku: 'SKU-$id',
    unit: 'pcs',
    price: 10000,
    priceText: 'Rp 10.000',
    stock: 10,
  );
}

CashierCustomer _customer({required String name}) {
  return CashierCustomer(id: 1, name: name, memberCode: 'MBR-001', points: 10);
}
