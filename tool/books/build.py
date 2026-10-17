"""Soru bankası şablonlarını üretir (assets/templates/*.json).

İki tür kitap var:
 - Ardışık testli (Bilgi Sarmal): her test 2 sayfa; ünitenin ilk testinin
   sayfası verilir, gerisi sırayla hesaplanır. İçindekilerdeki numaralarla
   birebir karşılaştırılır (assert).
 - Aralıklı (Dil Bilgisi Saati, Orijinal Matematik): test grupları sayfa
   aralığıyla verilir; gruptaki testlere aralık eşit bölünerek dağıtılır.
"""
import json, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, 'assets', 'templates')


def topic_of(title):
    """'Vektörler - 2' → 'Vektörler'; 'Canlıların Sınıflandırılması – 4 (Bakteriler Âlemi)' → 'Canlıların Sınıflandırılması'."""
    t = re.sub(r'\s*[–-]\s*\d+(\s*\(.*\))?\s*$', '', title.strip())
    return t.strip()


def sequential(units, last_page):
    """units: [(ünite adı, ilk sayfa, [test adı, ...], [ünite sonu test adları])]"""
    out = []
    for ui, (name, start, tests, closing) in enumerate(units):
        page = start
        konular = []  # [(konu, [leaf])]
        for i, t in enumerate(tests, 1):
            k = topic_of(t)
            leaf = {'title': f'Test {i}: {t}', 'pageStart': page, 'pageEnd': page + 1}
            if konular and konular[-1][0] == k:
                konular[-1][1].append(leaf)
            else:
                konular.append((k, [leaf]))
            page += 2
        close = []
        for t in closing:
            close.append({'title': t, 'pageStart': page, 'pageEnd': page + 1})
            page += 2
        if close:
            konular.append(('Ünite ve Sarmal Testleri' if 'Ünite' in close[0]['title'] else 'Tema ve Sarmal Testleri', close))
        end = page - 1
        children = [{'title': k, 'pageStart': ls[0]['pageStart'], 'pageEnd': ls[-1]['pageEnd'], 'children': ls}
                    for k, ls in konular]
        out.append({'title': name, 'pageStart': start, 'pageEnd': end, 'children': children})
    assert out[-1]['pageEnd'] <= last_page, (out[-1]['pageEnd'], last_page)
    return out


def split(start, end, names):
    """[start, end] aralığını testlere eşit böler (en az 1 sayfa)."""
    n = len(names)
    span = end - start + 1
    leaves = []
    for i, nm in enumerate(names):
        s = start + (span * i) // n
        e = start + (span * (i + 1)) // n - 1
        e = max(s, e)
        leaves.append({'title': nm, 'pageStart': s, 'pageEnd': min(e, end)})
    return leaves


def tests_range(kind, nums):
    return [f'{kind} {n}' for n in nums]


def book(title, publisher, exam, subject, pages, avg, units):
    return {'format': 'kocum.book-template', 'schemaVersion': 1, 'author': 'kocum',
            'book': {'title': title, 'publisher': publisher, 'examType': exam, 'subject': subject,
                     'pageCount': pages, 'avgQuestionsPerPage': avg},
            'units': units}


def ut(n, word='Ünite'): return [f'{word} Testi - {i}' for i in range(1, n + 1)]


