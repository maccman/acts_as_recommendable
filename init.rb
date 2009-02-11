# Include hook code here
require File.dirname(__FILE__) + '/lib/acts_as_recommendable'
ActiveRecord::Base.send(:include, MadeByMany::ActsAsRecommendable)

require File.dirname(__FILE__) + '/lib/progress_bar'

require File.dirname(__FILE__) + '/lib/cache_fix'

# Fix RubyInline's permission problem,
# RubyInline doesn't like directories with
# group write permissions (like /tmp).
ENV['INLINEDIR'] = File.join(Rails.respond_to?(:root) ? Rails.root : RAILS_ROOT, 'tmp', 'rubyinline')
begin
  require 'inline'
  require File.dirname(__FILE__) + '/lib/optimizations'
rescue LoadError; end