import 'package:flutter/material.dart';

import '../../models/cashier_models.dart';
import '../../services/api_client.dart';
import '../../utils/formatters.dart';
import '../common/app_ui.dart';

class SoldTransactionsPage extends StatefulWidget {
  const SoldTransactionsPage({
    super.key,
    required this.api,
    required this.onOpenReceipt,
    this.offlineSales = const <RecentSale>[],
    this.onForgetSyncedOfflineSales,
    this.trainingMode = false,
    this.trainingSales = const <RecentSale>[],
  });

  final ApiClient api;
  final ValueChanged<RecentSale> onOpenReceipt;
  final List<RecentSale> offlineSales;
  final Future<void> Function(Iterable<String> references)?
  onForgetSyncedOfflineSales;
  final bool trainingMode;
  final List<RecentSale> trainingSales;

  @override
  State<SoldTransactionsPage> createState() => _SoldTransactionsPageState();
}

class _SoldTransactionsPageState extends State<SoldTransactionsPage> {
  final _searchController = TextEditingController();
  late Future<List<RecentSale>> _future;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _future = _loadSales();
  }

  @override
  void didUpdateWidget(SoldTransactionsPage oldWidget) {
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<RecentSale> _filterSales(List<RecentSale> sales) {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      return sales;
    }

    final tokens = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();

    if (tokens.isEmpty) {
      return sales;
    }

    return sales.where((sale) {
      final searchable = _saleSearchText(sale);

      return tokens.every(searchable.contains);
    }).toList();
  }

  String _saleSearchText(RecentSale sale) {
    final parts = <String>[
      sale.invoiceNumber,
      sale.localReference ?? '',
      sale.customer ?? '',
      sale.paymentMethod ?? '',
      rupiah(sale.grandTotal),
      rupiah(sale.netTotal),
      _priceSearchValue(sale.grandTotal),
      _priceSearchValue(sale.netTotal),
      if (sale.paidAt != null) receiptDateTime(sale.paidAt!),
    ];

    for (final item in sale.items) {
      parts.addAll([
        item.productName,
        item.productSku,
        rupiah(item.unitPrice),
        rupiah(item.subtotal),
        _priceSearchValue(item.unitPrice),
        _priceSearchValue(item.subtotal),
        item.quantity.toString(),
      ]);
    }

    return parts.join(' ').toLowerCase();
  }

  String _priceSearchValue(num value) {
    final rounded = value.round();
    final thousands = rounded / 1000;
    final compact = thousands % 1 == 0
        ? thousands.toStringAsFixed(0)
        : thousands.toStringAsFixed(1).replaceAll('.', ',');

    return '$rounded $compact ${compact}k';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          widget.trainingMode ? 'Produk Terjual Training' : 'Produk Terjual',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<RecentSale>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: AppSurface(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Color(0xFFDC2626),
                        size: 34,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Gagal memuat detail transaksi',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        snapshot.error.toString(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _reload,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Coba Lagi'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          final sales = [...(snapshot.data ?? const <RecentSale>[])]
            ..sort((a, b) {
              final left = a.paidAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              final right = b.paidAt ?? DateTime.fromMillisecondsSinceEpoch(0);

              return right.compareTo(left);
            });
          final filteredSales = _filterSales(sales);
          final hasSearch = _searchController.text.trim().isNotEmpty;

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                _DateToolbar(
                  selectedDate: _selectedDate,
                  onPickDate: _pickDate,
                  onToday: _resetDateToToday,
                ),
                const SizedBox(height: 12),
                _SmartSearchField(
                  controller: _searchController,
                  resultCount: filteredSales.length,
                  totalCount: sales.length,
                  onChanged: (_) => setState(() {}),
                  onClear: () {
                    _searchController.clear();
                    setState(() {});
                  },
                ),
                const SizedBox(height: 12),
                _SalesSummary(sales: filteredSales),
                const SizedBox(height: 12),
                if (sales.isEmpty)
                  const AppSurface(
                    child: EmptyState(
                      text: 'Belum ada transaksi pada tanggal ini.',
                    ),
                  )
                else if (filteredSales.isEmpty)
                  AppSurface(
                    child: EmptyState(
                      text: hasSearch
                          ? 'Tidak ada invoice atau produk yang cocok.'
                          : 'Belum ada transaksi pada tanggal ini.',
                    ),
                  )
                else
                  ...filteredSales.map(
                    (sale) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _InvoiceCard(
                        sale: sale,
                        onOpenReceipt: () => widget.onOpenReceipt(sale),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DateToolbar extends StatelessWidget {
  const _DateToolbar({
    required this.selectedDate,
    required this.onPickDate,
    required this.onToday,
  });

  final DateTime selectedDate;
  final VoidCallback onPickDate;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.calendar_month_outlined,
              color: Color(0xFF2563EB),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tanggal transaksi',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  receiptDateTime(selectedDate).split(' ').first,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Pilih tanggal',
            onPressed: onPickDate,
            icon: const Icon(Icons.tune),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onToday, child: const Text('Hari ini')),
        ],
      ),
    );
  }
}

