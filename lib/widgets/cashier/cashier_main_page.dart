import 'package:flutter/material.dart';

import '../../models/cashier_models.dart';
import '../../services/api_client.dart';
import 'cashier_panels.dart';

/// Halaman utama kasir — menampilkan product panel dan cart panel
/// secara responsif (side-by-side di layar lebar, stacked di layar kecil).
class CashierMainPage extends StatelessWidget {
  const CashierMainPage({
    super.key,
    required this.api,
    required this.searchController,
    required this.searchFocusNode,
    required this.customerSearchController,
    required this.manualSearchKeyboard,
    required this.searching,
    required this.searchingCustomer,
    required this.products,
    required this.favoriteProducts,
    required this.customers,
    required this.selectedCustomer,
    required this.cart,
    required this.cartCount,
    required this.total,
    required this.pointDiscount,
    required this.payableTotal,
    required this.checkoutLoading,
    required this.message,
    required this.messageIsError,
    required this.onSearchTap,
    required this.onSearchSubmitted,
    required this.onClearSearch,
    required this.onToggleKeyboard,
    required this.onProductTap,
    required this.onClearCustomer,
    required this.onClearCustomerSearch,
    required this.onSelectCustomer,
    required this.onClearCart,
    required this.onOpenPayment,
    required this.onEditItem,
    required this.onRemoveItem,
    required this.onDecrementItem,
    required this.onIncrementItem,
    required this.onNegotiateItem,
  });

  // Search
  final ApiClient api;
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

  // Member
  final TextEditingController customerSearchController;
  final bool searchingCustomer;
  final List<CashierCustomer> customers;
  final CashierCustomer? selectedCustomer;
  final VoidCallback onClearCustomer;
  final VoidCallback onClearCustomerSearch;
  final ValueChanged<CashierCustomer> onSelectCustomer;

  // Cart
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscape = constraints.maxWidth > constraints.maxHeight;
        final hasEnoughHeightForSplit = constraints.maxHeight >= 420;
        final isWide =
            constraints.maxWidth >= 760 ||
            (isLandscape &&
                constraints.maxWidth >= 680 &&
                hasEnoughHeightForSplit);
        final pagePadding = constraints.maxWidth < 380 ? 8.0 : 12.0;
        final gap = constraints.maxWidth < 380 ? 8.0 : 12.0;
        final cartWidth = constraints.maxWidth >= 1000
            ? 400.0
            : (constraints.maxWidth * 0.42).clamp(292.0, 380.0).toDouble();
        final compactCartHeight = (constraints.maxHeight * 0.36)
            .clamp(112.0, 240.0)
            .toDouble();

        final memberPanel = MemberPanel(
          selectedCustomer: selectedCustomer,
          searchController: customerSearchController,
          searchingCustomer: searchingCustomer,
          customers: customers,
          onClearCustomer: onClearCustomer,
          onClearSearch: onClearCustomerSearch,
          onSelectCustomer: onSelectCustomer,
        );

        final productPanel = CashierProductPanel(
          memberPanel: memberPanel,
          searchController: searchController,
          searchFocusNode: searchFocusNode,
          manualSearchKeyboard: manualSearchKeyboard,
          searching: searching,
          products: products,
          favoriteProducts: favoriteProducts,
          message: message,
          messageIsError: messageIsError,
          onSearchTap: onSearchTap,
          onSearchSubmitted: onSearchSubmitted,
          onClearSearch: onClearSearch,
          onToggleKeyboard: onToggleKeyboard,
          onProductTap: onProductTap,
        );

        final Widget content = isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: productPanel),
                  SizedBox(width: gap),
                  SizedBox(
                    width: cartWidth,
                    child: CartPanel(
                      cart: cart,
                      cartCount: cartCount,
                      total: total,
                      pointDiscount: pointDiscount,
                      payableTotal: payableTotal,
                      checkoutLoading: checkoutLoading,
                      onClearCart: onClearCart,
                      onOpenPayment: onOpenPayment,
                      onEditItem: onEditItem,
                      onRemoveItem: onRemoveItem,
                      onDecrementItem: onDecrementItem,
                      onIncrementItem: onIncrementItem,
                      onNegotiateItem: onNegotiateItem,
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  Expanded(child: productPanel),
                  SizedBox(height: gap),
                  CartPanel(
                    cart: cart,
                    cartCount: cartCount,
                    total: total,
                    pointDiscount: pointDiscount,
                    payableTotal: payableTotal,
                    checkoutLoading: checkoutLoading,
                    onClearCart: onClearCart,
                    onOpenPayment: onOpenPayment,
                    onEditItem: onEditItem,
                    onRemoveItem: onRemoveItem,
                    onDecrementItem: onDecrementItem,
                    onIncrementItem: onIncrementItem,
                    onNegotiateItem: onNegotiateItem,
                    compact: true,
                    compactCartMaxHeight: compactCartHeight,
                  ),
                ],
              );

        return Padding(padding: EdgeInsets.all(pagePadding), child: content);
      },
    );
  }
}
