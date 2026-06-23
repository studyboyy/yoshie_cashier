import 'package:flutter_cashier/services/thermal_receipt_printer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults to 58mm columns and no selected printer', () async {
    final printer = ThermalReceiptPrinter();

    final settings = await printer.settings();

    expect(settings.receiptColumns, 32);
    expect(settings.paperLabel, '58mm');
    expect(settings.autoPrint, isFalse);
    expect(settings.selectedPrinter, isNull);
  });

  test('stores selected printer and auto print setting', () async {
    final printer = ThermalReceiptPrinter();
    const device = ThermalPrinterDevice(
      name: 'EPOS Thermal',
      address: '00:11:22:33:44:55',
      type: 'Bluetooth',
    );

    await printer.saveSelectedPrinter(device);
    await printer.setAutoPrint(true);

    final settings = await printer.settings();

    expect(settings.selectedPrinter?.name, 'EPOS Thermal');
    expect(settings.selectedPrinter?.address, '00:11:22:33:44:55');
    expect(settings.autoPrint, isTrue);
  });

  test('normalizes receipt columns to supported paper sizes', () async {
    final printer = ThermalReceiptPrinter();

    await printer.setReceiptColumns(40);
    expect(await printer.receiptColumns(), 32);

    await printer.setReceiptColumns(42);
    final settings = await printer.settings();

    expect(settings.receiptColumns, 42);
    expect(settings.paperLabel, '80mm');
  });

  test('clearing selected printer disables auto print', () async {
    final printer = ThermalReceiptPrinter();

    await printer.saveSelectedPrinter(
      const ThermalPrinterDevice(
        name: 'EPOS Thermal',
        address: '00:11:22:33:44:55',
        type: 'Bluetooth',
      ),
    );
    await printer.setAutoPrint(true);
    await printer.clearSelectedPrinter();

    final settings = await printer.settings();

    expect(settings.selectedPrinter, isNull);
    expect(settings.autoPrint, isFalse);
  });
}
