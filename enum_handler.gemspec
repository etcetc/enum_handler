$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "enum_handler/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "enum_handler"
  s.version     = EnumHandler::VERSION
  s.authors     = ["Farhad Farzaneh"]
  s.email       = ["ff@onebeat.com"]
  s.homepage    = ""
  s.summary     = "Provides functionality relating to handling of enums used in ActiveRecord models"
  s.description = "Please see Readme file"

  s.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  s.test_files = Dir["test/**/*"]

  #  WARNING - enum_handler is not compatible with rails 4.0.x or 4.1.x, but it is compatible with 4.2.x
  s.add_runtime_dependency "rails", "> 3.2.0"

  s.add_development_dependency "rspec", "> 2.6"
  s.add_development_dependency "sqlite3"
end
