# rubocop:disable Metrics/ModuleLength
module Webui::WebuiHelper
  include ActionView::Helpers::JavaScriptHelper
  include ActionView::Helpers::AssetTagHelper
  include Webui::BuildresultHelper

  def bugzilla_url(email_list = '', desc = '')
    return '' if @configuration['bugzilla_url'].blank?

    assignee = email_list.first if email_list
    if email_list.length > 1
      cc = ('&cc=' + email_list[1..-1].join('&cc=')) if email_list
    end

    URI.escape(
      "#{@configuration['bugzilla_url']}/enter_bug.cgi?classification=7340&product=openSUSE.org" \
      "&component=3rd party software&assigned_to=#{assignee}#{cc}&short_desc=#{desc}"
    )
  end

  def fuzzy_time(time, with_fulltime = true)
    if Time.now - time < 60
      return 'now' # rails' 'less than a minute' is a bit long
    end

    human_time_ago = time_ago_in_words(time) + ' ago'

    if with_fulltime
      raw("<span title='#{l(time.utc)}' class='fuzzy-time'>#{human_time_ago}</span>")
    else
      human_time_ago
    end
  end

  def fuzzy_time_string(timestring)
    fuzzy_time(Time.parse(timestring), false)
  end

  def format_projectname(prjname, login)
    splitted = prjname.split(':', 3)
    if splitted[0] == 'home'
      prjname = if login && splitted[1] == login
                  '~'
                else
                  "~#{splitted[1]}"
                end
      prjname += ":#{splitted[-1]}" if splitted.length > 2
    end
    prjname
  end

  REPO_STATUS_ICONS = {
    'published' => 'truck',
    'outdated_published' => 'truck',
    'publishing' => 'truck-loading',
    'outdated_publishing' => 'truck-loading',
    'unpublished' => 'dolly-flatbed',
    'outdated_unpublished' => 'dolly-flatbed',
    'building' => 'cog',
    'outdated_building' => 'cog',
    'finished' => 'check',
    'outdated_finished' => 'check',
    'blocked' => 'lock',
    'outdated_blocked' => 'lock',
    'broken' => 'exclamation-triangle',
    'outdated_broken' => 'exclamation-triangle',
    'scheduling' => 'calendar-alt',
    'outdated_scheduling' => 'calendar-alt'
  }.freeze

  REPO_STATUS_DESCRIPTIONS = {
    'published' => 'Repository has been published',
    'publishing' => 'Repository is being created right now',
    'unpublished' => 'Build finished, but repository publishing is disabled',
    'building' => 'Build jobs exist for the repository',
    'finished' => 'Build jobs have been processed, new repository is not yet created',
    'blocked' => 'No build possible at the moment, waiting for jobs in other repositories',
    'broken' => 'The repository setup is broken, build or publish not possible',
    'scheduling' => 'The repository state is being calculated right now'
  }.freeze

  def repo_status_description(status)
    REPO_STATUS_DESCRIPTIONS[status] || 'Unknown state of repository'
  end

  def repo_status_icon(status)
    REPO_STATUS_ICONS[status] || 'eye'
  end

  def check_first(first)
    first.nil? ? true : nil
  end

  def image_template_icon(template)
    default_icon = image_url('drive-optical-48.png')
    icon = template.public_source_path('_icon') if template.has_icon?
    capture_haml do
      haml_tag(:object, data: icon || default_icon, type: 'image/png', title: template.title, width: 32, height: 32) do
        haml_tag(:img, src: default_icon, alt: template.title, width: 32, height: 32)
      end
    end
  end

  def repository_status_icon(status:, details: nil, html_class: '')
    outdated = status.sub!(/^outdated_/, '')
    description = outdated ? 'State needs recalculations, former state was: ' : ''
    description << repo_status_description(status)
    description << " (#{details})" if details

    repo_state_class = repository_state_class(outdated, status)

    tag.i('', class: "repository-state-#{repo_state_class} #{html_class} fas fa-#{repo_status_icon(status)}")
  end

  def repository_info(status)
    outdated = status.sub!(/^outdated_/, '')
    description = outdated ? 'State needs recalculations, former state was: ' : ''
    description << repo_status_description(status)
  end

  def repository_state_class(outdated, status)
    return 'outdated' if outdated

    status =~ /broken|building|finished|publishing|published/ ? status : 'default'
  end

  # Shortens a text if it longer than 'length'.
  def elide(text, length = 20, mode = :middle)
    shortened_text = text.to_s # make sure it's a String

    return '' if text.blank?

    return '...' if length <= 3 # corner case

    if text.length > length
      case mode
      when :left # shorten at the beginning
        shortened_text = '...' + text[text.length - length + 3..text.length]
      when :middle # shorten in the middle
        pre = text[0..length / 2 - 2]
        offset = 2 # depends if (shortened) length is even or odd
        offset = 1 if length.odd?
        post = text[text.length - length / 2 + offset..text.length]
        shortened_text = pre + '...' + post
      when :right # shorten at the end
        shortened_text = text[0..length - 4] + '...'
      end
    end
    shortened_text
  end

  def elide_two(text1, text2, overall_length = 40, mode = :middle)
    half_length = overall_length / 2
    text1_free = half_length - text1.to_s.length
    text1_free = 0 if text1_free.negative?
    text2_free = half_length - text2.to_s.length
    text2_free = 0 if text2_free.negative?
    [elide(text1, half_length + text2_free, mode), elide(text2, half_length + text1_free, mode)]
  end

  def force_utf8_and_transform_nonprintables(text)
    return '' if text.blank?

    text.force_encoding('UTF-8')
    text = 'The file you look at is not valid UTF-8 text. Please convert the file.' unless text.valid_encoding?
    # Ged rid of stuff that shouldn't be part of PCDATA:
    text.gsub(%r{([^a-zA-Z0-9&;<>/\n \t()])}) do
      if Regexp.last_match(1)[0].getbyte(0) < 32
        ''
      else
        Regexp.last_match(1)
      end
    end
  end

  def next_codemirror_uid
    return @codemirror_editor_setup = 0 unless @codemirror_editor_setup

    @codemirror_editor_setup += 1
  end

  def codemirror_style(opts = {})
    opts.reverse_merge!(read_only: false, no_border: false, width: 'auto', height: 'auto')

    style = ".CodeMirror {\n"
    style += "border-width: 0 0 0 0;\n" if opts[:no_border] || opts[:read_only]
    style += "height: #{opts[:height]};\n" unless opts[:height] == 'auto'
    style += "width: #{opts[:width]}; \n" unless opts[:width] == 'auto'
    style + "}\n"
  end

  def package_link(pack, opts = {})
    opts[:project] = pack.project.name
    opts[:package] = pack.name
    project_or_package_link(opts)
  end

  def link_to_package(prj, pkg, opts)
    opts[:project_text] ||= opts[:project]
    opts[:package_text] ||= opts[:package]

    unless opts[:trim_to].nil?
      opts[:project_text], opts[:package_text] =
        elide_two(opts[:project_text], opts[:package_text], opts[:trim_to])
    end

    out = if opts[:short]
            ''.html_safe
          else
            'package '.html_safe
          end

    opts[:short] = true # for project
    out += link_to_project(prj, opts) + ' / ' +
           link_to_if(pkg, opts[:package_text],
                      { controller: '/webui/package', action: 'show',
                        project: opts[:project],
                        package: opts[:package] }, class: 'package', title: opts[:package])
    if opts[:rev] && pkg
      out += ' ('.html_safe +
             link_to("revision #{elide(opts[:rev], 10)}",
                     { controller: '/webui/package', action: 'show',
                       project: opts[:project], package: opts[:package], rev: opts[:rev] },
                     class: 'package', title: opts[:rev]) + ')'.html_safe
    end
    out
  end

  def link_to_project(prj, opts)
    opts[:project_text] ||= opts[:project]
    out = if opts[:short]
            ''.html_safe
          else
            'project '.html_safe
          end
    project_text = opts[:trim_to].nil? ? opts[:project_text] : elide(opts[:project_text], opts[:trim_to])
    out + link_to_if(prj, project_text,
                     { controller: '/webui/project', action: 'show', project: opts[:project] },
                     class: 'project', title: opts[:project])
  end

  def project_or_package_link(opts)
    defaults = { package: nil, rev: nil, short: false, trim_to: 40 }
    opts = defaults.merge(opts)

    # only care for database entries
    prj = Project.where(name: opts[:project]).select(:id, :name, :updated_at).first
    # Expires in 2 hours so that changes of local and remote packages eventually result in an update
    Rails.cache.fetch(['project_or_package_link', prj.try(:id), opts], expires_in: 2.hours) do
      opts[:project_text] ||= format_projectname(opts[:project], opts[:creator]) if prj && opts[:creator]
      pkg = prj.packages.where(name: opts[:package]).select(:id, :name, :project_id).first if opts[:package] && prj && opts[:package] != :multiple
      if opts[:package]
        link_to_package(prj, pkg, opts)
      else
        link_to_project(prj, opts)
      end
    end
  end

  def creator_intentions(role = nil)
    role.blank? ? 'become bugowner (previous bugowners will be deleted)' : "get the role #{role}"
  end

  def replace_jquery_meta_characters(input)
    # The stated characters are c&p from https://api.jquery.com/category/selectors/
    input.gsub(%r{[!"#$%&'()*+,./:\\;<=>?@\[\]^`{|}~]}, '_')
  end

  def word_break(string, length = 80)
    return '' unless string

    # adds a <wbr> tag after an amount of given characters
    safe_join(string.scan(/.{1,#{length}}/), '<wbr>'.html_safe)
  end

  # paths param will accept one or more paths to match to make this tab active.
  # Only the first one will be used as link though if more than one is present.
  def tab_link(label, paths, active = false, html_class = 'nav-link text-nowrap')
    paths = [paths] unless paths.respond_to?(:select)
    paths_match = paths.select { |path| request.path.eql?(path) }.any?
    html_class << ' active' if active || paths_match

    link_to(label, paths.first, class: html_class)
  end

  def image_tag_for(object, size: 500, custom_class: 'img-fluid')
    return unless object

    alt = "#{object.name}'s avatar"
    image_tag(gravatar_icon(object.email, size), alt: alt, size: size, title: object.name, class: custom_class)
  end

  def gravatar_icon(email, size)
    if ::Configuration.gravatar && email
      "https://www.gravatar.com/avatar/#{Digest::MD5.hexdigest(email.downcase)}?s=#{size}&d=robohash"
    else
      'default_face.png'
    end
  end

  def home_title
    @configuration ? @configuration['title'] : 'Open Build Service'
  end

  def pick_max_problems(remaining_checks, remaining_build_problems, max_shown)
    show_checks = [max_shown, remaining_checks.length].min
    show_builds = [max_shown - show_checks, remaining_build_problems.length].min
    # always prefer one build fail
    if show_builds.zero? && remaining_build_problems.present?
      show_builds += 1
      show_checks -= 1
    end

    checks = remaining_checks.shift(show_checks)
    build_problems = remaining_build_problems.shift(show_builds)
    [checks, build_problems, remaining_checks, remaining_build_problems]
  end

  def feature_enabled?(feature)
    Flipper.enabled?(feature, User.possibly_nobody)
  end

  def feature_css_class
    css_classes = []
    css_classes << 'user-profile-redesign' if feature_enabled?(:user_profile_redesign)
    css_classes << 'notifications-redesign' if feature_enabled?(:notifications_redesign)
    css_classes.join(' ')
  end

  def sign_up_link(css_class: nil)
    return unless can_sign_up?

    if proxy_mode?
      link_to(sign_up_params[:url], class: css_class) do
        link_content('Sign Up', css_class, 'fa-user-plus')
      end
    else
      link_to('#', class: css_class, data: { toggle: 'modal', target: '#sign-up-modal' }) do
        link_content('Sign Up', css_class, 'fa-user-plus')
      end
    end
  end

  def log_in_link(css_class: nil)
    if kerberos_mode?
      link_to(new_session_path, class: css_class) do
        link_content('Log In', css_class, 'fa-sign-in-alt')
      end
    else
      link_to('#', class: css_class, data: { toggle: 'modal', target: '#log-in-modal' }) do
        link_content('Log In', css_class, 'fa-sign-in-alt')
      end
    end
  end

  def link_content(text, css_class, icon)
    if css_class && css_class.include?('nav-link')
      capture do
        concat(tag.i('', class: "fas #{icon}"))
        concat(tag.div(text))
      end
    else
      text
    end
  end

  def sidebar_collapsed?
    cookies[:sidebar_collapsed].eql?('true')
  end
end

# rubocop:enable Metrics/ModuleLength
