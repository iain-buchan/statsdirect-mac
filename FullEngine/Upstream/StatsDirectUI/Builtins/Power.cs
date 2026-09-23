using StatsDirect.Numerics; 

using System;
namespace StatsDirect.Builtins
{
    public static class Power  
    { 
        ///  <summary>
        ///  power of a test for simple correlation
        ///  </summary>
        ///  <param name="r0">the null hypothesis correlation</param>
        ///  <param name="r1">the alternate hypothesis correlation</param>
        ///  <param name="N">the one-sided sample size</param>
        ///  <param name="alpha">the chosen significance level</param>
        ///  <returns></returns>
        public static double rpower( double r0, double r1, double N, double alpha ) 
        { 
            
            
            double dif = Math.Abs( fisher_zmean( r0, N ) - fisher_zmean( r1, N ) );
            double zsig = PDF.gauinv(1.0 - alpha / 2.0, out int ifault);
            if ( ifault != 0 ) 
                return Constant.MISSING; 
            double var = Math.Sqrt( N - 1.0 ); 
            return PDF.alnorm( dif * var - zsig ); 
        } 
        
        
        public static double fisher_z1( double r )
        {
            if ( Math.Abs( r ) >= 1.0 ) 
                return Constant.MISSING; 
            return 0.5 * Math.Log( ( 1.0 + r ) / ( 1.0 - r ) );
        }


        public static double fisher_z2( double r, double N )
        {
            if ( r < -1.0 || r > 1.0 || N <= 0.0 ) 
                return Constant.MISSING; 
            return fisher_z1( r ) - ( 3.0 * fisher_z1( r ) + r ) / ( 4.0 * N );
        }

        /// <summary>
        /// part of power for correlation coefficient via Fisher z transform
        /// </summary>
        /// <param name="x"></param>
        /// <param name="y"></param>
        /// <returns></returns>
        public static double fisher_zmean( double x, double y )
        {
            if ( x < -1.0 || x > 1.0 || y <= 1.0 ) 
                return Constant.MISSING; 
            return fisher_z2( x, y ) - ( 3.0 * fisher_z2( x, y ) + x ) / ( 4.0 * y ) + x / ( 2.0 * ( y - 1.0 ) ) + 3.0 * x / ( 8.0 * Math.Pow( y - 1.0, 2.0 ) );
        }


        ///  <summary>
        ///  sample size associated with BETA and the other parameters for studies that are analyzed with Fisher's Exact test.
        ///  </summary>
        ///  <param name="BETA"></param>
        ///  <param name="alpha"></param>
        ///  <param name="P1"></param>
        ///  <param name="P0"></param>
        ///  <param name="N"></param>
        ///  <param name="M"></param>
        ///  <returns></returns>
        ///  <remarks></remarks>
        private static double fisherss( double BETA, double alpha, double P1, double P0, double N, double M ) 
        {

            double zalpha = -PDF.gauinv(alpha / 2.0, out int fault);
            if ( fault != 0 )
                return Constant.MISSING; 
            double zbeta = -PDF.gauinv( BETA, out fault ); 
            if ( fault != 0 )
                return Constant.MISSING; 
            double P = ( N * P1 + M * N * P0 ) / ( M * N + N ); 
            double Q = 1.0 - P; 
            double Q1 = 1.0 - P1; 
            double Q0 = 1.0 - P0; 
            double nprime = Math.Pow( zalpha * Math.Sqrt( ( 1.0 + 1.0 / M ) * P * Q ) + zbeta * Math.Sqrt( P0 * Q0 / M + P1 * Q1 ), 2.0 ) / Math.Pow( P0 - P1, 2.0 ); 
            return nprime * Math.Pow( 1.0 + Math.Sqrt( 1.0 + 2.0 * ( M + 1.0 ) / ( nprime * M * Math.Abs( P0 - P1 ) ) ), 2.0 ) / 4.0 - N; 
        } 
        
        /// <summary>
        /// paired or one-sample Student t test power
        /// </summary>
        /// <param name="alpha"></param>
        /// <param name="mean"></param>
        /// <param name="s"></param>
        /// <param name="N"></param>
        /// <returns></returns>
        public static double ptpower( double alpha, double mean, double s, double N ) 
        {
            if ( s == 0.0 || N < 2.0 )
                return Constant.MISSING; 
            return nctpower( alpha, mean / ( s / Math.Sqrt( N ) ), N - 1.0 ); 
        } 
        
