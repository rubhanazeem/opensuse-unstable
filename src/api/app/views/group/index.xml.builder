xml.directory(count: @list.length) do
  @list.each do |group|
    xml.entry(name: group.title)
  end
end
