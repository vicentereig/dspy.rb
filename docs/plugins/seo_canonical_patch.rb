# frozen_string_literal: true

module SeoCanonicalPatch
  module DropPatch
    def canonical_url
      @canonical_url ||= if page["canonical_url"].to_s.present?
                           page["canonical_url"]
                         elsif page["url"].to_s.present?
                           cleaned_url = strip_leading_base_path(page["url"].to_s)
                           filters.absolute_url(cleaned_url).to_s.gsub(%r!/index\.html$!, "/")
                         else
                           cleaned_relative = strip_leading_base_path(page["relative_url"].to_s)
                           filters.absolute_url(cleaned_relative).to_s.gsub(%r!/index\.html$!, "/")
                         end
    end

    private

    def strip_leading_base_path(url)
      base_path = @context.registers[:site].config["base_path"].to_s
      return url if base_path.empty?

      url.sub(%r!^#{Regexp.escape(base_path)}!, "")
    end
  end
end

Bridgetown::SeoTag::Drop.prepend(SeoCanonicalPatch::DropPatch)