# ─────────────── Bilgi Sarmal İlk Aşama Fizik ───────────────
def fizik():
    F = 'Fizik Bilimi ve Kariyer Keşfi'
    units = [
        ('1. Ünite: Fizik Bilimi ve Kariyer Keşfi', 8, [f'{F} - {i}' for i in (1, 2, 3)], ut(2)),
        ('2. Ünite: Kuvvet ve Hareket', 20,
         [f'Fiziksel Niceliklerin Sınıflandırılması - {i}' for i in (1, 2, 3)] +
         [f'Vektörler - {i}' for i in (1, 2, 3)] + [f'Kuvvet - {i}' for i in (1, 2, 3)] +
         [f'Hareket ile İlgili Kavramlar - {i}' for i in (1, 2, 3)], ut(3) + ['Sarmal Test - 1']),
        ('3. Ünite: Akışkanlar', 54,
         [f'Katı Basıncı - {i}' for i in (1, 2, 3)] + [f'Durgun Sıvı Basıncı - {i}' for i in (1, 2, 3)] +
         [f'Açık Hava Basıncı - {i}' for i in (1, 2, 3)] + [f'Sıvıların Kaldırma Kuvveti - {i}' for i in (1, 2, 3)] +
         [f'Akışkan Basıncı - {i}' for i in (1, 2, 3)], ut(5)),
        ('4. Ünite: Enerji', 96,
         [f'Isı - İç Enerji - Öz Isı - Isı Sığası - {i}' for i in (1, 2, 3)] +
         [f'Termometreler - {i}' for i in (1, 2, 3)] + [f'Hâl Değişimi - {i}' for i in (1, 2, 3)] +
         [f'Isıl Denge - {i}' for i in (1, 2, 3)] + [f'Basıncın Hâl Değişimine Etkisi - {i}' for i in (1, 2, 3)] +
         [f'Enerji İletim Yolları ve Enerji İletim Hızı - {i}' for i in (1, 2, 3)], ut(5) + ['Sarmal Test - 2']),
        ('5. Ünite: Kuvvet ve Hareket', 146,
         [f'Sabit Hızlı Hareket - {i}' for i in (1, 2, 3)] +
         [f'Tek Boyutta Sabit İvmeli Hareket - {i}' for i in (1, 2, 3)], ut(3)),
        ('6. Ünite: Enerji', 166,
         [f'İş, Enerji ve Güç - {i}' for i in (1, 2, 3)] +
         [f'Mekanik Enerji - Enerji Biçimleri - {i}' for i in (1, 2, 3)] +
         [f'Enerji Kaynakları - {i}' for i in (1, 2, 3)], ut(4) + ['Sarmal Test - 3']),
        ('7. Ünite: Elektrik', 196,
         [f'Akım - Potansiyel Fark ve Direnç - {i}' for i in (1, 2, 3)] +
         [f'Dirençlerin Bağlanması - {i}' for i in (1, 2, 3)] + [f'Devre Elemanları - {i}' for i in (1, 2, 3)] +
         [f'Üreteçler - {i}' for i in (1, 2, 3)] +
         [f'Elektrik Kazalarından Korunma ve Topraklama - {i}' for i in (1, 2)], ut(5) + ['Sarmal Test - 4']),
        ('8. Ünite: Dalgalar', 238,
         [f'Periyodik Hareketler - {i}' for i in (1, 2, 3)] +
         [f'Dalgaların Temel Kavramları - {i}' for i in (1, 2, 3)] +
         [f'Dalgaların Sınıflandırılması - {i}' for i in (1, 2, 3)] +
         [f'Dalgaların Yayılma Sürati - {i}' for i in (1, 2, 3)] +
         [f'Su Dalgalarında Yansıma - {i}' for i in (1, 2)] + [f'Su Dalgalarında Kırılma - {i}' for i in (1, 2)] +
         [f'Ses ve Deprem Dalgaları - {i}' for i in (1, 2, 3)], ut(4) + ['Sarmal Test - 5']),
    ]
    u = sequential(units, 286)
    # İçindekilerle karşılaştırma: ünite başları ve son testler
    expect_last = [16, 50, 92, 142, 162, 192, 234, 284]
    assert [x['pageEnd'] - 1 for x in u] == expect_last, [x['pageEnd'] - 1 for x in u]
    return book('Bilgi Sarmal İlk Aşama Fizik Soru Bankası', 'Bilgi Sarmal Yayınları', 'TYT', 'Fizik', 286, 6, u)


