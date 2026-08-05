# Temporary Attribute Patches

Use patches to test a concrete presentation hypothesis without rebuilding.
Patches are not implementation and cannot prove a source fix.

## Workflow

1. Confirm both `attributePatchDiscovery` and `attributePatching`.
2. Call `list_patchable_attributes`. Select an advertised `attributePattern`
   compatible with the target role. Empty `targetRoles` means any compatible
   node role.
3. Refresh the hierarchy and locate the latest live node. Patch calls target
   live Runtime objects rather than frozen snapshot data.
4. For parameterized patterns, use the concrete identifier returned by node
   details.
5. Encode the value exactly as required by `valueType`, `valueConstraints`,
   `acceptedFormats`, and allowed-value casing.
6. Apply one hypothesis with `apply_attribute_patch` and confirm `actualValue`.
7. Use `list_attribute_patches` to verify active state, then re-read live detail
   and capture visual evidence when relevant.
8. If disproved, revert immediately. If confirmed, translate the hypothesis into
   a source change.
9. Use `revert_attribute_patch` for one experiment or
   `clear_attribute_patches` for all experiments.
10. Rebuild or relaunch, obtain a new `appId`, and verify source-backed behavior
    with `patchCount == 0`.

The Runtime catalog is the only source of truth for supported paths. Never use a
remembered whitelist or infer an unadvertised property. If `patchConflict` is
returned, inspect active patches and revert the conflicting one before retrying.

Do not use patches for business state, persistent data, or arbitrary method
invocation. App relaunch, rebuild, or Runtime replacement clears the live patch
state, but final verification must still confirm that no patch remains.
