import 'package:flutter_cashier/controllers/cashier_payment_calculator.dart';
import 'package:flutter_cashier/models/cashier_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const calculator = CashierPaymentCalculator();
  const customer = CashierCustomer(
    id: 1,
    name: 'Member',
    memberCode: 'MBR-001',
    points: 120,
  );

  test('limits redeem points by customer points and payable capacity', () {
    expect(calculator.maxRedeemPoints(customer: customer, total: 15000), 120);
    expect(calculator.maxRedeemPoints(customer: customer, total: 5000), 50);
    expect(calculator.maxRedeemPoints(customer: null, total: 5000), 0);
  });

  test('normalizes invalid and excessive redeem input', () {
    expect(
      calculator.normalizedRedeemPoints(
        text: '999',
        customer: customer,
        total: 5000,
      ),
      50,
    );
    expect(
      calculator.normalizedRedeemPoints(
        text: '-5',
        customer: customer,
        total: 5000,
      ),
      0,
    );
    expect(
      calculator.normalizedRedeemPoints(
        text: 'abc',
        customer: customer,
        total: 5000,
      ),
      0,
    );
  });

  test('calculates discount, payable total, change, and quick amounts', () {
    final discount = calculator.pointDiscount(
      redeemPoints: 30,
      maxRedeemPoints: 50,
    );
    final payable = calculator.payableTotal(
      total: 15000,
      pointDiscount: discount,
    );

    expect(discount, 3000);
    expect(payable, 12000);
    expect(
      calculator.changeAmount(paidAmount: 20000, payableTotal: payable),
      8000,
    );
    expect(calculator.quickPaidAmounts(payable), [12000, 20000, 50000, 100000]);
  });
}