# ─────────────── Bilgi Sarmal İlk Aşama Biyoloji ───────────────
def biyoloji():
    cos = 'Canlıların Ortak Özellikleri'
    cs = 'Canlıların Sınıflandırılması'
    t1 = ['Biyolojinin Önemi ve Biyolojideki Dönüm Noktaları',
          'Bilim, Bilimin Doğası ve Bilimsel Araştırma Süreçleri',
          'Bilimsel Yöntem Basamakları ile Bilimsel Araştırmalar ve Etik'] + \
         [f'{cos} - {i}' for i in (1, 2, 3, 4, 5)] + ['Virüsler', f'{cos} - 6'] + \
         [f'{cs} - {i}' for i in (1, 2, 3)] + \
         [f'{cs} - 4 (Bakteriler Âlemi)', f'{cs} - 5 (Bakteriler Âlemi)', f'{cs} - 6 (Arkeler Âlemi)',
          f'{cs} - 7 (Protista Âlemi)', f'{cs} - 8 (Bitkiler Âlemi)', f'{cs} - 9 (Mantarlar Âlemi)',
          f'{cs} - 10 (Canlılar Âlemi)', f'{cs} - 11 (Hayvanlar Âlemi)', f'{cs} - 12 (Omurgasız Hayvanlar)',
          f'{cs} - 13 (Omurgalı Hayvanlar)', f'{cs} - 14 (Omurgalı Hayvanlar)', f'{cs} - 15 (Omurgalı Hayvanlar)',
          f'{cs} - 16 (Biyoçeşitlilik ve Hayvanlar)']
    om = 'Organik Moleküller'
    t2 = ['İnorganik Moleküller - Su', 'İnorganik Moleküller - Su - Mineral', 'İnorganik Moleküller - Mineral',
          f'{om} - Karbohidrat - 1', f'{om} - Karbohidrat - 2', f'{om} - Lipit', f'{om} - Protein - 1',
          f'{om} - Protein - 2', f'{om} - Enzim - 1', f'{om} - Enzim - 2', f'{om} - Enzim - 3',
          f'{om} - Nükleik Asitler', f'{om} - Vitamin - 1', f'{om} - Vitamin - 2',
          f'{om} - Organik Moleküllerin Ayıraçları', 'Prokaryot ve Ökaryot Hücre'] + \
         [f'Hücrenin Kısımları - {i}' for i in (1, 2, 3)] + \
         [f'Hücre Zarından Madde Geçişleri - {i}' for i in (1, 2, 3)] + \
         ['Hücre, Doku, Organ ve Sistemlerin Organizasyonu']
    cy = 'Canlılarda Yaşamın Devam Etmesi İçin Enerjinin Gerekliliği'
    t3 = [f'{cy} - 1', f'{cy} - 2', 'Fotosentez ve Pigmentler', 'Fotosentez Reaksiyonları - 1',
          'Fotosentez Reaksiyonları - 2', 'Fotosentez Hızına Etki Eden Faktörler - 1',
          'Fotosentez Hızına Etki Eden Faktörler - 2', 'Fotosentezde Üretilen ve Kullanılan Maddeler ile Kemosentez',
          'Fotosentez ve Kemosentez - 1', 'Fotosentez ve Kemosentez - 2'] + \
         [f'Sindirim - {i}' for i in range(1, 8)] + [f'Oksijenli Solunum - {i}' for i in range(1, 7)] + \
         ['Fermantasyon - 1', 'Fermantasyon - 2', 'Enerji - Metabolizma İlişkisi']
    kt = 'Komünitede Tür İçi ve Türler Arası Etkileşimler'
    t4 = ['Ekosistemin Cansız Faktörleri - 1', 'Ekosistemin Canlı Faktörleri - 2'] + \
         [f'{kt} - {i}' for i in (1, 2, 3, 4)] + ['Popülasyon Dinamikleri - 1', 'Popülasyon Dinamikleri - 2',
          'Ekosistemde Madde ve Enerji Akışı', 'Besin Zinciri ve Besin Ağı', 'Ekolojik Piramitler - 1',
          'Ekolojik Piramitler - 2', 'Biyolojik Birikim ve Etkileri'] + \
         [f'Madde Döngüleri - {i}' for i in range(1, 6)] + \
         [f'Ekolojik Sürdürülebilirlik - {i}' for i in range(1, 7)] + \
         ['Ekolojik Ayak İzinin Küçültülmesi', 'Doğal Kaynakların ve Biyoçeşitliliğin Korunması', 'Atık Yönetimi']
    assert (len(t1), len(t2), len(t3), len(t4)) == (26, 23, 26, 27)
    tt = lambda n: [f'Tema Testi - {i}' for i in range(1, n + 1)]
    units = [('1. Tema: Yaşam', 8, t1, tt(5)),
             ('2. Tema: Organizasyon', 72, t2, tt(5) + ['Sarmal Test - 1', 'Sarmal Test - 2']),
             ('3. Tema: Enerji', 134, t3, tt(5) + ['Sarmal Test - 3', 'Sarmal Test - 4']),
             ('4. Tema: Ekoloji', 202, t4, tt(6) + ['Sarmal Test - 5', 'Sarmal Test - 6'])]
    u = sequential(units, 272)
    assert [x['pageEnd'] - 1 for x in u] == [68, 130, 198, 270], [x['pageEnd'] - 1 for x in u]
    return book('Bilgi Sarmal İlk Aşama Biyoloji Soru Bankası', 'Bilgi Sarmal Yayınları', 'TYT', 'Biyoloji', 272, 6, u)


