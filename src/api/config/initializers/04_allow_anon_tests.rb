if Rails.env.test?
  CONFIG['allow_anonymous'] = true
  CONFIG['read_only_hosts'] = ['127.0.0.1', '::1']
end
