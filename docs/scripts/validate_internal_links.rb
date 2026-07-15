#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "optparse"
require "pathname"
require "set"
require "uri"

module DocumentationQuality
  class InternalLinks
    BASE_PATH = "/dspy.rb"
    SITE_HOST = "oss.vicente.services"
    LINK_ATTRIBUTES = /\b(?:href|src)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))/i.freeze
    MARKDOWN_LINK = /\[[^\]]*\]\(([^\s)]+)(?:\s+"[^"]*")?\)/.freeze
    BARE_URL = %r{https?://[^\s<>)]+}.freeze

    def initialize(output:)
      @output = Pathname(output).expand_path
      @html = {}
      @files = {}
      index_output
    end

    def errors
      return ["#{@output}: production output directory is missing"] unless @output.directory?

      failures = []
      @html.each do |route, record|
        each_html_reference(record.fetch(:path), record.fetch(:text)) do |line, href|
          validate_reference(failures, record.fetch(:path), line, href, route)
        end
      end
      %w[llms.txt llms-full.txt].each do |name|
        path = @output.join(name)
        unless path.file?
          failures << "#{path}: production reference is missing"
          next
        end
        each_text_reference(path, path.read(encoding: "UTF-8")) do |line, href|
          validate_reference(failures, path, line, href, "#{BASE_PATH}/#{name}")
        end
      end
      failures.uniq
    end

    private

    def index_output
      return unless @output.directory?

      Dir[@output.join("**/*")].sort.each do |path_string|
        path = Pathname(path_string)
        next unless path.file?

        relative = path.relative_path_from(@output).to_s
        public_path = "#{BASE_PATH}/#{relative}"
        @files[normalize_path(public_path)] = path
        next unless path.extname == ".html"

        route = if relative == "index.html"
                  "#{BASE_PATH}/"
                elsif relative.end_with?("/index.html")
                  "#{BASE_PATH}/#{relative.delete_suffix('index.html')}"
                else
                  public_path
                end
        text = path.read(encoding: "UTF-8")
        ids = text.scan(/\b(?:id|name)=(?:"([^"]+)"|'([^']+)')/i).map { |values| CGI.unescapeHTML(values.compact.first) }.to_set
        @html[normalize_path(route)] = {path: path, text: text, ids: ids}
      end
    end

    def each_html_reference(path, text)
      text.to_enum(:scan, LINK_ATTRIBUTES).each do
        match = Regexp.last_match
        number = text[0...match.begin(0)].count("\n") + 1
        yield number, CGI.unescapeHTML(match.captures.compact.first)
      end
    rescue Encoding::InvalidByteSequenceError => error
      yield 1, "invalid-encoding:#{error.message}"
    end

    def each_text_reference(_path, text)
      fence = nil
      text.each_line.with_index(1) do |line, number|
        if (opening = line.match(/^\s{0,3}(`{3,}|~{3,})/))
          token = opening[1]
          if fence.nil?
            fence = token[0]
          elsif token[0] == fence
            fence = nil
          end
          next
        end
        next if fence

        seen = []
        line.scan(MARKDOWN_LINK) { |match| seen << match.first }
        line.scan(BARE_URL) { |match| seen << match.delete_suffix(".").delete_suffix(",") }
        seen.uniq.each { |href| yield number, CGI.unescapeHTML(href) }
      end
    end

    def validate_reference(failures, file, line, raw_href, current_route)
      href = raw_href.to_s.strip
      return if href.empty?

      uri = parse_uri(href)
      unless uri
        failures << diagnostic(file, line, href, "malformed URL")
        return
      end
      if uri.scheme
        if %w[http https].include?(uri.scheme.downcase)
          unless uri.host
            failures << diagnostic(file, line, href, "malformed external URL: host is missing")
            return
          end
          return unless uri.host&.downcase == SITE_HOST
        elsif uri.scheme.downcase == "mailto"
          failures << diagnostic(file, line, href, "malformed mailto URL") if uri.opaque.to_s.empty? && uri.path.to_s.empty?
          return
        else
          return
        end
      elsif uri.host
        return unless uri.host.downcase == SITE_HOST
      end

      path, fragment = internal_destination(uri, href, current_route)
      return unless path
      unless path == BASE_PATH || path.start_with?("#{BASE_PATH}/")
        failures << diagnostic(file, line, href, "root-relative documentation link is missing #{BASE_PATH}")
        return
      end

      target = lookup(path)
      unless target
        failures << diagnostic(file, line, href, "internal route or file does not exist: #{path}")
        return
      end
      return if fragment.nil? || fragment.empty?
      return unless target[:ids]

      decoded = URI::DEFAULT_PARSER.unescape(fragment)
      failures << diagnostic(file, line, href, "fragment does not exist: ##{decoded}") unless target[:ids].include?(decoded)
    rescue ArgumentError => error
      failures << diagnostic(file, line, href, "invalid percent encoding: #{error.message}")
    end

    def parse_uri(href)
      URI.parse(href.gsub(" ", "%20"))
    rescue URI::InvalidURIError
      nil
    end

    def internal_destination(uri, href, current_route)
      if uri.scheme || uri.host
        [normalize_path(uri.path.empty? ? "/" : uri.path), uri.fragment]
      elsif href.start_with?("/")
        [normalize_path(uri.path), uri.fragment]
      else
        base = "https://#{SITE_HOST}#{current_route}"
        resolved = URI.join(base, href)
        [normalize_path(resolved.path), resolved.fragment]
      end
    end

    def lookup(path)
      normalized = normalize_path(path)
      return @html[normalized] if @html.key?(normalized)
      return {path: @files[normalized]} if @files.key?(normalized)

      with_slash = normalized.end_with?("/") ? normalized : "#{normalized}/"
      return @html[with_slash] if @html.key?(with_slash)
      index_file = normalize_path("#{with_slash}index.html")
      return {path: @files[index_file]} if @files.key?(index_file)

      nil
    end

    def normalize_path(path)
      value = path.to_s
      trailing = value.end_with?("/")
      clean = Pathname.new(value.empty? ? "/" : value).cleanpath.to_s
      clean = "/#{clean}" unless clean.start_with?("/")
      trailing && clean != "/" ? "#{clean}/" : clean
    end

    def diagnostic(file, line, href, message)
      "#{file}:#{line}: href=#{href.inspect}: #{message}"
    end
  end
end

if $PROGRAM_NAME == __FILE__
  output = Pathname(__dir__).join("../output").expand_path
  OptionParser.new { _1.on("--output PATH") { |path| output = Pathname(path).expand_path } }.parse!
  validator = DocumentationQuality::InternalLinks.new(output: output)
  errors = validator.errors
  abort(errors.map { "ERROR: #{_1}" }.join("\n")) unless errors.empty?
  puts "Rendered internal links valid: HTML and llms references resolve under /dspy.rb; external URLs were not fetched."
end
