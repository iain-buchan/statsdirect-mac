using System;

using StatsDirect.Numerics;

namespace StatsDirect.Builtins
{
    public static class Matrix
    {

        ///  <summary>
        ///  work out the sorted permutation (iperm) of a matrix (x) sorted by column on key rows (indicated in indkey)
        ///  </summary>
        ///  <param name="nrx">Number of columns in x</param>
        ///  <param name="ncx">Number of rows in x</param>
        ///  <param name="x"></param>
        ///  <param name="nkey"></param>
        ///  <param name="indkey"></param>
        ///  <param name="iperm"></param>
        ///  <param name="ngroup"></param>
        ///  <param name="ni"></param>
        ///  <param name="ifault"></param>
        ///  <remarks></remarks>
        public static void MXSRT(int nrx, int ncx, double[] x, int nkey, int[] indkey, int[] iperm, ref int ngroup, int[] ni, ref int ifault)
        {
            int i = ncx > nrx ? ncx : nrx;
            double[] wk = new double[4 * i + 1];
            int[] iwk = new int[i + Convert.ToInt32(2.8854 * Math.Log(i)) + 2 + 1];

            if (nrx <= 0)
                ifault = 1;
            if (ncx <= 0)
                ifault = 2;
            if (nkey <= 0)
                ifault = 3;
            // int ner = 9; 
            int k1 = 0;
            for (i = 1; i <= nkey; i++)
                if (indkey[i] < 1 | nrx > 0 & indkey[i] > nrx)
                    k1 += 1;
            if (k1 > 0)
            {
                ifault = 1;
                if (k1 > 1)
                    ifault = 2;
            }
            if (ifault != 0)
                return;

            int ljr = nrx;
            int lir = ncx;
            int ix = 1;
            int ib = 0;
            for (i = 1; i <= lir; i++)
            {
                iperm[ix] = 1 + ib;
                ix += 1;
                ib += 1;
            }
            ix = 1;
            ib = 0;
            for (i = 1; i <= ljr; i++)
            {
                iwk[ix] = 1 + ib;
                ix += 1;
                ib += 1;
            }
            for (i = 1; i <= nkey; i++)
                iwk[indkey[i]] = -i;

            iqsort(ljr, iwk, iwk);
            int ibeg = 1;
            int iend = nkey;
            for (i = 1; i <= nkey / 2; i++)
            {
                int itemp = iwk[ibeg];
                iwk[ibeg] = iwk[iend];
                iwk[iend] = itemp;
                ibeg += 1;
                iend -= 1;
            }
            for (i = 1; i <= nkey; i++)
            {
                int iu = -iwk[i];
                iwk[i] = indkey[iu];
            }
            pmurc(nrx, ncx, x, iwk, 1, x, wk, ref ifault);
            int nn = nrx > ncx ? nrx : ncx;
            int nstk = (int)Math.Floor(1.4427 * Math.Log(Convert.ToDouble(nn)) + 1);
            MXSRT2(x, nrx, ncx, nkey, iperm, wk, iwk, nn, nn + nstk);
            ix = 1;
            int iy = 1;
            for (i = 1; i <= ljr; i++)
            {
                wk[iy] = iwk[ix];
                ix += 1;
                iy += 1;
            }
            ix = 1;
            ib = 0;
            for (i = 1; i <= ljr; i++)
            {
                iwk[ix] = 1 + ib;
                ix += 1;
                ib += 1;
            }
            dqsortperm(ljr, wk, wk, iwk);
            pmurc(nrx, ncx, x, iwk, 1, x, wk, ref ifault);
            int lind = 0;
            i = 1;
            while (i <= lir)
            {
                int icnt = 0;
                if (iperm[i] < 0)
                {
                    while (i <= lir)
                    {
                        if (iperm[i] < 0)
                        {
                            iperm[i] = -iperm[i];
                            icnt += 1;
                            i += 1;
                        }
                        else
                        {
                            break;
                        }
                    }
                }
                else
                {
                    while (i <= lir)
                    {
                        if (iperm[i] > 0)
                        {
                            icnt += 1;
                            i += 1;
                        }
                        else
                        {
                            break;
                        }
                    }
                }
                lind += 1;
                ni[lind] = icnt;
            }
            ngroup = lind;
            ix = 1;
            iy = 1;
            for (i = 1; i <= lir; i++)
            {
                wk[iy] = iperm[ix];
                ix += 1;
                iy += 1;
            }
            ix = 1;
            ib = 0;
            for (i = 1; i <= lir; i++)
            {
                iperm[ix] = 1 + ib;
                ix += 1;
                ib += 1;
            }
            dqsortperm(lir, wk, wk, iperm);
            pmurc(nrx, ncx, x, iperm, 2, x, wk, ref ifault);
            ix = 1;
            iy = 1;
            for (i = 1; i <= lir; i++)
            {
                wk[iy] = iperm[ix];
                ix += 1;
                iy += 1;
            }
            ix = 1;
            ib = 0;
            for (i = 1; i <= lir; i++)
            {
                iperm[ix] = 1 + ib;
                ix += 1;
                ib += 1;
            }
            dqsortperm(lir, wk, wk, iperm);
        }

