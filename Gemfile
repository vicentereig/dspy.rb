source 'https://rubygems.org'

gemspec name: "dspy"

if ENV.fetch('DSPY_WITH_SCHEMA', '1') == '1'
  gemspec name: "dspy-schema"
end

if ENV.fetch('DSPY_WITH_CODE_ACT', '0') == '1'
  gemspec name: "dspy-code_act"
end

if ENV.fetch('DSPY_WITH_DATASETS', '1') == '1'
  gemspec name: "dspy-datasets"
end

if ENV.fetch('DSPY_WITH_EVALS', '1') == '1'
  gemspec name: "dspy-evals"
end

if ENV.fetch('DSPY_WITH_MIPROV2', '1') == '1'
  gemspec name: "dspy-miprov2"
end

if ENV.fetch('DSPY_WITH_O11Y', '1') == '1'
  gemspec name: "dspy-o11y"
end

if ENV.fetch('DSPY_WITH_O11Y_LANGFUSE', '1') == '1'
  gemspec name: "dspy-o11y-langfuse"
end

if ENV.fetch('DSPY_WITH_GEPA', '1') == '1'
  gemspec name: "dspy-gepa"
  gemspec name: "gepa"
end

group :development, :test do
  gem 'rspec', '~> 3.12'
  gem 'dotenv', '~> 2.8'
  gem 'vcr', '~> 6.2'
  gem 'webmock', '~> 3.18'
  gem "byebug", "~> 11.1"
  gem 'faraday', '~> 2.0'
end

gem "newrelic_rpm", "~> 9.21"
gem "csv", "~> 3.2"
