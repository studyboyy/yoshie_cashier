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
    required this.manualSearchKeyboard,
    required this.searching,
    required this.products,
    required this.favoriteProducts,
    required this.cart,
    required this.cartCount,
    required this.total,
    required this.pointDiscount,
    required this.payableTotal,
    required this.checkoutLoading,
    required this.message,
    required this.messageIsError,
    required this.onSearchTap,
    required this.onSearchTapOutside,
    required this.onSearchSubmitted,
    required this.onClearSearch,
    required this.onToggleKeyboard,
    required this.onProductTap,
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
  final VoidCallback onSearchTapOutside;
  final VoidCallback onSearchSubmitted;
  final VoidCallback onClearSearch;
  final VoidCallback onToggleKeyboard;
  final ValueChanged<CashierProduct> onProductTap;

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
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final isLandscape = width > height;
        final pagePadding = width < 360 ? 6.0 : (width < 520 ? 8.0 : 12.0);
        final gap = width < 360 ? 8.0 : 12.0;
        final availableWidth = width - (pagePadding * 2);
        final availableHeight = height - (pagePadding * 2);
        final canSplitHorizontally =
            availableWidth >= 560 && (width >= 720 || isLandscape);
        final cartWidth = _cartPanelWidth(availableWidth, gap);
        final compactCartHeight = _stackedCartHeight(availableHeight);

        final productPanel = CashierProductPanel(
          searchController: searchController,
          searchFocusNode: searchFocusNode,
          manualSearchKeyboard: manualSearchKeyboard,
          searching: searching,
          products: products,
          favoriteProducts: favoriteProducts,
          message: message,
          messageIsError: messageIsError,
          onSearchTap: onSearchTap,
          onSearchTapOutside: onSearchTapOutside,
          onSearchSubmitted: onSearchSubmitted,
          onClearSearch: onClearSearch,
          onToggleKeyboard: onToggleKeyboard,
          onProductTap: onProductTap,
        );

        final Widget content = canSplitHorizontally
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  SizedBox(
                    height: compactCartHeight,
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
                      compact: false,
                    ),
                  ),
                ],
              );

        return AnimatedPadding(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.all(pagePadding),
          child: content,
        );
      },
    );
  }

  double _cartPanelWidth(double availableWidth, double gap) {
    final preferred = (availableWidth * 0.40).clamp(292.0, 400.0).toDouble();
    final maxForProduct = availableWidth - gap - 270;

    if (maxForProduct < 292) {
      return preferred;
    }

    return preferred.clamp(292.0, maxForProduct).toDouble();
  }

  double _stackedCartHeight(double availableHeight) {
    if (availableHeight < 430) {
      return (availableHeight * 0.58).clamp(230.0, 260.0).toDouble();
    }

    if (availableHeight < 620) {
      return (availableHeight * 0.48).clamp(260.0, 300.0).toDouble();
    }

    return (availableHeight * 0.36).clamp(260.0, 340.0).toDouble();
  }
}
