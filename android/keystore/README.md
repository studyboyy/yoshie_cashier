# Keystore Setup — Yosy Kasir Release Build

Folder ini untuk menyimpan keystore release APK. **Jangan commit file .jks ke git.**

## Cara Buat Keystore Baru

Jalankan perintah berikut (butuh Java/keytool, sudah include di Android Studio):

```bash
keytool -genkey -v \
  -keystore android/keystore/yosy-release.jks \
  -alias yosy-release \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000
```

Simpan password yang dimasukkan — tidak bisa di-recover.

## Environment Variables untuk CI/CD

Set variabel berikut sebelum `flutter build apk --release`:

```
KEYSTORE_PASSWORD=<password_keystore>
KEY_ALIAS=yosy-release
KEY_PASSWORD=<password_key>
```

## Build Release APK

```bash
flutter build apk --release --dart-define=APP_BASE_URL=https://yosygroup.id/api
```

APK output: `build/app/outputs/flutter-apk/app-release.apk`

## Catatan Penting

- File `.jks` TIDAK boleh di-push ke git (sudah di `.gitignore`)
- Simpan backup keystore di tempat aman — kehilangan keystore = tidak bisa update app di Play Store
- Keystore ini dipakai seumur hidup app, jangan sampai hilang
