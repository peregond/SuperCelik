using System.Collections;
using System.Globalization;
using System.Text;

namespace SerbiaID;

/// A tiny JSON reader/writer (objects, arrays, strings, numbers, bools, null) for the .NET 4.0 build, which has no
/// System.Text.Json. Parsed objects are Dictionary&lt;string, object&gt;, arrays List&lt;object&gt;, numbers double.
internal static class MiniJson
{
    public static object Parse(string s)
    {
        int i = 0;
        var v = Value(s, ref i);
        Ws(s, ref i);
        if (i != s.Length) throw new FormatException("JSON: trailing data");
        return v;
    }

    private static void Ws(string s, ref int i) { while (i < s.Length && char.IsWhiteSpace(s[i])) i++; }

    private static object Value(string s, ref int i)
    {
        Ws(s, ref i);
        if (i >= s.Length) throw new FormatException("JSON: unexpected end");
        char c = s[i];
        if (c == '{')
        {
            var d = new Dictionary<string, object>();
            i++; Ws(s, ref i);
            if (s[i] == '}') { i++; return d; }
            while (true)
            {
                Ws(s, ref i);
                var k = Str(s, ref i);
                Ws(s, ref i);
                if (s[i++] != ':') throw new FormatException("JSON: ':' expected");
                d[k] = Value(s, ref i);
                Ws(s, ref i);
                if (s[i] == ',') { i++; continue; }
                if (s[i] == '}') { i++; return d; }
                throw new FormatException("JSON: ',' or '}' expected");
            }
        }
        if (c == '[')
        {
            var l = new List<object>();
            i++; Ws(s, ref i);
            if (s[i] == ']') { i++; return l; }
            while (true)
            {
                l.Add(Value(s, ref i));
                Ws(s, ref i);
                if (s[i] == ',') { i++; continue; }
                if (s[i] == ']') { i++; return l; }
                throw new FormatException("JSON: ',' or ']' expected");
            }
        }
        if (c == '"') return Str(s, ref i);
        if (string.CompareOrdinal(s, i, "true", 0, 4) == 0) { i += 4; return true; }
        if (string.CompareOrdinal(s, i, "false", 0, 5) == 0) { i += 5; return false; }
        if (string.CompareOrdinal(s, i, "null", 0, 4) == 0) { i += 4; return null; }
        int st = i;
        while (i < s.Length && "+-0123456789.eE".IndexOf(s[i]) >= 0) i++;
        if (i == st) throw new FormatException("JSON: unexpected character");
        return double.Parse(s.Substring(st, i - st), CultureInfo.InvariantCulture);
    }

    private static string Str(string s, ref int i)
    {
        if (s[i] != '"') throw new FormatException("JSON: string expected");
        i++;
        var sb = new StringBuilder();
        while (true)
        {
            if (i >= s.Length) throw new FormatException("JSON: unterminated string");
            char c = s[i++];
            if (c == '"') return sb.ToString();
            if (c != '\\') { sb.Append(c); continue; }
            char e = s[i++];
            switch (e)
            {
                case 'n': sb.Append('\n'); break;
                case 'r': sb.Append('\r'); break;
                case 't': sb.Append('\t'); break;
                case 'b': sb.Append('\b'); break;
                case 'f': sb.Append('\f'); break;
                case 'u': sb.Append((char)Convert.ToInt32(s.Substring(i, 4), 16)); i += 4; break;
                default: sb.Append(e); break;   // " \ /
            }
        }
    }

    /// Copies the values of a parsed object into the public settable properties of `target`.
    public static T Populate<T>(T target, object tree)
    {
        var d = tree as Dictionary<string, object>;
        if (d == null) return target;
        foreach (var p in typeof(T).GetProperties())
        {
            object v;
            if (!p.CanWrite || !d.TryGetValue(p.Name, out v) || v == null) continue;
            try
            {
                if (p.PropertyType == typeof(string) && v is string) p.SetValue(target, v, null);
                else if (p.PropertyType == typeof(bool) && v is bool) p.SetValue(target, v, null);
                else if (p.PropertyType == typeof(int) && v is double) p.SetValue(target, (int)(double)v, null);
                else if (p.PropertyType == typeof(double) && v is double) p.SetValue(target, v, null);
            }
            catch { }
        }
        return target;
    }

    /// The public readable properties of `o` as an ordered tree (NaN / infinity become null).
    public static object ToTree(object o)
    {
        var d = new Dictionary<string, object>();
        foreach (var p in o.GetType().GetProperties())
        {
            if (!p.CanRead || p.GetIndexParameters().Length > 0) continue;
            var v = p.GetValue(o, null);
            if (v is double && (double.IsNaN((double)v) || double.IsInfinity((double)v))) v = null;
            d[p.Name] = v;
        }
        return d;
    }

    // ---- writer (indented, non-ASCII kept as is) ----

    public static string Write(object v)
    {
        var sb = new StringBuilder();
        Put(sb, v, 0);
        return sb.ToString();
    }

    private static void Put(StringBuilder sb, object v, int depth)
    {
        string ind = new string(' ', (depth + 1) * 2), end = new string(' ', depth * 2);
        if (v == null) sb.Append("null");
        else if (v is string str) Quote(sb, str);
        else if (v is bool b) sb.Append(b ? "true" : "false");
        else if (v is double dd) sb.Append(dd.ToString("R", CultureInfo.InvariantCulture));
        else if (v is IDictionary dict)
        {
            if (dict.Count == 0) { sb.Append("{}"); return; }
            sb.Append("{\n");
            bool first = true;
            foreach (DictionaryEntry e in dict)
            {
                if (!first) sb.Append(",\n");
                first = false;
                sb.Append(ind); Quote(sb, (string)e.Key); sb.Append(": "); Put(sb, e.Value, depth + 1);
            }
            sb.Append('\n').Append(end).Append('}');
        }
        else if (v is IEnumerable en)
        {
            var items = en.Cast<object>().ToList();
            if (items.Count == 0) { sb.Append("[]"); return; }
            sb.Append("[\n");
            for (int k = 0; k < items.Count; k++)
            {
                sb.Append(ind); Put(sb, items[k], depth + 1);
                sb.Append(k + 1 < items.Count ? ",\n" : "\n");
            }
            sb.Append(end).Append(']');
        }
        else sb.Append(Convert.ToString(v, CultureInfo.InvariantCulture));   // int, long
    }

    private static void Quote(StringBuilder sb, string s)
    {
        sb.Append('"');
        foreach (var c in s)
            switch (c)
            {
                case '"': sb.Append("\\\""); break;
                case '\\': sb.Append("\\\\"); break;
                case '\n': sb.Append("\\n"); break;
                case '\r': sb.Append("\\r"); break;
                case '\t': sb.Append("\\t"); break;
                default:
                    if (c < 0x20) sb.Append("\\u").Append(((int)c).ToString("x4"));
                    else sb.Append(c);
                    break;
            }
        sb.Append('"');
    }
}
