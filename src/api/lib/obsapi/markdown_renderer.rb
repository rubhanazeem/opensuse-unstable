require 'uri'
require 'cgi'

module OBSApi
  class MarkdownRenderer < Redcarpet::Render::Safe
    include Rails.application.routes.url_helpers

    def self.default_url_options
      { host: ::Configuration.first.obs_url }
    end

    def preprocess(fulldoc)
      # request#12345 links
      fulldoc.gsub!(/(sr|req|request)#(\d+)/i) { |s| "[#{s}](#{request_show_url(number: Regexp.last_match(2))})" }
      # @user links
      fulldoc.gsub!(/([^\w]|^)@(\b[-\w]+\b)(?:\b|$)/) \
                   { "#{Regexp.last_match(1)}[@#{Regexp.last_match(2)}](#{user_url(Regexp.last_match(2))})" }
      # bnc#12345 links
      IssueTracker.all.each do |t|
        fulldoc = t.get_markdown(fulldoc)
      end
      fulldoc
    end

    def block_html(raw_html)
      # sanitize the HTML we get
      scrubber = Rails::Html::PermitScrubber.new.tap { |a| a.tags = ['b', 'em', 'i', 'strong', 'u', 'pre'] }
      Rails::Html::SafeListSanitizer.new.sanitize(raw_html, scrubber: scrubber)
    end

    # unfortunately we can't call super (into C) - see vmg/redcarpet#51
    def link(link, title, content)
      # A return value of nil will not output any data
      # the contents of the span will be copied verbatim
      return nil if link.blank?

      title = " title='#{title}'" if title.present?
      begin
        link = URI.join(::Configuration.obs_url, link)
      rescue URI::InvalidURIError
      end
      "<a href='#{link}'#{title}>#{CGI.escape_html(content)}</a>"
    end

    def block_code(code, language)
      language ||= :plaintext
      CodeRay.scan(code, language).div(css: :class)
    rescue ArgumentError
      CodeRay.scan(code, :plaintext).div(css: :class) unless language == :plaintext
    end
  end
end
