import 'package:flutter/material.dart';

import '../../models/cashier_models.dart';
import '../../utils/formatters.dart';
import 'cashier_support_widgets.dart';

class ReceiptDialog extends StatelessWidget {
  const ReceiptDialog({
    super.key,
    required this.result,
    required this.onPrint,
    required this.onCopy,
  });

  final CheckoutResult result;
  final ValueChanged<String> onPrint;
  final ValueChanged<String> onCopy;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final maxWidth = size.width < 480 ? size.width - 24 : 430.0;
    final maxHeight = size.height < 760 ? size.height - 24 : 720.0;

    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth.clamp(300.0, 430.0).toDouble(),
          maxHeight: maxHeight.clamp(360.0, 720.0).toDouble(),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ReceiptHeader(result: result),
              const SizedBox(height: 14),
              _ReceiptMetrics(result: result),
              const SizedBox(height: 14),
              Flexible(
                child: ReceiptPaperPreview(
                  receiptText: result.receiptText,
                  compact: true,
                ),
              ),
              const SizedBox(height: 14),
              _ReceiptActions(
                result: result,
                onPrint: onPrint,
                onCopy: onCopy,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReceiptHeader extends StatelessWidget {
  const _ReceiptHeader({required this.result});

  final CheckoutResult result;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFFECFDF5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.check_circle, color: Color(0xFF047857)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Transaksi Berhasil',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 2),
              Text(
                result.invoiceNumber,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Tutup',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }
}

class _ReceiptMetrics extends StatelessWidget {
  const _ReceiptMetrics({required this.result});

  final CheckoutResult result;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          ReceiptMetric(label: 'Total', value: rupiah(result.grandTotal)),
          const SizedBox(width: 12),
          ReceiptMetric(label: 'Bayar', value: rupiah(result.paidAmount)),
          const SizedBox(width: 12),
          ReceiptMetric(label: 'Kembali', value: rupiah(result.changeAmount)),
        ],
      ),
    );
  }
}

class _ReceiptActions extends StatelessWidget {
  const _ReceiptActions({
    required this.result,
    required this.onPrint,
    required this.onCopy,
  });

  final CheckoutResult result;
  final ValueChanged<String> onPrint;
  final ValueChanged<String> onCopy;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 340;
        final halfWidth = (constraints.maxWidth - 10) / 2;

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: isNarrow ? constraints.maxWidth : halfWidth,
              child: FilledButton.icon(
                onPressed: () => onPrint(result.receiptText),
                icon: const Icon(Icons.print_outlined),
                label: const Text('Cetak'),
              ),
            ),
            SizedBox(
              width: isNarrow ? constraints.maxWidth : halfWidth,
              child: OutlinedButton.icon(
                onPressed: () => onCopy(result.receiptText),
                icon: const Icon(Icons.copy),
                label: const Text('Salin'),
              ),
            ),
            SizedBox(
              width: isNarrow ? constraints.maxWidth : halfWidth,
              child: OutlinedButton.icon(
                onPressed: () => _showPrintPreview(context, result),
                icon: const Icon(Icons.image_outlined),
                label: const Text('Preview Cetak'),
              ),
            ),
            SizedBox(
              width: isNarrow ? constraints.maxWidth : halfWidth,
              child: OutlinedButton.icon(
                onPressed: () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.point_of_sale),
                label: const Text('Baru'),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showPrintPreview(BuildContext context, CheckoutResult result) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Preview Struk Cetak',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Tutup',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Container(
                  width: double.infinity,
                  color: const Color(0xFFF1F5F9),
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(18),
                      child: ReceiptPaperPreview(
                        receiptText: result.receiptText,
                        compact: false,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReceiptPaperPreview extends StatelessWidget {
  const ReceiptPaperPreview({
    super.key,
    required this.receiptText,
    required this.compact,
  });

  final String receiptText;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final lines = receiptText.split('\n');
    final columns = lines.fold<int>(
      32,
      (max, line) => line.length > max ? line.length : max,
    );
    final fontSize = compact ? 11.5 : 13.0;
    final horizontalPadding = compact ? 14.0 : 18.0;
    final previewWidth = (columns * fontSize * 0.62 + horizontalPadding * 2)
        .clamp(250.0, compact ? 330.0 : 390.0)
        .toDouble();

    return Container(
      width: compact ? double.infinity : previewWidth,
      alignment: Alignment.topCenter,
      padding: EdgeInsets.all(compact ? 10 : 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Container(
        width: previewWidth,
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          compact ? 14 : 18,
          horizontalPadding,
          compact ? 14 : 18,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A0F172A),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Image.asset(
                'assets/images/brand.png',
                height: compact ? 48 : 64,
                fit: BoxFit.contain,
              ),
              SizedBox(height: compact ? 8 : 10),
              ..._styledLines(lines, fontSize),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _styledLines(List<String> lines, double fontSize) {
    var separatorCount = 0;
    var brandPrinted = false;
    var expectPriceLine = false;

    return lines.map((line) {
      final trimmed = line.trim();
      final separator = RegExp(r'^-{6,}$').hasMatch(trimmed);
      final brand = !brandPrinted && trimmed.isNotEmpty && separatorCount == 0;
      final itemName = separatorCount == 2 &&
          !separator &&
          trimmed.isNotEmpty &&
          !trimmed.startsWith('TOTAL') &&
          !expectPriceLine;
      final total = trimmed.startsWith('TOTAL');
      final bold = brand || itemName || total;

      final widget = Text(
        line.isEmpty ? ' ' : line,
        softWrap: false,
        overflow: TextOverflow.visible,
        style: TextStyle(
          color: const Color(0xFF111827),
          fontFamily: 'monospace',
          fontSize: fontSize,
          height: 1.28,
          fontWeight: bold ? FontWeight.w900 : FontWeight.w500,
        ),
      );

      if (brand) {
        brandPrinted = true;
      }

      if (separator) {
        separatorCount++;
        expectPriceLine = false;
      } else if (itemName) {
        expectPriceLine = true;
      } else if (expectPriceLine) {
        expectPriceLine = false;
      }

      return widget;
    }).toList();
  }
}