        ///  <summary>
        ///  nucleus called by mxsrt which sorts a matrix wrt vectors
        ///  </summary>
        ///  <param name="x"></param>
        ///  <param name="nrx"></param>
        ///  <param name="ncx"></param>
        ///  <param name="nkey"></param>
        ///  <param name="iperm"></param>
        ///  <param name="WK"></param>
        ///  <param name="istk"></param>
        ///  <param name="ix1"></param>
        ///  <param name="ix2"></param>
        ///  <remarks></remarks>
        private static void MXSRT2(double[] x, int nrx, int ncx, int nkey, int[] iperm, double[] WK, int[] istk, int ix1, int ix2)
        {
            int nr1 = nrx;
            int nk1 = nkey;
            int jcol1 = 1;
            int jcol2 = ncx;
            int irow1 = 1;
            int irow2 = nk1;
            int jcolx = Math.Min(jcol1, jcol2);
            int jcoly = Math.Max(jcol1, jcol2);
            int irowx = Math.Min(irow1, irow2);
            int kr = Math.Max(irow2 - irow1 + 1, 0);
            int m = 1;
            int i = jcolx;
            int j = jcoly;
            double r = 0.375;
            const double r1 = 0.5898437;
            const double ur = 0.0390625;
            const double dr = 0.21875;
            if (r <= r1)
                r += ur;
            else
                r -= dr;

            do
            {
                if (i == j)
                {
                    m -= 1;
                    if (m == 0)
                    {
                        if (ncx >= 2)
                        {
                            for (i = 2; i <= ncx; i++)
                            {
                                int ij = ncx - i + 2;
                                if (CompareVectors(kr, x, irowx + (ij - 2) * nrx, x, irowx + (ij - 1) * nrx) == 0)
                                {
                                    if (iperm[ij] < 0)
                                        iperm[ij - 1] = -iperm[ij - 1];
                                }
                                else
                                {
                                    if (iperm[ij] > 0)
                                        iperm[ij - 1] = -iperm[ij - 1];
                                }
                            }
                        }
                        return;
                    }
                    i = istk[m + ix2];
                    j = istk[m + ix1];
                }
                else
                {
                    int k = i;
                    int ij = (int)Math.Floor(i + (j - i) * r);
                    int iix = 1;
                    int iiw = 1;
                    for (int ii = 1; ii <= nr1; ii++)
                    {
                        WK[iiw] = x[iix + (ij - 1) * nrx];
                        iiw += 1;
                        iix += 1;
                    }
                    int it = iperm[ij];
                    int kompar = CompareVectors(kr, x, irowx + (i - 1) * nrx, WK, irowx);
                    if (kompar != -1 && kompar != 0)
                    {
                        for (int ii = 1; ii <= nr1; ii++)
                        {
                            x[ii + (ij - 1) * nrx] = x[ii + (i - 1) * nrx];
                            x[ii + (i - 1) * nrx] = WK[ii];
                            WK[ii] = x[ii + (ij - 1) * nrx];
                        }
                        iperm[ij] = iperm[i];
                        iperm[i] = it;
                        it = iperm[ij];
                    }
                    int l = j;
                    kompar = CompareVectors(kr, x, irowx + (j - 1) * nrx, WK, irowx);
                    if (kompar != 1 && kompar != 0)
                    {
                        for (int ii = 1; ii <= nr1; ii++)
                            x[ii + (ij - 1) * nrx] = x[ii + (j - 1) * nrx];
                        iix = 1;
                        iiw = 1;
                        for (int ii = 1; ii <= nr1; ii++)
                        {
                            x[iix + (j - 1) * nrx] = WK[iiw];
                            WK[iiw] = x[iix + (ij - 1) * nrx];
                            iiw += 1;
                            iix += 1;
                        }
                        iperm[ij] = iperm[j];
                        iperm[j] = it;
                        it = iperm[ij];
                        kompar = CompareVectors(kr, x, irowx + (i - 1) * nrx, WK, irowx);
                        if (kompar != -1 && kompar != 0)
                        {
                            for (int ii = 1; ii <= nr1; ii++)
                            {
                                x[ii + (ij - 1) * nrx] = x[ii + (i - 1) * nrx];
                                x[ii + (i - 1) * nrx] = WK[ii];
                                WK[ii] = x[ii + (ij - 1) * nrx];
                            }
                            iperm[ij] = iperm[i];
                            iperm[i] = it;
                            it = iperm[ij];
                        }
                    }
                    do
                    {
                        do
                        {
                            l -= 1;
                            if (CompareVectors(kr, x, irowx + (l - 1) * nrx, WK, irowx) != 1)
                                break;
                        }
                        while (true);
                        do
                        {
                            k += 1;
                            if (CompareVectors(kr, x, irowx + (k - 1) * nrx, WK, irowx) != -1)
                                break;
                        }
                        while (true);
                        if (k > l)
                            break;

                        if (CompareVectors(kr, x, irowx + (l - 1) * nrx, x, irowx + (k - 1) * nrx) != 0)
                        {
                            for (int ii = 1; ii <= nr1; ii++)
                            {
                                WK[nr1 + ii] = x[ii + (l - 1) * nrx];
                                x[ii + (l - 1) * nrx] = x[ii + (k - 1) * nrx];
                                x[ii + (k - 1) * nrx] = WK[nr1 + ii];
                            }
                            int itt = iperm[l];
                            iperm[l] = iperm[k];
                            iperm[k] = itt;
                        }
                    }
                    while (true);
                    if (l - i <= j - k)
                    {
                        istk[m + ix2] = k;
                        istk[m + ix1] = j;
                        j = l;
                        m += 1;
                    }
                    else
                    {
                        istk[m + ix2] = i;
                        istk[m + ix1] = l;
                        i = k;
                        m += 1;
                    }
                }
                if (j - i < 11)
                {
                    if (i != jcolx)
                    {
                        i -= 1;
                        do
                        {
                            i += 1;
                            if (i == j)
                                break;
                            for (int ii = 1; ii <= nr1; ii++)
                                WK[ii] = x[ii + i * nrx];
                            int it = iperm[i + 1];
                            int kompar = CompareVectors(kr, x, irowx + (i - 1) * nrx, WK, irowx);
                            if (kompar != -1 & kompar != 0)
                            {
                                int k = i;
                                do
                                {
                                    for (int ii = 1; ii <= nr1; ii++)
                                        x[ii + k * nrx] = x[ii + (k - 1) * nrx];
                                    iperm[k + 1] = iperm[k];
                                    k -= 1;
                                    kompar = CompareVectors(kr, WK, irowx, x, irowx + (k - 1) * nrx);
                                    if (kompar != -1)
                                        break;
                                }
                                while (true);
                                for (int ii = 1; ii <= nr1; ii++)
                                    x[ii + k * nrx] = WK[ii];
                                iperm[k + 1] = it;
                            }
                        }
                        while (true);
                    }
                }
                else
                {
                    if (r <= r1)
                        r += ur;
                    else
                        r -= dr;
                }
            }
            while (true);
        }

