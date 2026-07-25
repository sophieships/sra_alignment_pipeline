# Verification Commands

`make help` is the authoritative target list; run everything from the repository root.
This file records only the CI-mapping facts `make` can't express.

- **Full local CI:** `make ci` — the local equivalent of `.github/workflows/ci.yml`. Its
  prerequisite list in the Makefile is always current (currently: `nextflow-version-check
  pipeline-check manifest-validation manifest-stub reference-cache-tests
  download-fallback-tests image-manifest-tests build-images-tests`).
- Install Nextflow before running `make ci`; the local target keeps the GitHub workflow
  behavior but does not install tools for you.
- Individual areas map 1:1 to the `ci:` prerequisites — run one target when iterating on
  that area (e.g. `make manifest-validation` for manifest error messages).
