import 'package:flutter/material.dart';

import '../../models/cashier_models.dart';
import '../../utils/formatters.dart';

class CartItemTile extends StatelessWidget {
  const CartItemTile({
    super.key,
    required this.item,
    required this.onEdit,
    required this.onRemove,
    required this.onDecrement,
    required this.onIncrement,
    required this.onNegotiate,
  });

  final CartItem item;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  final VoidCallback onDecrement;
  final VoidCallback? onIncrement;
  final VoidCallback onNegotiate;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        final veryCompact = constraints.maxWidth < 310;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onEdit,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _CartItemInfo(item: item)),
                        if (!compact) ...[
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 104,
                            child: Text(
                              rupiah(item.subtotal),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (compact) ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          rupiah(item.subtotal),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            IconButton.outlined(
                              tooltip: 'Hapus item',
                              onPressed: onRemove,
                              icon: const Icon(Icons.delete_outline),
                            ),
                            if (item.product.canNegotiate)
                              OutlinedButton.icon(
                                onPressed: onNegotiate,
                                icon: const Icon(Icons.sell_outlined, size: 18),
                                label: Text(veryCompact ? '' : 'Nego'),
                              ),
                          ],
                        ),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: veryCompact ? 4 : 8,
                          children: [
                            IconButton.outlined(
                              tooltip: 'Kurangi',
                              onPressed: onDecrement,
                              icon: const Icon(Icons.remove),
                            ),
                            SizedBox(
                              width: veryCompact ? 22 : 28,
                              child: Text(
                                '${item.quantity}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            IconButton.outlined(
                              tooltip: 'Tambah',
                              onPressed: onIncrement,
                              icon: const Icon(Icons.add),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CartItemInfo extends StatelessWidget {
  const _CartItemInfo({required this.item});

  final CartItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.product.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 3),
        if (item.product.isFashion && item.product.variantText.isNotEmpty) ...[
          Text(
            item.product.variantText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF4F46E5),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
        ],
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${item.quantity} x ${rupiah(item.product.price)}',
              style: TextStyle(
                color: item.hasNegotiation
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF64748B),
                fontWeight: FontWeight.w800,
                decoration: item.hasNegotiation
                    ? TextDecoration.lineThrough
                    : null,
              ),
            ),
            if (item.hasNegotiation)
              Text(
                rupiah(item.negotiatedUnitPrice),
                style: const TextStyle(
                  color: Color(0xFF047857),
                  fontWeight: FontWeight.w900,
                ),
              ),
            Text(
              'Stok ${item.product.stock}',
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        if (item.hasNegotiation) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'Nego -${rupiah(item.unitDiscount)}/pcs',
              style: const TextStyle(
                color: Color(0xFF047857),
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
