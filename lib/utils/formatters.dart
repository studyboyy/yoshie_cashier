/// Formats [value] as Indonesian Rupiah, e.g. `Rp 1.250.000`.
/// Handles negative values correctly: `Rp -5.000`.
String rupiah(num value) {
  final isNegative = value < 0;
  final abs = value.abs().round().toString();
  final formatted = abs.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );

  return isNegative ? 'Rp -$formatted' : 'Rp $formatted';
}

/// Formats a [DateTime] as `dd/MM/yyyy HH:mm` in local time.
String receiptDateTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/'
      '${local.year} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

/// Centers [text] within [width] characters for thermal receipt printing.
String centerReceiptText(String text, int width) {
  if (text.length >= width) {
    return text.substring(0, width);
  }

  final left = ((width - text.length) / 2).floor();
  return '${' ' * left}$text';
}
