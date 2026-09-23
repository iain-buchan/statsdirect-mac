using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Text;

namespace StatsDirect.TemplateProcessing
{
    public static class RtfImageConverter
    {
        const float RTF_IMAGE_WIDTH = 6.0F; // Inches

        /// <summary>
        /// The number of hundredths of millimeters (0.01 mm) in an inch.
        /// </summary>
        private const int HMM_PER_INCH = 2540;

        /// <summary>
        /// The number of twips in an inch.
        /// </summary>
        private const int TWIPS_PER_INCH = 1440;

        /* RTF HEADER
         * ----------
         * 
         * \rtf[N]		- For text to be considered to be RTF, it must be enclosed in this tag.
         *				  rtf1 is used because the RichTextBox conforms to RTF Specification
         *				  version 1.
         * \ansi		- The character set.
         * \ansicpg[N]	- Specifies that unicode characters might be embedded. ansicpg1252
         *				  is the default used by Windows.
         * \deff[N]		- The default font. \deff0 means the default font is the first font
         *				  found.
         * \deflang[N]	- The default language. \deflang1033 specifies US English.
         */
        private const string RTF_HEADER = @"{\rtf1\ansi\ansicpg1252\deff0\deflang1033";
        private const string RTF_FOOTER = "}";


        public static string MetastreamToRtf(Stream metaStream, int widthInPixels, int heightInPixels)
        {
            StringBuilder rtf = new();

            // Append the RTF header
            rtf.Append(RTF_HEADER);

            float desiredPixelsPerInch = (float)Math.Ceiling(widthInPixels / RTF_IMAGE_WIDTH);
            float widthInInches = widthInPixels / desiredPixelsPerInch;
            float heightInInches = heightInPixels / desiredPixelsPerInch;

            // Calculate the current width and height of the image in (0.01)mm
            // TODO: HACK: Remove 2.6 bodge factor that's needed for approximately correct display when reloaded in XtraRichEdit.
            int picw = (int)Math.Round(widthInInches * HMM_PER_INCH * 2.6);
            int pich = (int)Math.Round(heightInInches * HMM_PER_INCH * 2.6);

            // Calculate the target width and height of the image in twips
            int picwgoal = (int)Math.Round(widthInInches * TWIPS_PER_INCH);
            int pichgoal = (int)Math.Round(heightInInches * TWIPS_PER_INCH);

            // Append values to RTF string
            rtf.Append(@"{\pict");
            rtf.Append(@"\emfblip");
            rtf.Append(@"\picw");
            rtf.Append(picw);
            rtf.Append(@"\pich");
            rtf.Append(pich);
            rtf.Append(@"\picwgoal");
            rtf.Append(picwgoal);
            rtf.Append(@"\pichgoal");
            rtf.Append(pichgoal);
            rtf.Append(" ");

            // Append its bytes in hex
            while (true)
            {
                int i = metaStream.ReadByte();
                if (-1 == i)
                    break;
                rtf.Append($"{i:X2}");
            }

            // Close the RTF image control string
            rtf.Append("}");
            rtf.Append(RTF_FOOTER);

            return rtf.ToString();
        }

        public static Image ParseRtfToImage(string rtf, out byte[] rawBytes)
        {
            string[] parts = rtf.Split(new[] { '\\', '\r', '\n', ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
            ImageFormat imageFormat = null;
            using MemoryStream bytes = new();
            foreach (string s in parts)
            {
                if (s.StartsWith("wmetafile"))
                {
                    imageFormat = ImageFormat.Emf;
                    int.TryParse(s.Substring(9), out int _);
                }
                else if (s.StartsWith("pngblip"))
                    imageFormat = ImageFormat.Png;
                else if (s.StartsWith("picwgoal"))
                {
                    int.TryParse(s.Substring(8), out int _);
                }
                else if (s.StartsWith("pichgoal"))
                {
                    int.TryParse(s.Substring(8), out int _);
                }
                else if (s.StartsWith("picw"))
                {
                    int.TryParse(s.Substring(4), out int _);
                }
                else if (s.StartsWith("pich"))
                {
                    int.TryParse(s.Substring(4), out int _);
                }
                else if (s.StartsWith("emfblip"))
                {
                    imageFormat = ImageFormat.Emf;
                }
                else if (s.StartsWith("picscale"))
                {
                    // Do nothing
                }
                else if (s.Length < 16)
                {
                    if (IsHex(s))
                    {
                        AccumulateHex(bytes, s);
                    }
                    // Else not a header value we know, and less than an 8-byte hex value - so a very small image!
                    // Assume another header value that we don't yet know about.
                    // On the principle of "be liberal in what you accept", ignore it.
                }
                else
                {
                    // Assume bytes encoded as hex
                    AccumulateHex(bytes, s);
                }
            }
            rawBytes = bytes.ToArray();
            bytes.Position = 0;
            Image img = null;
            if (imageFormat == ImageFormat.Emf)
            {
                img = Image.FromStream(bytes);
            }
            else if (imageFormat == ImageFormat.Png)
            {
                img = Image.FromStream(bytes);
            }
            return img;
        }

        private static bool IsHex(string s)
        {
            foreach (char c in s)
                if (!(c >= '0' && c <= '9' || c >= 'A' && c <= 'F' || c >= 'a' && c <= 'f'))
                    return false;
            return true;
        }

        private static void AccumulateHex(MemoryStream bytes, string s)
        {
            for (int i = 0; i < s.Length; i += 2)
            {
                int hiChar = s[i] - 48; // 48 is ASCII '0'
                if (hiChar > 9) hiChar -= 7; // 65 is ASCII 'A' = 10.  48 already subtracted, so need to subtract (65 - 10 - 48) = 7.
                if (hiChar > 15) hiChar -= 32; // 97 is ASCII 'a' = 10.  65 already subtracted, so need to subtract (97 - 65) = 32.
                if (hiChar > 15 || hiChar < 0)
                    throw new ArgumentException("Unexpected non-hex character '" + s[i] + "' in hex string");

                int loChar = s[i + 1] - 48; // 48 is ASCII '0'
                if (loChar > 9) loChar -= 7; // 65 is ASCII 'A' = 10.  48 already subtracted, so need to subtract (65 - 10 - 48) = 7.
                if (loChar > 15) loChar -= 32; // 97 is ASCII 'a' = 10.  65 already subtracted, so need to subtract (97 - 65) = 32.
                if (loChar > 15 || loChar < 0)
                    throw new ArgumentException("Unexpected non-hex character '" + s[i + 1] + "' in hex string");
                byte b = (byte)(hiChar * 16 + loChar);
                bytes.WriteByte(b);
            }
        }
    }
}
