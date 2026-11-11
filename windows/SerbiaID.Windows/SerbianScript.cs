using System.Text;
using System.Text.RegularExpressions;

namespace SerbiaID;

/// Serbian Latin -> Cyrillic (same rules as scripts/translit_sr.py and Sources/SerbiaID/SerbianScript.swift):
/// letters map one to one (lj, nj, dž are single letters); Serbian acronyms become Cyrillic (PIN, PUK, JMBG, MUP, RS);
/// international acronyms (NFC, USB, PDF, ID, CA), brand names, words with digits, a lone capital after a hyphen (USB-C), placeholders
/// ({0}, %s) and file extensions (.cer .p7s) stay unchanged.
public static class SerbianScript
{
    private static readonly Dictionary<char, char> Lower = new()
    {
        ['a'] = 'а', ['b'] = 'б', ['c'] = 'ц', ['č'] = 'ч', ['ć'] = 'ћ', ['d'] = 'д', ['đ'] = 'ђ', ['e'] = 'е', ['f'] = 'ф',
        ['g'] = 'г', ['h'] = 'х', ['i'] = 'и', ['j'] = 'ј', ['k'] = 'к', ['l'] = 'л', ['m'] = 'м', ['n'] = 'н', ['o'] = 'о',
        ['p'] = 'п', ['r'] = 'р', ['s'] = 'с', ['š'] = 'ш', ['t'] = 'т', ['u'] = 'у', ['v'] = 'в', ['z'] = 'з', ['ž'] = 'ж',
    };
    private static readonly Dictionary<string, char> Digraphs = new() { ["lj"] = 'љ', ["nj"] = 'њ', ["dž"] = 'џ' };
    private static readonly Dictionary<string, string> Acronyms = new() { ["PIN"] = "ПИН", ["PUK"] = "ПУК", ["JMBG"] = "ЈМБГ", ["MUP"] = "МУП", ["RS"] = "РС" };
    private static readonly HashSet<string> International = new() { "NFC", "USB", "PDF", "CMS", "OTG", "CCID", "ID", "CA", "OK", "APDU", "SHA", "RSA", "SIM", "UI", "API" };
    private static readonly HashSet<string> Protected = new()
    {
        "Super", "Celik", "SuperCelik", "Material", "You", "Liquid", "Glass", "iPhone", "iPad", "Mac", "macOS", "iOS",
        "Windows", "Android", "Xcode", "Apollo", "NetSeT", "Veridos", "CardEdge", "Chrome", "Safari", "Firefox",
        "MFi", "Quick", "Look", "GitHub", "Wi", "Fi",
    };
    private static readonly Regex Token = new(@"(https?://\S+)|(\w+)", RegexOptions.Compiled);
    private static readonly Dictionary<string, string> Cache = new();

    private static string Convert(string word)
    {
        var sb = new StringBuilder();
        for (int i = 0; i < word.Length; i++)
        {
            if (i + 1 < word.Length && Digraphs.TryGetValue(word.Substring(i, 2).ToLowerInvariant(), out var d))
            {
                sb.Append(char.IsUpper(word[i]) ? char.ToUpperInvariant(d) : d);
                i++;
                continue;
            }
            char ch = word[i], lo = char.ToLowerInvariant(ch);
            if (Lower.TryGetValue(lo, out var c)) sb.Append(char.IsUpper(ch) ? char.ToUpperInvariant(c) : c);
            else sb.Append(ch);
        }
        return sb.ToString();
    }

    private static string Word(string w, char prev)
    {
        if (prev != '\0' && "%$&\\.{".IndexOf(prev) >= 0) return w;                     // %d  {0}  .cer
        if (Acronyms.TryGetValue(w, out var a)) return a;
        if (w.Any(char.IsDigit) || Protected.Contains(w)) return w;
        if (International.Contains(w)) return w;
        if (w.Length == 1 && w[0] >= 'A' && w[0] <= 'Z' && prev == '-') return w;        // the C in USB-C
        return Convert(w);
    }

    public static string Cyrillic(string text)
    {
        lock (Cache)
        {
            if (Cache.TryGetValue(text, out var hit)) return hit;
            var res = Token.Replace(text, m => m.Groups[1].Success ? m.Value : Word(m.Value, m.Index > 0 ? text[m.Index - 1] : '\0'));
            Cache[text] = res;
            return res;
        }
    }
}
