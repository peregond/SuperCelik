#!/usr/bin/env python3
"""Serbian Latin -> Cyrillic transliteration used to build the Cyrillic UI strings.

The same rules are implemented at run time in Swift (Sources/SerbiaID/SerbianScript.swift) and C#
(windows/SerbiaID.Windows/SerbianScript.cs); Android's res/values-sr/strings.xml (Cyrillic) is generated from
res/values-b+sr+Latn/strings.xml with:  python3 scripts/translit_sr.py android <latin.xml> <cyrillic.xml>

Rules
- letters map one to one; lj, nj, dž are single Cyrillic letters (љ, њ, џ);
- Serbian acronyms become Cyrillic (PIN -> ПИН, PUK -> ПУК, JMBG -> ЈМБГ, MUP -> МУП, RS -> РС);
- international acronyms (NFC, USB, PDF, CMS, OTG, ID, CA...), brand/product names, words with digits, a single capital
  after a hyphen (USB-C), printf/XML placeholders (%s %d %@ &amp; \\n) and file extensions (.cer .p7s) stay as they are.
"""
import re, sys

LOWER = {'a':'а','b':'б','c':'ц','č':'ч','ć':'ћ','d':'д','đ':'ђ','e':'е','f':'ф','g':'г','h':'х','i':'и','j':'ј','k':'к',
         'l':'л','m':'м','n':'н','o':'о','p':'п','r':'р','s':'с','š':'ш','t':'т','u':'у','v':'в','z':'з','ž':'ж'}
UPPER = {k.upper(): v.upper() for k, v in LOWER.items()}
DIGRAPHS = {'lj': 'љ', 'nj': 'њ', 'dž': 'џ'}
ACRONYMS = {'PIN': 'ПИН', 'PUK': 'ПУК', 'JMBG': 'ЈМБГ', 'MUP': 'МУП', 'RS': 'РС'}
INTERNATIONAL = {'NFC', 'USB', 'PDF', 'CMS', 'OTG', 'CCID', 'ID', 'CA', 'OK', 'APDU', 'SHA', 'RSA', 'SIM', 'UI', 'API'}
PROTECTED = {'Super', 'Celik', 'SuperCelik', 'Material', 'You', 'Liquid', 'Glass', 'iPhone', 'iPad', 'Mac', 'macOS', 'iOS',
             'Windows', 'Android', 'Xcode', 'Apollo', 'NetSeT', 'Veridos', 'CardEdge', 'Chrome', 'Safari', 'Firefox',
             'MFi', 'Quick', 'Look', 'GitHub', 'Wi', 'Fi'}
WORD = re.compile(r"\w+", re.UNICODE)
URL = re.compile(r"(https?://\S+)")

def _convert(word):
    out, i = [], 0
    while i < len(word):
        pair = word[i:i + 2]
        if len(pair) == 2 and pair.lower() in DIGRAPHS:
            c = DIGRAPHS[pair.lower()]
            out.append(c.upper() if pair[0].isupper() else c)
            i += 2
            continue
        ch = word[i]
        out.append(LOWER.get(ch) or UPPER.get(ch) or ch)
        i += 1
    return ''.join(out)

def _word(text, m):
    w, start = m.group(0), m.start()
    prev = text[start - 1] if start > 0 else ''
    if prev in ('%', '$', '&', '\\', '.'):                      # %d  %@  &amp;  \n  .cer
        return w
    if w in ACRONYMS:
        return ACRONYMS[w]
    if any(ch.isdigit() for ch in w) or w in PROTECTED:
        return w
    if w in INTERNATIONAL or (len(w) == 1 and w.isascii() and w.isupper() and prev == '-'):   # NFC, USB, the C in USB-C
        return w
    return _convert(w)

def translit(text):
    return ''.join(p if URL.fullmatch(p) else WORD.sub(lambda m, p=p: _word(p, m), p) for p in URL.split(text))

def android(src, dst):
    xml = open(src, encoding='utf-8').read()
    def one(m):
        name, body = m.group(1), m.group(2)
        return m.group(0) if name == 'app_name' else f'<string name="{name}">{translit(body)}</string>'
    open(dst, 'w', encoding='utf-8').write(re.sub(r'<string name="([^"]+)">(.*?)</string>', one, xml, flags=re.S))

if __name__ == '__main__':
    if len(sys.argv) == 4 and sys.argv[1] == 'android':
        android(sys.argv[2], sys.argv[3])
    else:
        for line in sys.stdin:
            print(translit(line.rstrip('\n')))
