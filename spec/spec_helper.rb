require 'rubygems'
require 'active_record'
require 'sqlite3'
require 'rspec'

$:.unshift File.expand_path(File.dirname(__FILE__) + '/../lib')

require 'enum_handler'

# See http://rubydoc.info/gems/rspec-core/RSpec/Core/Configuration
RSpec.configure do |config|
  config.treat_symbols_as_metadata_keys_with_true_values = true
  config.run_all_when_everything_filtered = true
  config.filter_run :focus

  # Run specs in random order to surface order dependencies. If you find an
  # order dependency and want to debug it, you can fix the order by providing
  # the seed, which is printed after each run.
  #     --seed 1234
  # config.order = 'random'
end

puts "Testing against Active Record version #{ActiveRecord::VERSION::STRING}"

config = YAML::load(IO.read(File.dirname(__FILE__) + '/database.yml'))
ActiveRecord::Base.establish_connection(config['test'])
def build_model_table(model, columns={})
  table_name = model.table_name
  puts "Creating table #{table_name}"
  ActiveRecord::Base.connection.create_table table_name, :force => true do |table|
    columns.each do |key,type|
      puts "creating column #{key.inspect} with type #{type.inspect}"
      table.column key, type      
    end
  end
end
