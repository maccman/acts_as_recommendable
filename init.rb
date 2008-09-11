# Include hook code here
require File.dirname(__FILE__) + '/lib/acts_as_recommendable'
ActiveRecord::Base.send(:include, MadeByMany::ActsAsRecommendable)

require File.dirname(__FILE__) + '/lib/progress_bar'

begin
  require 'inline'
  require File.dirname(__FILE__) + '/lib/optimizations'
rescue LoadError; end