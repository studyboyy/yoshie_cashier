import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/cash_movement.dart';
import '../../services/api_client.dart';
import '../../utils/formatters.dart';
import '../common/app_ui.dart';

class CashMovementPage extends StatefulWidget {
  const CashMovementPage({
    super.key,
    required this.api,
    required this.hasActiveShift,
  });

  final ApiClient api;
  final bool hasActiveShift;

  @override
  State<CashMovementPage> createState() => _CashMovementPageState();
}

class _CashMovementPageState extends State<CashMovementPage> {
  late Future<List<CashMovementModel>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = widget.api.cashMovements();
    });
  }

  Future<void> _openForm(String type) async {
    if (!widget.hasActiveShift) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Buka shift kasir dulu sebelum mencatat kas.'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    final result = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _CashMovementForm(api: widget.api, type: type),
    );

    if (result == true) {
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Tombol Cash In / Out
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _openForm('in'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF047857),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Cash In'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _openForm('out'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                ),
                icon: const Icon(Icons.remove),
                label: const Text('Cash Out'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Daftar movement hari ini
        FutureBuilder<List<CashMovementModel>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              );
            }

            if (snapshot.hasError) {
              return MessageBanner(
                message: snapshot.error.toString(),
                isError: true,
              );
            }

            final movements = snapshot.data ?? [];

            if (movements.isEmpty) {
              return const AppSurface(
                child: EmptyState(text: 'Belum ada catatan kas hari ini.'),
              );
            }

            // Hitung ringkasan
            final totalIn = movements
                .where((m) => m.isCashIn)
                .fold(0.0, (sum, m) => sum + m.amount);
            final totalOut = movements
                .where((m) => !m.isCashIn)
                .fold(0.0, (sum, m) => sum + m.amount);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Ringkasan
                AppSurface(
                  child: Row(
                    children: [
                      Expanded(
                        child: _SummaryChip(
                          label: 'Total Cash In',
                          value: rupiah(totalIn),
                          color: const Color(0xFF047857),
                          bgColor: const Color(0xFFECFDF5),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SummaryChip(
                          label: 'Total Cash Out',
                          value: rupiah(totalOut),
                          color: const Color(0xFFDC2626),
                          bgColor: const Color(0xFFFEF2F2),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text(
                      'Riwayat Hari Ini',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Refresh',
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ...movements.map(
                  (m) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _CashMovementTile(movement: m),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ─── Form Input ───────────────────────────────────────────────────────────────

class _CashMovementForm extends StatefulWidget {
  const _CashMovementForm({required this.api, required this.type});

  final ApiClient api;
  final String type;

  @override
  State<_CashMovementForm> createState() => _CashMovementFormState();
}

class _CashMovementFormState extends State<_CashMovementForm> {
  final _amountController = TextEditingController();
  final _categoryController = TextEditingController();
  final _notesController = TextEditingController();
  bool _loading = false;
  String? _error;

  bool get _isCashIn => widget.type == 'in';

  @override
  void dispose() {
    _amountController.dispose();
    _categoryController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Nominal harus lebih dari 0.');
      return;
    }
    if (_notesController.text.trim().isEmpty) {
      setState(() => _error = 'Keterangan wajib diisi.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await widget.api.createCashMovement(
        type: widget.type,
        amount: amount,
        notes: _notesController.text.trim(),
        category: _categoryController.text.trim().isEmpty
            ? null
            : _categoryController.text.trim(),
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final color = _isCashIn ? const Color(0xFF047857) : const Color(0xFFDC2626);

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 18 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _isCashIn
                      ? const Color(0xFFECFDF5)
                      : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _isCashIn
                      ? Icons.add_circle_outline
                      : Icons.remove_circle_outline,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _isCashIn ? 'Cash In' : 'Cash Out',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amountController,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            decoration: const InputDecoration(
              labelText: 'Nominal',
              prefixText: 'Rp ',
              prefixStyle: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _categoryController,
            textInputAction: TextInputAction.next,
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            decoration: const InputDecoration(
              labelText: 'Kategori',
              hintText: 'Opsional, contoh: Belanja, Modal',
              prefixIcon: Icon(Icons.category_outlined),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _notesController,
            textInputAction: TextInputAction.done,
            maxLines: 2,
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            decoration: const InputDecoration(
              labelText: 'Keterangan',
              hintText: 'Wajib diisi',
              prefixIcon: Icon(Icons.notes_outlined),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            MessageBanner(message: _error!, isError: true),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _loading ? null : _submit,
            style: FilledButton.styleFrom(backgroundColor: color),
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(_isCashIn ? Icons.add : Icons.remove),
            label: Text(
              _loading
                  ? 'Menyimpan...'
                  : (_isCashIn ? 'Simpan Cash In' : 'Simpan Cash Out'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tile ─────────────────────────────────────────────────────────────────────

class _CashMovementTile extends StatelessWidget {
  const _CashMovementTile({required this.movement});

  final CashMovementModel movement;

  @override
  Widget build(BuildContext context) {
    final isCashIn = movement.isCashIn;
    final color = isCashIn ? const Color(0xFF047857) : const Color(0xFFDC2626);
    final bgColor = isCashIn
        ? const Color(0xFFECFDF5)
        : const Color(0xFFFEF2F2);

    // Format time
    final local = movement.occurredAt;
    final timeStr = local == null
        ? '-'
        : '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              isCashIn ? Icons.add_circle_outline : Icons.remove_circle_outline,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  movement.notes,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (movement.category != null &&
                        movement.category!.isNotEmpty)
                      movement.category!,
                    timeStr,
                    if (movement.shiftNumber != null) movement.shiftNumber!,
                  ].join(' · '),
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
          Text(
            '${isCashIn ? '+' : '-'} ${rupiah(movement.amount)}',
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

// ─── Summary Chip ─────────────────────────────────────────────────────────────

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.value,
    required this.color,
    required this.bgColor,
  });

  final String label;
  final String value;
  final Color color;
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