# ─────────────── Bilgi Sarmal İlk Aşama Kimya ───────────────
def kimya():
    kk = 'Kimyasal Maddelerin Kullanımı ve Güvenlik'
    a = [f'Günlük Hayatta Kimya - {i}' for i in (1, 2, 3)] + [f'Kimyanın Alt Disiplinleri - {i}' for i in (1, 2)] + \
        [f'{kk} - {i}' for i in (1, 2, 3, 4, 5)]
    ptb = 'Periyodik Tabloda Yer Bulma, Bazı Gruplar ve Özellikleri'
    b = ['Atom Teorileri ve Atomun Yapısı - 1', 'Atom Teorileri ve Atomun Yapısı - 2',
         'Atom Orbitalleri ve Elektron Dizilimi'] + \
        [f'Atom Orbital Türleri ve Elektron Dağılımı - {i}' for i in (1, 2, 3)] + \
        [f'{ptb} - {i}' for i in (1, 2, 3)] + ['Atomdan İyona - 1', 'Atomdan İyona - 2'] + \
        [f'Periyodik Özellikler - {i}' for i in (1, 2, 3)]
    c = ['Metalik Bağ', 'İyonik Bağ', 'Kovalent Bağ'] + [f'Lewis Nokta Yapısı - {i}' for i in (1, 2, 3)] + \
        [f'Molekül Polarlığı ve Apolarlığı - {i}' for i in (1, 2, 3)] + \
        ['İyonik Bağlı Bileşiklerin Adlandırılması', 'Kovalent Bağlı Bileşiklerin Adlandırılması'] + \
        [f'Moleküller Arası Etkileşimler - {i}' for i in (1, 2, 3, 4)] + ['Katılar'] + \
        [f'Buharlaşma - Denge Buhar Basıncı - {i}' for i in (1, 2)] + \
        [f'Denge Buhar Basıncı - Kaynama Sıcaklığı - {i}' for i in (1, 2)] + \
        ['Viskozite - 1', 'Viskozite - 2', 'Adezyon ve Kohezyon Kuvvetleri', 'Sıvıların Yüzey Gerilimi']
    d = [f'Nanoparçacıklar ve Ekolojik Sürdürülebilirlik - {i}' for i in (1, 2)]
    kh = 'Kimyasal Hesaplamalar'
    e = [f'Kimyasal Değişim Kanıtları - {i}' for i in (1, 2)] + \
        [f'Kimyasal Tepkimelerin Oluşumu - {i}' for i in (1, 2)] + \
        [f'Kimyasal Tepkime Türleri - {i}' for i in (1, 2, 3, 4)] + [f'Mol Kavramı - {i}' for i in range(1, 7)] + \
        [f'Kimyasal Tepkime Denklemlerinin Denkleştirilmesi - {i}' for i in (1, 2)] + \
        [f'{kh} - 1 (Denklemli Mol Hesaplamaları - 1)', f'{kh} - 2 (Denklemli Mol Hesaplamaları - 2)',
         f'{kh} - 3 (Sınırlayıcı Bileşen Hesaplamaları - 1)', f'{kh} - 4 (Sınırlayıcı Bileşen Hesaplamaları - 2)',
         f'{kh} - 5 (Verim Hesaplamaları - 1)', f'{kh} - 6 (Verim Hesaplamaları - 2)'] + \
        [f'Gazların Genel Özellikleri - {i}' for i in (1, 2)] + \
        ['Gaz Yasaları - 1 (Boyle Yasası)', 'Gaz Yasaları - 2 (Charles Yasası)',
         'Gaz Yasaları - 3 (Gay Lussac Yasası - Avogadro Yasası)'] + \
        [f'İdeal Gaz Yasası - {i}' for i in (1, 2, 3)] + \
        [f'Graham Difüzyon ve Efüzyon Yasası - {i}' for i in (1, 2)]
    f = [f'Çözünme Süreci - {i}' for i in (1, 2)] + \
        [f'Maddelerin Birbiri İçerisinde Çözünebilirliği - {i}' for i in (1, 2)] + \
        [f'Çözünme Olayının Sınıflandırılması - {i}' for i in (1, 2)] + [f'Çözünürlük - {i}' for i in (1, 2, 3)] + \
        [f'Çözünürlüğe Etki Eden Faktörler - {i}' for i in (1, 2)] + \
        [f'Çözeltilerin Sınıflandırılması - {i}' for i in (1, 2, 3)] + \
        [f'Derişim Birimleri - {i}' for i in (1, 2)] + [f'Koligatif Özellikler - {i}' for i in (1, 2, 3)]
    g = ['Makro ve Mikro Ölçekli Deneyler - 1', 'Makro ve Mikro Ölçekli Deneyler - 2',
         'Atmosferdeki Tepkimeler ve Küresel Sorunlar']
    assert [len(x) for x in (a, b, c, d, e, f, g)] == [10, 14, 24, 2, 32, 19, 3]
    tt = lambda n: [f'Tema Testi - {i}' for i in range(1, n + 1)]
    units = [('1. Tema (1. Kısım): Kimya Hayattır', 8, a, tt(3)),
             ('1. Tema (2. Kısım): Atomdan Periyodik Tabloya', 36, b, tt(3) + ['Sarmal Test - 1']),
             ('2. Tema: Etkileşimler - Etkileşimlerden Maddeye', 74, c, tt(4) + ['Sarmal Test - 2']),
             ('3. Tema: Nanoparçacıklar ve Ekolojik Sürdürülebilirlik', 134, d, ['Sarmal Test - 3']),
             ('4. Tema: Kimyasal Tepkimeler - Gazlar', 142, e, tt(3) + ['Sarmal Test - 4']),
             ('5. Tema: Çözeltiler', 216, f, tt(3) + ['Sarmal Test - 5']),
             ('6. Tema: Yeşil Kimya, Çevresel ve Ekolojik Sürdürülebilirlik', 264, g, ['Sarmal Test - 6'])]
    u = sequential(units, 272)
    assert [x['pageEnd'] - 1 for x in u] == [32, 70, 130, 138, 212, 260, 270], [x['pageEnd'] - 1 for x in u]
    return book('Bilgi Sarmal İlk Aşama Kimya Soru Bankası', 'Bilgi Sarmal Yayınları', 'TYT', 'Kimya', 272, 6, u)


