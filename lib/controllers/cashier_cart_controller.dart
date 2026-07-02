import 'package:flutter/foundation.dart';

import '../models/cashier_models.dart';

enum AddCartResult { added, duplicate, outOfStock }

class CashierCartController extends ChangeNotifier {
  final List<CartItem> _items = [];

  List<CartItem> get items => List.unmodifiable(_items);

  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;
  int get length => _items.length;

  double get total => _items.fold(0, (sum, item) => sum + item.subtotal);
  double get grossTotal =>
      _items.fold(0, (sum, item) => sum + item.grossSubtotal);
  double get negotiationDiscount =>
      _items.fold(0, (sum, item) => sum + item.discountAmount);
  int get count => _items.fold(0, (sum, item) => sum + item.quantity);

  AddCartResult addProduct(CashierProduct product) {
    if (product.stock <= 0) {
      return AddCartResult.outOfStock;
    }

    final exists = _items.any((item) => item.product.id == product.id);
    if (exists) {
      return AddCartResult.duplicate;
    }

    _items.add(CartItem(product: product));
    notifyListeners();
    return AddCartResult.added;
  }

  bool increment(CartItem item) {
    final index = _indexOf(item);
    if (index < 0 || _items[index].quantity >= _items[index].product.stock) {
      return false;
    }

    _items[index].quantity += 1;
    notifyListeners();
    return true;
  }

  void decrement(CartItem item) {
    final index = _indexOf(item);
    if (index < 0) {
      return;
    }

    _items[index].quantity -= 1;
    if (_items[index].quantity <= 0) {
      _items.removeAt(index);
    }
    notifyListeners();
  }

  void remove(CartItem item) {
    _items.removeWhere((cartItem) => cartItem.product.id == item.product.id);
    notifyListeners();
  }

  bool updateQuantity(CartItem item, int quantity) {
    final index = _indexOf(item);
    if (index < 0 || quantity <= 0 || quantity > _items[index].product.stock) {
      return false;
    }

    _items[index].quantity = quantity;
    notifyListeners();
    return true;
  }

  bool updateNegotiatedUnitPrice(CartItem item, double negotiatedUnitPrice) {
    final index = _indexOf(item);
    if (index < 0 || negotiatedUnitPrice < 0) {
      return false;
    }

    final normalPrice = _items[index].product.price;
    if (negotiatedUnitPrice > normalPrice) {
      return false;
    }

    _items[index].negotiatedUnitPrice = negotiatedUnitPrice;
    notifyListeners();
    return true;
  }

  void clearNegotiation(CartItem item) {
    final index = _indexOf(item);
    if (index < 0) {
      return;
    }

    _items[index].negotiatedUnitPrice = _items[index].product.price;
    notifyListeners();
  }

  void clear() {
    if (_items.isEmpty) {
      return;
    }

    _items.clear();
    notifyListeners();
  }

  void restore(List<CartItem> items) {
    _items
      ..clear()
      ..addAll(items.where((item) => item.product.stock > 0));
    notifyListeners();
  }

  int _indexOf(CartItem item) {
    return _items.indexWhere(
      (cartItem) => cartItem.product.id == item.product.id,
    );
  }
}
