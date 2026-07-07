import 'package:flutter/material.dart';

import '../../models/cashier_models.dart';
import '../../utils/formatters.dart';
import '../common/app_ui.dart';
import 'cart_item_tile.dart';
import 'cashier_support_widgets.dart';
import 'product_tile.dart';

class CashierProductPanel extends StatelessWidget {
  const CashierProductPanel({
    super.key,
    required this.searchController,
    required this.searchFocusNode,
    required this.manualSearchKeyboard,
    required this.searching,
    required this.products,
    required this.favoriteProducts,
    required this.message,
    required this.messageIsError,
    required this.onSearchTap,
    required this.onSearchSubmitted,
    required this.onClearSearch,
    required this.onToggleKeyboard,
    required this.onProductTap,
  });

  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final bool manualSearchKeyboard;
  final bool searching;
  final List<CashierProduct> products;
  final List<CashierProduct> favoriteProducts;
  final String? message;
  final bool messageIsError;
  final VoidCallback onSearchTap;
  final VoidCallback onSearchSubmitted;
  final VoidCallback onClearSearch;
  final VoidCallback onToggleKeyboard;
  final ValueChanged<CashierProduct> onProductTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final searchQuery = searchController.text.trim();
        final showSearchResults = searchQuery.isNotEmpty && products.isNotEmpty;
        final showMainProducts = searchQuery.isEmpty || !showSearchResults;
        final mainProducts = searchQuery.isEmpty ? favoriteProducts : products;
        final mainTitle = searchQuery.isEmpty ? 'Produk Favorit' : 'Produk';
        final mainCount = searchQuery.isEmpty
            ? '${favoriteProducts.length}/5'
            : '${products.length} hasil';
        final compact = constraints.maxWidth < 330 || constraints.maxHeight < 520;
        final resultMaxHeight = constraints.maxHeight < 520 ? 176.0 : 260.0;

        return AppSurface(
          padding: EdgeInsets.all(compact ? 12 : 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Kasir',
                style: TextStyle(
                  fontSize: compact ? 17 : 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (!compact) ...[
                const SizedBox(height: 4),
                const Text(
                  'Cari produk, scan barcode, lalu masukkan ke keranjang.',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              SizedBox(height: compact ? 10 : 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: searchController,
                      focusNode: searchFocusNode,
                      autofocus: false,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        labelText: 'Cari / scan barcode',
                        helperText: compact
                            ? null
                            : (manualSearchKeyboard
                                  ? 'Mode ketik manual aktif'
                                  : 'Scanner aktif - ketuk untuk mengetik manual'),
                        prefixIcon: const Icon(Icons.qr_code_scanner),
                        suffixIcon: SearchFieldActions(
                          hasText: searchController.text.isNotEmpty,
                          manualKeyboard: manualSearchKeyboard,
                          onClear: onClearSearch,
                          onToggleKeyboard: onToggleKeyboard,
                        ),
                      ),
                      onTap: onSearchTap,
                      onSubmitted: (_) => onSearchSubmitted(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: EdgeInsets.only(top: compact ? 4 : 8),
                    child: SizedBox(
                      height: compact ? 44 : 48,
                      width: compact ? 44 : 48,
                      child: FilledButton(
                        onPressed: searching ? null : onSearchSubmitted,
                        style: FilledButton.styleFrom(padding: EdgeInsets.zero),
                        child: searching
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.search),
                      ),
                    ),
                  ),
                ],
              ),
              if (message != null) ...[
                SizedBox(height: compact ? 8 : 10),
                MessageBanner(message: message!, isError: messageIsError),
              ],
              SizedBox(height: compact ? 10 : 14),
              if (showSearchResults) ...[
                _FloatingSearchResults(
                  products: products,
                  maxHeight: resultMaxHeight,
                  onProductTap: onProductTap,
                ),
                SizedBox(height: compact ? 10 : 14),
              ],
              if (showMainProducts) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        mainTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      mainCount,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: mainProducts.isEmpty
                        ? EmptyState(
                            key: ValueKey(
                              searchQuery.isEmpty
                                  ? 'empty-favorites'
                                  : 'empty-products',
                            ),
                            text: searchQuery.isEmpty
                                ? 'Belum ada produk favorit. Buka daftar produk cabang lalu pilih ikon bintang.'
                                : 'Produk tidak ditemukan.',
                          )
                        : ListView.separated(
                            key: ValueKey(
                              'products-${mainProducts.length}-$searchQuery',
                            ),
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            itemCount: mainProducts.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final product = mainProducts[index];
                              return ProductTile(
                                product: product,
                                onTap: product.stock <= 0
                                    ? null
                                    : () => onProductTap(product),
                              );
                            },
                          ),
                  ),
                ),
              ] else
                const Spacer(),
            ],
          ),
        );
      },
    );
  }
}

class _FloatingSearchResults extends StatelessWidget {
  const _FloatingSearchResults({
    required this.products,
    required this.maxHeight,
    required this.onProductTap,
  });

  final List<CashierProduct> products;
  final double maxHeight;
  final ValueChanged<CashierProduct> onProductTap;

