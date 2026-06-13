require 'spec_helper'

# The published gem must contain only bin/**, lib/**, LICENSE.txt, and README.md.
# Monorepo-only files (CLAUDE.md, docs/, lockfiles, etc.) must never ship to
# RubyGems. bin/publish enforces the same on the built artifact at release time;
# this guards against a regression in spec.files on every CI run.
describe 'gem packaging' do
  let(:gemspec) { Gem::Specification.load(File.expand_path('../abmeter.gemspec', __dir__)) }
  let(:allowed_file) { %r{\A(bin|lib)/|\A(LICENSE\.txt|README\.md)\z} }

  it 'ships only bin/**, lib/**, LICENSE.txt, and README.md' do
    disallowed = gemspec.files.grep_v(allowed_file)

    expect(disallowed).to be_empty
  end

  it 'never ships CLAUDE.md' do
    expect(gemspec.files).not_to include('CLAUDE.md')
  end
end
