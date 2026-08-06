import 'package:flutter_test/flutter_test.dart';
import 'package:huginn_messenger/src/models/chat_message.dart';

void main() {
  test('outgoing file resolves its persisted local path', () {
    final file = FileMeta.fromJson({
      'file_id': 'file-id',
      'filename': 'photo.png',
      'file_path': '/home/user/Pictures/photo.png',
    });

    expect(file.resolveLocalPath({}), '/home/user/Pictures/photo.png');
    expect(file.toJson()['file_path'], '/home/user/Pictures/photo.png');
  });

  test('downloaded file falls back to service path map', () {
    final file = FileMeta(fileId: 'file-id', filename: 'photo.png');

    expect(
      file.resolveLocalPath({'file-id': '/downloads/photo.png'}),
      '/downloads/photo.png',
    );
  });

  test('persisted outgoing path takes precedence over downloaded map', () {
    final file = FileMeta(
      fileId: 'file-id',
      filename: 'photo.png',
      filePath: '/original/photo.png',
    );

    expect(
      file.resolveLocalPath({'file-id': '/downloads/photo.png'}),
      '/original/photo.png',
    );
  });
}
