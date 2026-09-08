# Storage conformance tests

`test/jido_ecto/storage_test.exs` runs the shared `Jido.Storage` checkpoint and
thread-journal contract suites from the sibling Jido repository. The assertions
are loaded at test time; they are not copied into this repository, so the
adapter is tested against the same contract as Jido's other storage adapters.

## Test support source

The default layout is two sibling checkouts:

```text
parent/
├── jido/
└── jido_ecto/
```

When the repositories are arranged differently, set
`JIDO_STORAGE_CONFORMANCE_ROOT` to the Jido checkout's `test/support` directory:

```sh
JIDO_STORAGE_CONFORMANCE_ROOT=/path/to/jido/test/support mix test
```

This makes the integration portable for CI without embedding an absolute path.
The test helper fails early with the required setup when the shared suites are
not available.

## Backend selection

The test repository is selected through environment variables. SQLite remains
the default and does not require a service:

```sh
MIX_ENV=test mix clean
JIDO_ECTO_TEST_DB=sqlite mix test
```

Run the same contract suite against PostgreSQL by providing the normal
`PG*` connection variables:

```sh
MIX_ENV=test mix clean
JIDO_ECTO_TEST_DB=postgres \
  PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres \
  PGPASSWORD=postgres PGDATABASE=jido_ecto_test \
  mix test
```

The PostgreSQL build also runs `test/jido_ecto/postgres_concurrency_test.exs`.
It synchronizes real writers with a process barrier and verifies that burst
appends succeed through the adapter's bounded retry path, revisions equal
committed journal rows, and sequence numbers are unique and contiguous. It
also verifies the single-winner contract for two writers using the same
`expected_rev`.

`Jido.Ecto.TestRepo` embeds its adapter at compile time. Use a clean build (or
otherwise recompile after changing `JIDO_ECTO_TEST_DB`) when switching between
SQLite and PostgreSQL in the same checkout.

## Scope and mismatch

The shared checkpoint and thread suites run unchanged against both backends.
The adapter-specific tests in `test/jido_ecto/storage_test.exs` remain
responsible for Ecto error mapping, transaction behavior, persisted-state
validation, and corruption handling. Prefix/schema coverage remains in
`test/jido_ecto/migrations_test.exs`; its live PostgreSQL case creates and
verifies a real schema.

The PostgreSQL-specific concurrency suite is intentionally separate from the
shared contract because SQLite does not provide PostgreSQL row-lock semantics.
The shared helper therefore contains deterministic contract assertions only;
SQLite and PostgreSQL both run it unchanged. PostgreSQL additionally runs the
dedicated two-writer stress suite. Any backend-specific failure is reported by
the backend's own assertion rather than by a weakened substitute.

## CI conformance pin

CI checks out the Jido conformance helpers at the exact commit SHA recorded in
the workflow. That reviewed pin prevents contract changes from entering
Jido.Ecto by floating Jido's default branch. Update the SHA deliberately when
adopting a reviewed conformance-contract revision.
