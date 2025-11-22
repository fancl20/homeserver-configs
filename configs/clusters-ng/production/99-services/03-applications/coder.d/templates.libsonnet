{
  Templates:: [],
  AddTemplates()::
    std.foldl(
      function(acc, tmpl)
        acc
        .Config(tmpl.name + '/README.md', tmpl['README.md'])
        .Config(tmpl.name + '/main.tf', tmpl['main.tf']),
      self.Templates,
      self,
    ),
}