# ─────────────── Saat Yayınları Dil Bilgisi Saati ───────────────
def dil_bilgisi():
    R = ['Test I', 'Test II', 'Test III']
    def unite(name, s, e): return {'title': name, 'pageStart': s, 'pageEnd': e, 'children': split(s, e, R)}
    bolumler = [
        ('Bölüm 1: Ses Bilgisi, Yazım Kuralları, Noktalama İşaretleri ve Sözcükte Yapı', [
            ('Ses Bilgisi', 6, 13), ('Yazım Kuralları', 14, 19), ('Noktalama İşaretleri', 20, 26),
            ('Sözcükte Yapı', 27, 32), ('Bölüm 1 Karma Test', 33, 38)]),
        ('Bölüm 2: Sözcük Türleri', [
            ('İsim (Ad)', 40, 46), ('Sıfat (Ön Ad)', 47, 53), ('Zamir (Adıl)', 54, 59), ('Zarf (Belirteç)', 60, 67),
            ('Edat (İlgeç) - Bağlaç - Ünlem', 68, 75), ('Eylem (Fiil)', 76, 81), ('Ek Fiil (Ek Eylem)', 82, 87),
            ('Fiil Çatısı (Eylemde Çatı)', 88, 94), ('Fiilimsi (Eylemsi)', 95, 100), ('Bölüm 2 Karma Test', 101, 106)]),
        ('Bölüm 3: Cümle Bilgisi', [
            ('Cümlenin Ögeleri', 108, 114), ('Cümle Türleri ve Yapısı', 115, 120), ('Bölüm 3 Karma Test', 121, 126)]),
        ('Bölüm 4: Anlatım Bozuklukları', [
            ('Anlama Dayalı Anlatım Bozukluğu', 128, 136), ('Yapıya Dayalı Anlatım Bozukluğu', 137, 142),
            ('Bölüm 4 Karma Test', 143, 148)]),
    ]
    units = []
    for name, us in bolumler:
        ch = [unite(n, s, e) for n, s, e in us]
        units.append({'title': name, 'pageStart': ch[0]['pageStart'], 'pageEnd': ch[-1]['pageEnd'], 'children': ch})
    units.append({'title': 'Bölüm 5: Denemeler', 'pageStart': 150, 'pageEnd': 161,
                  'children': split(150, 161, [f'Deneme {i}' for i in range(1, 6)])})
    return book('Dil Bilgisi Saati Soru Bankası', 'Saat Yayınları', 'TYT', 'Türkçe', 168, 5, units)


