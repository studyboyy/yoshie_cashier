class CashMovementModel {
  const CashMovementModel({
    required this.id,
    required this.type,
    required this.amount,
    required this.notes,
    this.category,
    this.occurredAt,
    this.shiftNumber,
  });

  final int id;

  /// 'in' atau 'out'
  final String type;
  final double amount;
  final String notes;
  final String? category;
  final DateTime? occurredAt;
  final String? shiftNumber;

  bool get isCashIn => type == 'in';

  factory CashMovementModel.fromJson(Map<String, dynamic> json) {
    return CashMovementModel(
      id: _asInt(json['id']),
      type: json['type'] as String? ?? 'in',
      amount: _asDouble(json['amount']),
      notes: json['notes'] as String? ?? '',
      category: json['category'] as String?,
      occurredAt: DateTime.tryParse(
        json['occurred_at'] as String? ?? '',
      )?.toLocal(),
      shiftNumber: json['shift_number'] as String?,
    );
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}
