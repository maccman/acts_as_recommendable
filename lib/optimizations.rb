require 'inline'
module MadeByMany
  module ActsAsRecommendable
    class Optimizations
      InlineC = Module.new do
        inline do |builder|
          builder.c '
          #include <math.h>
          double c_sim_pearson(VALUE si, VALUE prefs1, VALUE prefs2, int n) {
            double sum1 = 0.0;
            double sum2 = 0.0;
            double sum1Sq = 0.0;
            double sum2Sq = 0.0;
            double pSum = 0.0;
            
            VALUE *prefs1_a = RARRAY(prefs1)->ptr;
            VALUE *prefs2_a = RARRAY(prefs2)->ptr;
            
            int i;
            for(i=0; i<n; i++) {
              double prefs1_item = NUM2DBL(prefs1_a[i]);
              double prefs2_item = NUM2DBL(prefs2_a[i]);
                            
              sum1   += prefs1_item;
              sum2   += prefs2_item;
              sum1Sq += pow(prefs1_item, 2);
              sum2Sq += pow(prefs2_item, 2);
              pSum   += prefs2_item * prefs1_item;
            }
            
            double num;
            double den;
            num = pSum - ( ( sum1 * sum2 ) / n );
            den = sqrt( ( sum1Sq - ( pow(sum1, 2) ) / n ) * ( sum2Sq - ( pow(sum2, 2) ) / n ) );
            if(den == 0){
              return 0.0;
            } else {
              return num / den;
            }
          }'
        end
      end
      class << self
        include InlineC
      end
    end
    
    module Logic  
      # Pearson score
      def self.sim_pearson(prefs, person1, person2)
        si = mutual_items(prefs[person1], prefs[person2])
        
        n = si.length

        return 0 if n == 0

        Optimizations.c_sim_pearson(si, prefs[person1].values, prefs[person2].values, n)
      end

    end     
  end
end
