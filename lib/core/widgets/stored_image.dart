import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../error/exceptions.dart';
import '../localization/app_localizations.dart';
import '../localization/app_text.dart';
import '../media/image_store.dart';
import '../theme/surfaces.dart';
import 'app_snack.dart';

/// A picture from [ImageStore], with something sensible when there is none.
///
/// The fallback is not decoration. Most shops photograph a few dozen items and
/// never finish the rest, so the *unphotographed* tile is the one a cashier
/// looks at all day: it gets the item's own tint, its icon, and its first
/// letter, which is enough to find a line in a grid without a picture at all.
class StoredImage extends StatelessWidget {
  const StoredImage({
    super.key,
    required this.name,
    this.size,
    this.width,
    this.height,
    this.radius = 10,
    this.tint,
    this.icon,
    this.letter,
    this.fit = BoxFit.cover,
    this.full = false,
  });

  /// The file name held in `items.image_path` or `categories.image_path`.
  final String? name;

  final double? size;
  final double? width;
  final double? height;
  final double radius;
  final Color? tint;
  final IconData? icon;
  final String? letter;
  final BoxFit fit;

  /// Draw the full-size file rather than the thumbnail. Only worth it where
  /// the picture is shown large — the editor, not a grid tile.
  final bool full;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color base = tint ?? theme.colorScheme.primary;
    final File? picture = full ? ImageStore.file(name) : ImageStore.thumb(name);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width ?? size,
        height: height ?? size,
        child: picture == null
            ? _Fallback(base: base, icon: icon, letter: letter)
            : Image.file(
                picture,
                fit: fit,
                width: width ?? size,
                height: height ?? size,
                // A file that was deleted from the folder while the app was
                // running must not paint an exception where a tile should be.
                errorBuilder: (_, __, ___) =>
                    _Fallback(base: base, icon: icon, letter: letter),
              ),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.base, this.icon, this.letter});

  final Color base;
  final IconData? icon;
  final String? letter;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ColoredBox(
      color: base.withValues(alpha: theme.isDark ? 0.18 : 0.10),
      child: Center(
        child: (letter ?? '').isNotEmpty
            ? Text(
                letter!,
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: base, fontWeight: FontWeight.w700),
              )
            : Icon(icon ?? Icons.image_outlined, size: 22, color: base),
      ),
    );
  }
}

/// Pick a picture, see it, remove it.
///
/// The widget owns nothing: it is handed the stored name and hands back a new
/// one, so the form it sits in stays the single place that knows whether the
/// change has been saved yet. The file is copied into the store as soon as it
/// is chosen — a manager who picks a photo and then cancels the form leaves a
/// stray file, which `ImageStore.prune` sweeps up, and that is a far cheaper
/// mistake than a form that "saves" a path to a file that has moved.
class ImagePickerField extends StatefulWidget {
  const ImagePickerField({
    super.key,
    required this.name,
    required this.onChanged,
    this.size = 96,
    this.prefix = 'img',
    this.icon = Icons.add_a_photo_outlined,
    this.enabled = true,
  });

  final String? name;
  final ValueChanged<String?> onChanged;
  final double size;
  final String prefix;
  final IconData icon;
  final bool enabled;

  @override
  State<ImagePickerField> createState() => _ImagePickerFieldState();
}

class _ImagePickerFieldState extends State<ImagePickerField> {
  bool _busy = false;

  /// Whether a camera is worth offering. On a desktop till the file dialog is
  /// the only sensible answer; on a tablet in the aisle the camera is the
  /// whole point.
  bool get _hasCamera => Platform.isAndroid || Platform.isIOS;

  Future<void> _pick({required bool camera}) async {
    setState(() => _busy = true);
    try {
      String? path;
      if (camera) {
        final XFile? shot = await ImagePicker().pickImage(
          source: ImageSource.camera,
          maxWidth: 1600,
          imageQuality: 85,
        );
        path = shot?.path;
      } else {
        final PlatformFile? picked = await FilePicker.pickFile(
          type: FileType.image,
        );
        path = picked?.path;
      }
      if (path == null) return;

      final String saved =
          await ImageStore.replace(widget.name, path, prefix: widget.prefix);
      if (!mounted) return;
      widget.onChanged(saved);
    } on AppFailure catch (failure) {
      if (mounted) AppSnack.error(context, failure.message);
    } on Object {
      if (mounted) {
        AppSnack.error(context, context.tr(AppText.imagePickFailed));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    final String? old = widget.name;
    widget.onChanged(null);
    await ImageStore.remove(old);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool has = ImageStore.thumb(widget.name) != null;
    final bool enabled = widget.enabled && !_busy;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Stack(
          children: <Widget>[
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: enabled ? () => _pick(camera: false) : null,
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.surfaces.hairline),
                  color: theme.surfaces.raised,
                ),
                child: _busy
                    ? const Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : has
                        ? StoredImage(
                            name: widget.name,
                            size: widget.size,
                            radius: 11,
                            full: true,
                          )
                        : Center(
                            child: Icon(
                              widget.icon,
                              size: 22,
                              color: theme.surfaces.muted,
                            ),
                          ),
              ),
            ),
            if (has && enabled)
              PositionedDirectional(
                top: -6,
                end: -6,
                child: IconButton(
                  tooltip: context.tr(AppText.imageRemove),
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.cancel),
                  onPressed: _clear,
                ),
              ),
          ],
        ),
        if (_hasCamera) ...<Widget>[
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: enabled ? () => _pick(camera: true) : null,
            icon: const Icon(Icons.photo_camera_outlined, size: 16),
            label: Text(context.tr(AppText.imageCamera)),
          ),
        ],
      ],
    );
  }
}
