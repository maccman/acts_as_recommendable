# desc "Explaining what the task does"
# task :acts_as_recommendable do
#   # Task goes here
# end
namespace :recommendations do
  task :rebuild => [:environment] do
    User.aar_dataset(true)
  end
end