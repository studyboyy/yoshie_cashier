import 'package:shared_preferences/shared_preferences.dart';

class FavoriteProductLimitException implements Exception {
  const FavoriteProductLimitException();

  @override
  String toString() => 'Maksimal 5 produk favorit.';
}

class FavoriteProductStore {
  const FavoriteProductStore();

  static const maxFavorites = 5;
  static const _key = 'yosy_group.favorite_product_ids';

  Future<Set<int>> ids() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? const <String>[])
        .map(int.tryParse)
        .whereType<int>()
        .where((id) => id > 0)
        .toSet();
  }

  Future<Set<int>> toggle(int productId) async {
    final nextIds = await ids();

    if (nextIds.contains(productId)) {
      nextIds.remove(productId);
    } else {
      if (nextIds.length >= maxFavorites) {
        throw const FavoriteProductLimitException();
      }
      nextIds.add(productId);
    }

    await _save(nextIds);
    return nextIds;
  }

  Future<void> prune(Set<int> validProductIds) async {
    final currentIds = await ids();
    final nextIds = currentIds.intersection(validProductIds);
    if (nextIds.length != currentIds.length) {
      await _save(nextIds);
    }
  }

  Future<void> _save(Set<int> ids) async {
    final prefs = await SharedPreferences.getInstance();
    final sortedIds = ids.toList()..sort();
    await prefs.setStringList(
      _key,
      sortedIds.map((id) => id.toString()).toList(),
    );
  }
}
