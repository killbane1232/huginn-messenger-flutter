import 'package:flutter_test/flutter_test.dart';
import 'package:huginn_messenger/src/models/config.dart';

void main() {
  test(
    'missing address stays unset; custom address survives serialization',
    () {
      expect(AppConfig().muninnAddr, isEmpty);
      expect(AppConfig.fromJson({}).muninnAddr, isEmpty);
      final config = AppConfig.fromJson({
        'muninn': 'http://muninn.internal:8080',
      });
      expect(AppConfig.fromJson(config.toJson()).muninnAddr, config.muninnAddr);
    },
  );

  test('Muninn requires an HTTP URL without query or fragment', () {
    for (final value in [
      '',
      'host:8080',
      'ftp://host',
      'https://',
      'http://host?x=1',
      'http://host#fragment',
    ]) {
      expect(AppConfig.isValidMuninnAddr(value), isFalse, reason: value);
    }
    expect(AppConfig.isValidMuninnAddr('https://host/directory'), isTrue);
    expect(AppConfig.isValidMuninnAddr('http://127.0.0.1:8080'), isTrue);
  });
}
