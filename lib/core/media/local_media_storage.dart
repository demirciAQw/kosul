import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/id_generator.dart';
import 'media_storage.dart';

class LocalMediaStorage implements MediaStorage {
  LocalMediaStorage._(this._root, this._tempRoot, this._ids);

  static Future<LocalMediaStorage> open({IdGenerator ids = const UuidV7Generator()}) async {
    final docs = await getApplicationDocumentsDirectory();
    final temp = await getTemporaryDirectory();
    final root = Directory(p.join(docs.path, 'media'));
    await root.create(recursive: true);
    return LocalMediaStorage._(root, temp.path, ids);
  }

  final Directory _root;
  final String _tempRoot;
  final IdGenerator _ids;

  @override
  Future<String> importFile(String sourcePath, {required String bucket}) async {
    final now = DateTime.now();
    // questions/2026/10/<uuid>.webp → tek klasörde on binlerce dosya birikmez.
    final relative = p.posix.join(
      bucket,
      '${now.year}',
      now.month.toString().padLeft(2, '0'),
      '${_ids.next()}${p.extension(sourcePath)}',
    );
    final target = resolve(relative);
    await target.parent.create(recursive: true);
    await File(sourcePath).copy(target.path);
    return relative;
  }

  @override
  File resolve(String relativePath) =>
      File(p.joinAll([_root.path, ...p.posix.split(relativePath)]));

  @override
  Future<void> delete(String relativePath) async {
    final file = resolve(relativePath);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> discardTemp(String? absolutePath) async {
    // Güvenlik kilidi: önbellek dışındaki (ör. galerideki) bir dosya asla silinmez.
    if (absolutePath == null || !p.isWithin(_tempRoot, absolutePath)) return;
    try {
      final file = File(absolutePath);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Önbellek dosyası; silinemezse işletim sistemi zaten temizler.
    }
  }
}
