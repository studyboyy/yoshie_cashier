import 'package:flutter/material.dart';

import '../models/cashier_models.dart';
import '../services/api_client.dart';
import '../services/favorite_product_store.dart';
import '../utils/formatters.dart';

class AvailableProductsScreen extends StatefulWidget {
  const AvailableProductsScreen({
    super.key,
    required this.api,
    this.favoriteStore = const FavoriteProductStore(),
  });

  final ApiClient api;
  final FavoriteProductStore favoriteStore;

  @override
  State<AvailableProductsScreen> createState() =>
      _AvailableProductsScreenState();
}

class _AvailableProductsScreenState extends State<AvailableProductsScreen> {
  final _searchController = TextEditingController();
  late Future<List<CashierProduct>> _future;
  Set<int> _favoriteIds = <int>{};
  bool _favoriteChanged = false;

  @override
  void initState() {
    super.initState();
    _future = widget.api.availableProducts();
    _searchController.addListener(() => setState(() {}));
    _loadFavoriteIds();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future = widget.api.availableProducts();
    });
  }

  Future<void> _loadFavoriteIds() async {
    final ids = await widget.favoriteStore.ids();
    if (!mounted) {
      return;
    }

    setState(() => _favoriteIds = ids);
  }

  Future<void> _toggleFavorite(CashierProduct product) async {
    try {
      final ids = await widget.favoriteStore.toggle(product.id);
      if (!mounted) {
        return;
      }

      setState(() {
        _favoriteIds = ids;
        _favoriteChanged = true;
      });
    } on FavoriteProductLimitException {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maksimal 5 produk favorit.')),
      );
    }
  }

  List<CashierProduct> _filter(List<CashierProduct> products) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return products;
    }

    return products.where((product) {
      return product.name.toLowerCase().contains(query) ||
          product.sku.toLowerCase().contains(query) ||
          (product.barcode ?? '').toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          Navigator.of(context).pop(_favoriteChanged);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(
            onPressed: () => Navigator.of(context).pop(_favoriteChanged),
          ),
          title: const Text('Produk Cabang'),
          actions: [
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _FavoriteCountPill(count: _favoriteIds.length),
              ),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: FutureBuilder<List<CashierProduct>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: _InfoState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Produk belum bisa dimuat',
                  message: snapshot.error.toString(),
                ),
              );
            }

            final products = _filter(snapshot.data ?? []);

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    decoration: InputDecoration(
                      labelText: 'Cari produk',
                      hintText: 'Nama, SKU, atau barcode',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Bersihkan',
                              onPressed: _searchController.clear,
                              icon: const Icon(Icons.close),
                            ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${products.length} produk tersedia',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.inventory_2_outlined,
                        size: 18,
                        color: Color(0xFF64748B),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: products.isEmpty
                      ? const _InfoState(
                          icon: Icons.inventory_2_outlined,
                          title: 'Produk tidak ditemukan',
                          message: 'Coba kata kunci lain atau refresh data.',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          itemCount: products.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final product = products[index];
                            return _ProductStockCard(
                              product: product,
                              isFavorite: _favoriteIds.contains(product.id),
                              favoriteLimitReached:
                                  _favoriteIds.length >=
                                  FavoriteProductStore.maxFavorites,
                              onToggleFavorite: () => _toggleFavorite(product),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProductStockCard extends StatelessWidget {
  const _ProductStockCard({
    required this.product,
    required this.isFavorite,
    required this.favoriteLimitReached,
    required this.onToggleFavorite,
  });

  final CashierProduct product;
  final bool isFavorite;
  final bool favoriteLimitReached;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  color: Color(0xFF4F46E5),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      product.sku.isEmpty ? '-' : product.sku,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: isFavorite
                    ? 'Hapus dari favorit'
                    : favoriteLimitReached
                    ? 'Favorit sudah penuh'
                    : 'Jadikan favorit',
                onPressed: isFavorite || !favoriteLimitReached
                    ? onToggleFavorite
                    : null,
                icon: Icon(isFavorite ? Icons.star : Icons.star_border),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DetailChip(
                icon: Icons.payments_outlined,
                label: product.priceText.isEmpty
                    ? rupiah(product.price)
                    : product.priceText,
              ),
              _DetailChip(
                icon: Icons.store_outlined,
                label: '${product.stock} ${product.unit}',
              ),
              if ((product.barcode ?? '').isNotEmpty)
                _DetailChip(icon: Icons.qr_code_2, label: product.barcode!),
            ],
          ),
        ],
      ),
    );
  }
}

class _FavoriteCountPill extends StatelessWidget {
  const _FavoriteCountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Text(
        '$count/${FavoriteProductStore.maxFavorites} favorit',
        style: const TextStyle(
          color: Color(0xFF92400E),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF64748B)),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 210),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoState extends StatelessWidget {
  const _InfoState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: const Color(0xFF94A3B8)),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
