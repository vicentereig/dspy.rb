# frozen_string_literal: true

require "cgi"
require "json"
require "yaml"

class UrlRedirects < Bridgetown::Builder
  def build
    hook :site, :pre_render, priority: :high do |site|
      manifest = YAML.safe_load_file(File.join(site.root_dir, "editorial/url-redirects.yml"))
      redirects = manifest.fetch("redirects").select { _1.fetch("state") == "active" }
      base_path = site.config.fetch("base_path", "").delete_suffix("/")
      site_url = site.config.fetch("url").delete_suffix("/")

      redirects.each do |redirect|
        page = Bridgetown::GeneratedPage.new(site, site.source, "/", "redirect.html")
        page.data.permalink = redirect.fetch("from")
        page.data.layout = "none"
        page.data.sitemap = false
        page.content = redirect_html(redirect, base_path, site_url)
        site.generated_pages << page
      end

      public_manifest = Bridgetown::GeneratedPage.new(site, site.source, "/", "redirects.json")
      public_manifest.data.permalink = "/redirects.json"
      public_manifest.data.layout = "none"
      public_manifest.data.sitemap = false
      public_manifest.content = JSON.pretty_generate(
      "version" => manifest.fetch("version"),
        "base_path" => base_path,
        "redirects" => redirects.map { resolved_redirect(_1, base_path) }
      ) + "\n"
      site.generated_pages << public_manifest
    end
  end

  private

  def resolved_redirect(redirect, base_path)
    {
      "from" => "#{base_path}#{redirect.fetch("from")}",
      "to" => public_target(redirect.fetch("to"), base_path),
    }
  end

  def public_target(target, base_path)
    return target if target.match?(%r{\Ahttps://})

    "#{base_path}#{target}"
  end

  def redirect_html(redirect, base_path, site_url)
    target = public_target(redirect.fetch("to"), base_path)
    canonical = target.sub(/#.*/, "")
    canonical = "#{site_url}#{canonical}" unless canonical.match?(%r{\Ahttps://})
    fragments = redirect.fetch("fragments", {})
    mappings = fragments.fetch("mappings", {})
    retired = fragments.fetch("retired", {}).keys

    <<~HTML
      <!doctype html>
      <html lang="en" data-redirect-id="#{CGI.escapeHTML(redirect.fetch("id"))}">
      <head>
        <meta charset="utf-8">
        <title>Documentation moved</title>
        <link rel="canonical" href="#{CGI.escapeHTML(canonical)}">
        <meta http-equiv="refresh" content="0; url=#{CGI.escapeHTML(target)}">
        <script>
          (() => {
            const defaultTarget = #{script_json(target)};
            const mappings = #{script_json(mappings)};
            const retired = #{script_json(retired)};
            let oldFragment = window.location.hash.slice(1);
            try { oldFragment = decodeURIComponent(oldFragment); } catch (_) { /* use encoded input */ }
            let destination = defaultTarget;
            if (oldFragment && Object.hasOwn(mappings, oldFragment)) {
              const replacement = mappings[oldFragment];
              destination = replacement.startsWith("/")
                ? #{script_json(base_path)} + replacement
                : defaultTarget.replace(/#.*$/, "") + "#" + replacement;
            }
            window.location.replace(destination);
          })();
        </script>
      </head>
      <body><p>This documentation moved to <a href="#{CGI.escapeHTML(target)}">#{CGI.escapeHTML(target)}</a>.</p></body>
      </html>
    HTML
  end

  def script_json(value)
    JSON.generate(value)
      .gsub("<", "\\u003c")
      .gsub(">", "\\u003e")
      .gsub("&", "\\u0026")
      .gsub("\u2028", "\\u2028")
      .gsub("\u2029", "\\u2029")
  end
end

UrlRedirects.register