        ///  <summary>
        ///  nucleus called by mxsrt that compares two vectors
        ///  </summary>
        ///  <param name="n">Number of elements to compare</param>
        ///  <param name="sx">Array where -1 will be returned if this is less than sy</param>
        ///  <param name="ix">Index of first element to compare in sx</param>
        ///  <param name="sy">Array where 1 will be returned if this is greater than sy</param>
        ///  <param name="iy">Index of first element to compare in sy</param>
        ///  <returns>-1 if sx < sy, 0 if sx = sy, 1 if sx > sy</sy></returns>
        private static int CompareVectors(int n, double[] sx, int ix, double[] sy, int iy)
        {
            for (int i = 0; i < n; i++)
                if (!(sx[ix + i] == sy[iy + i]))
                    return sx[ix + i] < sy[iy + i] ? -1 : 1;
            // If we get here, we have not found any unequal values
            return 0;
        }

        /// <summary>
        /// permute the rows or columns of a matrix
        /// </summary>
        /// <param name="nra"></param>
        /// <param name="nca"></param>
        /// <param name="a"></param>
        /// <param name="ipermu"></param>
        /// <param name="ipath"></param>
        /// <param name="aper"></param>
        /// <param name="work"></param>
        /// <param name="ifault"></param>
        private static void pmurc(int nra, int nca, double[] a, int[] ipermu, int ipath, double[] aper, double[] work, ref int ifault)
        {
            if (nra <= 0)
                ifault = 1;
            if (nca <= 0)
                ifault = 2;
            //if ( nra > nra )
            //{ 
            //    ifault = 3; 
            //} 
            if (ifault != 0)
                return;

            if (ipath == 1)
            {
                for (int j = 1; j <= nca; j++)
                    vprmuf(nra, a, 1 + (j - 1) * nra, ipermu, aper, 1 + (j - 1) * nra, ref ifault);
            }
            else if (ipath == 2)
            {
                for (int i = 1; i <= nra; i++)
                {
                    for (int j = 1; j <= nca; j++)
                        work[j] = a[i + (j - 1) * nra];
                    vprmuf(nca, work, 1, ipermu, work, 1, ref ifault);
                    for (int j = 1; j <= nca; j++)
                        aper[i + (j - 1) * nra] = work[j];
                }
            }
            else
            {
                ifault = 7;
            }
        }