  @override
  Widget build(BuildContext context) {
    final visibleProducts = products.take(5).toList();

    return Material(
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: 0.10),
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          itemCount: visibleProducts.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final product = visibleProducts[index];
            return ProductTile(
              product: product,
              onTap: product.stock <= 0 ? null : () => onProductTap(product),
            );
          },
        ),
      ),
    );
  }
}

class StockAlertPanel extends StatelessWidget {
  const StockAlertPanel({super.key, required this.alerts});

  final List<StockAlert> alerts;

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Row(
          children: [
            Icon(Icons.inventory_2_outlined, color: Color(0xFF64748B)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Info stok cabang belum tersedia.',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined, color: Color(0xFF4F46E5)),
              const SizedBox(width: 8),
              const Text(
                'Info Stok Cabang',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              Text(
                '${alerts.length} produk',
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 112),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: alerts.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                return StockAlertTile(alert: alerts[index]);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class CartPanel extends StatelessWidget {
  const CartPanel({
    super.key,
    required this.cart,
    required this.cartCount,
    required this.total,
    required this.pointDiscount,
    required this.payableTotal,
    required this.checkoutLoading,
    required this.onClearCart,
    required this.onOpenPayment,
    required this.onEditItem,
    required this.onRemoveItem,
    required this.onDecrementItem,
    required this.onIncrementItem,
    required this.onNegotiateItem,
    this.compact = false,
    this.compactCartMaxHeight = 210,
  });

  final List<CartItem> cart;
  final int cartCount;
  final double total;
  final double pointDiscount;
  final double payableTotal;
  final bool checkoutLoading;
  final VoidCallback onClearCart;
  final VoidCallback onOpenPayment;
  final ValueChanged<CartItem> onEditItem;
  final ValueChanged<CartItem> onRemoveItem;
  final ValueChanged<CartItem> onDecrementItem;
  final ValueChanged<CartItem> onIncrementItem;
  final ValueChanged<CartItem> onNegotiateItem;
  final bool compact;
  final double compactCartMaxHeight;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Keranjang',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ),
              if (cart.isNotEmpty)
                IconButton(
                  tooltip: 'Kosongkan keranjang',
                  onPressed: onClearCart,
                  icon: const Icon(Icons.delete_outline),
                ),
              AppPill('$cartCount item'),
            ],
          ),
          const SizedBox(height: 10),
          if (cart.isEmpty)
            const EmptyState(text: 'Belum ada item di keranjang.')
          else if (compact)
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: compactCartMaxHeight),
              child: _CartList(
                cart: cart,
                onEditItem: onEditItem,
                onRemoveItem: onRemoveItem,
                onDecrementItem: onDecrementItem,
                onIncrementItem: onIncrementItem,
                onNegotiateItem: onNegotiateItem,
              ),
            )
          else
            Expanded(
              child: _CartList(
                cart: cart,
                onEditItem: onEditItem,
                onRemoveItem: onRemoveItem,
                onDecrementItem: onDecrementItem,
                onIncrementItem: onIncrementItem,
                onNegotiateItem: onNegotiateItem,
              ),
            ),
          const SizedBox(height: 12),
          SummaryLine(label: 'Subtotal', value: rupiah(total)),
          if (cart.fold<double>(0, (sum, item) => sum + item.discountAmount) >
              0) ...[
            const SizedBox(height: 6),
            SummaryLine(
              label: 'Potongan nego',
              value:
                  '-${rupiah(cart.fold<double>(0, (sum, item) => sum + item.discountAmount))}',
              highlight: true,
            ),
          ],
          if (pointDiscount > 0) ...[
            const SizedBox(height: 6),
            SummaryLine(
              label: 'Diskon poin',
              value: '-${rupiah(pointDiscount)}',
              highlight: true,
            ),
          ],
          const SizedBox(height: 10),
          PaymentTotalBox(total: payableTotal),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: checkoutLoading || cart.isEmpty ? null : onOpenPayment,
            icon: checkoutLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.payments_outlined),
            label: Text(checkoutLoading ? 'Memproses...' : 'Bayar'),
          ),
        ],
      ),
    );
  }
}

class _CartList extends StatelessWidget {
  const _CartList({
    required this.cart,
    required this.onEditItem,
    required this.onRemoveItem,
    required this.onDecrementItem,
    required this.onIncrementItem,
    required this.onNegotiateItem,
  });

  final List<CartItem> cart;
  final ValueChanged<CartItem> onEditItem;
  final ValueChanged<CartItem> onRemoveItem;
  final ValueChanged<CartItem> onDecrementItem;
  final ValueChanged<CartItem> onIncrementItem;
  final ValueChanged<CartItem> onNegotiateItem;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      itemCount: cart.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = cart[index];
        return CartItemTile(
          item: item,
          onEdit: () => onEditItem(item),
          onRemove: () => onRemoveItem(item),
          onDecrement: () => onDecrementItem(item),
          onIncrement: item.quantity >= item.product.stock
              ? null
              : () => onIncrementItem(item),
          onNegotiate: () => onNegotiateItem(item),
        );
      },
    );
  }
}
