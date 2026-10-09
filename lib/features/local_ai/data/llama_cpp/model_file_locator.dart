import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Finds the GGUF file on the device.
///
/// 1. App-private support directory, `<support>/models/<fileName>`: where
///    the in-app Model Setup screen installs it (the customer path).
/// 2. Development fallback (Android): the app's external files directory,
///    `/sdcard/Android/data/<applicationId>/files/models/<fileName>`, which
///    `adb push` can write to without a storage permission.
class ModelFileLocator {
  const ModelFileLocator();

  static const String modelsDirectory = 'models';

  /// Every location searched, in order.
  Future<List<String>> candidatePaths(String fileName) async {
    final directories = <Directory?>[
      await getApplicationSupportDirectory(),
      if (Platform.isAndroid) await getExternalStorageDirectory(),
    ];
    return [
      for (final directory in directories.whereType<Directory>())
        p.join(directory.path, modelsDirectory, fileName),
    ];
  }

  /// The first existing candidate, or null if the model is not installed.
  Future<String?> find(String fileName) async {
    for (final path in await candidatePaths(fileName)) {
      if (await File(path).exists()) return path;
    }
    return null;
  }
}
