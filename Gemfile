source "https://rubygems.org"

# Specify your gem's dependencies in abmeter.gemspec
gemspec

gem "rake", "~> 13.0"

group :development, :test do
  gem "rspec", "~> 3.0"
  gem 'rubocop', '~> 1.7'
  gem 'rubocop-rspec'
  gem 'pry-byebug'
  # for better github actions reporting:
  gem 'rspec-github'
  gem 'vcr', '~> 6.2'
end
