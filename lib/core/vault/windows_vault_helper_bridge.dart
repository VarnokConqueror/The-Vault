import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'vault_bridge_base.dart';
import 'vault_models.dart';

class WindowsVaultHelperBridge implements VaultBridge {
  const WindowsVaultHelperBridge();

  static final _helperClient = _WindowsVaultHelperClient();

  static bool get isConfiguredSync => _helperClient.isConfiguredSync;
  static Future<void> restartHelper() => _helperClient.restart();

  @override
  Future<VaultDeviceIdentity> getOrCreateIdentity({
    required String userId,
    required int deviceId,
  }) async {
    final map = await _invokeMap('getOrCreateIdentity', <String, dynamic>{
      'userId': userId,
      'deviceId': deviceId,
    });
    return VaultDeviceIdentity.fromJson(map);
  }

  @override
  Future<VaultPreKeyUpload> generatePreKeyUpload({
    required String userId,
    required int deviceId,
    required int oneTimePreKeyCount,
  }) async {
    final map = await _invokeMap('generatePreKeyUpload', <String, dynamic>{
      'userId': userId,
      'deviceId': deviceId,
      'oneTimePreKeyCount': oneTimePreKeyCount,
    });
    return VaultPreKeyUpload.fromJson(map);
  }

  @override
  Future<void> processPreKeyBundle({
    required VaultAddress localAddress,
    required VaultPreKeyBundle bundle,
  }) {
    return _invokeVoid('processPreKeyBundle', <String, dynamic>{
      'localAddress': localAddress.toJson(),
      'bundle': bundle.toJson(),
    });
  }

  @override
  Future<VaultCiphertext> encrypt({
    required VaultAddress localAddress,
    required VaultAddress destination,
    required List<int> plaintext,
  }) async {
    final map = await _invokeMap('encrypt', <String, dynamic>{
      'localAddress': localAddress.toJson(),
      'destination': destination.toJson(),
      'plaintext': plaintext,
    });
    return VaultCiphertext.fromJson(map);
  }

  @override
  Future<List<int>> decrypt({
    required VaultAddress localAddress,
    required VaultInboundEnvelope envelope,
  }) async {
    final raw = await _helperClient.invoke('decrypt', <String, dynamic>{
      'localAddress': localAddress.toJson(),
      'envelope': envelope.toJson(),
    });
    if (raw is! List) {
      throw PlatformException(
        code: 'vault_null_plaintext',
        message: 'Windows Vault helper returned no plaintext bytes',
      );
    }
    return raw.map((value) => _parseInt(value, 'decrypt result')).toList();
  }

  @override
  Future<void> archiveSession({
    required VaultAddress localAddress,
    required VaultAddress remoteAddress,
  }) {
    return _invokeVoid('archiveSession', <String, dynamic>{
      'localAddress': localAddress.toJson(),
      'remoteAddress': remoteAddress.toJson(),
    });
  }

  @override
  Future<VaultFingerprint> generateFingerprint({
    required VaultAddress localAddress,
    required VaultDeviceIdentity remoteIdentity,
  }) async {
    final map = await _invokeMap('generateFingerprint', <String, dynamic>{
      'localAddress': localAddress.toJson(),
      'remoteIdentity': remoteIdentity.toJson(),
    });
    return VaultFingerprint.fromJson(map);
  }

  @override
  Future<void> reset() => _helperClient.restart();

  Future<void> _invokeVoid(
    String method,
    Map<String, dynamic> arguments,
  ) async {
    await _helperClient.invoke(method, arguments);
  }

  Future<Map<String, dynamic>> _invokeMap(
    String method,
    Map<String, dynamic> arguments,
  ) async {
    final raw = await _helperClient.invoke(method, arguments);
    if (raw is! Map) {
      throw PlatformException(
        code: 'vault_null_result',
        message: 'Windows Vault helper method $method returned no payload',
      );
    }
    return Map<String, dynamic>.from(raw);
  }

  int _parseInt(Object? value, String field) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
    throw PlatformException(
      code: 'vault_invalid_argument',
      message: 'Windows Vault helper returned invalid $field value',
    );
  }
}

