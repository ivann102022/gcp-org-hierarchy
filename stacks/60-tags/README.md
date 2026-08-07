<!--
File:        stacks/60-tags/README.md
Author:      Ismael Cruz
Version:     0.1.0
Description: Placeholder for the tags stack — planned for v0.3.0.
             Not yet scaffolded with HCL.
-->

# Stack `60-tags` (planned v0.3.0)

Resource Manager tag keys and tag values at the Organization scope for cross-tier governance (e.g. `environment=prod|nonprod`, `data-classification=public|internal|confidential`). Also demonstrates one tag-based IAM condition as a reference example.

**Not yet implemented.** Scaffolded as an empty directory to reserve the stack number and document intent. Implementation lands in v0.3.0.

Opt-in by default (`create_tags = false`): tags are useful but not universally required, and creating them introduces a small ongoing operational cost (tag propagation, tag inheritance semantics on folder moves).

## Planned outputs

- `tag_keys` &mdash; tag key display name &rarr; ID.
- `tag_values` &mdash; `"<key>/<value>"` &rarr; ID.

## Cross-references

- [../../docs/architecture.md](../../docs/architecture.md) &mdash; section "`60-tags` (planned v0.3.0)".
- [../../docs/contract.md](../../docs/contract.md) &mdash; planned outputs.
