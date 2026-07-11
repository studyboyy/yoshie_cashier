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
    final invoiceNumber = _normalizeReference(sale.invoiceNumber);
    final localReference = _normalizeReference(sale.localReference ?? '');

    if (sales.any((item) {
      return _normalizeReference(item.invoiceNumber) == invoiceNumber ||
          (localReference.isNotEmpty &&
              _normalizeReference(item.localReference ?? '') == localReference);
    })) {
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
    final invoiceNumber = _normalizeReference(sale.invoiceNumber);
    final localReference = _normalizeReference(sale.localReference ?? '');
    await _save(
      sales.map((item) {
        final sameInvoice =
            _normalizeReference(item.invoiceNumber) == invoiceNumber;
        final sameLocalReference =
            localReference.isNotEmpty &&
            _normalizeReference(item.localReference ?? '') == localReference;

        return sameInvoice || sameLocalReference ? sale : item;
      }).toList(),
    );
  }

  Future<void> removeMany(Iterable<String> invoiceNumbers) async {
    final removeSet = invoiceNumbers
        .map(_normalizeReference)
        .where((reference) => reference.isNotEmpty)
        .toSet();
    if (removeSet.isEmpty) {
      return;
    }

    final sales = await all();
    await _save(
      sales.where((sale) {
        final invoiceNumber = _normalizeReference(sale.invoiceNumber);
        final localReference = _normalizeReference(sale.localReference ?? '');

        return !removeSet.contains(invoiceNumber) &&
            !removeSet.contains(localReference);
      }).toList(),
    );
  }

  Future<void> _save(List<RecentSale> sales) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(sales.map((sale) => sale.toJson()).toList()),
    );
  }

  String _normalizeReference(String value) {
    return value.trim().toUpperCase();
  }
}
