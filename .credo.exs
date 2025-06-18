%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "src/", "web/", "apps/"],
        excluded: ["mix.lock"]
      },
      plugins: [],
      requires: [],
      strict: false,
      parse_timeout: 5000,
      color: true,
      checks: %{
        extra: [{Credo.Check.Refactor.Nesting, [max_nesting: 3]}],
        disabled: [
          {Credo.Check.Readability.ModuleDoc, []},
          {Credo.Check.Design.TagTODO, []}
          # ... other checks omitted for readability ...
        ]
      }
    }
  ]
}
