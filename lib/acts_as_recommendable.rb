# ActsAsRecommended
module MadeByMany
  module ActsAsRecommendable
    def self.included(base)
      base.extend(ActsMethods)
    end
      
    module ActsMethods
      def acts_as_recommendable(on, options = {})
        raise "You need to specify ':through'" unless options[:through]
        
        options[:algorithm]   ||= :sim_pearson
        options[:use_dataset] ||= false
        
        options[:on]          =   on
        on_class_name         =   options[:on].to_s.singularize
        options[:on_singular] ||= on_class_name.downcase
        options[:on_class]    ||= on_class_name.camelize.constantize
        
        options[:class] = self
        
        options[:through_singular]  ||= options[:through].to_s.singularize
        options[:through_class]     ||= options[:through_singular].camelize.constantize
        
        class_inheritable_accessor :aar_options
        self.aar_options = options

        define_method "similar_#{options[:class].name.underscore.pluralize}" do
          Logic.similar(self, options)
        end
          
        define_method "recommended_#{options[:on_class].name.underscore.pluralize}" do
          # We're not using the dataset yet,
          # it's not ready...
          #
          # if self.aar_options[:use_dataset]
          #   Logic.dataset_recommended(self, options)
          # else
            Logic.recommended(self, options)
          # end
        end
        
        def self.aar_dataset(force = false)
          Rails.cache.fetch("#{self.name}_aar_dataset", {
            :force => force
          }) do
            Logic.dataset(self.aar_options)
          end
        end
        
        define_method "aar_items_with_scores" do
          @aar_items_with_scores ||= begin
            self.__send__(self.aar_options[:through]).collect {|ui|
              item = ui.__send__(self.aar_options[:on_singular])
              if self.aar_options[:score]
                score = ui.__send__(self.aar_options[:score]).to_f
                score = 1.0 if !score or score <= 0
              else
                score = 1.0
              end
              def item.aar_score; @aar_score; end
              def item.aar_score=(d); @aar_score = d; end
              item.aar_score = score
              item
            }.inject({}) {|h, item| h[item.id] = item; h }
          end
        end
        
      end
    end
      
    module Logic
      
      def self.prefs(options)
        items = options[:on_class].find(:all)
        prefs = {}
        options[:class].find(:all, :include => options[:on]).each do |user|
          prefs[user.id] ||= {}
          items.each do |item|
            if user.aar_items_with_scores[item.id]
              score = user.aar_items_with_scores[item.id].aar_score
              prefs[user.id][item.id] = score
            else
              prefs[user.id][item.id] = 0.0
            end
          end
        end
        prefs
      end
    
      # Euclidean distance 
      def self.sim_distance(prefs, person1, person2)
        si = mutual_items(prefs[person1], prefs[person2])
        return 0 if si.length == 0

        squares = []
        prefs[person1].keys.each do |item|
          if prefs[person2].include? item
            squares << (prefs[person1][item] - prefs[person2][item]) ** 2
          end
        end
        
        sum_of_squares = squares.inject { |sum,value| sum += value }
        return 1/(1 + sum_of_squares)
      end
    
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

        num = pSum - ( ( sum1 * sum2 ) / n )
        den = Math.sqrt( ( sum1Sq - ( sum1 ** 2 ) / n ) * ( sum2Sq - ( sum2 ** 2 ) / n ) )
        
        return 0 if den == 0

        num / den
      end
      
      def self.similar(user, options)
        rankings = []
        prefs = self.prefs(options)
        prefs.each do |u, _|
          next if u == user.id
          rankings << [self.__send__(options[:algorithm], prefs, user.id, u), u]
        end
        
        # Return the sorted list
        ranking_ids = rankings.collect {|_, u| u }
        ar_users = options[:class].find(ranking_ids)
        ar_users = ar_users.inject({}){ |h, user| h[user.id] = user; h }
        
        rankings = rankings.select {|score, _| score > 0.0 }
        rankings = rankings.sort_by {|score, _| score }.reverse
        
        rankings.collect {|score, user_id|
          user = ar_users[user_id]
          def user.similar_score; return @similar_score; end
          def user.similar_score=(d); @similar_score = d; end
          user.similar_score = score
          user
        }
      end
        
      def self.recommended(user, options)
        totals = {}
        simSums = {}
        prefs = self.prefs(options)
        user = user.id
  
        prefs.keys.each do |other|
          # don't compare me to myself
          next if other == user

          sim = self.__send__(options[:algorithm], prefs, user, other)

          # ignore scores of zero or lower
          next if sim <= 0

          prefs[other].keys.each do |item|
            if !prefs[user].include? item or prefs[user][item] == 0
              # similarity * score
              totals.default = 0
              totals[item] += prefs[other][item] * sim
              # sum of similarities
              simSums.default = 0
              simSums[item] += sim
            end
          end
        end

        # Create a normalized list
        rankings = []
        items = []
        totals.each do |item,total|
          rankings << [total/simSums[item], item]
        end
        
        # So we can do everything in one SQL query
        ranking_ids = rankings.collect {|_, i| i }
        ar_items = options[:on_class].find(ranking_ids)
        ar_items = ar_items.inject({}){ |h, item| h[item.id] = item; h }

        # Return the sorted list
        rankings = rankings.select {|score, _| score > 0.0 }
        rankings = rankings.sort_by {|score, _| score }.reverse
        
        rankings.collect {|score, item_id|
          item = ar_items[item_id]
          def item.recommendation_score; return @recommendation_score; end
          def item.recommendation_score=(d); @recommendation_score = d; end
          item.recommendation_score = score
          item
        }
      end
      
      def self.dataset(options)
        result = {}
        item_prefs = self.tranform_prefs(self.prefs(options))
        for item in item_prefs.keys
          scores = []
          for other in item_prefs.keys
            scores << [self.__send__(options[:algorithm], item_prefs, item, other), other]
          end
          scores = scores.sort_by {|score,_| score }.reverse
          result[item] = scores
        end
        result
      end
      
      def self.dataset_recommended(user, options)
        scores = {}
        total_sim = {}
        items = user.aar_items_with_scores
        item_ids = items.values.collect(&:id)
        
        item_ids.each do |item_id|
          ratings = options[:class].aar_dataset[item_id]
          next unless ratings
          ratings.each do |similarity, item2_id|
            # Ignore if this user has already rated this item
            next if item_ids.include?(item2_id)
            
            scores[item2_id]    ||= 0
            total_sim[item2_id] ||= 0
            if options[:score]
              # Weighted sum of rating times similarity
              scores[item2_id]    += similarity * items[item_id].aar_score

              # Sum of all the similarities
              total_sim[item2_id] += similarity
            else
              scores[item2_id]    += similarity 
              total_sim[item2_id] += 1.0
            end
          end
        end
        
        # Divide each total score by total weighting to get an average
        rankings = []
        scores.each do |item, score|
          rankings << [0, item] and next if score == 0
          rankings << [score/total_sim[item], item]
        end
        
        # So we can do everything in one SQL query
        ranking_ids = rankings.collect {|_, i| i }
        ar_items = options[:on_class].find(ranking_ids)
        ar_items = ar_items.inject({}){ |h, item| h[item.id] = item; h }

        rankings.sort_by {|score, _| score }.reverse.collect {|score, item_id|
          item = ar_items[item_id]
          item.instance_variable_set('@recommendation_score', score)
          def item.recommendation_score; return @recommendation_score; end
          item
        }
      end
      
      private

        def self.mutual_items(person1, person2)
          si = []
          person1.each_pair do |item,value|
            si << item if person2.include?(item)
          end
          si
        end
      
        def self.tranform_prefs(prefs)
          result = {}
          for person in prefs.keys
            for item in prefs[person].keys
              result[item] = {} if result[item] == nil
              # Flip item and person
              result[item][person] = prefs[person][item]
            end
          end
          return result
        end
    
    end

  end
end