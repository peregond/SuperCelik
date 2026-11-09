using System.Text;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace SerbiaID;

/// Minimal single-page A4 PDF writer: the print sheet is rendered to a high-resolution JPEG
/// and embedded as an image (no external PDF library, no printer driver needed).
internal static class PdfWriter
{
    public static void SaveSheet(FrameworkElement sheet, string path)
    {
        const double dpi = 200;
        int w = (int)Math.Round(sheet.Width / 96 * dpi), h = (int)Math.Round(sheet.Height / 96 * dpi);
        var rtb = new RenderTargetBitmap(w, h, dpi, dpi, PixelFormats.Pbgra32);
        rtb.Render(sheet);
        var enc = new JpegBitmapEncoder { QualityLevel = 92 };
        enc.Frames.Add(BitmapFrame.Create(rtb));
        using var jpegMs = new MemoryStream();
        enc.Save(jpegMs);
        File.WriteAllBytes(path, Build(jpegMs.ToArray(), w, h));
    }

    private static byte[] Build(byte[] jpeg, int w, int h)
    {
        using var ms = new MemoryStream();
        var offsets = new List<long>();
        void W(string s) { var b = Encoding.ASCII.GetBytes(s); ms.Write(b, 0, b.Length); }
        void Obj(int n, string body) { offsets.Add(ms.Position); W($"{n} 0 obj\n{body}\nendobj\n"); }

        W("%PDF-1.4\n%âãÏÓ\n");
        Obj(1, "<< /Type /Catalog /Pages 2 0 R >>");
        Obj(2, "<< /Type /Pages /Kids [3 0 R] /Count 1 >>");
        Obj(3, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595.28 841.89] /Contents 4 0 R /Resources << /XObject << /Im0 5 0 R >> >> >>");
        const string content = "q 595.28 0 0 841.89 0 0 cm /Im0 Do Q";
        Obj(4, $"<< /Length {content.Length} >>\nstream\n{content}\nendstream");

        offsets.Add(ms.Position);
        W($"5 0 obj\n<< /Type /XObject /Subtype /Image /Width {w} /Height {h} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length {jpeg.Length} >>\nstream\n");
        ms.Write(jpeg, 0, jpeg.Length);
        W("\nendstream\nendobj\n");

        long xref = ms.Position;
        W($"xref\n0 {offsets.Count + 1}\n0000000000 65535 f \n");
        foreach (var o in offsets) W($"{o:D10} 00000 n \n");
        W($"trailer\n<< /Size {offsets.Count + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n");
        return ms.ToArray();
    }
}