# ─────────────── Orijinal Matematik Birinci Aşama ───────────────
def matematik():
    def grp(kind, nums, s, e): return split(s, e, [f'{kind} Tema Test {n}' for n in nums])
    B, C, G = 'Bilgi Temelli', 'Beceri Temelli', 'Bağlam Temelli'
    def konu(title, groups):
        leaves = [l for g in groups for l in g]
        return {'title': title, 'pageStart': min(l['pageStart'] for l in leaves),
                'pageEnd': max(l['pageEnd'] for l in leaves), 'children': leaves}
    r = lambda a, b: list(range(a, b + 1))
    t1 = [
        konu('Üslü İfadeler', [grp(B, r(1, 8), 6, 14), grp(C, r(9, 12), 15, 22), grp(G, [13], 23, 25)]),
        konu('Köklü İfadeler', [grp(B, r(1, 6), 26, 33), grp(C, r(7, 11), 34, 43), grp(G, [12], 44, 45)]),
        konu('Sayılar - 1 (Sayı Kümeleri ve Gerçek Sayı Aralıkları)',
             [grp(B, r(1, 9), 46, 57), grp(C, [10, 11], 58, 61), grp(G, [12], 62, 63)]),
        konu('Sayılar - 2', [grp(B, r(13, 19), 64, 71), grp(C, r(20, 22), 72, 77), grp(G, [23], 78, 78)]),
        konu('Bir Doğal Sayının Asal Çarpanları ve Bölen Sayıları',
             [grp(B, r(1, 6), 79, 86), grp(C, [7], 87, 88), grp(G, [8], 89, 90)]),
        konu('EBOB-EKOK', [grp(B, r(1, 4), 91, 95), grp(C, r(5, 8), 96, 102), grp(G, [12], 103, 104)]),
        konu('Bölme ve Bölünebilme', [grp(B, r(1, 6), 105, 115), grp(C, r(7, 9), 116, 121), grp(G, [10], 122, 123)]),
    ]
    t2 = [
        konu('Doğrusal Fonksiyonlar', [grp(B, r(1, 19), 126, 158), grp(C, r(20, 22), 159, 164), grp(G, [23], 165, 166)]),
        konu('Karesel Fonksiyonlar', [grp(B, r(1, 16), 167, 191), grp(C, r(17, 19), 192, 196), grp(G, [20], 197, 199)]),
        konu('Karekök Fonksiyonlar', [grp(B, r(1, 6), 200, 210), grp(C, [7, 8], 211, 214), grp(G, [9], 215, 216)]),
        konu('Rasyonel Fonksiyonlar', [grp(B, r(1, 5), 217, 225), grp(C, [6, 7], 226, 229), grp(G, [8], 230, 230)]),
        konu('Ters Fonksiyonlar', [grp(B, r(1, 7), 231, 243), grp(C, r(8, 10), 244, 248), grp(G, [11], 249, 249)]),
        konu('Fonksiyonlarda İfade Edilebilen Denklem ve Eşitsizlikler İçeren Problemlerin Çözümü',
             [grp(B, r(1, 4), 250, 257), grp(C, [5, 6], 258, 260), grp(G, [7], 261, 261)]),
    ]
    t3 = [
        konu('Algoritma ve Bilişim', [
            grp(B, r(1, 4), 264, 271), grp(C, r(5, 9), 272, 282), grp(G, [10, 11], 283, 286),
            grp(B, [12, 13], 287, 290), grp(C, [14, 15], 291, 294), grp(G, [16], 295, 296),
            grp(B, r(17, 21), 297, 303), grp(C, [22], 304, 305), grp(B, [23], 306, 308),
            grp(C, [24], 309, 311), grp(B, [25], 312, 314)]),
        konu('İstatistiksel Araştırma Süreci', [
            grp(B, r(1, 10), 315, 335), grp(C, [11, 12], 335, 338), grp(G, [13], 339, 340),
            grp(B, r(14, 17), 341, 348), grp(C, [18], 349, 350), grp(G, [19], 351, 353)]),
    ]
    def tema(title, ks): return {'title': title, 'pageStart': ks[0]['pageStart'], 'pageEnd': ks[-1]['pageEnd'], 'children': ks}
    units = [tema('1. Tema: Sayılar', t1), tema('2. Tema: Nicelikler ve Değişimler', t2),
             tema('3. Tema: Algoritma ve Bilişim - İstatistiksel Araştırma Süreci', t3)]
    return book('Orijinal Matematik Birinci Aşama Soru Bankası', 'Orijinal Matematik Yayınları', 'TYT', 'Matematik', 356, 5, units)


