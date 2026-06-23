import 'package:flutter/material.dart';

import '../../models/cashier_models.dart';
import '../../models/user_profile.dart';
import '../../services/api_client.dart';
import '../../utils/formatters.dart';
import '../common/app_ui.dart';
import '../dashboard/dashboard_metric.dart';
import 'cashier_support_widgets.dart';

class CashierDashboardPage extends StatelessWidget {
  const CashierDashboardPage({
    super.key,
    required this.user,
    required this.api,
    required this.bootstrap,
    required this.activeShift,
    required this.cartCount,
    required this.offlinePendingCount,
    required this.onOpenAvailableProducts,
    required this.onCashier,
    required this.onTransactions,
    required this.onShift,
    required this.onSync,
  });

  final UserProfile user;
  final ApiClient api;
  final CashierBootstrap? bootstrap;
  final CashierShiftInfo? activeShift;
  final int cartCount;
  final int offlinePendingCount;
  final VoidCallback onOpenAvailableProducts;
  final VoidCallback onCashier;
  final VoidCallback onTransactions;
  final VoidCallback onShift;
  final VoidCallback? onSync;

  @override
  Widget build(BuildContext context) {
    final lowStock =
        bootstrap?.stockAlerts.where((stock) => stock.isLow).length ?? 0;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        AppSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Halo, ${user.name}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                bootstrap == null
                    ? 'Cabang belum terbaca'
                    : '${bootstrap!.outlet.name} - ${bootstrap!.outlet.code}',
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              FutureBuilder<CashierSummary>(
                future: api.summary(),
                builder: (context, snapshot) {
                  final summary = snapshot.data;
                  final isLoading =
                      snapshot.connectionState == ConnectionState.waiting;

                  return DashboardMetricGrid(
                    children: [
                      DashboardMetric(
                        icon: Icons.payments_outlined,
                        label: 'Penjualan hari ini',
                        value: isLoading
                            ? 'Memuat...'
                            : rupiah(summary?.todaySalesTotal ?? 0),
                        color: const Color(0xFF047857),
                      ),
                      DashboardMetric(
                        icon: Icons.receipt_long_outlined,
                        label: 'Transaksi hari ini',
                        value: isLoading
                            ? 'Memuat...'
                            : '${summary?.todaySalesCount ?? 0} trx',
                        color: const Color(0xFF4F46E5),
                      ),
                      DashboardMetric(
                        icon: Icons.shopping_bag_outlined,
                        label: 'Item terjual',
                        value: isLoading
                            ? 'Memuat...'
                            : '${summary?.todayItemsCount ?? 0} item',
                        color: const Color(0xFF7C3AED),
                      ),
                      DashboardMetric(
                        icon: Icons.storefront_outlined,
                        label: 'Produk tersedia',
                        value: isLoading
                            ? 'Memuat...'
                            : '${summary?.availableProductCount ?? 0} produk',
                        color: const Color(0xFF0F766E),
                        onTap: onOpenAvailableProducts,
                      ),
                      DashboardMetric(
                        icon: Icons.inventory_2_outlined,
                        label: 'Stok rendah',
                        value: isLoading
                            ? '$lowStock produk'
                            : '${summary?.lowStockCount ?? lowStock} produk',
                        color: const Color(0xFFDC2626),
                      ),
                      DashboardMetric(
                        icon: activeShift == null
                            ? Icons.lock_clock_outlined
                            : Icons.lock_open_outlined,
                        label: 'Shift',
                        value: activeShift == null ? 'Belum buka' : 'Aktif',
                        color: activeShift == null
                            ? const Color(0xFFB45309)
                            : const Color(0xFF047857),
                      ),
                      DashboardMetric(
                        icon: Icons.point_of_sale,
                        label: 'Keranjang',
                        value: '$cartCount item',
                        color: const Color(0xFF4F46E5),
                      ),
                      DashboardMetric(
                        icon: Icons.cloud_upload_outlined,
                        label: 'Offline',
                        value: '$offlinePendingCount pending',
                        color: const Color(0xFFB45309),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        QuickMenu(
          onCashier: onCashier,
          onTransactions: onTransactions,
          onShift: onShift,
          onSync: onSync,
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<CashierProduct>>(
          future: api.availableProducts(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const _BranchStockPanel.loading();
            }

            if (snapshot.hasError) {
              return _BranchStockPanel.error(
                onRetry: onOpenAvailableProducts,
              );
            }

            return _BranchStockPanel(
              products: snapshot.data ?? const [],
              onOpenDetails: onOpenAvailableProducts,
            );
          },
        ),
      ],
    );
  }
}

class _BranchStockPanel extends StatelessWidget {
  const _BranchStockPanel({required this.products, this.onOpenDetails})
      : loading = false,
        error = false,
        onRetry = null;

  const _BranchStockPanel.loading()
      : products = const [],
        loading = true,
        error = false,
        onRetry = null,
        onOpenDetails = null;

  const _BranchStockPanel.error({required this.onRetry})
      : products = const [],
        loading = false,
        error = true,
        onOpenDetails = null;

  final List<CashierProduct> products;
  final bool loading;
  final bool error;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenDetails;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return _panel(
        child: const Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text(
              'Memuat info stok cabang...',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    if (error) {
      return _panel(
        child: Row(
          children: [
            const Icon(Icons.inventory_2_outlined, color: Color(0xFFDC2626)),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Info stok gagal dimuat.',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Lihat')),
          ],
        ),
      );
    }

    if (products.isEmpty) {
      return _panel(
        child: const Row(
          children: [
            Icon(Icons.inventory_2_outlined, color: Color(0xFF64748B)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Belum ada produk aktif tersedia di cabang ini.',
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

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined, color: Color(0xFF4F46E5)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Info Stok Cabang',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${products.length} produk',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (onOpenDetails != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Lihat semua produk',
                  visualDensity: VisualDensity.compact,
                  onPressed: onOpenDetails,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 112),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: products.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final product = products[index];

                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          product.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${product.stock} ${product.unit}',
                        style: const TextStyle(
                          color: Color(0xFF111827),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: child,
    );
  }
}
