import 'package:flutter/material.dart';

import '../../models/cashier_models.dart';
import '../../services/api_client.dart';
import '../common/app_ui.dart';
import 'cashier_support_widgets.dart';

class CashierTransactionsPage extends StatefulWidget {
  const CashierTransactionsPage({
    super.key,
    required this.api,
    required this.onOpenReceipt,
  });

  final ApiClient api;
  final ValueChanged<RecentSale> onOpenReceipt;

  @override
  State<CashierTransactionsPage> createState() =>
      _CashierTransactionsPageState();
}

class _CashierTransactionsPageState extends State<CashierTransactionsPage> {
  late Future<List<RecentSale>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.recentSales();
  }

  void _reload() {
    setState(() {
      _future = widget.api.recentSales();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RecentSale>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          final errorMsg = snapshot.error.toString();
          // Deteksi pesan "belum punya cabang" dari server
          final isOutletError = errorMsg.toLowerCase().contains('cabang')
              || errorMsg.toLowerCase().contains('outlet');

          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isOutletError
                        ? const Color(0xFFFFF7ED)
                        : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isOutletError
                          ? const Color(0xFFFED7AA)
                          : const Color(0xFFFECACA),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        isOutletError
                            ? Icons.store_outlined
                            : Icons.cloud_off_outlined,
                        color: isOutletError
                            ? const Color(0xFFD97706)
                            : const Color(0xFFDC2626),
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isOutletError
                                  ? 'Akun belum masuk cabang'
                                  : 'Gagal memuat transaksi',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: isOutletError
                                    ? const Color(0xFFD97706)
                                    : const Color(0xFFDC2626),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isOutletError
                                  ? 'Akun Anda belum di-assign ke cabang manapun. Minta admin untuk menambahkan di menu User Cabang.'
                                  : errorMsg,
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Coba Lagi'),
                ),
              ],
            ),
          );
        }

        final sales = snapshot.data ?? [];

        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Row(
              children: [
                const Text(
                  'Transaksi Terbaru',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh',
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (sales.isEmpty)
              const AppSurface(
                child: EmptyState(text: 'Belum ada transaksi terbaru.'),
              )
            else
              ...sales.map(
                (sale) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: RecentSaleTile(
                    sale: sale,
                    onTap: () => widget.onOpenReceipt(sale),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