        /// <summary>
        /// rearrange vector by forward permutation
        /// </summary>
        /// <param name="n"></param>
        /// <param name="x"></param>
        /// <param name="ix"></param>
        /// <param name="ipermu"></param>
        /// <param name="xpermu"></param>
        /// <param name="ipx"></param>
        /// <param name="ifault"></param>
        private static void vprmuf(int n, double[] x, int ix, int[] ipermu, double[] xpermu, int ipx, ref int ifault)
        {
            if (n <= 0)
                return;

            for (int i = 0; i < n; i++)
                xpermu[ipx + i] = x[ix + i];

            if (n == 1)
                return;

            for (int i = 1; i <= n; i++)
            {
                if (ipermu[i] < 1 || ipermu[i] > n)
                    ifault = 4;
                else
                    ipermu[i] = -ipermu[i];
            }
            if (ifault != 0)
                return;

            int ipxm1 = ipx - 1;
            for (int i = 1; i <= n; i++)
            {
                if (ipermu[i] <= 0)
                {
                    int j = i;
                    ipermu[j] = -ipermu[j];
                    int k = ipermu[j];
                    while (ipermu[k] <= 0)
                    {
                        double temp = xpermu[ipxm1 + j];
                        xpermu[ipxm1 + j] = xpermu[ipxm1 + k];
                        xpermu[ipxm1 + k] = temp;
                        ipermu[k] = -ipermu[k];
                        j = k;
                        k = ipermu[k];
                    }
                }
            }
        }

