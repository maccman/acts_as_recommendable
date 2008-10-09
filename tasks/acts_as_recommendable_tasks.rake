namespace :recommendations do
  task :build => [:environment] do
    MadeByMany::ActsAsRecommendable::Logic.module_eval do
      # This will need to change to your specific model:
      options = User.aar_options
      
      puts 'Finding items...'

      # You may want to optimize this SQL, like this:
      # items = options[:on_class].connection.select_values("SELECT id from #{options[:on_class].table_name}").collect(&:to_i)
      items = options[:on_class].find(:all).collect(&:id)
      
      prefs = {}
      
      puts 'Finding users...'
      
      # You may want to optimize this SQL
      users = options[:class].find(:all, :include => options[:on])
      
      pbar = MadeByMany::ProgressBar.new('Gen matrix', items.length)
      items.each do |item_id|
        prefs[item_id] ||= {}
        users.each do |user|
          if user.aar_items_with_scores[item_id]
            score = user.aar_items_with_scores[item_id].aar_score
            prefs[item_id][user.id] = score
          end
        end
        pbar.inc
      end
      pbar.finish
      matrix = [users.collect(&:id), prefs]
      
      pbar = MadeByMany::ProgressBar.new('Gen dataset', prefs.keys.length)
      
      if options[:split_dataset]
        generate_dataset(options, matrix) {|item, scores|
          Rails.cache.write("aar_#{options[:on]}_#{item}", scores)
          pbar.inc
        }
      else
        result = {}
        generate_dataset(options, matrix) {|item, scores|
          result[item] = scores
          pbar.inc
        }
        Rails.cache.write("aar_#{options[:on]}_dataset", result)
      end
      
      pbar.finish
      
      puts 'Rebuild successful'
    end
  end
end