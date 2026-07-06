import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../app_config.dart';
import '../models/cashier_models.dart';

class OfflineSaleHistoryStore {
  const OfflineSaleHistoryStore();

  static const _storageKey = 'yosy_group.offline_sales.history';

  Future<List<RecentSale>> all() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;

      return decoded
          .whereType<Map<String, dynamic>>()
          .map(RecentSale.fromJson)
          .where((sale) => sale.invoiceNumber.trim().isNotEmpty)
          .toList();
    } catch (_) {
      await prefs.remove(_storageKey);
      return const [];
    }
  }

  Future<void> append(RecentSale sale) async {
    var sales = await all();

    if (sales.any((item) => item.invoiceNumber == sale.invoiceNumber)) {
      return;
    }

    sales = [sale.copyWith(localOnly: true), ...sales];
    if (sales.length > AppConfig.offlineQueueMaxSize) {
      sales = sales.take(AppConfig.offlineQueueMaxSize).toList();
    }

    await _save(sales);
  }

  Future<void> update(RecentSale sale) async {
    final sales = await all();
    await _save(
      sales
          .map((item) => item.invoiceNumber == sale.invoiceNumber ? sale : item)
          .toList(),
    );
  }

  Future<void> removeMany(Iterable<String> invoiceNumbers) async {
    final removeSet = invoiceNumbers.toSet();
    if (removeSet.isEmpty) {
      return;
    }

    final sales = await all();
    await _save(
      sales.where((sale) => !removeSet.contains(sale.invoiceNumber)).toList(),
    );
  }

  Future<void> _save(List<RecentSale> sales) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(sales.map((sale) => sale.toJson()).toList()),
    );
  }
}