        /// <summary>
        /// sort an ix (indices 1..n) in increasing order, returning in iy.
        /// </summary>
        /// <param name="n">Number of elements to sort, starting from index 1.</param>
        /// <param name="ix">Unsorted input array; unchanged.</param>
        /// <param name="iy">Preallocated output array of at least n+1 elements. Returned with elements 1..n of ix sorted in increasing order.</param>
        /// <remarks>Singleton, R. C., Algorithm 347, An Efficient Algorithm for Sorting with Minimal Storage, CACM,12(3),1969,185-7.</remarks>
        private static void iqsort(int n, int[] ix, int[] iy)
        {
            int[] il = new int[22];
            int[] iu = new int[22];
            int i;

            for (i = 1; i <= n; i++)
                iy[i] = ix[i];
            if (n <= 0)
                return;
            int m = 1;
            i = 1;
            int j = n;
            double r = 0.375;
            if (r <= 0.5898437)
                r += 0.0390625;
            else
                r -= 0.21875;
            do
            {
                int k;
                int ic;
                if (i != j)
                {
                    k = i;
                    //        pick a central element (ic)
                    int ij = i + (j - i) * (int)Math.Floor(r);
                    ic = iy[ij];
                    //        swap ic with first element if that is larger
                    if (iy[i] > ic)
                    {
                        iy[ij] = iy[i];
                        iy[i] = ic;
                        ic = iy[ij];
                    }
                    int l = j;
                    //        swap ic with last element if that is smaller
                    if (iy[j] < ic)
                    {
                        iy[ij] = iy[j];
                        iy[j] = ic;
                        ic = iy[ij];
                        if (iy[i] > ic)
                        {
                            iy[ij] = iy[i];
                            iy[i] = ic;
                            ic = iy[ij];
                        }
                    }
                    do
                    {
                        //         find element smaller than ic in the second half
                        do
                        {
                            l -= 1;
                            if (iy[l] <= ic)
                                break;
                        }
                        while (true);
                        //         find element larger than ic in the first half
                        do
                        {
                            k += 1;
                            if (iy[k] >= ic)
                                break;
                        }
                        while (true);
                        if (k > l)
                            break;
                        if (iy[l] != iy[k])
                        {
                            //          swap elements between halves
                            int mx = iy[l];
                            iy[l] = iy[k];
                            iy[k] = mx;
                        }
                    }
                    while (true);
                    //        save upper and lower points
                    if (l - i > j - k)
                    {
                        il[m] = i;
                        iu[m] = l;
                        i = k;
                        m += 1;
                    }
                    else
                    {
                        il[m] = k;
                        iu[m] = j;
                        j = l;
                        m += 1;
                    }
                    //        start over in another part of the array
                }
                else
                {
                    m -= 1;
                    if (m == 0)
                        return;
                    i = il[m];
                    j = iu[m];
                }
                if (j - i < 11)
                {
                    if (r <= 0.5898437)
                        r += 0.0390625;
                    else
                        r -= 0.21875;
                    if (i != 1)
                    {
                        i -= 1;
                        do
                        {
                            i += 1;
                            if (i == j)
                                break;
                            ic = iy[i + 1];
                            if (iy[i] > ic)
                            {
                                k = i;
                                do
                                {
                                    iy[k + 1] = iy[k];
                                    k -= 1;
                                    if (ic >= iy[k])
                                        break;
                                }
                                while (true);
                                iy[k + 1] = ic;
                            }
                        }
                        while (true);
                    }
                }
            }
            while (true);
        }

        /// <summary>sort a double array in increasing order and return the permutation that orders the array</summary>
        /// <remarks>Singleton, R. C., Algorithm 347, An Efficient Algorithm for Sorting with Minimal Storage, CACM,12(3),1969,185-7.</remarks>
        public static void dqsortperm(int n, double[] x, double[] y, int[] ipmu)
        {
            int[] il = new int[22];
            int[] iu = new int[22];
            int i;

            if (n <= 0)
                return;

            for (i = 1; i <= n; i++)
            {
                y[i] = x[i];
                if (y[i] < 0.0)
                {
                    ipmu[i] = -ipmu[i];
                    y[i] = -y[i];
                }
            }
            int m = 1;
            i = 1;
            int j = n;
            double r = 0.375;
            if (r <= 0.5898437)
                r += 0.0390625;
            else
                r -= 0.21875;
            do
            {
                double cp;
                int it;
                int k;
                if (i != j)
                {
                    k = i;
                    //        pick a central element (cp)
                    int ij = i + (j - i) * (int)Math.Floor(r);
                    cp = y[ij];
                    it = ipmu[ij];
                    //        swap cp with first element if that is larger
                    if (y[i] > cp)
                    {
                        y[ij] = y[i];
                        y[i] = cp;
                        cp = y[ij];
                        ipmu[ij] = ipmu[i];
                        ipmu[i] = it;
                        it = ipmu[ij];
                    }
                    int l = j;
                    //        swap cp with last element if that is smaller
                    if (y[j] < cp)
                    {
                        y[ij] = y[j];
                        y[j] = cp;
                        cp = y[ij];
                        ipmu[ij] = ipmu[j];
                        ipmu[j] = it;
                        it = ipmu[ij];
                        if (y[i] > cp)
                        {
                            y[ij] = y[i];
                            y[i] = cp;
                            cp = y[ij];
                            ipmu[ij] = ipmu[i];
                            ipmu[i] = it;
                            it = ipmu[ij];
                        }
                    }
                    do
                    {
                        //         find element smaller than cp in the second half
                        do
                        {
                            l -= 1;
                            if (y[l] <= cp)
                                break;
                        }
                        while (true);
                        //         find element larger than cp in the first half
                        do
                        {
                            k += 1;
                            if (y[k] >= cp)
                                break;
                        }
                        while (true);
                        if (k > l)
                            break;
                        if (y[l] != y[k])
                        {
                            //          swap elements between halves
                            double tt = y[l];
                            y[l] = y[k];
                            y[k] = tt;
                            int mx = ipmu[l];
                            ipmu[l] = ipmu[k];
                            ipmu[k] = mx;
                        }
                    }
                    while (true);
                    //        save upper and lower points
                    if (l - i > j - k)
                    {
                        il[m] = i;
                        iu[m] = l;
                        i = k;
                        m += 1;
                    }
                    else
                    {
                        il[m] = k;
                        iu[m] = j;
                        j = l;
                        m += 1;
                    }
                    //        start over in another part of the array
                }
                else
                {
                    m -= 1;
                    if (m == 0)
                    {
                        int ik;
                        for (ik = 1; ik <= n; ik++)
                        {
                            if (ipmu[ik] < 0)
                            {
                                ipmu[ik] = -ipmu[ik];
                                y[ik] = -y[ik];
                            }
                        }
                        return;
                    }
                    i = il[m];
                    j = iu[m];
                }
                if (j - i < 11)
                {
                    if (r <= 0.5898437)
                        r += 0.0390625;
                    else
                        r -= 0.21875;
                    if (i != 1)
                    {
                        i -= 1;
                        do
                        {
                            i += 1;
                            if (i == j)
                                break;
                            cp = y[i + 1];
                            it = ipmu[i + 1];
                            if (y[i] > cp)
                            {
                                k = i;
                                do
                                {
                                    y[k + 1] = y[k];
                                    ipmu[k + 1] = ipmu[k];
                                    k -= 1;
                                    if (cp >= y[k])
                                        break;
                                }
                                while (true);
                                y[k + 1] = cp;
                                ipmu[k + 1] = it;
                            }
                        }
                        while (true);
                    }
                }
            }
            while (true);

        }

