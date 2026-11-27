import Config

config :git_ops,
  mix_project: JidoEcto.MixProject,
  changelog_file: "CHANGELOG.md",
  repository_url: "https://github.com/agentjido/jido_ecto",
  manage_mix_version?: true,
  version_source: :tags,
  version_tag_prefix: "v"
