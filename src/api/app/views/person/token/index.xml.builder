xml.directory(count: @list.length) do |dir|
  @list.each do |token|
    p = { id: token.id, string: token.string, kind: token.token_name }
    if token.package
      p[:project] = token.package.project.name
      p[:package] = token.package.name
    end
    dir.entry(p)
  end
end
