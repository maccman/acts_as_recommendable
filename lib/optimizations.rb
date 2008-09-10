require 'inline'
module MadeByMany
  module ActsAsRecommendable
    class Optimizations
      InlineC = Module.new do
        inline do |builder|
          builder.c '
          #include <math.h>
          #include "ruby.h"
          double c_sim_pearson(VALUE items, int n, VALUE prefs1, VALUE prefs2) {
            double sum1 = 0.0;
            double sum2 = 0.0;
            double sum1Sq = 0.0;
            double sum2Sq = 0.0;
            double pSum = 0.0;
            
            VALUE *items_a  = RARRAY(items) ->ptr;
            
            int i;
            for(i=0; i<n; i++) {              
              VALUE prefs1_item_ob;
              VALUE prefs2_item_ob;
              
              double prefs1_item;
              double prefs2_item;
              
              if (!st_lookup(RHASH(prefs1)->tbl, items_a[i], &prefs1_item_ob)) {
                prefs1_item = 0.0;
              } else {
                prefs1_item = NUM2DBL(prefs1_item_ob);
              }
              
              if (!st_lookup(RHASH(prefs2)->tbl, items_a[i], &prefs2_item_ob)) {
                prefs2_item = 0.0;
              } else {
                prefs2_item = NUM2DBL(prefs2_item_ob);
              }
                            
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
      def self.sim_pearson(prefs, items, person1, person2)
        n = items.length
        return 0 if n == 0
        Optimizations.c_sim_pearson(items, n, prefs[person1], prefs[person2])
      end

    end     
  end
end
