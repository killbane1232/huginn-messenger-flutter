import 'package:flutter_test/flutter_test.dart';
import 'package:huginn_messenger/src/models/config.dart';

void main() {
  test('legacy address and candidate list survive serialization', () {
    expect(AppConfig().allMuninnServers, isEmpty);
    expect(AppConfig.fromJson({}).allMuninnServers, isEmpty);
    final config = AppConfig.fromJson({
      'muninn': 'http://muninn.internal:8080',
      'muninn_servers': ['https://backup.example'],
      'turn_addr': 'legacy',
      'turn_user': 'legacy',
      'turn_pass': 'legacy',
    });
    final saved = config.toJson();
    expect(AppConfig.fromJson(saved).allMuninnServers, [
      'http://muninn.internal:8080',
      'https://backup.example',
    ]);
    expect(saved.keys.where((key) => key.startsWith('turn_')), isEmpty);
  });

  test('list-only bootstrap normalizes and deduplicates candidates', () {
    final config = AppConfig.fromJson({
      'muninn_servers': [
        ' https://MUNINN.example.:443/ ',
        'https://muninn.example',
        'http://127.0.0.1:8080/',
      ],
    });
    config.setMuninnServers(config.allMuninnServers);
    expect(config.muninnAddr, 'https://muninn.example');
    expect(config.muninnServers, ['http://127.0.0.1:8080']);
    config.setMuninnServers(['http://127.0.0.1:8080']);
    expect(config.muninnAddr, 'http://127.0.0.1:8080');
    expect(config.muninnServers, isEmpty);
  });

  test(
    'Muninn requires an HTTP origin, matching core candidate validation',
    () {
      for (final value in [
        '',
        'host:8080',
        'ftp://host',
        'https://',
        'http://host?x=1',
        'http://host?',
        'http://host#fragment',
        'http://host#',
        'http://user:password@host',
        'http://@host',
        'http://host/path',
        'http://host:0',
        'http://host:65536',
        'http://host:invalid',
        'http://bad host',
      ]) {
        expect(AppConfig.isValidMuninnAddr(value), isFalse, reason: value);
      }
      for (final value in [
        'https://host/',
        'http://127.0.0.1:8080',
        'http://[::1]:8080',
      ]) {
        expect(AppConfig.isValidMuninnAddr(value), isTrue, reason: value);
      }
    },
  );
}
