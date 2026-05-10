// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:typed_data';

Future<String> saveFileBytes({
  required Uint8List bytes,
  required String filename,
  String? contentType,
}) async {
  final blob = html.Blob([bytes], contentType ?? 'application/octet-stream');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = filename.isEmpty ? 'promptd-image' : filename
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
  return anchor.download ?? filename;
}
