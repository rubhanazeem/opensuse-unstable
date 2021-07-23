module Webui::PackageHelper
  include Webui::WebuiHelper

  def removable_file?(file_name:, package:)
    !file_name.start_with?('_service:') && !package.belongs_to_product?
  end

  def file_url(project, package, filename, revision = nil)
    opts = {}
    opts[:rev] = revision if revision
    Package.source_path(project, package, filename, opts)
  end

  def human_readable_fsize(bytes)
    number_to_human_size(bytes)
  end

  def title_or_name(package)
    package.title.presence || package.name
  end

  def guess_code_class(filename)
    return 'xml' if filename.in?(['_aggregate', '_link', '_patchinfo', '_service']) || filename =~ /.*\.service/
    return 'shell' if filename =~ /^rc[\w-]+$/ # rc-scripts are shell
    return 'python' if filename =~ /^.*rpmlintrc$/
    return 'makefile' if filename == 'debian.rules'
    return 'baselibs' if filename == 'baselibs.conf'
    return 'spec' if filename =~ /^macros\.\w+/
    return 'dockerfile' if filename =~ /^(D|d)ockerfile.*$/

    ext = Pathname.new(filename).extname.downcase
    case ext
    when '.group', '.kiwi', '.product' then 'xml'
    when '.patch', '.dif' then 'diff'
    when '.pl', '.pm' then 'perl'
    when '.py' then 'python'
    when '.rb' then 'ruby'
    when '.tex' then 'latex'
    when '.js' then 'javascript'
    when '.sh' then 'shell'
    when '.spec' then 'rpm-spec'
    when '.changes' then 'rpm-changes'
    when '.diff', '.php', '.html', '.xml', '.css', '.perl' then ext[1..-1]
    else ''
    end
  end

  def nbsp(text)
    result = ''.html_safe
    text.split.each do |text_chunk|
      result << text_chunk
      result << '&nbsp;'.html_safe
    end
    result.chomp!('&nbsp;')

    if result.length >= 50
      # Allow break line for very long file names
      result = result.scan(/.{1,50}/).join('<wbr>')
    end
    # We just need to make it a SafeBuffer object again, after calling chomp and join.
    # But at this point we know it truly is html safe
    result.html_safe
  end

  def humanize_time(seconds)
    [[60, :s], [60, :m], [24, :h], [0, :d]].map do |count, name|
      if seconds.positive?
        seconds, n = seconds.divmod(count.positive? ? count : seconds + 1)
        "#{n.to_i}#{name}"
      end
    end.compact.reverse.join(' ')
  end

  def uploadable?(filename, architecture)
    ::Cloud::UploadJob.new(filename: filename, arch: architecture).uploadable?
  end

  def expand_diff?(filename, state)
    state != 'deleted' && filename.exclude?('/') && (filename == '_patchinfo' || filename.ends_with?('.spec', '.changes'))
  end

  def viewable_file?(filename)
    !Package.is_binary_file?(filename) && filename.exclude?('/')
  end

  def calculate_revision_on_state(revision, state)
    result = revision.to_i
    result -= 1 if state == 'deleted'
    [result, 0].max
  end
end