def check(doc):
    pc = doc['book']['pageCount']; bad = []
    def walk(n, d, p):
        if not (1 <= n['pageStart'] <= n['pageEnd'] <= pc): bad.append(f'{p}: {n["pageStart"]}-{n["pageEnd"]}')
        if n.get('children'):
            if d + 1 >= 3: bad.append(f'{p}: çok derin')
            for i, c in enumerate(n['children']): walk(c, d + 1, f'{p}/{i}')
    for i, u in enumerate(doc['units']): walk(u, 0, f'U{i}')
    return bad


if __name__ == '__main__':
    out = {'BilgiSarmal_IlkAsama_Fizik': fizik(), 'BilgiSarmal_IlkAsama_Biyoloji': biyoloji(),
           'BilgiSarmal_IlkAsama_Kimya': kimya(), 'Saat_DilBilgisi_Saati': dil_bilgisi(),
           'OrijinalMatematik_BirinciAsama': matematik()}
    total = 0
    for name, doc in out.items():
        b = check(doc); total += len(b)
        for x in b: print('UYARI', name, x)
        json.dump(doc, open(os.path.join(OUT, name + '.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
        leaves = []
        def walk(n):
            if n.get('children'):
                for c in n['children']: walk(c)
            else: leaves.append(n)
        for u in doc['units']: walk(u)
        print(f'{name}: {len(doc["units"])} ana konu, {len(leaves)} test, s. {doc["units"][0]["pageStart"]}–{doc["units"][-1]["pageEnd"]}')
    print('uyarı:', total)
