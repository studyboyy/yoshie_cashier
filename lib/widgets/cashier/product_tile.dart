import 'package:flutter/material.dart';

import '../../models/cashier_models.dart';
import '../../utils/formatters.dart';

class ProductTile extends StatelessWidget {
  const ProductTile({super.key, required this.product, required this.onTap});

  final CashierProduct product;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isOutOfStock = product.stock <= 0;
    final compact = MediaQuery.sizeOf(context).width < 390;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isOutOfStock
                      ? const Color(0xFFF1F5F9)
                      : const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  isOutOfStock
                      ? Icons.inventory_2_outlined
                      : Icons.add_shopping_cart,
                  color: isOutOfStock
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF4F46E5),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    if (product.isFashion &&
                        product.variantText.isNotEmpty) ...[
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: [
                          _InfoBadge(
                            label: 'Fashion',
                            background: const Color(0xFFEDE9FE),
                            foreground: const Color(0xFF5B21B6),
                          ),
                          _InfoBadge(
                            label: product.variantText,
                            background: const Color(0xFFEFF6FF),
                            foreground: const Color(0xFF1D4ED8),
                          ),
                          if (product.canNegotiate)
                            _InfoBadge(
                              label: 'Nego',
                              background: const Color(0xFFDCFCE7),
                              foreground: const Color(0xFF047857),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      '${product.sku} - Stok ${product.stock} ${product.unit}',
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
              SizedBox(width: compact ? 6 : 10),
              ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: compact ? 86 : 104,
                  maxWidth: compact ? 96 : 124,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      rupiah(product.price),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF111827),
                      ),
                    ),
                    if (isOutOfStock) ...[
                      const SizedBox(height: 3),
                      const Text(
                        'Habis',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(0xFFDC2626),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  const _InfoBadge({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
