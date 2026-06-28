import 'package:flutter/material.dart';

import '../../app_config.dart';
import '../../models/user_profile.dart';
import '../../services/thermal_receipt_printer.dart';
import '../common/app_ui.dart';
import 'cashier_support_widgets.dart';

class CashierAccountPage extends StatelessWidget {
  const CashierAccountPage({
    super.key,
    required this.user,
    required this.receiptPrinter,
    required this.offlinePendingCount,
    required this.onSettingsChanged,
    required this.onSelectReceiptPrinter,
    required this.onTestReceiptPrinter,
    required this.onSyncOffline,
    required this.onOpenOfflineCenter,
    required this.onRefreshData,
    required this.onCheckServer,
    required this.onCheckUpdate,
    required this.pinLockEnabled,
    required this.onConfigurePinLock,
    required this.onLockApp,
    required this.onLogout,
  });

  final UserProfile user;
  final ThermalReceiptPrinter receiptPrinter;
  final int offlinePendingCount;
  final VoidCallback onSettingsChanged;
  final Future<ThermalPrinterDevice?> Function() onSelectReceiptPrinter;
  final Future<void> Function(ThermalPrinterDevice printer, int receiptColumns)
  onTestReceiptPrinter;
  final VoidCallback onSyncOffline;
  final VoidCallback onOpenOfflineCenter;
  final VoidCallback onRefreshData;
  final VoidCallback onCheckServer;
  final VoidCallback onCheckUpdate;
  final bool pinLockEnabled;
  final VoidCallback onConfigurePinLock;
  final VoidCallback onLockApp;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        AppSurface(
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.person_outline,
                  color: Color(0xFF4F46E5),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      user.email,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FutureBuilder<ThermalPrinterSettings>(
          future: receiptPrinter.settings(),
          builder: (context, snapshot) {
            final settings = snapshot.data;
            final printer = settings?.selectedPrinter;
            final receiptColumns = settings?.receiptColumns ?? 32;
            final autoPrint = settings?.autoPrint ?? false;

            return AppSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.print_outlined,
                          color: Color(0xFF4F46E5),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Printer Struk',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              printer == null
                                  ? 'Belum dipilih'
                                  : '${printer.name} - ${printer.address}',
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
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Pairing printer dari pengaturan Bluetooth HP, lalu pilih di sini. Setelah tersimpan, tombol cetak struk akan langsung memakai printer ini.',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('58mm'),
                          selected: receiptColumns == 32,
                          onSelected: (_) async {
                            await receiptPrinter.setReceiptColumns(32);
                            onSettingsChanged();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('80mm'),
                          selected: receiptColumns == 42,
                          onSelected: (_) async {
                            await receiptPrinter.setReceiptColumns(42);
                            onSettingsChanged();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Cetak otomatis setelah bayar',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(
                      printer == null
                          ? 'Pilih printer dulu untuk mengaktifkan auto-print.'
                          : autoPrint
                          ? 'Struk langsung dicetak setelah transaksi berhasil. Tombol cetak manual tetap tersedia.'
                          : 'Matikan jika ingin cetak struk manual dari dialog transaksi.',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    value: autoPrint,
                    onChanged: printer == null
                        ? null
                        : (value) async {
                            await receiptPrinter.setAutoPrint(value);
                            onSettingsChanged();
                          },
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () async {
                      final selected = await onSelectReceiptPrinter();
                      if (selected != null) {
                        await receiptPrinter.setAutoPrint(true);
                      }
                      onSettingsChanged();
                    },
                    icon: const Icon(Icons.bluetooth_searching),
                    label: Text(
                      printer == null ? 'Pilih Printer' : 'Ganti Printer',
                    ),
                  ),
                  if (printer != null) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () =>
                          onTestReceiptPrinter(printer, receiptColumns),
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('Tes Cetak'),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () async {
                        await receiptPrinter.clearSelectedPrinter();
                        onSettingsChanged();
                      },
                      icon: const Icon(Icons.link_off),
                      label: const Text('Hapus Printer'),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        AppSurface(
          child: Column(
            children: [
              ActionRow(
                icon: Icons.offline_bolt_outlined,
                label: 'Offline Center',
                value: '$offlinePendingCount pending',
                onTap: onOpenOfflineCenter,
              ),
              const Divider(height: 1),
              ActionRow(
                icon: Icons.sync,
                label: 'Sync cepat',
                value: 'Kirim',
                onTap: onSyncOffline,
              ),
              const Divider(height: 1),
              ActionRow(
                icon: Icons.refresh,
                label: 'Refresh data',
                value: 'Update',
                onTap: onRefreshData,
              ),
              const Divider(height: 1),
              ActionRow(
                icon: Icons.health_and_safety_outlined,
                label: 'Cek koneksi server',
                value: 'Tes',
                onTap: onCheckServer,
              ),
              const Divider(height: 1),
              ActionRow(
                icon: Icons.system_update_alt,
                label: 'Cek update APK',
                value: 'Versi',
                onTap: onCheckUpdate,
              ),
              const Divider(height: 1),
              ActionRow(
                icon: Icons.lock_outline,
                label: pinLockEnabled
                    ? 'Ubah PIN aplikasi'
                    : 'Atur PIN aplikasi',
                value: pinLockEnabled ? 'Aktif' : 'Nonaktif',
                onTap: onConfigurePinLock,
              ),
              if (pinLockEnabled) ...[
                const Divider(height: 1),
                ActionRow(
                  icon: Icons.lock_person_outlined,
                  label: 'Kunci aplikasi',
                  value: 'Lock',
                  onTap: onLockApp,
                ),
              ],
              const Divider(height: 1),
              ActionRow(
                icon: Icons.logout,
                label: 'Keluar',
                value: 'Logout',
                onTap: onLogout,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Yosy Kasir v${AppConfig.appVersion} (${AppConfig.appBuild})',
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
