import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../error/exceptions.dart';

//? Manages local image storage, caching, and thumbnail generation.
//? Database rows only store the leaf name for portable backups.
abstract final class ImageStore {
  //! Changing this folder name breaks existing stored image paths
  static const String folder = 'images';

  //? Maximum thumbnail width/height in pixels.
  static const int thumbSize = 320;

  //? Maximum allowed file upload size (12 MB).
  static const int maxBytes = 12 * 1024 * 1024;

  static String? _root;

  // ** Must be called before accessing any file operations.
  static Future<void> configure() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, folder));
    if (!dir.existsSync()) await dir.create(recursive: true);
    _root = dir.path;
  }

  //? Checks if the image store directory has been configured.
  static bool get isReady => _root != null;

  //? Gets the absolute path of the root image folder.
  static String get root => _root ?? '';

  //? Returns full-size [File] by [name], or `null` if not found.
  static File? file(String? name) {
    if (_root == null || name == null || name.isEmpty) return null;
    final f = File(p.join(_root!, name));
    return f.existsSync() ? f : null;
  }

  //? Returns thumbnail [File] by [name], falling back to original file.
  static File? thumb(String? name) {
    if (_root == null || name == null || name.isEmpty) return null;
    final t = File(p.join(_root!, 't_${p.setExtension(name, '.png')}'));
    return t.existsSync() ? t : file(name);
  }

  //? Saves image from [sourcePath] and generates its thumbnail.
  // ** Unique filename generated using microsecond timestamps.
  static Future<String> save(
    String sourcePath, {
    String prefix = 'img',
  }) async {
    if (_root == null) {
      throw const AppFailure('The picture folder is not ready.');
    }

    final source = File(sourcePath);
    if (!source.existsSync()) {
      throw const AppFailure.validation('That file is no longer there.');
    }
    if (await source.length() > maxBytes) {
      throw const AppFailure.validation(
        'That picture is too large. Please use one under 12 MB.',
      );
    }

    final bytes = await source.readAsBytes();
    final thumbnail = await _thumbnail(bytes);

    final ext = p.extension(sourcePath).toLowerCase();
    final name = '${prefix}_${DateTime.now().microsecondsSinceEpoch}'
        '${ext.isEmpty ? '.png' : ext}';

    await File(p.join(_root!, name)).writeAsBytes(bytes, flush: true);
    await File(p.join(_root!, 't_${p.setExtension(name, '.png')}'))
        .writeAsBytes(thumbnail, flush: true);

    return name;
  }

  //? Deletes main image and thumbnail by [name].
  static Future<void> remove(String? name) async {
    if (_root == null || name == null || name.isEmpty) return;
    final targets = [name, 't_${p.setExtension(name, '.png')}'];

    for (final fileName in targets) {
      try {
        final f = File(p.join(_root!, fileName));
        if (f.existsSync()) await f.delete();
      } catch (_) {
        // Safe skip if deletion fails
      }
    }
  }


  // ** Old image deleted only after new file is successfully saved.
  static Future<String> replace(
    String? old,
    String sourcePath, {
    String prefix = 'img',
  }) async {
    final name = await save(sourcePath, prefix: prefix);
    if (old != name) await remove(old);
    return name;
  }

  //? Calculates total size of stored images in bytes.
  static int bytesUsed() {
    if (_root == null) return 0;
    final dir = Directory(_root!);
    if (!dir.existsSync()) return 0;

    return dir
        .listSync()
        .whereType<File>()
        .fold(0, (sum, file) => sum + file.lengthSync());
  }


  static Future<int> prune(Set<String> keep) async {
    if (_root == null) return 0;
    final dir = Directory(_root!);
    if (!dir.existsSync()) return 0;

    final wanted = {
      for (final name in keep) ...[name, 't_${p.setExtension(name, '.png')}'],
    };

    int removed = 0;
    for (final entity in dir.listSync().whereType<File>()) {
      if (!wanted.contains(p.basename(entity.path))) {
        try {
          await entity.delete();
          removed++;
        } catch (_) {
        }
      }
    }
    return removed;
  }

  //? Resizes image bytes using Flutter's native UI codec.
  // ! Throws AppFailure.validation if image decode fails.
  // TODO: Support WebP compression format to save more storage.
  static Future<Uint8List> _thumbnail(Uint8List bytes) async {
    try {
      final codec =
          await ui.instantiateImageCodec(bytes, targetWidth: thumbSize);
      final frame = await codec.getNextFrame();
      final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);

      frame.image.dispose();
      codec.dispose();

      if (png == null) {
        throw const AppFailure.validation('That picture could not be resized.');
      }
      return png.buffer.asUint8List();
    } catch (e) {
      if (e is AppFailure) rethrow;
      throw const AppFailure.validation(
        'That file is not a picture this app can read.',
      );
    }
  }
}