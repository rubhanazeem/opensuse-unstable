xml.directory do
  @request_list.each do |r|
    xml.entry name: r
  end
end
