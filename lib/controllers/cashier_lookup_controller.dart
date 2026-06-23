import 'package:flutter/foundation.dart';

import '../models/cashier_models.dart';
import '../services/api_client.dart';

class LookupResult<T> {
  const LookupResult({required this.items, required this.isCurrent});

  final List<T> items;
  final bool isCurrent;
}

class CashierLookupController extends ChangeNotifier {
  CashierLookupController({required this.api});

  final ApiClient api;

  List<CashierProduct> _products = [];
  List<CashierCustomer> _customers = [];
  bool _searchingProducts = false;
  bool _searchingCustomers = false;
  int _productRequestId = 0;
  int _customerRequestId = 0;
  String _productQuery = '';
  String _customerQuery = '';

  List<CashierProduct> get products => List.unmodifiable(_products);
  List<CashierCustomer> get customers => List.unmodifiable(_customers);
  bool get searchingProducts => _searchingProducts;
  bool get searchingCustomers => _searchingCustomers;

  void setProductQuery(String query) {
    _productQuery = query;
  }

  void setCustomerQuery(String query) {
    _customerQuery = query;
  }

  void clearProducts() {
    _productRequestId++;
    _productQuery = '';
    _products = [];
    _searchingProducts = false;
    notifyListeners();
  }

  void clearCustomers() {
    _customerRequestId++;
    _customerQuery = '';
    _customers = [];
    _searchingCustomers = false;
    notifyListeners();
  }

  void clearAll() {
    _productRequestId++;
    _customerRequestId++;
    _productQuery = '';
    _customerQuery = '';
    _products = [];
    _customers = [];
    _searchingProducts = false;
    _searchingCustomers = false;
    notifyListeners();
  }

  Future<CashierProduct?> productByBarcodeOrNull(String query) async {
    try {
      return await api.productByBarcode(query);
    } on ApiException {
      return null;
    }
  }

  Future<LookupResult<CashierProduct>> searchProducts(String query) async {
    final requestId = ++_productRequestId;
    _productQuery = query;
    _searchingProducts = true;
    notifyListeners();

    try {
      final products = await api.searchProducts(query);
      final isCurrent =
          requestId == _productRequestId && _productQuery == query;

      if (isCurrent) {
        _products = products;
        _searchingProducts = false;
        notifyListeners();
      }

      return LookupResult(items: products, isCurrent: isCurrent);
    } catch (_) {
      if (requestId == _productRequestId) {
        _searchingProducts = false;
        notifyListeners();
      }
      rethrow;
    }
  }

  Future<LookupResult<CashierCustomer>> searchCustomers(String query) async {
    final requestId = ++_customerRequestId;
    _customerQuery = query;
    _searchingCustomers = true;
    notifyListeners();

    try {
      final customers = await api.searchCustomers(query);
      final isCurrent =
          requestId == _customerRequestId && _customerQuery == query;

      if (isCurrent) {
        _customers = customers;
        _searchingCustomers = false;
        notifyListeners();
      }

      return LookupResult(items: customers, isCurrent: isCurrent);
    } catch (_) {
      if (requestId == _customerRequestId) {
        _searchingCustomers = false;
        notifyListeners();
      }
      rethrow;
    }
  }
}
