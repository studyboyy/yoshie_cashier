import 'package:flutter/material.dart';

import '../../models/cashier_models.dart';
import '../../services/api_client.dart';
import '../../utils/formatters.dart';
import '../common/app_ui.dart';

class ShiftSheet extends StatefulWidget {
  const ShiftSheet({
    super.key,
    required this.shift,
    required this.api,
    required this.onChanged,
    this.onUnauthorized,
  });

  final CashierShiftInfo? shift;
  final ApiClient api;
  final ValueChanged<CashierShiftInfo?> onChanged;
  final VoidCallback? onUnauthorized;

  @override
  State<ShiftSheet> createState() => _ShiftSheetState();
}

class _ShiftSheetState extends State<ShiftSheet> {
  late CashierShiftInfo? _shift = widget.shift;
  final _cashController = TextEditingController();
  final _notesController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cashController.text = (_shift?.expectedCash ?? 0).toStringAsFixed(0);
  }

  @override
  void dispose() {
    _cashController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final cash = double.tryParse(_cashController.text.trim());
    if (cash == null || cash < 0) {
      setState(() => _error = 'Nominal kas tidak valid.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_shift == null) {
        final opened = await widget.api.openShift(
          openingCash: cash,
          notes: _notesController.text,
        );
        widget.onChanged(opened);
        if (mounted) {
          setState(() => _shift = opened);
        }
      } else {
        await widget.api.closeShift(
          closingCash: cash,
          notes: _notesController.text,
        );
        widget.onChanged(null);
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } catch (error) {
      if (!mounted) return;
      if (error is UnauthorizedException) {
        Navigator.of(context).pop();
        widget.onUnauthorized?.call();
        return;
      }
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final shift = _shift;
    final title = shift == null ? 'Buka Shift Kasir' : 'Shift Aktif';

    return Padding(
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
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          if (shift != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  SummaryLine(label: 'Nomor shift', value: shift.shiftNumber),
                  const SizedBox(height: 6),
                  SummaryLine(
                    label: 'Modal awal',
                    value: rupiah(shift.openingCash),
                  ),
                  const SizedBox(height: 6),
                  SummaryLine(
                    label: 'Kas sistem',
                    value: rupiah(shift.expectedCash),
                    highlight: true,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _cashController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: shift == null ? 'Modal awal' : 'Kas fisik penutupan',
              prefixIcon: const Icon(Icons.payments_outlined),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _notesController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Catatan',
              hintText: 'Opsional',
              prefixIcon: Icon(Icons.notes_outlined),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            MessageBanner(message: _error!, isError: true),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _loading ? null : _submit,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    shift == null
                        ? Icons.lock_open_outlined
                        : Icons.lock_outline,
                  ),
            label: Text(shift == null ? 'Buka Shift' : 'Tutup Shift'),
          ),
        ],
      ),
    );
  }
}
