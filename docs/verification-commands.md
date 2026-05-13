# Verification Commands

Last reviewed: 2026-05-13.

Use these commands from the repository root when you want a local replacement
for GitHub Actions.

## Local Command Matrix

| Area | Command | What it verifies |
| --- | --- | --- |
| Pipeline parse | `make pipeline-check` | `nextflow run main.nf --help` succeeds |
| Manifest failures | `make manifest-validation` | Invalid image manifests fail with readable errors |
| Stub run | `make manifest-stub` | Stub execution emits manifest-derived container refs |
| Manifest script tests | `make image-manifest-tests` | Image manifest regression script |
| Build orchestration tests | `make build-images-tests` | `build_images.sh` orchestration regression script |
| Full local CI | `make ci` | Local equivalent of `.github/workflows/ci.yml` |

## CI Mapping

| Workflow | Local equivalent |
| --- | --- |
| `.github/workflows/ci.yml` | `make ci` |

Install Nextflow before running `make ci`. The local target keeps the GitHub
workflow behavior but does not install tools for you.
