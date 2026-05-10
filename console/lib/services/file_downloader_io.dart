import 'dart:io';
import 'dart:typed_data';

Future<String> saveFileBytes({
  required Uint8List bytes,
  required String filename,
  String? contentType,
}) async {
  final dir = await _downloadDirectory();
  await dir.create(recursive: true);
  final file = File(
    '${dir.path}${Platform.pathSeparator}${_safeName(filename)}',
  );
  final target = await _uniqueFile(file);
  await target.writeAsBytes(bytes, flush: true);
  return target.path;
}

Future<Directory> _downloadDirectory() async {
  if (Platform.isAndroid) {
    final androidDownloads = Directory('/storage/emulated/0/Download');
    if (await androidDownloads.exists()) return androidDownloads;
  }
  final home = Platform.environment['HOME'];
  if (home != null && home.isNotEmpty) {
    return Directory('$home${Platform.pathSeparator}Downloads');
  }
  final profile = Platform.environment['USERPROFILE'];
  if (profile != null && profile.isNotEmpty) {
    return Directory('$profile${Platform.pathSeparator}Downloads');
  }
  return Directory.systemTemp;
}

Future<File> _uniqueFile(File file) async {
  if (!await file.exists()) return file;
  final path = file.path;
  final dot = path.lastIndexOf('.');
  final base = dot > 0 ? path.substring(0, dot) : path;
  final ext = dot > 0 ? path.substring(dot) : '';
  for (var i = 1; i < 1000; i++) {
    final candidate = File('$base-$i$ext');
    if (!await candidate.exists()) return candidate;
  }
  return file;
}

String _safeName(String value) {
  final cleaned = value.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_').trim();
  return cleaned.isEmpty ? 'promptd-image' : cleaned;
}
