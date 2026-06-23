import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class QtyResult {
  const QtyResult({this.qty = 0, this.delete = false});

  final int qty;
  final bool delete;
}

class QtyEditSheet extends StatefulWidget {
  const QtyEditSheet({
    super.key,
    required this.productName,
    required this.unit,
    required this.maxStock,
    required this.initialQty,
  });

  final String productName;
  final String unit;
  final int maxStock;
  final int initialQty;

  @override
  State<QtyEditSheet> createState() => _QtyEditSheetState();
}

class _QtyEditSheetState extends State<QtyEditSheet> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialQty.toString());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() {
    final v = int.tryParse(_ctrl.text.trim());
    if (v != null && v > 0) {
      Navigator.of(context).pop(QtyResult(qty: v));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Baca viewInsets di dalam build widget ini agar aman dari perubahan keyboard.
    // context di sini adalah context dari State ini, bukan builder closure.
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 18 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.productName,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            'Stok tersedia ${widget.maxStock} ${widget.unit}',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(5),
            ],
            decoration: InputDecoration(
              labelText: 'Jumlah',
              hintText: '1 - ${widget.maxStock}',
              prefixIcon: const Icon(Icons.production_quantity_limits_outlined),
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pop(const QtyResult(delete: true)),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Hapus'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check),
                  label: const Text('Simpan'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
