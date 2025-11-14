{
  Templates:: [],
  AddTemplates()::
    local names = std.map(function(name) std.reverse(std.split(name, '/'))[1], self.Templates);
    std.foldl(
      function(acc, name)
        acc
        .Config(name + '/README.md', 'README.md')
        .Config(name + '/main.tf', 'main.tf'),
      names,
      self,
    ),
}
