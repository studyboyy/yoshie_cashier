import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/cashier_models.dart';
import '../../utils/formatters.dart';
import '../common/app_ui.dart';
import 'cashier_support_widgets.dart';

class PaymentSheet extends StatefulWidget {
  const PaymentSheet({
    super.key,
    required this.cartCount,
    required this.paymentMethods,
    required this.selectedPaymentMethod,
    required this.paidController,
    required this.redeemController,
    required this.referenceController,
    required this.hasSelectedCustomer,
    required this.maxRedeemPoints,
    required this.quickPaidAmounts,
    required this.subtotal,
    required this.negotiationDiscount,
    required this.pointDiscount,
    required this.payableTotal,
    required this.checkoutLoading,
    required this.onSelectPaymentMethod,
    required this.onRedeemMax,
    required this.onCheckout,
    required this.onTotalsChanged,
  });

  final int cartCount;
  final List<PaymentMethod> paymentMethods;
  final PaymentMethod? selectedPaymentMethod;
  final TextEditingController paidController;
  final TextEditingController redeemController;
  final TextEditingController referenceController;
  final bool hasSelectedCustomer;
  final int maxRedeemPoints;
  final List<double> quickPaidAmounts;
  final double subtotal;
  final double negotiationDiscount;
  final double pointDiscount;
  final double payableTotal;
  // changeAmount dihitung langsung di State agar reactive terhadap input
  final bool checkoutLoading;
  final Future<PaymentMethod?> Function() onSelectPaymentMethod;
  final VoidCallback onRedeemMax;
  final VoidCallback onCheckout;
  final VoidCallback onTotalsChanged;

  @override
  State<PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<PaymentSheet> {
  late PaymentMethod? _selectedPaymentMethod = widget.selectedPaymentMethod;

  /// Hitung kembali langsung dari controller — bukan dari parent widget.
  double get _changeAmount {
    final paid = double.tryParse(widget.paidController.text.trim()) ?? 0;
    return (paid - widget.payableTotal).clamp(0, double.infinity);
  }

  void _refreshTotals() {
    widget.onTotalsChanged();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        18 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                'Pembayaran',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              AppPill('${widget.cartCount} item'),
            ],
          ),
          const SizedBox(height: 14),
          PaymentMethodField(
            value: _selectedPaymentMethod,
            enabled: widget.paymentMethods.isNotEmpty,
            onTap: () async {
              final selected = await widget.onSelectPaymentMethod();
              if (mounted) {
                setState(() => _selectedPaymentMethod = selected);
              }
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: widget.paidController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => _refreshTotals(),
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            decoration: InputDecoration(
              labelText: 'Nominal bayar',
              hintText: rupiah(widget.payableTotal),
              helperText: widget.paidController.text.isEmpty
                  ? 'Kosongkan untuk bayar pas sesuai total'
                  : null,
              prefixIcon: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                child: Text(
                  'Rp',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF475569),
                  ),
                ),
              ),
            ),
          ),
          if (widget.quickPaidAmounts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.quickPaidAmounts.map((amount) {
                final isExact = amount == widget.payableTotal;
                return ActionChip(
                  avatar: Icon(
                    isExact
                        ? Icons.check_circle_outline
                        : Icons.payments_outlined,
                    size: 18,
                  ),
                  label: Text(isExact ? 'Pas' : rupiah(amount)),
                  onPressed: () {
                    widget.paidController.text = amount.toStringAsFixed(0);
                    _refreshTotals();
                  },
                );
              }).toList(),
            ),
          ],
          if (widget.hasSelectedCustomer) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.redeemController,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _refreshTotals(),
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    decoration: InputDecoration(
                      labelText: 'Pakai poin',
                      helperText: 'Maksimal ${widget.maxRedeemPoints} poin',
                      prefixIcon: const Icon(Icons.stars_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 54,
                  child: OutlinedButton(
                    onPressed: widget.maxRedeemPoints <= 0
                        ? null
                        : () {
                            widget.onRedeemMax();
                            _refreshTotals();
                          },
                    child: const Text('Maks'),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: widget.referenceController,
            textInputAction: TextInputAction.done,
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            decoration: const InputDecoration(
              labelText: 'No. referensi',
              hintText: 'Opsional',
              prefixIcon: Icon(Icons.receipt_long_outlined),
            ),
          ),
          const SizedBox(height: 14),
          SummaryLine(label: 'Subtotal', value: rupiah(widget.subtotal)),
          if (widget.negotiationDiscount > 0) ...[
            const SizedBox(height: 6),
            SummaryLine(
              label: 'Potongan nego',
              value: '-${rupiah(widget.negotiationDiscount)}',
              highlight: true,
            ),
          ],
          if (widget.pointDiscount > 0) ...[
            const SizedBox(height: 6),
            SummaryLine(
              label: 'Diskon poin',
              value: '-${rupiah(widget.pointDiscount)}',
              highlight: true,
            ),
          ],
          const SizedBox(height: 10),
          PaymentTotalBox(total: widget.payableTotal),
          if (widget.cartCount > 0) ...[
            const SizedBox(height: 8),
            SummaryLine(
              label: 'Kembali',
              value: rupiah(_changeAmount),
              highlight: true,
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: widget.checkoutLoading ? null : widget.onCheckout,
            icon: widget.checkoutLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.point_of_sale),
            label: Text(
              widget.checkoutLoading ? 'Memproses...' : 'Simpan Transaksi',
            ),
          ),
        ],
      ),
    );
  }
}
