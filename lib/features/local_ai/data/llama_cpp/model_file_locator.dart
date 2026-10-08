import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Finds the GGUF file on the device.
///
/// Development location (Android): the app's external files directory,
/// `/sdcard/Android/data/<applicationId>/files/models/<fileName>`, which
/// `adb push` can write to without any storage permission and which is
/// removed with the app. Falls back to the internal support directory, where
/// a future first-run install would place the model.
class ModelFileLocator {
  const ModelFileLocator();

  static const String modelsDirectory = 'models';

  /// Every location searched, in order.
  Future<List<String>> candidatePaths(String fileName) async {
    final directories = <Directory?>[
      if (Platform.isAndroid) await getExternalStorageDirectory(),
      await getApplicationSupportDirectory(),
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
