import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app.dart';

void main() {
  // Use bundled font assets instead of fetching from Google Fonts CDN.
  // Required for airgap deployments; harmless in connected environments.
  GoogleFonts.config.allowRuntimeFetching = false;
  runApp(const PromptdConsoleApp());
}
