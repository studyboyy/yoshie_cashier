import 'package:flutter/material.dart';

import '../../models/cashier_models.dart';
import '../../utils/formatters.dart';
import '../common/app_ui.dart';

class SearchFieldActions extends StatelessWidget {
  const SearchFieldActions({
    super.key,
    required this.hasText,
    required this.manualKeyboard,
    required this.onClear,
    required this.onToggleKeyboard,
  });

  final bool hasText;
  final bool manualKeyboard;
  final VoidCallback onClear;
  final VoidCallback onToggleKeyboard;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasText)
          IconButton(
            tooltip: 'Bersihkan',
            onPressed: onClear,
            icon: const Icon(Icons.close),
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 4),
          ),
        IconButton(
          tooltip: manualKeyboard ? 'Matikan keyboard' : 'Ketik manual',
          onPressed: onToggleKeyboard,
          icon: Icon(
            manualKeyboard ? Icons.keyboard_hide_outlined : Icons.keyboard,
          ),
          iconSize: 20,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
      ],
    );
  }
}

class StockAlertTile extends StatelessWidget {
  const StockAlertTile({super.key, required this.alert});

  final StockAlert alert;

  @override
  Widget build(BuildContext context) {
    final color = alert.isLow
        ? const Color(0xFFDC2626)
        : const Color(0xFF111827);
    final bgColor = alert.isLow ? const Color(0xFFFEF2F2) : Colors.white;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: alert.isLow
              ? const Color(0xFFFECACA)
              : const Color(0xFFE5E7EB),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              alert.productName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${alert.quantity} ${alert.unit}',
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class QuickMenu extends StatelessWidget {
  const QuickMenu({
    super.key,
    required this.onCashier,
    required this.onTransactions,
    required this.onShift,
    required this.onSync,
  });

  final VoidCallback onCashier;
  final VoidCallback onTransactions;
  final VoidCallback onShift;
  final VoidCallback? onSync;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Menu Cepat',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              QuickChip(
                icon: Icons.point_of_sale,
                label: 'Buka Kasir',
                onTap: onCashier,
              ),
              QuickChip(
                icon: Icons.receipt_long,
                label: 'Transaksi',
                onTap: onTransactions,
              ),
              QuickChip(icon: Icons.lock_clock, label: 'Shift', onTap: onShift),
              QuickChip(
                icon: Icons.cloud_upload_outlined,
                label: 'Sync',
                onTap: onSync,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class QuickChip extends StatelessWidget {
  const QuickChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onTap,
    );
  }
}

class ActionRow extends StatelessWidget {
  const ActionRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: const Color(0xFF4F46E5)),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
      trailing: Text(
        value,
        style: const TextStyle(
          color: Color(0xFF64748B),
          fontWeight: FontWeight.w800,
        ),
      ),
      onTap: onTap,
    );
  }
}

class CustomerTile extends StatelessWidget {
  const CustomerTile({super.key, required this.customer, required this.onTap});

  final CashierCustomer customer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.person_outline, color: Color(0xFF4F46E5)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.name,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      customer.phone == null || customer.phone!.isEmpty
                          ? customer.memberCode
                          : '${customer.memberCode} - ${customer.phone}',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${customer.points} poin',
                style: const TextStyle(
                  color: Color(0xFF4F46E5),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OfflineSyncButton extends StatelessWidget {
  const OfflineSyncButton({
    super.key,
    required this.pendingCount,
    required this.syncing,
    required this.onPressed,
  });

  final int pendingCount;
  final bool syncing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: syncing
          ? 'Menyinkronkan transaksi offline'
          : 'Sinkron $pendingCount transaksi offline',
      child: TextButton.icon(
        onPressed: syncing ? null : onPressed,
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF4F46E5),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        icon: syncing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.cloud_upload_outlined, size: 20),
        label: Text(
          '$pendingCount',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class ReceiptMetric extends StatelessWidget {
  const ReceiptMetric({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class RecentSaleTile extends StatelessWidget {
  const RecentSaleTile({super.key, required this.sale, required this.onTap});

  final RecentSale sale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Convert UTC to local time before display.
    final local = sale.paidAt?.toLocal();
    final paidAt = local == null
        ? '-'
        : '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';

    return Material(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(14),
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
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    if (sale.localOnly) ...[
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFFFED7AA)),
                        ),
                        child: const Text(
                          'Offline lokal',
                          style: TextStyle(
                            color: Color(0xFFC2410C),
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 3),
                    Text(
                      '${sale.customer ?? 'Non member'} - ${sale.paymentMethod ?? '-'} - $paidAt',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (sale.returnedTotal > 0)
                    Text(
                      rupiah(sale.grandTotal),
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  Text(
                    rupiah(sale.netTotal),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  if (sale.returnedTotal > 0)
                    Text(
                      sale.returnStatus == 'full'
                          ? 'Retur full'
                          : 'Retur sebagian',
                      style: const TextStyle(
                        color: Color(0xFFD97706),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PaymentMethodField extends StatelessWidget {
  const PaymentMethodField({
    super.key,
    required this.value,
    required this.enabled,
    required this.onTap,
  });

  final PaymentMethod? value;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled ? onTap : null,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Metode bayar',
            prefixIcon: const Icon(Icons.payments_outlined),
            suffixIcon: Icon(
              Icons.keyboard_arrow_down,
              color: enabled
                  ? const Color(0xFF475569)
                  : const Color(0xFFCBD5E1),
            ),
            enabled: enabled,
          ),
          child: Text(
            value?.name ?? 'Pilih metode bayar',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: enabled
                  ? const Color(0xFF111827)
                  : const Color(0xFF94A3B8),
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}
