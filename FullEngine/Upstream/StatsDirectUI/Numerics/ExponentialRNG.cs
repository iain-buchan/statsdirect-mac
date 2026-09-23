namespace StatsDirect.Numerics
{
    // TRANSMISSINGCOMMENT: Class ExponentialRNG
    public class ExponentialRNG  
    { 
        
        private readonly double[] Q = new double[ 15 ]; 
        
        private MersenneTwister RNG; 
        
        private bool SEEDED; 
        
        // TRANSMISSINGCOMMENT: Method Seed
        public void Seed( int sd, ref MersenneTwister rug ) 
        { 
            
            Q[ 0 ] = 0.693147180559945; 
            Q[ 1 ] = 0.933373687519046; 
            Q[ 2 ] = 0.988877796183868; 
            Q[ 3 ] = 0.998495925291496; 
            Q[ 4 ] = 0.999829281106139; 
            Q[ 5 ] = 0.999983316410073; 
            Q[ 6 ] = 0.999998569143877; 
            Q[ 7 ] = 0.999999890692556; 
            Q[ 8 ] = 0.999999992473416; 
            Q[ 9 ] = 0.999999999528328; 
            Q[ 10 ] = 0.999999999972881; 
            Q[ 11 ] = 0.99999999999856; 
            Q[ 12 ] = 0.999999999999929; 
            Q[ 13 ] = 0.999999999999997; 
            Q[ 14 ] = 1.0; 
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
            SEEDED = true; 
        } 
        
        public void Seed( int sd ) 
        { 
            MersenneTwister transTemp0 = null;
            Seed( sd,  ref transTemp0 );
        } 
        
        /// <summary>
        ///  Random variates from the standard exponential distribution.
        /// 
        ///  Ahrens, J.H. and Dieter, U. (1972).
        ///  Computer methods for sampling from the exponential and normal distributions.
        ///  Comm. ACM, 15, 873-882.
        /// </summary>
        /// <returns></returns>
        public double GenExp() 
        { 
            double genExpReturn;
            
            //  q[k-1] = sum(log(2)^k / k!)  k=1,..,n,
            //  The highest n (here 8) is determined by q[n-1] = 1.0 within standard precision

            if ( SEEDED == false )
            { 
                Seed( Base.DefaultSeed() ); 
            } 
            
            double Q0 = Q[ 0 ]; 
            
            double a = 0.0; 
            double u = RNG.NextDoubleX(); 
            do 
            { 
                u += u; 
                if ( u >= 1.0 )
                { 
                    break; 
                } 
                a += Q0; 
            } 
            while ( true ); 
            u -= 1.0; 
            if ( u <= Q0 ) 
            { 
                genExpReturn = a + u; 
                return genExpReturn; 
            } 
            int i = 0; 
            double ustar = RNG.NextDoubleX(); 
            double umin = ustar; 
            do 
            { 
                ustar = RNG.NextDoubleX(); 
                if ( ustar < umin )
                { 
                    umin = ustar; 
                } 
                i += 1; 
            } 
            while ( u > Q[ i ] ); 
            genExpReturn = a + umin * Q0; 
            
            return genExpReturn;
        } 
    } 
} 
