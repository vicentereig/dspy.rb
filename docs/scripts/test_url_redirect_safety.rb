#!/usr/bin/env ruby
# frozen_string_literal: true

require "bridgetown"
require_relative "../plugins/url_redirects"

builder = UrlRedirects.allocate
encoded = builder.send(:script_json, "</script><>&\u2028\u2029")

abort "script JSON contains a raw closing tag" if encoded.include?("</script")
abort "script JSON contains raw HTML metacharacters" if encoded.match?(/[<>&]/)
%w[\\u003c \\u003e \\u0026 \\u2028 \\u2029].each do |escape|
  abort "script JSON is missing #{escape}" unless encoded.include?(escape)
end

plugin = File.read(File.expand_path("../plugins/url_redirects.rb", __dir__))
abort "fragment decoding lacks malformed-input fallback" unless plugin.include?("try { oldFragment = decodeURIComponent(oldFragment); } catch (_)")

puts "Redirect script safety checks pass."
