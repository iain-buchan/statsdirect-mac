using System;

namespace StatsDirect.Numerics
{
    public class BinomialRND  
    { 
        
        //   Kachitvichyanukul, V. and Schmeiser, B. W. (1988).
        //   Binomial random variate generation.
        //   Communications of the ACM 31, p216.
        //   (Algorithm BTPEC).
        
        private double C; 
        private double FM; 
        private double NPQ; 
        private double P1; 
        private double P2; 
        private double P3; 
        private double P4; 
        private double QN; 
        private double XL; 
        private double XLL; 
        private double XLR; 
        private double XM; 
        private double XR; 
        private int M; 
        
        private double PSAVE; 
        private int NSAVE; 
        
        private bool SEEDED; 
        
        private MersenneTwister RNG; 
        
        public double GenBinom( double nin, double PP ) 
        { 
            double genBinomReturn;
            
            
            //  Binomial random variate
            
            double f, u;
            int ix ;

            if ( SEEDED == false )
            { 
                Seed( Base.DefaultSeed() ); 
            } 
            
            int n = ( int )Math.Floor(nin + 0.5); 
            if ( n != nin ) 
            { 
                genBinomReturn = double.NaN; 
                return genBinomReturn; 
            } 
            
            if ( n < 0 | PP < 0.0 | PP > 1.0 ) 
            { 
                genBinomReturn = double.NaN; 
                return genBinomReturn; 
            } 
            
            if ( n == 0 | PP == 0.0 ) 
            { 
                genBinomReturn = 0.0; 
                return genBinomReturn; 
            } 
            
            if ( PP == 1.0 ) 
            { 
                genBinomReturn = n; 
                return genBinomReturn; 
            } 
            
            double P = Math.Min( PP, 1.0 - PP ); 
            double Q = 1.0 - P; 
            double np = n * P; 
            double r = P / Q; 
            double g = r * ( n + 1 ); 
            
            if ( PP != PSAVE | n != NSAVE ) 
            { 
                // setup afresh when parameters change
                PSAVE = PP; 
                NSAVE = n; 
                if ( np < 30.0 ) 
                { 
                    // inverse cdf logic for mean less than 30
                    QN = Math.Pow( Q, Convert.ToDouble( n ) ); 
                    GenBinomSmall( out ix, out f, out u, g, r ); 
                    return GenBinomFin( ix, n ); 
                }
                double ffm = np + P; 
                M = ( int )Math.Floor(ffm); 
                FM = M; 
                NPQ = np * Q; 
                P1 =  Math.Floor(2.195 * Math.Sqrt( NPQ ) - 4.6 * Q) + 0.5; 
                XM = FM + 0.5; 
                XL = XM - P1; 
                XR = XM + P1; 
                C = 0.134 + 20.5 / ( 15.3 + FM ); 
                double al = ( ffm - XL ) / ( ffm - XL * P ); 
                XLL = al * ( 1.0 + 0.5 * al ); 
                al = ( XR - ffm ) / ( XR * Q ); 
                XLR = al * ( 1.0 + 0.5 * al ); 
                P2 = P1 * ( 1.0 + C + C ); 
                P3 = P2 + C / XLL; 
                P4 = P3 + C / XLR;
            } 
            else if ( n == NSAVE ) 
            { 
                if ( np < 30.0 ) 
                { 
                    GenBinomSmall( out ix, out f, out u, g, r ); 
                    genBinomReturn = GenBinomFin( ix, n ); 
                    return genBinomReturn; 
                } 
            } 
            
            do 
            { 
                u = RNG.NextDoubleX() * P4; 
                double v = RNG.NextDoubleX(); 
                //  triangular region
                if ( u <= P1 ) 
                { 
                    ix = ( int )Math.Floor(XM - P1 * v + u); 
                    break;
                } 
                //  parallelogram region
                bool backup = false; 
                if ( u <= P2 ) 
                { 
                    double x = XL + ( u - P1 ) / C; 
                    v = v * C + 1.0 - Math.Abs( XM - x ) / P1; 
                    if ( v > 1.0 | v <= 0.0 )
                    { 
                        backup = true; 
                    } 
                    ix = ( int )Math.Floor(x); 
                } 
                else 
                { 
                    if ( u > P3 ) 
                    { 
                        //  right tail
                        ix = ( int )Math.Floor(XR - Math.Log( v ) / XLR); 
                        if ( ix > n )
                        { 
                            backup = true; 
                        } 
                        v = v * ( u - P3 ) * XLR; 
                    } 
                    else 
                    { 
                        //  left tail
                        ix = ( int )Math.Floor(XL + Math.Log( v ) / XLL); 
                        if ( ix < 0 )
                        { 
                            backup = true; 
                        } 
                        v = v * ( u - P2 ) * XLL; 
                    } 
                } 
                if ( backup == false )
                {
                    //  determine the appropriate way to perform acceptance/rejection
                    int k = Math.Abs( ix - M );
                    if ( k <= 20 || k >= NPQ / 2 - 1 ) 
                    { 
                        //  explicit evaluation
                        f = 1.0;
                        int i ;
                        if ( M < ix ) 
                        { 
                            for ( i=M + 1; i <= ix; i++ ) 
                            { 
                                f *= ( g / i - r ); 
                            } 
                        } 
                        else if ( M != ix ) 
                        { 
                            for ( i=ix + 1; i <= M; i++ ) 
                            { 
                                f /= ( g / i - r ); 
                            } 
                        } 
                        if ( v <= f )
                        { 
                            break; 
                        } 
                    } 
                    else 
                    { 
                        //  squeezing using upper and lower bounds on log(f(x))
                        double amaxp = k / NPQ * ( ( k * ( k / 3.0 + 0.625 ) + 0.1666666666666 ) / NPQ + 0.5 ); 
                        double ynorm = -k * k / ( 2.0 * NPQ ); 
                        double alv = Math.Log( v ); 
                        if ( alv < ynorm - amaxp )
                            break;
                        if ( alv <= ynorm + amaxp ) 
                        { 
                            //  stirling's formula to machine accuracy
                            //  for the final acceptance/rejection test
                            double x1 = ix + 1; 
                            double f1 = FM + 1.0; 
                            double z = n + 1 - FM; 
                            double w = n - ix + 1.0; 
                            double z2 = z * z; 
                            double x2 = x1 * x1; 
                            double f2 = f1 * f1; 
                            double w2 = w * w; 
                            if ( alv <= XM * Math.Log( f1 / x1 ) + ( n - M + 0.5 ) * Math.Log( z / w ) + ( ix - M ) * Math.Log( w * P / ( x1 * Q ) ) + ( 13860.0 - ( 462.0 - ( 132.0 - ( 99.0 - 140.0 / f2 ) / f2 ) / f2 ) / f2 ) / f1 / 166320.0 + ( 13860.0 - ( 462.0 - ( 132.0 - ( 99.0 - 140.0 / z2 ) / z2 ) / z2 ) / z2 ) / z / 166320.0 + ( 13860.0 - ( 462.0 - ( 132.0 - ( 99.0 - 140.0 / x2 ) / x2 ) / x2 ) / x2 ) / x1 / 166320.0 + ( 13860.0 - ( 462.0 - ( 132.0 - ( 99.0 - 140.0 / w2 ) / w2 ) / w2 ) / w2 ) / w / 166320.0 )
                                break;
                        } 
                    }
                }
            } 
            while ( true ); 
            
            genBinomReturn = GenBinomFin( ix, n ); 
            
            return genBinomReturn;
        } 
        
        
        private double GenBinomFin( int ix, int n ) 
        {
            if ( PSAVE > 0.5 )
            { 
                ix = n - ix; 
            } 
            return Convert.ToDouble( ix ); 
        } 
        
        
        // TRANSMISSINGCOMMENT: Method GenBinomSmall
        private void GenBinomSmall( out int ix, out double f, out double u, double g, double r ) 
        { 
            
            do 
            { 
                ix = 0; 
                f = QN; 
                u = RNG.NextDoubleX(); 
                do 
                { 
                    if ( u < f )
                    { 
                        return; 
                    } 
                    if ( ix > 110 )
                    { 
                        break;
                    } 
                    u -= f; 
                    ix++; 
                    f *= g / ix - r; 
                } 
                while ( true ); 
            } 
            while ( true ); 
        } 
        
        public void Seed( int sd, MersenneTwister rug ) 
        { 
            
                RNG = null; 
            if ( rug == null ) 
            { 
                RNG = new MersenneTwister(); 
                RNG.Seed( sd ); 
            } 
            else 
            { 
                RNG = rug; 
            } 
            PSAVE = -1.0; 
            NSAVE = -1; 
            SEEDED = true; 
        } 
        
        public void Seed( int sd ) 
        { 
            Seed( sd, null );
        } 
    } 
} 
