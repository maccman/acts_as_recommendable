# Include hook code here
require File.dirname(__FILE__) + '/lib/acts_as_recommendable'
ActiveRecord::Base.send(:include, MadeByMany::ActsAsRecommendable)