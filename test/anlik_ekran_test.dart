// Anlık ekranının duman testi: açılıyor mu, etiket önerisi çıkıyor mu,
// arama ve süz çipleri çalışıyor mu (telefonsuz). Veri sabit akışlarla verilir
// (Drift akışları test saatinde beklemede kalıyor).
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kocum/core/database/app_database.dart';
import 'package:kocum/core/di/core_providers.dart';
import 'package:kocum/features/anlik/anlik_providers.dart';
import 'package:kocum/features/anlik/domain/anlik.dart';
import 'package:kocum/features/anlik/domain/graf.dart';
import 'package:kocum/features/anlik/presentation/anlik_ekrani.dart';
import 'package:kocum/features/anlik/presentation/graf_ekrani.dart';

final _t = DateTime.now();

// Scaffold'da gövde, üst çubuktan önce gelir: arama kutusu üst çubukta.
final _arama = find.descendant(of: find.byType(AppBar), matching: find.byType(TextField));
final _yazma = find.descendant(of: find.byType(Column), matching: find.byType(TextField)).first;

void main() {
  Future<void> ac(WidgetTester tester, {List<Anlik> anliklar = const [], Widget ekran = const AnlikEkrani()}) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          anliklarProvider.overrideWith((ref) => Stream.value(anliklar)),
          etiketlerProvider.overrideWith(
            (ref) => Stream.value([
              Etiket(id: 'g', ad: 'garson', normAd: 'garson', tur: EtiketTur.kisi, olusturma: _t, guncelleme: _t),
            ]),
          ),
          baglarProvider.overrideWith((ref) => Stream.value(const <Bag>[])),
        ],
        child: MaterialApp(home: ekran),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('boş ekran; (( yazınca öneri, seçince tamamlanır', (tester) async {
    await ac(tester);
    expect(find.textContaining('Henüz anlık yok'), findsOneWidget);
    await tester.enterText(_yazma, 'bugün ((gar');
    await tester.pump();
    expect(find.widgetWithText(ListTile, 'garson'), findsOneWidget);
    expect(find.text('Yeni etiket: gar'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'garson'));
    await tester.pump();
    final kutu = tester.widget<TextField>(_yazma);
    expect(kutu.controller!.text, 'bugün ((garson)) ');
    expect(find.widgetWithText(InputChip, 'garson'), findsOneWidget); // şeritte çerçeveli çip
  });

  testWidgets('liste, arama ve süz çipleri', (tester) async {
    await ac(
      tester,
      anliklar: [
        Anlik(id: '1', metin: 'kantin kalabalıktı', olusturma: _t, guncelleme: _t, duygu: -1),
        Anlik(id: '2', metin: 'matematik testi', olusturma: _t, guncelleme: _t),
      ],
    );
    expect(find.text('Bugün'), findsOneWidget);
    expect(find.textContaining('kalabalıktı'), findsOneWidget);
    await tester.enterText(_arama, 'kantn');
    await tester.pump();
    expect(find.text('1 anlık'), findsOneWidget);
    expect(find.text('Grafikte göster'), findsOneWidget);
    await tester.tap(find.byTooltip('Süz'));
    await tester.pump();
    expect(find.text('Etiketsiz'), findsOneWidget);
  });

  testWidgets('grafik ekranı çizilir, görünüm değişir', (tester) async {
    await ac(
      tester,
      ekran: const GrafEkrani(),
      anliklar: [
        for (var i = 0; i < 20; i++)
          Anlik(
            id: '$i',
            metin: 'not $i',
            olusturma: _t.subtract(Duration(days: i)),
            guncelleme: _t,
            duygu: i % 7 - 3,
          ),
      ],
    );
    for (var i = 0; i < 50 && find.byType(InteractiveViewer).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    expect(find.text('Gösterilecek bir şey yok.'), findsNothing);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.byType(DropdownButton<GrafGorunum>));
    await tester.pump();
    await tester.tap(find.text('Takvim').last);
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
