/// App-wide configuration.
///
/// Base URL is resolved from the `APP_BASE_URL` compile-time environment
/// variable so you can target different environments without changing code:
///
///   flutter run  --dart-define=APP_BASE_URL=http://192.168.1.10/api
///   flutter build apk --dart-define=APP_BASE_URL=https://yosygroup.id/api
///
/// If the variable is not supplied the production URL is used as the default.
class AppConfig {
  const AppConfig._();

  static const baseUrl = String.fromEnvironment(
    'APP_BASE_URL',
    defaultValue: 'https://yosygroup.id/api',
  );

  /// Maximum number of offline sale drafts kept in local storage.
  /// Older drafts beyond this limit are dropped to prevent unbounded growth.
  static const offlineQueueMaxSize = 200;

  /// HTTP request timeout in seconds.
  static const httpTimeoutSeconds = 20;

  /// App version shown in the About / Account page.
  static const appVersion = '1.1.23';
  static const appBuild = 25;
}