class _WindowsVaultHelperClient {
  Process? _process;
  Future<void>? _starting;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  final Map<String, Completer<dynamic>> _pending =
      <String, Completer<dynamic>>{};
  int _nextRequestId = 0;

  bool get isConfiguredSync =>
      _resolveJavaExecutable() != null && _resolveHelperJar() != null;

  Future<void> restart() async {
    final pending = Map<String, Completer<dynamic>>.from(_pending);
    _pending.clear();
    final error = PlatformException(
      code: 'vault_bridge_error',
      message: 'Windows Vault helper restarted',
    );
    for (final completer in pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }

    final process = _process;
    _process = null;
    await _stdoutSubscription?.cancel();
    _stdoutSubscription = null;
    await _stderrSubscription?.cancel();
    _stderrSubscription = null;
    if (process != null) {
      try {
        process.kill();
      } catch (_) {}
    }
  }

  Future<dynamic> invoke(String method, Map<String, dynamic> arguments) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      await _ensureStarted(method);
      final process = _process;
      if (process == null) {
        throw _unimplemented(
          method,
          'Windows Vault helper process did not start',
        );
      }

      final requestId = (++_nextRequestId).toString();
      final completer = Completer<dynamic>();
      _pending[requestId] = completer;

      try {
        process.stdin.writeln(
          jsonEncode(<String, dynamic>{
            'id': requestId,
            'method': method,
            'args': arguments,
          }),
        );
      } catch (error) {
        _pending.remove(requestId);
        final bridgeError = PlatformException(
          code: 'vault_bridge_error',
          message: 'Could not send $method to the Windows Vault helper',
          details: error.toString(),
        );
        await restart();
        if (attempt == 0) {
          continue;
        }
        throw bridgeError;
      }

