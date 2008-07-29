ActiveRecord::Schema.define(:version => 1) do
  create_table "books", :force => true do |t|
    t.string   "name"
    t.datetime "created_at"
    t.datetime "updated_at"
  end
  
  create_table "user_books", :force => true do |t|
    t.integer "user_id",                :null => false
    t.integer "book_id",                :null => false
    t.integer "score",                 :default => 0
  end
  
  create_table "users", :force => true do |t|
    t.string   "name"
    t.datetime "created_at"
    t.datetime "updated_at"
  end
end