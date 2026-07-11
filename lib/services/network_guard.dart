import 'dart:async';

import '../app_config.dart';

class NetworkGuardState {
  const NetworkGuardState({
    required this.consecutiveFailures,
    required this.cooldownUntil,
    required this.lastError,
  });

  final int consecutiveFailures;
  final DateTime? cooldownUntil;
  final String? lastError;

  bool get isCoolingDown {
    final until = cooldownUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  Duration get remainingCooldown {
    final until = cooldownUntil;
    if (until == null) {
      return Duration.zero;
    }

    final remaining = until.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }
}

class NetworkGuard {
  NetworkGuard({
    this.failureThreshold = 2,
    this.cooldown = const Duration(
      seconds: AppConfig.networkFailureCooldownSeconds,
    ),
  });

  final int failureThreshold;
  final Duration cooldown;

  final _controller = StreamController<NetworkGuardState>.broadcast();
  var _consecutiveFailures = 0;
  DateTime? _cooldownUntil;
  String? _lastError;

  Stream<NetworkGuardState> get changes => _controller.stream;

  NetworkGuardState get state => NetworkGuardState(
    consecutiveFailures: _consecutiveFailures,
    cooldownUntil: _cooldownUntil,
    lastError: _lastError,
  );

  bool get isCoolingDown => state.isCoolingDown;

  void ensureRequestAllowed() {
    if (!isCoolingDown) {
      return;
    }

    final seconds = state.remainingCooldown.inSeconds.clamp(1, 999);
    throw NetworkCircuitOpenException(
      'Server sedang tidak stabil. Mode offline dipakai dulu, coba lagi $seconds detik.',
    );
  }

  void recordSuccess() {
    if (_consecutiveFailures == 0 &&
        _cooldownUntil == null &&
        _lastError == null) {
      return;
    }

    _consecutiveFailures = 0;
    _cooldownUntil = null;
    _lastError = null;
    _notify();
  }

  void recordFailure(String message) {
    _consecutiveFailures++;
    _lastError = message.trim().isEmpty ? 'Koneksi server gagal.' : message;

    if (_consecutiveFailures >= failureThreshold) {
      _cooldownUntil = DateTime.now().add(cooldown);
    }

    _notify();
  }

  void reset() {
    _consecutiveFailures = 0;
    _cooldownUntil = null;
    _lastError = null;
    _notify();
  }

  void dispose() {
    _controller.close();
  }

  void _notify() {
    if (!_controller.isClosed) {
      _controller.add(state);
    }
  }
}

class NetworkCircuitOpenException implements Exception {
  const NetworkCircuitOpenException(this.message);

  final String message;

  @override
  String toString() => message;
}
