import 'dart:typed_data';

import 'file_downloader_stub.dart'
    if (dart.library.html) 'file_downloader_web.dart'
    if (dart.library.io) 'file_downloader_io.dart';

Future<String> saveDownloadedFile({
  required Uint8List bytes,
  required String filename,
  String? contentType,
}) {
  return saveFileBytes(
    bytes: bytes,
    filename: filename,
    contentType: contentType,
  );
}
