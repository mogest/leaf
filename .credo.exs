# Credo's defaults already state CLAUDE.md's rules — alias ordering, aliasing anything nested
# deeper than 2 or called more than once, and a 120-character line — but only under `strict`.
%{
  configs: [
    %{
      name: "default",
      strict: true
    }
  ]
}
