using System;
using System.Linq;

namespace StatsDirect.Charting
{
    ///  <summary>
    ///  A way of carrying ROC series values around the system.
    ///  </summary>
    public class ROCSeriesRecord
    {
        public double[] pdata;
        public double[] adata;
        public double[] tdata;
        public double pmn;
        public double amn;
        public double min;
        public double max;
        public int a;
        public int b;
        public int c;
        public int d;
        public double cutoff;
        public double sens;
        public double spec;
        public double auc;
        public double weight;
        public Comparison comparison;
        public Func<double, double, bool> comparisonFunction;

        public void ReCut()
        {
            a = pdata.Count(value => comparisonFunction(value, cutoff));
            c = pdata.Length - a;
            b = adata.Count(value => comparisonFunction(value, cutoff));
            d = adata.Length - b;
            sens = a / (double)(a + c);
            spec = d / (double)(b + d);
        }


        ///  <summary>
        ///  Copy the values so that an original record can be changed.
        ///  The arrays never change, so a shallow copy is sufficient.
        ///  </summary>
        ///  <returns>The copied object</returns>
        public ROCSeriesRecord Clone()
        {
            return new ROCSeriesRecord
            {
                a = a,
                b = b,
                c = c,
                d = d,
                pdata = pdata,
                adata = adata,
                tdata = tdata,
                pmn = pmn,
                amn = amn,
                min = min,
                max = max,
                cutoff = cutoff,
                spec = spec,
                sens = sens,
                auc = auc,
                comparison = comparison,
                comparisonFunction = comparisonFunction,
                weight = weight
            };
        }
    }
}
