import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app/app.dart';

void main() {
  // Giấy phép font Be Vietnam Pro (SIL OFL 1.1) hiện trong trang "Giấy phép".
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString(
      'assets/fonts/BeVietnamPro/OFL.txt',
    );
    yield LicenseEntryWithLineBreaks(const ['Be Vietnam Pro'], license);
  });

  runApp(const SafeFamilyApp());
}
