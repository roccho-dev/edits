# WT-03 architecture-boundary RED

Purpose: make the `edits` operator-console boundary executable as a package/dependency contract before moving implementation.

Merge condition: provider-independent core, client/service/mux ports, exact provider adapters, and allowed dependency edges exist; worker/effect/result authority remains absent from production edits code.