        ///  <summary>
        ///  upper triangular factorization of a real symmetric matrix
        ///  </summary>
        ///  <param name="n"></param>
        ///  <param name="a"></param>
        ///  <param name="lda"></param>
        ///  <param name="tol"></param>
        ///  <param name="irank"></param>
        ///  <param name="r"></param>
        ///  <param name="ldr"></param>
        ///  <param name="ifault"></param>
        ///  <remarks></remarks>
        public static void mxfac(int n, double[] a, int lda, double tol, ref int irank, double[] r, int ldr, ref int ifault)
        {
            if (tol < 0.0 || tol > 1.0)
            {
                ifault = 1;
            }
            if (ifault != 0)
            {
                return;
            }
            int info = 0;
            for (int j = 1; j <= n; j++)
            {
                for (int ii = 1 + lda * (j - 1); ii <= lda * (j - 1) + j; ii++)
                {
                    r[ii] = a[ii];
                }
            }
            irank = 0;
            for (int j = 1; j <= n; j++)
            {
                double s = 0.0;
                double x = tol * Math.Sqrt(Math.Abs(r[j + ldr * (j - 1)]));
                for (int k = 1; k < j; k++)
                {
                    double vvdot = 0.0;
                    for (int ii = 1; ii < k; ii++)
                    {
                        vvdot += r[ii + ldr * (k - 1)] * r[ii + ldr * (j - 1)];
                    }
                    double t = r[k + ldr * (j - 1)] - vvdot;
                    if (r[k + ldr * (k - 1)] != 0.0)
                    {
                        t /= r[k + ldr * (k - 1)];
                        r[k + ldr * (j - 1)] = t;
                        s += t * t;
                    }
                    else
                    {
                        if (info == 0)
                        {
                            if (Math.Abs(t) > x * snrm2(k - 1, r, 1 + ldr * (k - 1)))
                            {
                                info = j;
                            }
                        }
                        r[k + ldr * (j - 1)] = 0.0;
                    }
                }
                s = r[j + ldr * (j - 1)] - s;
                if (Math.Abs(s) <= tol * Math.Abs(r[j + ldr * (j - 1)]))
                {
                    s = 0.0;
                }
                else if (s < 0.0)
                {
                    s = 0.0;
                    if (info == 0)
                    {
                        info = j;
                    }
                }
                else
                {
                    irank++;
                }
                r[j + ldr * (j - 1)] = Math.Sqrt(s);
            }
            if (info != 0)
            {
                ifault = 2;
            }
            for (int i = 1; i < n; i++)
            {
                for (int ii = i + 1 + ldr * (i - 1); ii <= n + ldr * (i - 1); ii++)
                {
                    r[ii] = 0.0;
                }
            }
        }