class _SmartSearchField extends StatelessWidget {
  const _SmartSearchField({
    required this.controller,
    required this.resultCount,
    required this.totalCount,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final int resultCount;
  final int totalCount;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final hasText = controller.text.trim().isNotEmpty;

    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.manage_search_outlined),
              suffixIcon: hasText
                  ? IconButton(
                      tooltip: 'Bersihkan pencarian',
                      onPressed: onClear,
                      icon: const Icon(Icons.close),
                    )
                  : null,
              labelText: 'Cari invoice, produk, SKU, atau harga',
              hintText: 'Contoh: INV, kaos kaki, DPT-KK1, 15000, 15k',
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(
                  color: Color(0xFF4F46E5),
                  width: 2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasText
                ? '$resultCount dari $totalCount transaksi cocok'
                : '$totalCount transaksi pada tanggal ini',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SalesSummary extends StatelessWidget {
  const _SalesSummary({required this.sales});

  final List<RecentSale> sales;

  @override
  Widget build(BuildContext context) {
    final itemsCount = sales.fold<int>(
      0,
      (sum, sale) =>
          sum + sale.items.fold<int>(0, (a, item) => a + item.quantity),
    );
    final returnsCount = sales.fold<int>(
      0,
      (sum, sale) =>
          sum + sale.items.fold<int>(0, (a, item) => a + item.returnedQuantity),
    );
    final netTotal = sales.fold<double>(0, (sum, sale) => sum + sale.netTotal);
    final returnedTotal = sales.fold<double>(
      0,
      (sum, sale) => sum + sale.returnedTotal,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        final width = compact
            ? constraints.maxWidth
            : (constraints.maxWidth - 10) / 2;

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _SummaryCard(
              width: width,
              icon: Icons.receipt_long_outlined,
              label: 'Invoice',
              value: '${sales.length} transaksi',
              color: const Color(0xFF4F46E5),
            ),
            _SummaryCard(
              width: width,
              icon: Icons.shopping_bag_outlined,
              label: 'Item terjual',
              value: '$itemsCount item',
              color: const Color(0xFF7C3AED),
            ),
            _SummaryCard(
              width: width,
              icon: Icons.payments_outlined,
              label: 'Omzet bersih',
              value: rupiah(netTotal),
              color: const Color(0xFF047857),
            ),
            _SummaryCard(
              width: width,
              icon: Icons.keyboard_return_outlined,
              label: 'Retur',
              value: returnsCount <= 0
                  ? rupiah(returnedTotal)
                  : '$returnsCount item - ${rupiah(returnedTotal)}',
              color: const Color(0xFFB45309),
            ),
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final double width;
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: AppSurface(
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
      ),
    );
  }
}

class _InvoiceCard extends StatefulWidget {
  const _InvoiceCard({required this.sale, required this.onOpenReceipt});

  final RecentSale sale;
  final VoidCallback onOpenReceipt;

  @override
  State<_InvoiceCard> createState() => _InvoiceCardState();
}

class _InvoiceCardState extends State<_InvoiceCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final sale = widget.sale;
    final time = sale.paidAt == null ? '-' : receiptDateTime(sale.paidAt!);
    final itemCount = sale.items.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );
    final hasReturn = sale.returnedTotal > 0 || sale.returnStatus != 'none';

    return AppSurface(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          onExpansionChanged: (expanded) {
            setState(() => _expanded = expanded);
          },
          tilePadding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          initiallyExpanded: false,
          leading: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: sale.localOnly
                  ? const Color(0xFFFFFBEB)
                  : const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              sale.localOnly
                  ? Icons.cloud_off_outlined
                  : Icons.receipt_long_outlined,
              color: sale.localOnly
                  ? const Color(0xFFB45309)
                  : const Color(0xFF2563EB),
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  sale.invoiceNumber,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                time,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 6),
              AnimatedRotation(
                turns: _expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: const Icon(Icons.expand_more, color: Color(0xFF94A3B8)),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _MiniInfo(
                  icon: Icons.shopping_bag_outlined,
                  text: '$itemCount item',
                ),
                _MiniInfo(
                  icon: Icons.payments_outlined,
                  text: rupiah(sale.netTotal),
                ),
                if (sale.paymentMethod != null &&
                    sale.paymentMethod!.trim().isNotEmpty)
                  _MiniInfo(
                    icon: Icons.payments_outlined,
                    text: sale.paymentMethod!,
                  ),
                if (sale.localOnly)
                  const _SoftChip(
                    text: 'Offline',
                    color: Color(0xFFB45309),
                    backgroundColor: Color(0xFFFFFBEB),
                  ),
                if (hasReturn)
                  const _SoftChip(
                    text: 'Ada retur',
                    color: Color(0xFFB45309),
                    backgroundColor: Color(0xFFFFFBEB),
                  ),
              ],
            ),
          ),
          trailing: const SizedBox.shrink(),
          children: [
            const Divider(height: 1),
            const SizedBox(height: 12),
            ...sale.items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _InvoiceItemTile(item: item),
              ),
            ),
            const SizedBox(height: 2),
            _InvoiceTotals(sale: sale),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: widget.onOpenReceipt,
                icon: const Icon(Icons.print_outlined),
                label: const Text('Lihat Struk'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoiceItemTile extends StatelessWidget {
  const _InvoiceItemTile({required this.item});

  final RecentSaleItem item;

  @override
  Widget build(BuildContext context) {
    final returned = item.returnedQuantity > 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              color: Color(0xFF4F46E5),
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
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
                const SizedBox(height: 3),
                Text(
                  item.productSku,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  runSpacing: 6,
                  children: [
                    _SoftChip(
                      text: '${item.quantity} x ${rupiah(item.unitPrice)}',
                    ),
                    if (item.discountAmount > 0)
                      _SoftChip(
                        text: 'Nego -${rupiah(item.discountAmount)}',
                        color: const Color(0xFFB45309),
                        backgroundColor: const Color(0xFFFFFBEB),
                      ),
                    if (returned)
                      _SoftChip(
                        text: 'Retur ${item.returnedQuantity}',
                        color: const Color(0xFFB45309),
                        backgroundColor: const Color(0xFFFFFBEB),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                rupiah(item.subtotal),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 3),
              Text(
                'Net ${rupiah(item.finalUnitPrice * item.returnableQuantity)}',
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InvoiceTotals extends StatelessWidget {
  const _InvoiceTotals({required this.sale});

  final RecentSale sale;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          _TotalRow(label: 'Subtotal', value: rupiah(sale.grandTotal)),
          if (sale.returnedTotal > 0) ...[
            const SizedBox(height: 8),
            _TotalRow(
              label: 'Retur',
              value: '-${rupiah(sale.returnedTotal)}',
              highlight: true,
            ),
          ],
          const Divider(height: 18, color: Color(0xFF334155)),
          _TotalRow(
            label: 'Total bersih',
            value: rupiah(sale.netTotal),
            highlight: true,
            large: true,
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    this.highlight = false,
    this.large = false,
  });

  final String label;
  final String value;
  final bool highlight;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final color = highlight ? const Color(0xFF67E8F9) : const Color(0xFFE2E8F0);

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: large ? 15 : 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: large ? 18 : 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _MiniInfo extends StatelessWidget {
  const _MiniInfo({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: const Color(0xFF64748B)),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _SoftChip extends StatelessWidget {
  const _SoftChip({
    required this.text,
    this.color = const Color(0xFF4F46E5),
    this.backgroundColor = const Color(0xFFEEF2FF),
  });

  final String text;
  final Color color;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _isSameDate(DateTime? left, DateTime right) {
  if (left == null) {
    return false;
  }

  final local = left.toLocal();

  return local.year == right.year &&
      local.month == right.month &&
      local.day == right.day;
}
