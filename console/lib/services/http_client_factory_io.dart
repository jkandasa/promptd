import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

http.Client createHttpClient({required bool allowInsecureTls}) {
  final client = HttpClient();
  if (allowInsecureTls) {
    client.badCertificateCallback = (_, _, _) => true;
  }
  return IOClient(client);
}
