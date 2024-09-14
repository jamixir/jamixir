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
        disabled: [
          {Credo.Check.Readability.ModuleDoc, []},
          {Credo.Check.Design.TagTODO, []}
          # ... other checks omitted for readability ...
        ]
      }
    }
  ]
}
