"""MEB 11. sınıf içindekiler verisini (tool/meb/data*.txt) uygulamanın kitap
şablonu biçimine (assets/templates/*.json) çevirir.

Biçim, her satır bir kayıt:
  #BOOK|başlık|sınav türü|ders|sayfa sayısı
  U|ana konu (ünite/tema)|başlangıç|bitiş
  K|konu|başlangıç          (ana konunun altında)
  A|alt konu|başlangıç      (konunun altında; ayrıca bir düzey yok)

Sayfa aralıkları bir sonraki kaydın başlangıcından hesaplanır; böylece içindekiler
sayfası gibi yalnızca başlangıç numaraları yazmak yeterlidir.
"""
import glob, json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, 'assets', 'templates')
SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)))


def parse(path):
    book = None
    units = []
    for raw in open(path, encoding='utf-8'):
        line = raw.strip()
        if not line or line.startswith('//'):
            continue
        parts = line.split('|')
        tag = parts[0]
        if tag == '#BOOK':
            _, title, exam, subject, pages = parts
            book = dict(title=title, examType=exam, subject=subject, pageCount=int(pages))
        elif tag == 'U':
            start = int(parts[2])
            end = int(parts[3]) if len(parts) > 3 else None
            units.append(dict(title=parts[1], start=start, end=end, konu=[]))
        elif tag == 'K':
            units[-1]['konu'].append(dict(title=parts[1], start=int(parts[2]), alt=[]))
        elif tag == 'A':
            units[-1]['konu'][-1]['alt'].append(dict(title=parts[1], start=int(parts[2])))
        else:
            raise SystemExit(f'{path}: bilinmeyen satır: {line}')
    return book, units


def span(start, nxt_start, limit):
    """start..(nxt_start-1), en az start, en fazla limit."""
    end = (nxt_start - 1) if nxt_start is not None else limit
    return start, max(start, min(end, limit))


def build(book, units):
    nodes = []
    for ui, u in enumerate(units):
        unit_end = u['end'] if u['end'] is not None else (
            units[ui + 1]['start'] - 1 if ui + 1 < len(units) else book['pageCount'])
        children = []
        konu = u['konu']
        for ki, k in enumerate(konu):
            nxt = konu[ki + 1]['start'] if ki + 1 < len(konu) else None
            k_start, k_end = span(k['start'], nxt, unit_end)
            leaves = []
            alts = k['alt']
            for ai, a in enumerate(alts):
                a_nxt = alts[ai + 1]['start'] if ai + 1 < len(alts) else nxt
                a_start, a_end = span(a['start'], a_nxt, unit_end)
                a_end = min(a_end, k_end) if a_nxt == nxt else a_end
                leaves.append({'title': a['title'], 'pageStart': a_start, 'pageEnd': a_end})
            node = {'title': k['title'], 'pageStart': k_start, 'pageEnd': k_end}
            if leaves:
                node['children'] = leaves
            children.append(node)
        nodes.append({'title': u['title'], 'pageStart': u['start'], 'pageEnd': unit_end, 'children': children})
    return {
        'format': 'kocum.book-template',
        'schemaVersion': 1,
        'author': 'kocum',
        'book': {
            'title': book['title'],
            'publisher': 'MEB',
            'examType': book['examType'],
            'subject': book['subject'],
            'pageCount': book['pageCount'],
            'avgQuestionsPerPage': 3,
        },
        'units': nodes,
    }


def check(doc):
    pc = doc['book']['pageCount']
    problems = []

    def walk(n, depth, path):
        s, e = n['pageStart'], n['pageEnd']
        if not (1 <= s <= e <= pc):
            problems.append(f'{path}: sayfa {s}-{e} (kitap {pc})')
        if n.get('children'):
            if depth + 1 >= 3:
                problems.append(f'{path}: çok derin')
            for i, c in enumerate(n['children']):
                walk(c, depth + 1, f'{path}/{i}')
    for i, u in enumerate(doc['units']):
        walk(u, 0, f'U{i}')
    return problems


def main():
    os.makedirs(OUT, exist_ok=True)
    files = sorted(glob.glob(os.path.join(SRC, 'data*.txt')))
    bad = 0
    for f in files:
        book, units = parse(f)
        doc = build(book, units)
        issues = check(doc)
        bad += len(issues)
        for x in issues:
            print('UYARI', os.path.basename(f), x)
        name = 'MEB_11_' + book['subject'].replace(' ', '_').replace('ı', 'i') + '.json'
        with open(os.path.join(OUT, name), 'w', encoding='utf-8') as fh:
            json.dump(doc, fh, ensure_ascii=False, indent=1)
        leaves = sum(len(k.get('children', [])) or 1 for u in doc['units'] for k in u['children'])
        print(f'{name}: {len(doc["units"])} ana konu, {sum(len(u["children"]) for u in doc["units"])} konu, {leaves} yaprak')
    print('toplam uyarı:', bad)
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