        /// <summary>
        /// power of a two sided Student t test from the non-central t distribution:
        /// P(|T'| > t) where T' has df degrees of freedom and non-centrality delta and t is the central critical value for alpha
        /// (ExFortran.pnct takes integer df, so power at a fractional df is interpolated linearly between the adjacent integer df)
        /// </summary>
        /// <param name="alpha">two sided significance level</param>
        /// <param name="delta">non-centrality parameter (expected difference divided by its standard error)</param>
        /// <param name="df">degrees of freedom</param>
        /// <returns></returns>
        private static double nctpower( double alpha, double delta, double df ) 
        {
            if ( !( df >= 1.0 ) || df > int.MaxValue - 1.0 || double.IsNaN( delta ) || double.IsInfinity( delta ) )
                return Constant.MISSING; 
            int idf = (int)Math.Floor( df ); 
            double frac = df - idf; 
            if ( frac < 0.00000001 || frac > 1.0 - 0.00000001 )
                return nctpower( alpha, delta, frac > 0.5 ? idf + 1 : idf ); 
            // Fractional degrees of freedom (Welch): P(T' <= t) = integral over v of Phi(t sqrt(v/df) - delta) f(v) dv,
            // f the chi-square density with df degrees of freedom, evaluated by Simpson's rule on w = sqrt(v).
            double tcrit = PDF.tfromp2( alpha, df ); 
            if ( double.IsNaN( tcrit ) )
                return Constant.MISSING; 
            double upper = pnctFractional( tcrit, df, delta ); 
            double lower = pnctFractional( -tcrit, df, delta ); 
            if ( double.IsNaN( upper ) || double.IsNaN( lower ) )
                return Constant.MISSING; 
            return 1.0 - upper + lower; 
        } 

        /// <summary>
        /// Non-central t distribution function for non-integer degrees of freedom, by numerical integration over
        /// the chi-square denominator (w = sqrt(v), so the integrand is smooth at the origin for df >= 1).
        /// </summary>
        private static double pnctFractional( double t, double df, double delta ) 
        {
            double wmax = Math.Sqrt( df + 12.0 * Math.Sqrt( 2.0 * df ) + 60.0 ); 
            const int panels = 4000; 
            double h = wmax / panels; 
            double lc = -0.5 * df * Math.Log( 2.0 ) - PDF.alogam( 0.5 * df ) + Math.Log( 2.0 ); // 2 w f(w^2) 
            double sum = 0.0; 
            for ( int i = 0; i <= panels; i++ ) 
            {
                double w = i * h; 
                double g; 
                if ( w <= 0.0 )
                    g = 0.0; 
                else
                {
                    double logf = lc + ( df - 1.0 ) * Math.Log( w ) - 0.5 * w * w; 
                    g = Math.Exp( logf ) * PDF.alnorm( t * w / Math.Sqrt( df ) - delta ); 
                }
                double weight = ( i == 0 || i == panels ) ? 1.0 : ( ( i % 2 == 1 ) ? 4.0 : 2.0 ); 
                sum += weight * g; 
            }
            return sum * h / 3.0; 
        } 

