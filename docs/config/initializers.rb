# Initializers allow you to configure Bridgetown and various plugins/gems used by
# your site. This file is executed during the initialization process.

Bridgetown.configure do |config|
  # Load the DSPy version from the gem
  version_file = File.expand_path("../../lib/dspy/version.rb", __dir__)
  
  require version_file
  config.dspy_version = DSPy::VERSION
  config.dspy_release_url = "https://github.com/vicentereig/dspy.rb/releases/tag/v#{DSPy::VERSION}"
  
  # Initialize sitemap plugin
  init :"bridgetown-sitemap"
end
