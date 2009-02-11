# ActsAsRecommended
module MadeByMany
  module ActsAsRecommendable
    def self.included(base)
      base.extend(ActsMethods)
    end
      
    module ActsMethods
      # Send an array to ActiveRecord without fear that some elements don't exist.
      def find_some_without_failing(ids, options = {})
        return [] if !ids or ids.empty?
        conditions = " AND (#{sanitize_sql(options[:conditions])})" if options[:conditions]
        ids_list   = ids.map { |id| quote_value(id,columns_hash[primary_key]) }.join(',')
        options.update :conditions => "#{quoted_table_name}.#{connection.quote_column_name(primary_key)} IN (#{ids_list})#{conditions}"
        result = find_every(options)
        result
      end
      
      def acts_as_recommendable(on, options = {})
        defaults = {
          :algorithm      => :sim_pearson,
          :use_dataset    => false,
          :split_dataset  => true,
          :limit          => 10,
          :min_score      => 0.0
        }
        
        options = defaults.merge(options)

        # reflect on the specified association to derive the extra details we need
        options[:on]          =   on
        assoc = self.reflections[on.to_sym]
        through_assoc = assoc.through_reflection
        options[:through] = through_assoc.name
        raise "No association specified to recommend." if assoc.nil?
        raise "The #{on} association does not have a :through association" unless through_assoc
        
        on_class_name         =   assoc.class_name
        options[:on_singular] ||= on_class_name.downcase
        options[:on_class]    ||= assoc.klass
        
        options[:class] = self
        
        options[:through_singular]  ||= through_assoc.class_name.downcase
        options[:through_class]     ||= through_assoc.klass
        
        class_inheritable_accessor :aar_options
        self.aar_options = options
        
        options[:on_class].class_eval do
          define_method "similar_#{options[:on]}" do
            Logic.similar_items(self, options)
          end
        end

        define_method "similar_#{options[:class].name.underscore.pluralize}" do
          Logic.similar_users(self, options)
        end
          
        define_method "recommended_#{options[:on_class].name.underscore.pluralize}" do
          if self.aar_options[:use_dataset]
            Logic.dataset_recommended(self, options)
          else
            Logic.recommended(self, options)
          end
        end
        
        define_method "aar_items_with_scores" do
          @aar_items_with_scores ||= begin
            self.__send__(self.aar_options[:through]).collect {|ui|
              item = ui.__send__(self.aar_options[:on_singular])
              next unless item
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
            }.compact.inject({}) {|h, item| h[item.id] = item; h }
          end
        end
                
      end
    end
      
    module Logic
      
      def self.matrix(options)
        items = options[:on_class].find(:all).collect(&:id)
        prefs = {}
        users = options[:class].find(:all, :include => options[:on])
        users.each do |user|
          prefs[user.id] ||= {}
          items.each do |item_id|
            if user.aar_items_with_scores[item_id]
              score = user.aar_items_with_scores[item_id].aar_score
              prefs[user.id][item_id] = score
            end
          end
        end
        [items, prefs]
      end
      
      def self.inverted_matrix(options)
        items = options[:on_class].find(:all).collect(&:id)
        prefs = {}
        users = options[:class].find(:all, :include => options[:on])
        items.each do |item_id|
          prefs[item_id] ||= {}
          users.each do |user|
            if user.aar_items_with_scores[item_id]
              score = user.aar_items_with_scores[item_id].aar_score
              prefs[item_id][user.id] = score
            end
          end
        end
        [users.collect(&:id), prefs]
      end
    
      # Euclidean distance 
      def self.sim_distance(prefs, items, person1, person2)
        return 0 if items.length == 0

        squares = []
        
        items.each do |item|
          squares << ((prefs[person1][item] || 0.0) - (prefs[person2][item] || 0.0)) ** 2
        end
        
        sum_of_squares = squares.inject { |sum,value| sum += value }
        return 1/(1 + sum_of_squares)
      end
    
      # Pearson score
      def self.sim_pearson(prefs, items, person1, person2)
        n = items.length
        return 0 if n == 0

        sum1 = sum2 = sum1Sq = sum2Sq = pSum = 0.0
        
        items.each do |item|
          prefs1_item = prefs[person1][item] || 0.0
          prefs2_item = prefs[person2][item] || 0.0
          sum1   += prefs1_item
          sum2   += prefs2_item
          sum1Sq += prefs1_item ** 2
          sum2Sq += prefs2_item ** 2
          pSum   += prefs2_item * prefs1_item
        end

        num = pSum - ( ( sum1 * sum2 ) / n )
        den = Math.sqrt( ( sum1Sq - ( sum1 ** 2 ) / n ) * ( sum2Sq - ( sum2 ** 2 ) / n ) )
        
        return 0 if den == 0

        num / den
      end
      
      def self.similar_users(user, options)
        rankings = []
        items, prefs = self.matrix(options)
        prefs.each do |u, _|
          next if u == user.id
          rankings << [self.__send__(options[:algorithm], prefs, items, user.id, u), u]
        end
        
        rankings = rankings.select {|score, _| score > options[:min_score] }
        rankings = rankings.sort_by {|score, _| score }.reverse
        rankings = rankings[0..(options[:limit] - 1)]
        
        # Return the sorted list
        ranking_ids = rankings.collect {|_, u| u }
        ar_users = options[:class].find_some_without_failing(ranking_ids)
        ar_users = ar_users.inject({}){ |h, user| h[user.id] = user; h }
        
        rankings.collect {|score, user_id|
          user = ar_users[user_id]
          def user.similar_score; return @similar_score; end
          def user.similar_score=(d); @similar_score = d; end
          user.similar_score = score
          user
        }
      end
      
      def self.similar_items(item, options)
        if options[:use_dataset]
          if options[:split_dataset]
            rankings = Rails.cache.read("aar_#{options[:on]}_#{item.id}")
          else
            cached_dataset = Rails.cache.read("aar_#{options[:on]}_dataset")
            logger.warn 'ActsRecommendable has an empty dataset - rebuild it' unless cached_dataset
            rankings = cached_dataset && cached_dataset[self.id]
          end      
        else
          users, prefs = self.inverted_matrix(options)
          rankings = []
          prefs.each do |i, _|
            next if i == item.id
            rankings << [self.__send__(options[:algorithm], prefs, users, item.id, i), i]
          end
        end
        return [] unless rankings
        
        rankings = rankings.select {|score, _| score > options[:min_score] }
        rankings = rankings.sort_by {|score, _| score }.reverse
        rankings = rankings[0..(options[:limit] - 1)]
        
        # Return the sorted list
        ranking_ids = rankings.collect {|_, u| u }
        ar_items = options[:on_class].find_some_without_failing(ranking_ids)
        ar_items = ar_items.inject({}){ |h, item| h[item.id] = item; h }
        
        rankings.collect {|score, item_id|
          item = ar_items[item_id]
          def item.similar_score; return @similar_score; end
          def item.similar_score=(d); @similar_score = d; end
          item.similar_score = score
          item
        }
      end
        
      def self.recommended(user, options)
        totals        = {}
        sim_sums      = {}
        items, prefs  = self.matrix(options)
        user          = user.id
        user_ratings  = prefs[user]
  
        prefs.keys.each do |other|
          # don't compare me to myself
          next if other == user

          sim = self.__send__(options[:algorithm], prefs, items, user, other)

          # ignore scores of zero or lower
          next if sim <= 0

          prefs[other].keys.each do |item|
            if !prefs[user].include? item or prefs[user][item] == 0
              # similarity * score
              totals.default = 0
              totals[item] += prefs[other][item] * sim
              # sum of similarities
              sim_sums.default = 0
              sim_sums[item] += sim
            end
          end
        end

        # Create a normalized list
        rankings = []
        items = []
        totals.each do |item,total|
          rankings << [total/sim_sums[item], item]
        end
        
        # Return the sorted list
        rankings = rankings.select {|score, _| score > options[:min_score] }
        rankings = rankings.sort_by {|score, _| score }.reverse
        rankings = rankings[0..(options[:limit] - 1)]
        
        # So we can do everything in one SQL query
        ranking_ids = rankings.collect {|_, i| i }
        ar_items = options[:on_class].find_some_without_failing(ranking_ids)
        ar_items = ar_items.inject({}){ |h, item| h[item.id] = item; h }
        
        rankings.collect {|score, item_id|
          item = ar_items[item_id]
          def item.recommendation_score; return @recommendation_score; end
          def item.recommendation_score=(d); @recommendation_score = d; end
          item.recommendation_score = score
          item
        }
      end
      
      def self.generate_dataset(options, matrix = nil)
        users, prefs = matrix || self.inverted_matrix(options)
        for item in prefs.keys
          scores = []
          for other in prefs.keys
            next if other == item
            scores << [self.__send__(options[:algorithm], prefs, users, item, other), other]
          end
          scores = scores.sort_by {|score, _| score }.reverse
          yield(item, scores) if block_given?
        end
      end
      
      def self.dataset_recommended(user, options)
        scores    = {}
        total_sim = {}
        items     = user.aar_items_with_scores
        item_ids  = items.values.collect(&:id)
        unless options[:split_dataset]
          cached_dataset = Rails.cache.read("aar_#{options[:on]}_dataset")
          logger.warn 'ActsRecommendable has an empty dataset - rebuild it' unless cached_dataset
        end
        
        item_ids.each do |item_id|
          if options[:split_dataset] 
            ratings = Rails.cache.read("aar_#{options[:on]}_#{item_id}")
          else
            ratings = cached_dataset && cached_dataset[item_id]
          end
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
          next unless score > 0.0
          rankings << [score/total_sim[item], item]
        end
        
        rankings = rankings.select {|score, _| score > options[:min_score] }
        rankings = rankings.sort_by {|score, _| score }.reverse
        rankings = rankings[0..(options[:limit] - 1)]
        
        # So we can do everything in one SQL query
        ranking_ids = rankings.collect {|_, i| i }
        ar_items = options[:on_class].find_some_without_failing(ranking_ids)
        ar_items = ar_items.inject({}){ |h, item| h[item.id] = item; h }

        rankings.collect {|score, item_id|
          item = ar_items[item_id]
          def item.recommendation_score; @recommendation_score; end
          def item.recommendation_score=(d); @recommendation_score = d; end
          item.recommendation_score = score
          item
        }
      end
      
      def self.logger
        RAILS_DEFAULT_LOGGER
      end
    
    end

  end
end