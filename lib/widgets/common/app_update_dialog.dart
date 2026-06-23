import 'dart:io';

import 'package:flutter/material.dart';

import '../../app_config.dart';
import '../../models/app_update.dart';
import '../../services/app_update_service.dart';
import 'app_ui.dart';

class AppUpdateDialog extends StatefulWidget {
  const AppUpdateDialog({
    super.key,
    required this.update,
    required this.updateService,
  });

  final AppUpdateInfo update;
  final AppUpdateService updateService;

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  bool _downloading = false;
  double _progress = 0;
  String? _error;

  Future<void> _downloadAndInstall() async {
    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });

    try {
      final File apk = await widget.updateService.downloadApk(
        widget.update,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _progress = progress.clamp(0, 1));
          }
        },
      );
      await widget.updateService.installApk(apk);
      if (mounted && !widget.update.required) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final percent = (_progress * 100).round();

    return PopScope(
      canPop: !widget.update.required && !_downloading,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
        contentPadding: const EdgeInsets.fromLTRB(22, 14, 22, 10),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.system_update_alt,
                color: Color(0xFF4F46E5),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Update tersedia')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Versi ${widget.update.latestVersion} (${widget.update.latestBuild}) siap dipasang.',
              style: const TextStyle(
                color: Color(0xFF475569),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Versi sekarang ${AppConfig.appVersion} (${AppConfig.appBuild}).',
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
            if (widget.update.releaseNotes.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              AppSurface(
                padding: const EdgeInsets.all(12),
                child: Text(
                  widget.update.releaseNotes,
                  style: const TextStyle(
                    color: Color(0xFF334155),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            if (_downloading) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(value: _progress),
              ),
              const SizedBox(height: 8),
              Text(
                'Mengunduh APK $percent%',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              MessageBanner(message: _error!, isError: true),
            ],
          ],
        ),
        actions: [
          if (!widget.update.required)
            TextButton(
              onPressed: _downloading
                  ? null
                  : () => Navigator.of(context).pop(),
              child: const Text('Nanti'),
            ),
          FilledButton.icon(
            onPressed: _downloading ? null : _downloadAndInstall,
            icon: _downloading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download),
            label: Text(_downloading ? 'Mengunduh...' : 'Update'),
          ),
        ],
      ),
    );
  }
}
