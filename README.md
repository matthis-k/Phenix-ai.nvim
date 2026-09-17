# Phenix AI.nvim

Canonical Neovim client for Phenix AI.

This repository owns the Neovim-specific Lua client, UI, interaction model, and its Nix package. It depends on `matthis-k/phenix-ai` for the generic Phenix runtime, native Lua interface, and ACP/default-harness executable.

## Nix

`packages.<system>.default` and `packages.<system>.phenix-ai-nvim` expose the complete plugin. The package includes the matching native `phenix` Lua module and is configured to launch the matching packaged `phenix-acp` runtime.

`phenix-nvim` consumes this package. Phenix AI core does not depend on this repository.

The current `phenix-ai` input is pinned to the exact core revision from which this client was extracted. After the corresponding core PR lands, advance the input to `github:matthis-k/phenix-ai` and commit the generated lock file.
