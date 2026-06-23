import 'package:flutter/material.dart';

import '../../models/cashier_models.dart';
import '../../utils/formatters.dart';
import '../common/app_ui.dart';

class CashierShiftPage extends StatelessWidget {
  const CashierShiftPage({
    super.key,
    required this.shift,
    required this.loadingShift,
    required this.onShowShiftSheet,
  });

  final CashierShiftInfo? shift;
  final bool loadingShift;
  final VoidCallback onShowShiftSheet;

  @override
  Widget build(BuildContext context) {
    final shift = this.shift;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        AppSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    shift == null
                        ? Icons.lock_clock_outlined
                        : Icons.lock_open_outlined,
                    color: shift == null
                        ? const Color(0xFFB45309)
                        : const Color(0xFF047857),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      shift == null ? 'Shift belum dibuka' : shift.shiftNumber,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (shift == null)
                const Text(
                  'Buka shift sebelum mulai operasional supaya laporan kas harian lebih rapi.',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                  ),
                )
              else ...[
                SummaryLine(
                  label: 'Modal awal',
                  value: rupiah(shift.openingCash),
                ),
                const SizedBox(height: 8),
                SummaryLine(
                  label: 'Kas sistem',
                  value: rupiah(shift.expectedCash),
                  highlight: true,
                ),
              ],
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: loadingShift ? null : onShowShiftSheet,
                icon: Icon(
                  shift == null ? Icons.lock_open_outlined : Icons.lock_outline,
                ),
                label: Text(shift == null ? 'Buka Shift' : 'Tutup Shift'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
