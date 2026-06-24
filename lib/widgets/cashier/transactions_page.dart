import 'package:flutter/material.dart';

import '../../models/cashier_models.dart';
import '../../services/api_client.dart';
import '../../utils/formatters.dart';
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

  void _showSaleDetail(RecentSale sale) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _SaleDetailSheet(
        sale: sale,
        onOpenReceipt: () {
          Navigator.of(context).pop();
          widget.onOpenReceipt(sale);
        },
      ),
    );
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
          final isOutletError =
              errorMsg.toLowerCase().contains('cabang') ||
              errorMsg.toLowerCase().contains('outlet');

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
                    onTap: () => _showSaleDetail(sale),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SaleDetailSheet extends StatelessWidget {
  const _SaleDetailSheet({required this.sale, required this.onOpenReceipt});

  final RecentSale sale;
  final VoidCallback onOpenReceipt;

  @override
  Widget build(BuildContext context) {
    final paidAt = sale.paidAt == null ? '-' : receiptDateTime(sale.paidAt!);

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          MediaQuery.paddingOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.receipt_long_outlined,
                    color: Color(0xFF4F46E5),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sale.invoiceNumber,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        paidAt,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  _DetailRow(
                    label: 'Member',
                    value: sale.customer ?? 'Non member',
                  ),
                  _DetailRow(
                    label: 'Pembayaran',
                    value: sale.paymentMethod ?? '-',
                  ),
                  _DetailRow(label: 'Total', value: rupiah(sale.grandTotal)),
                  _DetailRow(label: 'Bayar', value: rupiah(sale.paidAmount)),
                  _DetailRow(
                    label: 'Kembali',
                    value: rupiah(sale.changeAmount),
                    isLast: true,
                  ),
                ],
              ),
            ),
            if (sale.items.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 220),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Item Transaksi',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: sale.items.length,
                        separatorBuilder: (_, _) => const Divider(height: 14),
                        itemBuilder: (context, index) {
                          return _SaleItemRow(item: sale.items[index]);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onOpenReceipt,
              icon: const Icon(Icons.print_outlined),
              label: const Text('Buka Struk / Cetak Ulang'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaleItemRow extends StatelessWidget {
  const _SaleItemRow({required this.item});

  final RecentSaleItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.productName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 2),
              Text(
                '${item.quantity} x ${rupiah(item.unitPrice)}',
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          rupiah(item.subtotal),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}
