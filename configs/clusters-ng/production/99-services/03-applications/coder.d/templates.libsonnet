{
  Templates:: [],
  AddTemplates()::
    std.foldl(
      function(acc, tmpl)
        acc
        .Config(tmpl.name + '_README.md', tmpl['README.md'])
        .Config(tmpl.name + '_main.tf', tmpl['main.tf']),
      self.Templates,
      self,
    ),
}
