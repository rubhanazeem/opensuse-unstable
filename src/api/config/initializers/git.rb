module Git
  if File.exist?(File.join(Rails.root, 'last_deploy'))
    COMMIT = File.open(File.join(Rails.root, 'last_deploy'), 'r') { |f| GIT_REVISION = f.gets.try(:chomp) }
    LAST_DEPLOYMENT = File.new(File.join(Rails.root, 'last_deploy')).mtime
  else
    COMMIT = `SHA1=$(git rev-parse --short HEAD 2> /dev/null); if [ $SHA1 ]; then echo $SHA1; else echo ''; fi`.chomp
    LAST_DEPLOYMENT = ''.freeze
  end
end
