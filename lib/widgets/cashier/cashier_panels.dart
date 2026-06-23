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
    required this.memberPanel,
    required this.searchController,
    required this.searchFocusNode,
    required this.manualSearchKeyboard,
    required this.searching,
    required this.products,
    required this.message,
    required this.messageIsError,
    required this.onSearchTap,
    required this.onSearchSubmitted,
    required this.onClearSearch,
    required this.onToggleKeyboard,
    required this.onProductTap,
  });

  final Widget memberPanel;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final bool manualSearchKeyboard;
  final bool searching;
  final List<CashierProduct> products;
  final String? message;
  final bool messageIsError;
  final VoidCallback onSearchTap;
  final VoidCallback onSearchSubmitted;
  final VoidCallback onClearSearch;
  final VoidCallback onToggleKeyboard;
  final ValueChanged<CashierProduct> onProductTap;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Kasir',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          const Text(
            'Cari produk, scan barcode, lalu masukkan ke keranjang.',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          memberPanel,
          const SizedBox(height: 14),
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
                    helperText: manualSearchKeyboard
                        ? 'Mode ketik manual aktif'
                        : 'Scanner aktif - ketuk untuk mengetik manual',
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
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(
                  height: 48,
                  width: 48,
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
            const SizedBox(height: 10),
            MessageBanner(message: message!, isError: messageIsError),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Produk',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${products.length} hasil',
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
              child: products.isEmpty
                  ? const EmptyState(
                      key: ValueKey('empty-products'),
                      text:
                          'Cari produk atau scan barcode untuk mulai transaksi.',
                    )
                  : ListView.separated(
                      key: ValueKey(
                        'products-${products.length}-${searchController.text}',
                      ),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: products.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final product = products[index];
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
        ],
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

class MemberPanel extends StatelessWidget {
  const MemberPanel({
    super.key,
    required this.selectedCustomer,
    required this.searchController,
    required this.searchingCustomer,
    required this.customers,
    required this.onClearCustomer,
    required this.onClearSearch,
    required this.onSelectCustomer,
  });

  final CashierCustomer? selectedCustomer;
  final TextEditingController searchController;
  final bool searchingCustomer;
  final List<CashierCustomer> customers;
  final VoidCallback onClearCustomer;
  final VoidCallback onClearSearch;
  final ValueChanged<CashierCustomer> onSelectCustomer;

  @override
  Widget build(BuildContext context) {
    final selected = selectedCustomer;

    if (selected != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.verified_user_outlined,
                color: Color(0xFF047857),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selected.name,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${selected.memberCode} - ${selected.points} poin',
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Hapus member',
              onPressed: onClearCustomer,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: searchController,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: 'Cari member',
            prefixIcon: const Icon(Icons.person_search_outlined),
            suffixIcon: searchingCustomer
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : searchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Bersihkan',
                    onPressed: onClearSearch,
                    icon: const Icon(Icons.close),
                  ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: customers.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  key: ValueKey(
                    'customers-${customers.length}-${searchController.text}',
                  ),
                  padding: const EdgeInsets.only(top: 8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 156),
                    child: ListView.separated(
                      shrinkWrap: true,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: customers.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final customer = customers[index];
                        return CustomerTile(
                          customer: customer,
                          onTap: () => onSelectCustomer(customer),
                        );
                      },
                    ),
                  ),
                ),
        ),
      ],
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
              ),
            ),
          const SizedBox(height: 12),
          SummaryLine(label: 'Subtotal', value: rupiah(total)),
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
  });

  final List<CartItem> cart;
  final ValueChanged<CartItem> onEditItem;
  final ValueChanged<CartItem> onRemoveItem;
  final ValueChanged<CartItem> onDecrementItem;
  final ValueChanged<CartItem> onIncrementItem;

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
        );
      },
    );
  }
}
