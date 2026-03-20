# Changelog

All notable changes to this project will be documented in this file.

## [0.1.0] - 2026-03-20

### Added

- Initial `jido_ecto` package structure.
- `Jido.Ecto.Storage` implementation backed by `Ecto.Repo`.
- `Jido.Ecto.Migrations.create_storage_tables/1` migration helper.
- Checkpoint, thread metadata, and thread entry schemas for storage persistence.
- End-to-end storage and `Jido.Persist` test coverage with SQLite.
- Contributor docs, CI workflow, and release automation aligned with Jido package standards.
