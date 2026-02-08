# ABMeter Gem

A simple A/B testing client library for Ruby applications.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'abmeter'
```

And then execute:

```bash
$ bundle install
```

## Usage

```ruby
# configure the client
ABMeter.configure do |config|
  config.api_key = ENV['ABMETER_API_KEY']
end

# Somewhere in the renedring code:
user = ABMeter.user(id: current_user.id, email: current_user.email)
text = ABMeter.param('welcome_text', user)

# Somewhere in the model code:
    current_user.plan = purchased_plan.name
    user = ABMeter.user(id: current_user.id, email: current_user.email)
    ABMeter.event(`user_purchases_plan`, user, {plan: purchased_plan.name, price: purchased_plan.price})
```

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT). 
