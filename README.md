# ABMeter Gem

[ABMeter](https://abmeter.ai) is a feature-flag and A/B-testing platform. You define parameters, experiments, and feature flags in the ABMeter Lab; this gem reads the value assigned to each user in your Ruby app and reports events back.

> **Breaking change in 0.3.0:** `ABMeter.reset!` now discards queued data without any network I/O; use `ABMeter.reset` for the previous drain-on-exit behavior.

## Supported Ruby versions

`abmeter` supports **Ruby 3.2 and newer**.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'abmeter'
```

And then execute:

```bash
$ bundle install
```

## Getting an API key

Sign up at [abmeter.ai](https://abmeter.ai), then in the **Lab** open **API Keys** and create one. Expose it to your app (e.g. as `ABMETER_API_KEY`).

## Usage

Configure the client once at startup:

```ruby
ABMeter.configure do |config|
  config.api_key = ENV['ABMETER_API_KEY']
end
```

The example below assumes a parameter `welcome_text` (in a space, with a variant, controlled by a running experiment or feature flag) and an event type `user_purchases_plan` already exist — create them through the ABMeter API or, more easily, your AI assistant over MCP. Until they do, `resolve_parameter` just returns the parameter's default and `track_event` rejects unknown event types.

```ruby
# In request handling: read the value assigned to this user. `user_id` is the
# only required field; an optional `email:` is available for predicate-based
# (email-pattern) audience targeting.
user = ABMeter::User.new(user_id: current_user.id)
text = ABMeter.resolve_parameter(user: user, parameter_slug: 'welcome_text')

# In business logic: record an action that feeds a metric.
ABMeter.track_event('user_purchases_plan', current_user.id, { plan: purchased_plan.name, price: purchased_plan.price })
```

The two calls are one loop: the experiment varies `welcome_text`, and the event feeds a metric whose effect the experiment measures across variants. Note that `resolve_parameter` is **not** a pure read — it resolves the value locally and records an exposure in the background; use `get_exposure` for the same resolution without submitting. Full guides live at [abmeter.ai](https://abmeter.ai).

## Shutdown

```ruby
# Graceful — bounded blocking, flushes pending exposures/events.
# Returns true on clean shutdown, false if the timeout elapsed.
ABMeter.reset(timeout: 5.0)

# Immediate — non-blocking, discards anything still queued.
# Use only when the process is exiting *right now* and you cannot afford I/O.
ABMeter.reset!
```

## Development

The gem uses [mise](https://mise.jdx.dev/) to pin Ruby (`mise.toml`). Pure-Ruby — no Postgres / Redis required.

```bash
brew install mise            # one-time
mise install                 # one-time: install pinned Ruby
bundle install
bundle exec rspec            # tests
bundle exec rubocop          # lint (if .rubocop.yml present)
```

The gem is tested against Ruby 3.2, 3.3, 3.4, and 4.0.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT). 
