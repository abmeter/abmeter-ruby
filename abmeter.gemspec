require_relative 'lib/abmeter/version'

Gem::Specification.new do |spec|
  spec.name          = 'abmeter'
  spec.version       = ABMeter::VERSION
  spec.authors       = ['ABMeter']
  spec.email         = ['info@abmeter.com']

  spec.summary       = 'ABMeter SDK for feature flags and A/B testing'
  spec.description   = 'ABMeter SDK is a client library for interacting with the ABMeter testing service'
  spec.homepage      = 'https://github.com/abmeter/abmeter-ruby'
  spec.license       = 'MIT'
  spec.required_ruby_version = Gem::Requirement.new('>= 3.2.0')

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.glob('{bin,lib}/**/*') + ['LICENSE.txt', 'README.md']
  spec.require_paths = ['lib']

  # Dependencies
  spec.add_dependency 'activesupport', '>= 7.0'
  spec.add_dependency 'faraday', '~> 2.0'

  spec.metadata['rubygems_mfa_required'] = 'true'
end
