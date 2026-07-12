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
    required this.onPrintDailySummary,
    required this.onPrintDailyReceipts,
    this.offlineSales = const <RecentSale>[],
    this.onForgetSyncedOfflineSales,
    this.onOfflineReturn,
    this.trainingMode = false,
    this.trainingSales = const <RecentSale>[],
    this.onTrainingReturn,
  });

  final ApiClient api;
  final ValueChanged<RecentSale> onOpenReceipt;
  final Future<void> Function(List<RecentSale> sales) onPrintDailySummary;
  final Future<void> Function(List<RecentSale> sales) onPrintDailyReceipts;
  final List<RecentSale> offlineSales;
  final Future<void> Function(Iterable<String> references)?
  onForgetSyncedOfflineSales;
  final Future<SaleReturnResult> Function(
    RecentSale sale,
    List<SaleReturnItemRequest> items,
    String reason,
  )?
  onOfflineReturn;
  final bool trainingMode;
  final List<RecentSale> trainingSales;
  final Future<SaleReturnResult> Function(
    RecentSale sale,
    List<SaleReturnItemRequest> items,
    String reason,
  )?
  onTrainingReturn;

  @override
  State<CashierTransactionsPage> createState() =>
      _CashierTransactionsPageState();
}

class _CashierTransactionsPageState extends State<CashierTransactionsPage> {
  late Future<List<RecentSale>> _future;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _future = _loadSales();
  }

  @override
  void didUpdateWidget(CashierTransactionsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trainingMode != oldWidget.trainingMode ||
        widget.trainingSales != oldWidget.trainingSales ||
        widget.offlineSales != oldWidget.offlineSales) {
      _reload();
    }
  }

  Future<List<RecentSale>> _loadSales() {
    final selectedDate = _dateOnly(_selectedDate);

    if (widget.trainingMode) {
      return Future.value(
        widget.trainingSales
            .where((sale) => _isSameDate(sale.paidAt, selectedDate))
            .toList(),
      );
    }

    return widget.api
        .recentSales(date: selectedDate)
        .then((sales) async {
          final datedOfflineSales = widget.offlineSales
              .where((sale) => _isSameDate(sale.paidAt, selectedDate))
              .toList();

          if (datedOfflineSales.isEmpty) {
            return sales;
          }

          final onlineReferences = sales.expand(_saleReferences).toSet();
          final offlineReferences = datedOfflineSales
              .expand(_saleReferences)
              .toSet();
          final syncedLocalReferences = sales
              .map((sale) => sale.localReference?.trim().toUpperCase())
              .whereType<String>()
              .where((reference) => reference.isNotEmpty)
              .toSet();
          syncedLocalReferences.addAll(
            await _syncedOfflineReferences(offlineReferences),
          );

          if (syncedLocalReferences.isNotEmpty) {
            await widget.onForgetSyncedOfflineSales?.call({
              ...onlineReferences,
              ...syncedLocalReferences,
            });
          }

          return [
            ...datedOfflineSales.where((sale) {
              final references = _saleReferences(sale);

              return references.intersection(onlineReferences).isEmpty &&
                  references.intersection(syncedLocalReferences).isEmpty;
            }),
            ...sales,
          ];
        })
        .catchError((error) {
          if (error is NetworkException && widget.offlineSales.isNotEmpty) {
            return widget.offlineSales
                .where((sale) => _isSameDate(sale.paidAt, selectedDate))
                .toList();
          }

          throw error;
        });
  }

  Future<Set<String>> _syncedOfflineReferences(Set<String> references) async {
    if (references.isEmpty) {
      return const <String>{};
    }

    try {
      final statuses = await widget.api.offlineSaleStatuses(references);

      return statuses
          .where((status) => status.isSynced)
          .map((status) => status.localReference.trim().toUpperCase())
          .where((reference) => reference.isNotEmpty)
          .toSet();
    } catch (_) {
      return const <String>{};
    }
  }

  Set<String> _saleReferences(RecentSale sale) {
    return {
      _normalizeReference(sale.invoiceNumber),
      _normalizeReference(sale.localReference),
    }..remove('');
  }

  String _normalizeReference(String? value) {
    return (value ?? '').trim().toUpperCase();
  }

  void _reload() {
    setState(() {
      _future = _loadSales();
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: 'Pilih tanggal transaksi',
    );

    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      _selectedDate = picked;
      _future = _loadSales();
    });
  }

  void _resetDateToToday() {
    final today = DateTime.now();
    if (_isSameDate(_selectedDate, today)) {
      return;
    }

    setState(() {
      _selectedDate = today;
      _future = _loadSales();
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
        onReturn: sale.items.any((item) => item.canReturn)
            ? () {
                Navigator.of(context).pop();
                _showReturnSheet(sale);
              }
            : null,
      ),
    );
  }

  void _showReturnSheet(RecentSale sale) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _ReturnSheet(
        sale: sale,
        onSave: (items, reason) {
          if (widget.trainingMode) {
            return widget.onTrainingReturn!(sale, items, reason);
          }

          if (sale.localOnly) {
            return widget.onOfflineReturn!(sale, items, reason);
          }

          return widget.api.createSaleReturn(
            saleId: sale.id,
            items: items,
            reason: reason,
          );
        },
        onSaved: (result) {
          _reload();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${result.returnNumber} tersimpan. Refund ${rupiah(result.refundAmount)}.',
              ),
            ),
          );
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
        final total = sales.fold<double>(0, (sum, sale) => sum + sale.netTotal);

        return ListView(
          padding: const EdgeInsets.all(12),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.trainingMode
                            ? 'Histori Training'
                            : 'Transaksi Hari Ini',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${sales.length} transaksi - ${rupiah(total)}',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh',
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  label: Text(_formatSelectedDate(_selectedDate)),
                ),
                if (!_isSameDate(_selectedDate, DateTime.now()))
                  TextButton.icon(
                    onPressed: _resetDateToToday,
                    icon: const Icon(Icons.today_outlined, size: 18),
                    label: const Text('Hari ini'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (sales.isNotEmpty) ...[
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 420;
                  final buttonWidth = isNarrow
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 10) / 2;

                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SizedBox(
                        width: buttonWidth,
                        child: FilledButton.icon(
                          onPressed: () => widget.onPrintDailySummary(sales),
                          icon: const Icon(Icons.summarize_outlined),
                          label: Text(
                            widget.trainingMode
                                ? 'Print Rekap Training'
                                : 'Print Rekap Harian',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: buttonWidth,
                        child: OutlinedButton.icon(
                          onPressed: () => widget.onPrintDailyReceipts(sales),
                          icon: const Icon(Icons.receipt_long_outlined),
                          label: const Text('Print Semua Struk'),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
            ],
            if (sales.isEmpty)
              AppSurface(
                child: EmptyState(
                  text: widget.trainingMode
                      ? 'Belum ada transaksi training.'
                      : 'Belum ada transaksi hari ini.',
                ),
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

DateTime _dateOnly(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}

bool _isSameDate(DateTime? left, DateTime right) {
  if (left == null) {
    return false;
  }

  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

String _formatSelectedDate(DateTime date) {
  final today = DateTime.now();
  if (_isSameDate(date, today)) {
    return 'Hari ini';
  }

  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _SaleDetailSheet extends StatelessWidget {
  const _SaleDetailSheet({
    required this.sale,
    required this.onOpenReceipt,
    this.onReturn,
  });

  final RecentSale sale;
  final VoidCallback onOpenReceipt;
  final VoidCallback? onReturn;

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
                  _DetailRow(
                    label: 'Total awal',
                    value: rupiah(sale.grandTotal),
                  ),
                  if (sale.returnedTotal > 0)
                    _DetailRow(
                      label: 'Retur',
                      value: '- ${rupiah(sale.returnedTotal)}',
                    ),
                  if (sale.returnedTotal > 0)
                    _DetailRow(
                      label: 'Total bersih',
                      value: rupiah(sale.netTotal),
                    ),
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
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onOpenReceipt,
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Cetak Ulang'),
                  ),
                ),
                if (onReturn != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onReturn,
                      icon: const Icon(Icons.assignment_return_outlined),
                      label: const Text('Retur'),
                    ),
                  ),
                ],
              ],
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
                '${item.quantity} x ${rupiah(item.finalUnitPrice)}'
                '${item.returnedQuantity > 0 ? ' - retur ${item.returnedQuantity}' : ''}',
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

class _ReturnSheet extends StatefulWidget {
  const _ReturnSheet({
    required this.sale,
    required this.onSave,
    required this.onSaved,
  });

  final RecentSale sale;
  final Future<SaleReturnResult> Function(
    List<SaleReturnItemRequest> items,
    String reason,
  )
  onSave;
  final ValueChanged<SaleReturnResult> onSaved;

  @override
  State<_ReturnSheet> createState() => _ReturnSheetState();
}

class _ReturnSheetState extends State<_ReturnSheet> {
  final _reasonController = TextEditingController(text: 'Retur pelanggan');
  final Map<int, int> _qtyByItem = {};
  final Map<int, String> _conditionByItem = {};
  bool _saving = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  List<RecentSaleItem> get _returnableItems =>
      widget.sale.items.where((item) => item.canReturn).toList();

  List<SaleReturnItemRequest> get _selectedItems => _returnableItems
      .map(
        (item) => SaleReturnItemRequest(
          saleItemId: item.id,
          productId: item.productId,
          qty: _qtyByItem[item.id] ?? 0,
          condition: _conditionByItem[item.id] ?? 'sellable',
        ),
      )
      .where((item) => item.qty > 0)
      .toList();

  double get _refundTotal {
    var total = 0.0;
    for (final item in _returnableItems) {
      total += (_qtyByItem[item.id] ?? 0) * item.finalUnitPrice;
    }
    return total;
  }

  Future<void> _save() async {
    final items = _selectedItems;
    if (items.isEmpty || _saving) {
      return;
    }

    setState(() => _saving = true);
    try {
      final result = await widget.onSave(items, _reasonController.text);
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSaved(result);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _setQty(RecentSaleItem item, int qty) {
    setState(() {
      _qtyByItem[item.id] = qty < 0
          ? 0
          : (qty > item.returnableQuantity ? item.returnableQuantity : qty);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final items = _returnableItems;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, bottom + 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.assignment_return_outlined,
                    color: Color(0xFFD97706),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Retur Transaksi',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        widget.sale.invoiceNumber,
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
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: const Text(
                'Pilih item yang ingin diretur saja. Qty default 0, jadi produk lain tidak ikut diretur.',
                style: TextStyle(
                  color: Color(0xFF92400E),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _ReturnItemCard(
                    item: item,
                    qty: _qtyByItem[item.id] ?? 0,
                    condition: _conditionByItem[item.id] ?? 'sellable',
                    onQtyChanged: (qty) => _setQty(item, qty),
                    onConditionChanged: (condition) {
                      setState(() => _conditionByItem[item.id] = condition);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reasonController,
              minLines: 1,
              maxLines: 2,
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              decoration: const InputDecoration(
                labelText: 'Catatan retur',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Estimasi refund',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    rupiah(_refundTotal),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _selectedItems.isEmpty || _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Simpan Retur'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReturnItemCard extends StatelessWidget {
  const _ReturnItemCard({
    required this.item,
    required this.qty,
    required this.condition,
    required this.onQtyChanged,
    required this.onConditionChanged,
  });

  final RecentSaleItem item;
  final int qty;
  final String condition;
  final ValueChanged<int> onQtyChanged;
  final ValueChanged<String> onConditionChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: qty > 0 ? const Color(0xFFEEF2FF) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: qty > 0 ? const Color(0xFFC7D2FE) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
                      '${item.productSku} - sisa retur ${item.returnableQuantity}',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                rupiah(item.finalUnitPrice),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton.outlined(
                onPressed: qty <= 0 ? null : () => onQtyChanged(qty - 1),
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 54,
                child: Text(
                  '$qty',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton.filledTonal(
                onPressed: qty >= item.returnableQuantity
                    ? null
                    : () => onQtyChanged(qty + 1),
                icon: const Icon(Icons.add),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: condition,
                  decoration: const InputDecoration(
                    labelText: 'Kondisi',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'sellable',
                      child: Text('Bagus, masuk stok'),
                    ),
                    DropdownMenuItem(
                      value: 'damaged',
                      child: Text('Rusak, jangan masuk stok'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      onConditionChanged(value);
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
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
