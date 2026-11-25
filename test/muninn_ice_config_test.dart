import 'package:flutter_test/flutter_test.dart';
import 'package:huginn_messenger/src/models/config.dart';
import 'package:huginn_messenger/src/models/muninn_ice_config.dart';

void main() {
  test('profiles survive JSON and removed servers lose their credentials', () {
    final profile = MuninnIceConfig(
      stunUrls: ['stun:host:3478'],
      turnUrls: ['turns:host:5349?transport=tcp'],
      turnUsername: 'alice',
      turnPassword: ' password ',
    );
    final config = AppConfig(
      muninnAddr: 'https://first.example',
      muninnServers: ['https://second.example'],
      muninnIce: {
        'https://FIRST.example:443/': profile,
        'https://second.example': profile,
      },
    );
    final copy = AppConfig.fromJson(config.toJson());
    expect(
      copy.iceFor('https://first.example').sameSettingsAs(profile),
      isTrue,
    );
    copy.setMuninnServers(['https://second.example']);
    expect(copy.muninnIce.keys, ['https://second.example']);
    expect(config.muninnIce.length, 2);
    expect(copy.iceFor('https://second.example').turnPassword, ' password ');
    expect(copy.iceFor('https://unknown.example').turnUrls, isEmpty);
  });

  test('ICE schemes, ports, transports and credentials are validated', () {
    for (final url in [
      'https://host',
      'stun://host',
      'stun:host:0',
      'stun:host:65536',
      'stun:host:3478?transport=udp',
      'stun:host#fragment',
      'stun:user@host',
    ]) {
      expect(
        MuninnIceConfig.isValidUrl(url, turn: false),
        isFalse,
        reason: url,
      );
    }
    for (final url in ['stun:host', 'stuns:host:5349', 'stun:[::1]:3478']) {
      expect(MuninnIceConfig.isValidUrl(url, turn: false), isTrue, reason: url);
    }
    expect(
      MuninnIceConfig.isValidUrl('turn:host:3478?transport=udp', turn: true),
      isTrue,
    );
    expect(
      MuninnIceConfig.isValidUrl('turn:host:3478?transport=http', turn: true),
      isFalse,
    );
    expect(
      MuninnIceConfig(turnUrls: ['turn:host:3478']).validationError,
      isNotNull,
    );
    final cleared = MuninnIceConfig(
      turnUsername: 'old',
      turnPassword: 'old',
    ).normalized();
    expect(cleared.turnUsername, isEmpty);
    expect(cleared.turnPassword, isEmpty);
  });
}
