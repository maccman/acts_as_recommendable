require 'inline'
module MadeByMany
  module ActsAsRecommendable
    class Optimizations
      InlineC = Module.new do
        inline do |builder|
          builder.c '
          #include <math.h>
          double c_sim_pearson(double sum1, double sum2, double sum1Sq, double sum2Sq, double pSum, double n) {
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

        sum1 = sum2 = sum1Sq = sum2Sq = pSum = 0.0

        si.each do |item|
          sum1   += prefs[person1][item]
          sum2   += prefs[person2][item]
          sum1Sq += prefs[person1][item] ** 2
          sum2Sq += prefs[person2][item] ** 2
          pSum   += prefs[person2][item] * prefs[person1][item]
        end

        Optimizations.c_sim_pearson(sum1, sum2, sum1Sq, sum2Sq, pSum, n)
      end

    end     
  end
end
