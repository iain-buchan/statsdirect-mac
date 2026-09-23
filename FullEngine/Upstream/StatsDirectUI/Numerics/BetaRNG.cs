namespace StatsDirect.Numerics
{
    public class BetaRNG  
    { 
        private double OLDB, K2, DELTA, BETA, GAMMA, K1, OLDA; 
        
        // private bool SEEDED = false; 
        
        private MersenneTwister RNG; 
        
        // TRANSMISSINGCOMMENT: Method GenBeta
        public double GenBeta( double aa, double bb ) 
        { 
            double genBetaReturn;
            
            //  R. C. H. Cheng (1978).
            //  Generating beta variates with nonintegral shape parameters.
            //  Communications of the ACM 21, 317-322.
            //  (Algorithms BB and BC)

            double v, u1;
            double u2, w, z;

            if ( aa <= 0.0 || bb <= 0 ) 
            { 
                genBetaReturn = double.NaN; 
                return genBetaReturn; 
            } 
            
            bool qsame = ( OLDA == aa ) & ( OLDB == bb ); 
            if ( qsame == false ) 
            { 
                OLDA = aa; 
                OLDB = bb; 
            } 
            
            double a = System.Math.Min( aa, bb ); 
            double b = System.Math.Max( aa, bb ); 
            double alpha = a + b; 
            
            if ( a <= 1.0 ) 
            { //  algorithm BC
            
                
                if ( qsame == false ) 
                { // initialize
                
                    BETA = 1.0 / a; 
                    DELTA = 1.0 + b - a; 
                    K1 = DELTA * ( 0.0138889 + 0.0416667 * a ) / ( b * BETA - 0.777778 ); 
                    K2 = 0.25 + ( 0.5 + 0.25 / DELTA ) * a; 
                } 
                
                do 
                { 
                    bool skip = false; 
                    u1 = RNG.NextDoubleX(); 
                    u2 = RNG.NextDoubleX(); 
                    if ( u1 < 0.5 ) 
                    { 
                        double y = u1 * u2; 
                        z = u1 * y; 
                        if ( 0.25 * u2 + z - y >= K1 )
                        { 
                            skip = true; 
                        } 
                    } 
                    else 
                    { 
                        z = u1 * u1 * u2; 
                        if ( z <= 0.25 ) 
                        { 
                            GetVW( b, u1, out v, out w ); 
                            break;
                        } 
                        if ( z >= K2 )
                        { 
                            skip = true; 
                        } 
                    } 
                    if ( skip == false ) 
                    { 
                        GetVW( b, u1, out v, out w ); 
                        if ( alpha * ( System.Math.Log( alpha / ( a + w ) ) + v ) - 1.3862944 >= System.Math.Log( z ) )
                        { 
                            break;
                        } 
                    } 
                } 
                while ( true ); 
                
                if ( aa == a ) 
                { 
                    genBetaReturn = a / ( a + w ); 
                } 
                else 
                { 
                    genBetaReturn = w / ( a + w ); 
                } 
                
            } 
            else 
            { // algorithm BB
            
                
                if ( qsame == false ) 
                { // initialise
                
                    BETA = System.Math.Sqrt( ( alpha - 2.0 ) / ( 2.0 * a * b - alpha ) ); 
                    GAMMA = a + 1.0 / BETA; 
                }

                double r;
                double t;
                do 
                { 
                    u1 = RNG.NextDoubleX(); 
                    u2 = RNG.NextDoubleX(); 
                    GetVW( a, u1, out v, out w ); 
                    z = u1 * u1 * u2; 
                    r = GAMMA * v - 1.3862944; 
                    double s = a + r - w; 
                    if ( s + 2.609438 >= 5.0 * z )
                    { 
                        break;
                    } 
                    t = System.Math.Log( z ); 
                    if ( s > t )
                    { 
                        break;
                    } 
                } 
                while ( r + alpha * System.Math.Log( alpha / ( b + w ) ) < t ); 
                
                if ( aa != a ) 
                { 
                    genBetaReturn = b / ( b + w ); 
                } 
                else 
                { 
                    genBetaReturn = w / ( b + w ); 
                } 
                
            } 
            
            return genBetaReturn;
        } 
        
        
        // TRANSMISSINGCOMMENT: Method Seed
        public void Seed( int sd, MersenneTwister rug ) 
        { 
            
            OLDA = -1.0; 
            OLDB = -1.0; 
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
            // SEEDED = true; 
        } 
        
        public void Seed( int sd ) 
        { 
            Seed( sd, null );
        } 
        
        private void GetVW( double x, double u1, out double v, out double w ) 
        { 
            
            v = BETA * System.Math.Log( u1 / ( 1.0 - u1 ) ); 
            if ( v <= Constant.MAXEXP ) 
                w = x * System.Math.Exp( v ); 
            else 
                w = double.MaxValue; 
        } 
    } 
} 
