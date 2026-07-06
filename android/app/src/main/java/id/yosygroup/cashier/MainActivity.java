package id.yosygroup.cashier;

import android.Manifest;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.ColorMatrix;
import android.graphics.ColorMatrixColorFilter;
import android.graphics.Paint;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;

import androidx.annotation.NonNull;
import androidx.core.content.FileProvider;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.OutputStream;
import java.nio.charset.Charset;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

@SuppressWarnings("deprecation")
public class MainActivity extends FlutterActivity {
    private static final String CHANNEL_NAME = "yosy_group/thermal_printer";
    private static final String UPDATE_CHANNEL_NAME = "yosy_group/app_update";
    private static final int PERMISSION_REQUEST_CODE = 4812;

    private MethodChannel.Result pendingResult;
    private MethodCall pendingCall;

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL_NAME)
                .setMethodCallHandler((call, result) -> {
                    switch (call.method) {
                        case "listBondedPrinters":
                            withBluetoothPermission(call, result, () -> listBondedPrinters(result));
                            break;
                        case "printReceipt":
                            withBluetoothPermission(call, result, () -> printReceipt(call, result));
                            break;
                        case "openCashDrawer":
                            withBluetoothPermission(call, result, () -> openCashDrawer(call, result));
                            break;
                        default:
                            result.notImplemented();
                            break;
                    }
                });

        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), UPDATE_CHANNEL_NAME)
                .setMethodCallHandler((call, result) -> {
                    switch (call.method) {
                        case "apkCachePath":
                            apkCachePath(call, result);
                            break;
                        case "installApk":
                            installApk(call, result);
                            break;
                        default:
                            result.notImplemented();
                            break;
                    }
                });
    }

    private void withBluetoothPermission(
            MethodCall call,
            MethodChannel.Result result,
            Runnable action
    ) {
        List<String> missing = new ArrayList<>();
        for (String permission : requiredBluetoothPermissions()) {
            if (checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED) {
                missing.add(permission);
            }
        }

        if (missing.isEmpty()) {
            action.run();
            return;
        }

        pendingCall = call;
        pendingResult = result;
        requestPermissions(missing.toArray(new String[0]), PERMISSION_REQUEST_CODE);
    }

    @Override
    public void onRequestPermissionsResult(
            int requestCode,
            @NonNull String[] permissions,
            @NonNull int[] grantResults
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);

        if (requestCode != PERMISSION_REQUEST_CODE || pendingResult == null) {
            return;
        }

        MethodChannel.Result result = pendingResult;
        MethodCall call = pendingCall;
        pendingResult = null;
        pendingCall = null;

        for (int grantResult : grantResults) {
            if (grantResult != PackageManager.PERMISSION_GRANTED) {
                result.error(
                        "PERMISSION_DENIED",
                        "Izin Bluetooth diperlukan untuk mencetak struk.",
                        null
                );
                return;
            }
        }

        if (call == null) {
            result.notImplemented();
            return;
        }

        if ("listBondedPrinters".equals(call.method)) {
            listBondedPrinters(result);
        } else if ("printReceipt".equals(call.method)) {
            printReceipt(call, result);
        } else if ("openCashDrawer".equals(call.method)) {
            openCashDrawer(call, result);
        } else {
            result.notImplemented();
        }
    }

    /**
     * Returns the Bluetooth permissions required at runtime for the current API level.
     * Android 12+ (API 31+) requires BLUETOOTH_CONNECT and BLUETOOTH_SCAN.
     * Older versions rely on the legacy BLUETOOTH / BLUETOOTH_ADMIN permissions declared
     * in the manifest (no runtime grant needed).
     */
    private List<String> requiredBluetoothPermissions() {
        List<String> permissions = new ArrayList<>();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            permissions.add(Manifest.permission.BLUETOOTH_CONNECT);
            permissions.add(Manifest.permission.BLUETOOTH_SCAN);
        }
        return permissions;
    }

    private BluetoothAdapter bluetoothAdapter() {
        return BluetoothAdapter.getDefaultAdapter();
    }

    private void listBondedPrinters(MethodChannel.Result result) {
        BluetoothAdapter adapter = bluetoothAdapter();
        if (adapter == null) {
            result.error("NO_BLUETOOTH", "Perangkat ini tidak punya Bluetooth.", null);
            return;
        }

        if (!adapter.isEnabled()) {
            result.error("BLUETOOTH_OFF", "Bluetooth belum aktif.", null);
            return;
        }

        Set<BluetoothDevice> bondedDevices = adapter.getBondedDevices();
        List<BluetoothDevice> sortedDevices = new ArrayList<>(bondedDevices);
        sortedDevices.sort(Comparator.comparing(device -> {
            String name = device.getName();
            return name == null ? device.getAddress() : name;
        }));

        List<Map<String, String>> devices = new ArrayList<>();
        for (BluetoothDevice device : sortedDevices) {
            Map<String, String> item = new HashMap<>();
            item.put("name", device.getName() == null ? "Printer Bluetooth" : device.getName());
            item.put("address", device.getAddress());
            item.put("type", deviceTypeLabel(device));
            devices.add(item);
        }

        result.success(devices);
    }

    private void printReceipt(MethodCall call, MethodChannel.Result result) {
        String address = call.argument("address");
        String receiptText = call.argument("receiptText");
        Integer feedLines = call.argument("feedLines");
        byte[] logoBytes = call.argument("logoBytes");
        Integer logoMaxWidthDots = call.argument("logoMaxWidthDots");

        if (address == null || address.trim().isEmpty()) {
            result.error("NO_PRINTER", "Printer belum dipilih.", null);
            return;
        }

        BluetoothAdapter adapter = bluetoothAdapter();
        if (adapter == null) {
            result.error("NO_BLUETOOTH", "Perangkat ini tidak punya Bluetooth.", null);
            return;
        }

        if (!adapter.isEnabled()) {
            result.error("BLUETOOTH_OFF", "Bluetooth belum aktif.", null);
            return;
        }

        new Thread(() -> {
            try {
                BluetoothDevice device = adapter.getRemoteDevice(address);
                UUID uuid = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB");
                android.bluetooth.BluetoothSocket socket =
                        device.createRfcommSocketToServiceRecord(uuid);

                adapter.cancelDiscovery();
                socket.connect();

                OutputStream output = socket.getOutputStream();

                // ESC @ — initialize printer
                writeChunk(output, new byte[]{0x1B, 0x40});

                // Print logo jika ada
                if (logoBytes != null && logoBytes.length > 0) {
                    int logoWidth = logoMaxWidthDots == null
                            ? 240
                            : Math.max(120, Math.min(logoMaxWidthDots, 576));
                    byte[] logoEscPos = buildLogoBytes(logoBytes, logoWidth);
                    if (logoEscPos != null) {
                        writeChunk(output, logoEscPos);
                        // Feed 1 baris setelah logo
                        writeChunk(output, new byte[]{0x0A});
                        sleepQuietly(180);
                    }
                }

                // Teks struk
                Charset charset = Charset.forName("CP437");
                // ESC t 0 — select character code table (PC437)
                writeChunk(output, new byte[]{0x1B, 0x74, 0x00});
                // ESC M 0 — select printer Font A, the most compatible receipt font.
                writeChunk(output, new byte[]{0x1B, 0x4D, 0x00});
                byte[] receiptBytes = buildReceiptTextBytes(receiptText, charset);
                if (receiptBytes.length == 0) {
                    receiptBytes = "Struk kosong\n".getBytes(charset);
                }
                writeInChunks(output, receiptBytes, 192);

                // Feed lines
                int feed = (feedLines == null) ? 4 : feedLines;
                writeChunk(output, "\n".repeat(Math.max(1, Math.min(feed, 8))).getBytes(charset));

                // GS V B 0 — partial cut
                writeChunk(output, new byte[]{0x1D, 0x56, 0x42, 0x00});
                socket.close();

                mainThread(() -> result.success(true));
            } catch (Exception exception) {
                mainThread(() -> result.error(
                        "PRINT_FAILED",
                        exception.getMessage() == null
                                ? "Gagal mencetak ke printer Bluetooth."
                                : exception.getMessage(),
                        null
                ));
            }
        }).start();
    }

    private void openCashDrawer(MethodCall call, MethodChannel.Result result) {
        String address = call.argument("address");

        if (address == null || address.trim().isEmpty()) {
            result.error("NO_PRINTER", "Printer belum dipilih.", null);
            return;
        }

        BluetoothAdapter adapter = bluetoothAdapter();
        if (adapter == null) {
            result.error("NO_BLUETOOTH", "Perangkat ini tidak punya Bluetooth.", null);
            return;
        }

        if (!adapter.isEnabled()) {
            result.error("BLUETOOTH_OFF", "Bluetooth belum aktif.", null);
            return;
        }

        new Thread(() -> {
            android.bluetooth.BluetoothSocket socket = null;

            try {
                BluetoothDevice device = adapter.getRemoteDevice(address);
                UUID uuid = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB");
                socket = device.createRfcommSocketToServiceRecord(uuid);

                adapter.cancelDiscovery();
                socket.connect();

                OutputStream output = socket.getOutputStream();
                writeChunk(output, new byte[]{0x1B, 0x40});
                // ESC p m t1 t2 — cash drawer pulse. m=0 uses drawer pin 2.
                writeChunk(output, new byte[]{0x1B, 0x70, 0x00, 0x19, (byte) 0xFA});
                output.flush();
                sleepQuietly(160);

                mainThread(() -> result.success(true));
            } catch (Exception exception) {
                mainThread(() -> result.error(
                        "DRAWER_FAILED",
                        exception.getMessage() == null
                                ? "Gagal membuka laci kasir."
                                : exception.getMessage(),
                        null
                ));
            } finally {
                if (socket != null) {
                    try {
                        socket.close();
                    } catch (Exception ignored) {
                    }
                }
            }
        }).start();
    }

    private byte[] buildReceiptTextBytes(String receiptText, Charset charset) throws Exception {
        String normalized = (receiptText == null ? "" : receiptText).replace("\r\n", "\n");
        String[] lines = normalized.split("\n", -1);
        ByteArrayOutputStream buf = new ByteArrayOutputStream();
        int separatorCount = 0;
        boolean brandPrinted = false;
        boolean expectItemPriceLine = false;

        for (String line : lines) {
            boolean separator = line.matches("^-{6,}$");
            boolean itemName = separatorCount == 2
                    && !separator
                    && !line.trim().isEmpty()
                    && !line.trim().startsWith("TOTAL")
                    && !expectItemPriceLine;
            boolean totalLine = line.trim().startsWith("TOTAL");
            boolean brandLine = !brandPrinted && !line.trim().isEmpty() && separatorCount == 0;
            boolean bold = brandLine || itemName || totalLine;

            if (bold) {
                buf.write(new byte[]{0x1B, 0x45, 0x01});
            }

            buf.write(line.getBytes(charset));
            buf.write(0x0A);

            if (bold) {
                buf.write(new byte[]{0x1B, 0x45, 0x00});
            }

            if (brandLine) {
                brandPrinted = true;
            }

            if (separator) {
                separatorCount++;
                expectItemPriceLine = false;
            } else if (itemName) {
                expectItemPriceLine = true;
            } else if (expectItemPriceLine) {
                expectItemPriceLine = false;
            }
        }

        return buf.toByteArray();
    }

    private void writeChunk(OutputStream output, byte[] bytes) throws Exception {
        if (bytes == null || bytes.length == 0) {
            return;
        }

        output.write(bytes);
        output.flush();
        sleepQuietly(35);
    }

    private void writeInChunks(OutputStream output, byte[] bytes, int chunkSize) throws Exception {
        if (bytes == null || bytes.length == 0) {
            return;
        }

        int safeChunkSize = Math.max(64, chunkSize);
        for (int offset = 0; offset < bytes.length; offset += safeChunkSize) {
            int length = Math.min(safeChunkSize, bytes.length - offset);
            output.write(bytes, offset, length);
            output.flush();
            sleepQuietly(45);
        }
    }

    private void sleepQuietly(long millis) {
        try {
            Thread.sleep(millis);
        } catch (InterruptedException ignored) {
            Thread.currentThread().interrupt();
        }
    }

    /**
     * Konversi byte[] gambar (PNG/JPG) ke ESC/POS raster bitmap bytes.
     * Printer EPOS / generik 58mm pakai GS v 0 command.
     *
     * @param imageBytes   raw PNG/JPG bytes
     * @param maxWidthDots maksimum lebar dalam dots (384 untuk 58mm @203dpi)
     */
    private byte[] buildLogoBytes(byte[] imageBytes, int maxWidthDots) {
        try {
            // Decode gambar
            Bitmap original = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.length);
            if (original == null) return null;

            // Scale agar tidak melebihi lebar printer, jaga aspect ratio
            int origWidth  = original.getWidth();
            int origHeight = original.getHeight();
            int newWidth   = Math.min(origWidth, maxWidthDots);
            int newHeight  = (int) ((float) origHeight / origWidth * newWidth);

            // Width harus kelipatan 8 untuk ESC/POS
            newWidth = Math.max(8, (newWidth / 8) * 8);

            Bitmap scaled = Bitmap.createScaledBitmap(original, newWidth, newHeight, true);

            // Konversi ke grayscale lalu threshold ke hitam putih
            Bitmap bw = Bitmap.createBitmap(newWidth, newHeight, Bitmap.Config.ARGB_8888);
            Canvas canvas = new Canvas(bw);
            canvas.drawColor(Color.WHITE);
            Paint paint = new Paint();
            ColorMatrix cm = new ColorMatrix();
            cm.setSaturation(0);
            paint.setColorFilter(new ColorMatrixColorFilter(cm));
            canvas.drawBitmap(scaled, 0, 0, paint);

            // Generate ESC/POS GS v 0 raster bitmap
            // Format: GS v 0 m xL xH yL yH d1...dk
            int bytesPerRow = newWidth / 8;
            int rows = newHeight;

            ByteArrayOutputStream buf = new ByteArrayOutputStream();

            // Center alignment: ESC a 1
            buf.write(new byte[]{0x1B, 0x61, 0x01});

            // GS v 0 command
            buf.write(0x1D);
            buf.write(0x76);
            buf.write(0x30);
            buf.write(0x00);                          // m = 0 (normal)
            buf.write(bytesPerRow & 0xFF);             // xL
            buf.write((bytesPerRow >> 8) & 0xFF);      // xH
            buf.write(rows & 0xFF);                    // yL
            buf.write((rows >> 8) & 0xFF);             // yH

            // Pixel data — setiap bit = 1 pixel, 1 = hitam, 0 = putih
            for (int y = 0; y < rows; y++) {
                for (int byteCol = 0; byteCol < bytesPerRow; byteCol++) {
                    int bits = 0;
                    for (int bit = 0; bit < 8; bit++) {
                        int x = byteCol * 8 + bit;
                        int pixel = bw.getPixel(x, y);
                        // Ambil channel merah (grayscale) — jika gelap, set bit
                        int gray = (pixel >> 16) & 0xFF;
                        if (gray < 210) {
                            bits |= (0x80 >> bit);
                        }
                    }
                    buf.write(bits);
                }
            }

            // Kembali ke left alignment setelah logo
            buf.write(new byte[]{0x1B, 0x61, 0x00});

            return buf.toByteArray();
        } catch (Exception e) {
            return null;
        }
    }

    private String deviceTypeLabel(BluetoothDevice device) {
        if (device.getBluetoothClass() == null) {
            return "Bluetooth";
        }

        int majorClass = device.getBluetoothClass().getMajorDeviceClass();
        if (majorClass == 1536) {
            return "Imaging/Printer";
        }

        return "Bluetooth";
    }

    private void mainThread(Runnable action) {
        new Handler(Looper.getMainLooper()).post(action);
    }

    private void apkCachePath(MethodCall call, MethodChannel.Result result) {
        String fileName = call.argument("fileName");
        if (fileName == null || fileName.trim().isEmpty() || !fileName.endsWith(".apk")) {
            fileName = "yosy-cashier-update.apk";
        }

        File updatesDir = new File(getCacheDir(), "updates");
        if (!updatesDir.exists() && !updatesDir.mkdirs()) {
            result.error("CACHE_FAILED", "Folder cache update tidak bisa dibuat.", null);
            return;
        }

        result.success(new File(updatesDir, fileName).getAbsolutePath());
    }

    private void installApk(MethodCall call, MethodChannel.Result result) {
        String path = call.argument("path");
        if (path == null || path.trim().isEmpty()) {
            result.error("INVALID_APK", "File update tidak ditemukan.", null);
            return;
        }

        File apkFile = new File(path);
        if (!apkFile.exists()) {
            result.error("INVALID_APK", "File update tidak ditemukan.", null);
            return;
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !getPackageManager().canRequestPackageInstalls()) {
            Intent settingsIntent = new Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:" + getPackageName())
            );
            settingsIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(settingsIntent);
            result.error(
                    "INSTALL_PERMISSION_REQUIRED",
                    "Izinkan install aplikasi dari Yosy Kasir, lalu ulangi update.",
                    null
            );
            return;
        }

        Uri apkUri = FileProvider.getUriForFile(
                this,
                getPackageName() + ".fileprovider",
                apkFile
        );

        Intent installIntent = new Intent(Intent.ACTION_VIEW);
        installIntent.setDataAndType(apkUri, "application/vnd.android.package-archive");
        installIntent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        installIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        startActivity(installIntent);
        result.success(true);
    }
}
