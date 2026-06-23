import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/cashier_models.dart';

class CartDraftStore {
  const CartDraftStore();

  static const _storageKey = 'yosy_group.cashier.cart_draft';

  Future<List<CartItem>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const [];
      }

      return decoded
          .whereType<Map<String, dynamic>>()
          .map(CartItem.fromDraftJson)
          .where((item) => item.product.id > 0 && item.quantity > 0)
          .toList();
    } on FormatException {
      await clear();
      return const [];
    }
  }

  Future<void> save(List<CartItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    if (items.isEmpty) {
      await prefs.remove(_storageKey);
      return;
    }

    await prefs.setString(
      _storageKey,
      jsonEncode(items.map((item) => item.toDraftJson()).toList()),
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}
