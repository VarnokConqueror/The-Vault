import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class SecureStorageMock {
  static const MethodChannel _channel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  static Map<String, String> _values = <String, String>{};

  static void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (MethodCall call) async {
          final arguments =
              (call.arguments as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          final key = (arguments['key'] ?? '').toString();
          switch (call.method) {
            case 'read':
              return _values[key];
            case 'write':
              _values[key] = (arguments['value'] ?? '').toString();
              return null;
            case 'delete':
              _values.remove(key);
              return null;
            case 'containsKey':
              return _values.containsKey(key);
            case 'readAll':
              return Map<String, String>.from(_values);
            case 'deleteAll':
              _values.clear();
              return null;
            default:
              return null;
          }
        });
  }

  static void reset() {
    _values = <String, String>{};
  }
}
