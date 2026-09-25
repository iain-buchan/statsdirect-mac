using System.Globalization;
using StatsDirect.Numerics;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
string line;
while ((line = Console.ReadLine()) != null)
{
    var c = line.Split('\t');
    if (c[0] == "id") continue;
    double x = double.Parse(c[2]), a = double.Parse(c[3]), b = double.Parse(c[4]);
    bool lower = c[5] == "TRUE", log = c[6] == "TRUE";
    int fault = 0;
    double value;
    try
    {
        switch (c[1])
        {
            // These are the unchanged Windows entry points, including their historical argument orders.
            case "pbeta": value = PDF.betain(x, a, b, out fault); break;
            case "qbeta": value = PDF.xinbta(a, b, x, out fault); break;
            case "pf": value = PDF.fvalp(x, a, b); break;
            case "qf": value = PDF.ffromp(b, a, x); break;
            case "pt": value = PDF.tvalp(x, a); break;
            case "qt": value = PDF.tfromp(x, a); break;
            case "pchisq": value = PDF.chivalp(x, a); break;
            case "qchisq": value = PDF.ppchi2(x, a, !lower, out fault); break;
            case "pgamma": value = PDF.gammad(x, a, !lower, out fault); break;
#if MODERN
            case "pf_direct": value = PDF.FProbability(x, a, b, lower, log); break;
            case "qf_direct": value = PDF.FQuantile(x, a, b, lower, log); break;
            case "pt_direct": value = PDF.TProbability(x, a, lower, log); break;
            case "qt_direct": value = PDF.TQuantile(x, a, lower, log); break;
#endif
            default: Console.WriteLine(c[0] + "\tNaN\tunsupported"); continue;
        }
        Console.WriteLine($"{c[0]}\t{value:R}\t{fault}");
    }
    catch (Exception e) { Console.WriteLine($"{c[0]}\tNaN\t{e.GetType().Name}"); }
}