        private static double nctpower( double alpha, double delta, int idf ) 
        {
            double tcrit = PDF.tfromp2( alpha, idf ); 
            if ( double.IsNaN( tcrit ) )
                return Constant.MISSING; 
            double upper = ExFortran.pnct( tcrit, idf, delta, out int ifault ); 
            if ( ifault != 0 )
                return Constant.MISSING; 
            double lower = ExFortran.pnct( -tcrit, idf, delta, out ifault ); 
            if ( ifault != 0 )
                return Constant.MISSING; 
            return 1.0 - upper + lower; 
        } 
        
        
        private static double rootfish( ref double x1, ref double x2, ref double alpha, ref double P1, ref double P0, ref double N, ref double M ) 
        { 
            double rootfishReturn;
            int j;
            double dx;

            const int jmax = 400;
            double xacc = 0.000002 * Math.Min( P0, 1.0 - P0 ); 
            // bisection, the root of a function func known to lie between x1 and x2
            double fmid = fisherss( x2, alpha, P1, P0, N, M ); 
            double f = fisherss( x1, alpha, P1, P0, N, M ); 
            if ( f * fmid >= 0.0 ) 
            { 
                // root must be bracketed in rootfish
                rootfishReturn = Constant.MISSING; 
                return rootfishReturn; 
            } 
            if ( f < 0.0 ) 
            { 
                // Orient the search so that f>0 lies at x+dx.
                rootfishReturn = x1; 
                dx = x2 - x1; 
            } 
            else 
            { 
                rootfishReturn = x2; 
                dx = x1 - x2; 
            } 
            for ( j=1; j <= jmax; j++ ) 
            { 
                dx *= 0.5; 
                double xmid = rootfishReturn + dx; 
                fmid = fisherss( xmid, alpha, P1, P0, N, M ); 
                if ( fmid == Constant.MISSING ) 
                { 
                    rootfishReturn = Constant.MISSING; 
                    return rootfishReturn; 
                } 
                if ( fmid <= 0.0 )
                { 
                    rootfishReturn = xmid; 
                } 
                if ( Math.Abs( dx ) < xacc | fmid == 0.0 )
                { 
                    return rootfishReturn; 
                } 
            } 
            rootfishReturn = Constant.MISSING; 
            return rootfishReturn;
        } 
        
        
        public static double fishpower( double alpha, double a, double b, double n1, double n2, ref bool dofish ) 
        {

            //  power for Fisher exact test or continuity corrected chi-squaure test
            //  n = number of experimental subjects
            //  m = controls per experimental subject
            if (n1 == 0 || n2 == 0)
                return Constant.MISSING;
            double P0 = b / n2; 
            double P1 = a / n1; 
            double M = n2 / n1; 
            double N = n1;
            double zalpha = -PDF.gauinv( alpha / 2.0, out int fault ); 
            if ( fault != 0 ) 
                return Constant.MISSING; 
            double pbar = ( P1 + M * P0 ) / ( M + 1.0 ); 
            double qbar = 1.0 - pbar; 
            double Q1 = 1.0 - P1; 
            double Q0 = 1.0 - P0; 
            double S1 = Math.Sqrt( pbar * qbar * ( 1.0 + 1.0 / M ) / N ); 
            double S2 = Math.Sqrt( ( P0 * Q0 / M + P1 * Q1 ) / N ); 
            double BETA = PDF.alnorm( ( zalpha * S1 - ( P0 - P1 ) ) / S2 ) - PDF.alnorm( ( -zalpha * S1 - ( P0 - P1 ) ) / S2 ); 
            double fishpowerReturn = 1.0 - BETA; 
            if ( dofish ) 
            { 
                //  if the test type is Fisher's exact then use the bisection routine to search for a root of the function.
                double y1 = BETA; 
                double Y2 = 1.0 - alpha; 
                BETA = rootfish( ref y1, ref Y2, ref alpha, ref P1, ref P0, ref N, ref M ); 
                if ( BETA != Constant.MISSING ) 
                { 
                    fishpowerReturn = 1.0 - BETA; 
                } 
                else 
                { 
                    dofish = false; 
                } 
            } 
            return fishpowerReturn;
        } 
        
        /// <summary>
        /// two-sample Student t test power
        /// </summary>
        /// <param name="alpha">two sided significance level</param>
        /// <param name="DELTA">difference between means</param>
        /// <param name="s">pooled standard deviation</param>
        /// <param name="N">size of the first sample</param>
        /// <param name="M">size of the second sample as a ratio of the first (n2 / n1)</param>
        /// <returns></returns>
        public static double tstpower( double alpha, double DELTA, double s, double N, double M ) 
        {
            if ( s == 0.0 || N <= 0.0 || M <= 0.0 )
                return Constant.MISSING; 
            return nctpower( alpha, DELTA / ( s * Math.Sqrt( ( 1.0 + 1.0 / M ) / N ) ), N * ( M + 1.0 ) - 2.0 ); 
        } 
        
        /// <summary>
        /// power for two sample t test with unequal variances
        /// </summary>
        /// <param name="sig"></param>
        /// <param name="dif"></param>
        /// <param name="n1"></param>
        /// <param name="n2"></param>
        /// <param name="sdev1"></param>
        /// <param name="sdev2"></param>
        /// <returns></returns>
        public static double uvttpower( double sig, double dif, double n1, double n2, double sdev1, double sdev2 ) 
        {
            double k = Math.Pow( sdev1, 2.0 ) / n1 + Math.Pow( sdev2, 2.0 ) / n2; 
            double f = Math.Pow( sdev1, 4.0 ) / ( Math.Pow( k, 2.0 ) * Math.Pow( n1, 2.0 ) * ( n1 - 1.0 ) ) + Math.Pow( sdev2, 4.0 ) / ( Math.Pow( k, 2.0 ) * Math.Pow( n2, 2.0 ) * ( n2 - 1.0 ) ); 
            double df = 1.0 / f; 
            double denom = Math.Sqrt( k ); 
            if ( denom == 0.0 )
                return Constant.MISSING; 
            return nctpower( sig, dif / denom, df ); 
        } 
        
    } 
} 