        ///  <summary>
        ///  snrm2 returns the euclidean norm of a vector via the function name, so that
        ///  snrm2 := sqrt( x'*x )
        ///  </summary>
        ///  <param name="n"></param>
        ///  <param name="x"></param>
        ///  <param name="ixi"></param>
        ///  <returns></returns>
        ///  <remarks>Iain Buchan's F90 translation of BLAS routine</remarks>
        public static double snrm2(int n, double[] x, int ixi)
        {
            double xnorm;

            if (n < 1)
            {
                xnorm = 0.0;
            }
            else if (n == 1)
            {
                xnorm = Math.Abs(x[ixi]);
            }
            else
            {
                double scale = 0.0;
                double ssq = 1.0;
                for (int ix = ixi; ix < ixi + n; ix++)
                {
                    if (x[ix] != 0.0)
                    {
                        double absxi = Math.Abs(x[ix]);
                        if (scale < absxi)
                        {
                            ssq = 1.0 + ssq * Math.Pow(scale / absxi, 2.0);
                            scale = absxi;
                        }
                        else
                        {
                            ssq += Math.Pow(absxi / scale, 2.0);
                        }
                    }
                }
                xnorm = scale * Math.Sqrt(ssq);
            }
            return xnorm;
        }


        ///  <summary>
        ///  Solve trans(R)*X = B in an upper triangular matrix
        ///  </summary>
        ///  <param name="n"></param>
        ///  <param name="r"></param>
        ///  <param name="ldr"></param>
        ///  <param name="b"></param>
        ///  <param name="ldb"></param>
        ///  <param name="irank"></param>
        ///  <param name="x"></param>
        ///  <param name="ldx"></param>
        ///  <param name="rinv"></param>
        ///  <param name="ldrinv"></param>
        ///  <param name="ifault"></param>
        ///  <remarks></remarks>
        public static void transrxb(int n, double[] r, int ldr, double[] b, int ldb, ref int irank, double[] x, int ldx, double[] rinv, int ldrinv, ref int ifault)
        {
            if (ifault != 0)
            {
                return;
            }
            for (int i = 1; i <= n; i++)
            {
                if (r[i + ldr * (i - 1)] == 0.0)
                {
                    for (int j = i + 1; j <= n; j++)
                    {
                        if (r[i + ldr * (j - 1)] != 0.0)
                        {
                            ifault = 5;
                            return;
                        }
                    }
                }
            }
            if (ifault != 0)
            {
                return;
            }
            irank = 0;
            for (int i = 1; i <= n; i++)
            {
                if (r[i + ldr * (i - 1)] != 0.0)
                {
                    irank += 1;
                }
            }
            for (int j = 1; j <= n; j++)
                x[j] = b[j];

            if (irank < n)
            {
                for (int j = 1; j <= n; j++)
                {
                    double dd = 0.0;
                    for (int i = 1; i < j; i++)
                        dd += x[i] * r[i + ldr * (j - 1)];
                    double temp1 = x[j] - dd;
                    if (r[j + ldr * (j - 1)] == 0.0)
                    {
                        double ap = 0.0;
                        for (int i = 1; i < j; i++)
                            ap += Math.Abs(x[i]) * Math.Abs(r[i + ldr * (j - 1)]);
                        double temp2 = Math.Abs(x[j] + ap);
                        temp2 = temp2 * 200.0 * Constant.EPSILON;
                        if (Math.Abs(temp1) > temp2)
                        {
                            ifault = 2;
                        }
                        x[j] = 0.0;
                    }
                    else
                    {
                        x[j] = temp1 / r[j + ldr * (j - 1)];
                    }
                }

            }
            else
            {
                int ix = 1;
                for (int i = 1; i <= n; i++)
                {
                    double dd = 0.0;
                    int iix = 1;
                    int iiy = 1 + ldr * (i - 1);
                    for (int ii = 1; ii < i; ii++)
                    {
                        dd += r[iiy] * x[iix];
                        iiy += 1;
                        iix += 1;
                    }
                    x[ix] = x[ix] - dd;
                    x[ix] = x[ix] / r[i + ldr * (i - 1)];
                    ix += 1;
                }
            }
        }

    }


}
