class AppUpdateInfo {
  const AppUpdateInfo({
    required this.updateAvailable,
    required this.latestVersion,
    required this.latestBuild,
    required this.apkUrl,
    required this.releaseNotes,
    required this.required,
  });

  final bool updateAvailable;
  final String latestVersion;
  final int latestBuild;
  final String apkUrl;
  final String releaseNotes;
  final bool required;

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    return AppUpdateInfo(
      updateAvailable: json['update_available'] == true,
      latestVersion: json['latest_version']?.toString() ?? '',
      latestBuild: (json['latest_build'] as num?)?.toInt() ?? 0,
      apkUrl: json['apk_url']?.toString() ?? '',
      releaseNotes: json['release_notes']?.toString() ?? '',
      required: json['required'] == true,
    );
  }
}
