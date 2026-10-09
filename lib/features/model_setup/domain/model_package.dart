import 'package:flutter/foundation.dart';

/// One file of a model package, identified by name, exact size and SHA-256.
@immutable
class ModelFileSpec {
  const ModelFileSpec({
    required this.name,
    required this.bytes,
    required this.sha256,
  });

  final String name;
  final int bytes;

  /// Lower-case hex.
  final String sha256;
}

/// A model the user installs by importing files (no download).
@immutable
class ModelPackage {
  const ModelPackage({
    required this.id,
    required this.title,
    required this.installDir,
    required this.files,
    this.acceptsZip = false,
  });

  /// Stable identifier, also used for staging folder names.
  final String id;

  /// User-facing name.
  final String title;

  /// Install folder relative to the app-private root, e.g. `models` or
  /// `stt/<model>`. Every file of the package lives directly in it.
  final String installDir;

  final List<ModelFileSpec> files;

  /// Whether the package may be imported as one ZIP containing [files]
  /// (in any folder of the archive).
  final bool acceptsZip;

  int get totalBytes => files.fold(0, (sum, f) => sum + f.bytes);

  bool get isMultiFile => files.length > 1;
}

enum ModelState {
  /// Not found anywhere.
  missing,

  /// Present with the expected file sizes.
  installed,

  /// Present but at least one file has the wrong size (damaged or wrong).
  invalid,
}

/// Where an installed model was found.
enum ModelSource {
  /// Imported through the app (app-private storage). The customer path.
  imported,

  /// Pushed with adb into the app's external files folder (development).
  developer,
}

@immutable
class ModelStatus {
  const ModelStatus(this.state, {this.source});

  const ModelStatus.missing() : this(ModelState.missing);

  final ModelState state;
  final ModelSource? source;

  bool get isReady => state == ModelState.installed;
}
