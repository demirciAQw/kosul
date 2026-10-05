import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart';

import '../../../core/database/app_database.dart';
import '../../../core/json/json_reader.dart';
import '../domain/curriculum.dart';

class DriftCurriculumRepository implements CurriculumRepository {
  DriftCurriculumRepository(this._db);
  final AppDatabase _db;

  @override
  Stream<List<CurriculumNode>> watchAll() =>
      _db.select(_db.curriculumNodes).watch().map((rows) => rows.map(_toEntity).toList());

  @override
  Future<List<CurriculumNode>> all() async =>
      (await _db.select(_db.curriculumNodes).get()).map(_toEntity).toList();

  static CurriculumNode _toEntity(CurriculumNodeRow r) => CurriculumNode(
        id: r.id,
        parentId: r.parentId,
        examType: r.examType,
        subject: r.subject,
        title: r.title,
        aliases: r.aliases,
        depth: r.depth,
        sortOrder: r.sortOrder,
      );
}

/// Asset'teki MEB ağacını, asset sürümü yükseldiğinde upsert eder.
/// Asla silmez: mevcut kart/kitap eşleştirmeleri korunur.
class CurriculumSeeder {
  CurriculumSeeder(this._db, {AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static const assetPath = 'assets/meb/kazanim_agaci.json';
  static const _versionKey = 'curriculum_version';

  final AppDatabase _db;
  final AssetBundle _bundle;

  Future<void> run() async {
    final asset = parseCurriculumAsset(await _bundle.loadString(assetPath));
    final stored = await (_db.select(_db.appMeta)..where((m) => m.metaKey.equals(_versionKey)))
        .getSingleOrNull();
    if ((int.tryParse(stored?.metaValue ?? '') ?? 0) >= asset.version) return;

    await _db.transaction(() async {
      await _db.batch((b) => b.insertAllOnConflictUpdate(_db.curriculumNodes, [
            for (final n in asset.nodes)
              CurriculumNodesCompanion.insert(
                id: n.id,
                parentId: Value(n.parentId),
                examType: n.examType,
                subject: n.subject,
                title: n.title,
                aliases: n.aliases,
                depth: n.depth,
                sortOrder: n.sortOrder,
              ),
          ]));
      await _db.into(_db.appMeta).insertOnConflictUpdate(
          AppMetaCompanion.insert(metaKey: _versionKey, metaValue: '${asset.version}'));
    });
  }
}

({int version, List<CurriculumNode> nodes}) parseCurriculumAsset(String raw) {
  final root = JsonReader.root(jsonDecode(raw));
  final version = root.requireInt('version', min: 1);
  final nodes = <CurriculumNode>[];
  for (final subject in root.objectList('subjects', required: true)) {
    final exam = subject.requireString('examType');
    final name = subject.requireString('subject');
    void walk(List<JsonReader> items, String? parentId, int depth) {
      for (var i = 0; i < items.length; i++) {
        final r = items[i];
        final id = r.requireString('id');
        nodes.add(CurriculumNode(
          id: id,
          parentId: parentId,
          examType: exam,
          subject: name,
          title: r.requireString('title'),
          aliases: r.stringList('aliases'),
          depth: depth,
          sortOrder: i,
        ));
        walk(r.objectList('children'), id, depth + 1);
      }
    }

    walk(subject.objectList('topics', required: true), null, 0);
  }
  return (version: version, nodes: nodes);
}
