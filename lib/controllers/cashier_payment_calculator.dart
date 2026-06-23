import '../models/cashier_models.dart';

class CashierPaymentCalculator {
  const CashierPaymentCalculator({this.pointValue = 100});

  final int pointValue;

  int redeemPointsFromText(String text) {
    return int.tryParse(text.trim()) ?? 0;
  }

  int maxRedeemPoints({
    required CashierCustomer? customer,
    required double total,
  }) {
    if (customer == null) {
      return 0;
    }

    final totalPointCapacity = (total / pointValue).floor();
    return customer.points < totalPointCapacity
        ? customer.points
        : totalPointCapacity;
  }

  int normalizedRedeemPoints({
    required String text,
    required CashierCustomer? customer,
    required double total,
  }) {
    final points = redeemPointsFromText(text);
    final maxPoints = maxRedeemPoints(customer: customer, total: total);
    return points.clamp(0, maxPoints);
  }

  double pointDiscount({
    required int redeemPoints,
    required int maxRedeemPoints,
  }) {
    return (redeemPoints.clamp(0, maxRedeemPoints) * pointValue).toDouble();
  }

  double payableTotal({required double total, required double pointDiscount}) {
    return (total - pointDiscount).clamp(0, double.infinity);
  }

  double paidAmountFromText(String text) {
    return double.tryParse(text.trim()) ?? 0;
  }

  double changeAmount({
    required double paidAmount,
    required double payableTotal,
  }) {
    return (paidAmount - payableTotal).clamp(0, double.infinity);
  }

  List<double> quickPaidAmounts(double payableTotal) {
    if (payableTotal <= 0) {
      return [];
    }

    final suggestions = <double>{payableTotal};
    const steps = [10000, 20000, 50000, 100000, 200000, 500000];

    for (final step in steps) {
      final rounded = ((payableTotal / step).ceil() * step).toDouble();
      if (rounded >= payableTotal) {
        suggestions.add(rounded);
      }
      if (suggestions.length >= 4) {
        break;
      }
    }

    return suggestions.take(4).toList();
  }
}