      try {
        return await completer.future.timeout(const Duration(seconds: 20));
      } on TimeoutException catch (_) {
        _pending.remove(requestId);
        final bridgeError = PlatformException(
          code: 'vault_bridge_error',
          message:
              'Timed out waiting for Windows Vault helper response ($method)',
        );
        await restart();
        if (attempt == 0) {
          continue;
        }
        throw bridgeError;
      } on PlatformException catch (error) {
        if (error.code == 'vault_bridge_error') {
          await restart();
          if (attempt == 0) {
            continue;
          }
        }
        rethrow;
      }
    }
    throw PlatformException(
      code: 'vault_bridge_error',
      message: 'Windows Vault helper did not recover for $method',
    );
  }

  Future<void> _ensureStarted(String method) async {
    final inFlight = _starting;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    if (_process != null) {
      return;
    }
    final startFuture = _startProcess(method);
    _starting = startFuture;
    try {
      await startFuture;
    } finally {
      if (identical(_starting, startFuture)) {
        _starting = null;
      }
    }
  }

  Future<void> _startProcess(String method) async {
    final javaExecutable = _resolveJavaExecutable();
    final helperJar = _resolveHelperJar();
    if (javaExecutable == null || helperJar == null) {
      throw _unimplemented(
        method,
        'Windows Vault helper files are not bundled yet',
      );
    }

    final process = await Process.start(
      javaExecutable.path,
      <String>['-jar', helperJar.path],
      runInShell: false,
      workingDirectory: helperJar.parent.path,
      mode: ProcessStartMode.normal,
    );

    _process = process;
    _stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleStdoutLine);
    _stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (line.trim().isNotEmpty) {
            debugPrint('[VaultHelper] $line');
          }
        });
    process.exitCode.then((code) {
      _handleProcessExit(code);
      return code;
    });
  }

  void _handleStdoutLine(String line) {
    if (line.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) return;
      final payload = Map<String, dynamic>.from(decoded);
      final requestId = payload['id']?.toString();
      if (requestId == null || requestId.isEmpty) return;
      final completer = _pending.remove(requestId);
      if (completer == null || completer.isCompleted) return;
      final errorPayload = payload['error'];
      if (errorPayload is Map) {
        final errorMap = Map<String, dynamic>.from(errorPayload);
        completer.completeError(
          PlatformException(
            code: (errorMap['code'] ?? 'vault_bridge_error').toString(),
            message: errorMap['message']?.toString(),
            details: errorMap['details'],
          ),
        );
        return;
      }
      completer.complete(payload['result']);
    } catch (error) {
      debugPrint('[VaultHelper] Failed to parse helper output: $error');
    }
  }

  void _handleProcessExit(int exitCode) {
    _stdoutSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription?.cancel();
    _stderrSubscription = null;
    _process = null;
    if (_pending.isEmpty) {
      return;
    }
    final error = PlatformException(
      code: 'vault_bridge_error',
      message: 'Windows Vault helper exited unexpectedly (code $exitCode)',
    );
    final pending = Map<String, Completer<dynamic>>.from(_pending);
    _pending.clear();
    for (final completer in pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
  }

  PlatformException _unimplemented(String method, String message) {
    return PlatformException(
      code: 'UNIMPLEMENTED',
      message: '$message ($method)',
    );
  }

  File? _resolveJavaExecutable() {
    final candidates = <String>[
      if (_envValue('VAULT_WINDOWS_JAVA_EXE') != null)
        _envValue('VAULT_WINDOWS_JAVA_EXE')!,
      ..._relativeCandidates(<String>['vault_runtime', 'bin', 'java.exe']),
      ..._relativeCandidates(<String>[
        'data',
        'vault_runtime',
        'bin',
        'java.exe',
      ]),
      if (_repoRootCandidate() != null)
        _joinPath(<String>[
          _repoRootCandidate()!,
          'tool',
          'vendor',
          'jdk',
          'microsoft-jdk-21',
          'jdk-21.0.10+7',
          'bin',
          'java.exe',
        ]),
    ];

    for (final candidate in candidates) {
      final file = File(candidate);
      if (file.existsSync()) {
        return file;
      }
    }

    try {
      final whereResult = Process.runSync('where.exe', const <String>[
        'java.exe',
      ], runInShell: false);
      if (whereResult.exitCode == 0) {
        final first = whereResult.stdout
            .toString()
            .split(RegExp(r'[\r\n]+'))
            .map((line) => line.trim())
            .firstWhere((line) => line.isNotEmpty, orElse: () => '');
        if (first.isNotEmpty && File(first).existsSync()) {
          return File(first);
        }
      }
    } catch (_) {}

    return null;
  }

  File? _resolveHelperJar() {
    final candidates = <String>[
      if (_envValue('VAULT_WINDOWS_HELPER_JAR') != null)
        _envValue('VAULT_WINDOWS_HELPER_JAR')!,
      ..._relativeCandidates(<String>[
        'vault_bridge_helper',
        'vault-bridge-helper-all.jar',
      ]),
      ..._relativeCandidates(<String>[
        'data',
        'vault_bridge_helper',
        'vault-bridge-helper-all.jar',
      ]),
      if (_repoRootCandidate() != null)
        _joinPath(<String>[
          _repoRootCandidate()!,
          'windows',
          'vault_bridge_helper',
          'build',
          'libs',
          'vault-bridge-helper-all.jar',
        ]),
    ];

    for (final candidate in candidates) {
      final file = File(candidate);
      if (file.existsSync()) {
        return file;
      }
    }
    return null;
  }

  List<String> _relativeCandidates(List<String> suffixParts) {
    final executableDir = File(Platform.resolvedExecutable).parent.path;
    final workingDir = Directory.current.path;
    final bases = <String>{executableDir, workingDir};
    return bases
        .map((base) => _joinPath(<String>[base, ...suffixParts]))
        .toList();
  }

  String? _repoRootCandidate() {
    final cwd = Directory.current;
    if (File(_joinPath(<String>[cwd.path, 'pubspec.yaml'])).existsSync()) {
      return cwd.path;
    }
    return null;
  }

  String? _envValue(String key) {
    final value = Platform.environment[key]?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  String _joinPath(List<String> parts) {
    return parts.join(Platform.pathSeparator);
  }
}
