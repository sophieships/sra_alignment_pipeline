SHELL := /bin/bash

.PHONY: help ci pipeline-check manifest-validation manifest-stub image-manifest-tests build-images-tests clean-ci-artifacts

help:
	@echo "Local CI targets:"
	@echo "  make ci                   Run the local equivalent of GitHub Actions CI"
	@echo "  make pipeline-check       Verify Nextflow parses and --help works"
	@echo "  make manifest-validation  Exercise manifest validation failures"
	@echo "  make manifest-stub        Verify manifest-derived refs in a stub run"
	@echo "  make image-manifest-tests Run Python manifest regression checks"
	@echo "  make build-images-tests   Run build_images orchestration checks"
	@echo "  make clean-ci-artifacts   Remove local Nextflow CI artifacts"

ci: pipeline-check manifest-validation manifest-stub image-manifest-tests build-images-tests

pipeline-check:
	nextflow run main.nf --help -ansi-log false

manifest-validation:
	@bad_json="$$(mktemp)" && \
	printf '{bad json\n' > "$$bad_json" && \
	if nextflow_output="$$(nextflow run main.nf --help --image_manifest "$$bad_json" -ansi-log false 2>&1)"; then \
		echo "Expected malformed manifest check to fail." >&2; \
		rm -f "$$bad_json"; \
		exit 1; \
	fi; \
	[[ "$$nextflow_output" == *"Invalid container image manifest"* ]] || { echo "$$nextflow_output"; rm -f "$$bad_json"; exit 1; }; \
	rm -f "$$bad_json"
	@non_object_manifest="$$(mktemp)" && \
	printf '[1, 2, 3]\n' > "$$non_object_manifest" && \
	if nextflow_output="$$(nextflow run main.nf --help --image_manifest "$$non_object_manifest" -ansi-log false 2>&1)"; then \
		echo "Expected top-level non-object manifest check to fail." >&2; \
		rm -f "$$non_object_manifest"; \
		exit 1; \
	fi; \
	[[ "$$nextflow_output" == *"top-level JSON value must be an object"* ]] || { echo "$$nextflow_output"; rm -f "$$non_object_manifest"; exit 1; }; \
	rm -f "$$non_object_manifest"
	@missing_defaults="$$(mktemp)" && \
	printf '%s\n' '{"images":{"aria2":{"runtime_name":"aria2-sra-download","version":"1.37.0","build":{"enabled":true,"dockerfile":"dockerfiles/multiarch/aria2/Dockerfile","context":"dockerfiles/multiarch/aria2"}}}}' > "$$missing_defaults" && \
	if nextflow_output="$$(nextflow run main.nf --help --image_manifest "$$missing_defaults" -ansi-log false 2>&1)"; then \
		echo "Expected missing-defaults manifest check to fail." >&2; \
		rm -f "$$missing_defaults"; \
		exit 1; \
	fi; \
	[[ "$$nextflow_output" == *"defaults must be an object"* ]] || { echo "$$nextflow_output"; rm -f "$$missing_defaults"; exit 1; }; \
	rm -f "$$missing_defaults"
	@missing_required_image="$$(mktemp)" && \
	printf '%s\n' '{"defaults":{"registry":"docker.io","namespace":"eoksen"},"images":{"aria2":{"runtime_name":"aria2-sra-download","version":"1.37.0","build":{"enabled":true,"dockerfile":"dockerfiles/multiarch/aria2/Dockerfile","context":"dockerfiles/multiarch/aria2"}}}}' > "$$missing_required_image" && \
	if nextflow_output="$$(nextflow run main.nf --help --image_manifest "$$missing_required_image" -ansi-log false 2>&1)"; then \
		echo "Expected missing required image manifest check to fail." >&2; \
		rm -f "$$missing_required_image"; \
		exit 1; \
	fi; \
	[[ "$$nextflow_output" == *"images.bcftools must be an object"* ]] || { echo "$$nextflow_output"; rm -f "$$missing_required_image"; exit 1; }; \
	rm -f "$$missing_required_image"
	@ignored_extra_manifest="$$(mktemp)" && \
	python3 -c "import json, sys; from pathlib import Path; p=Path(sys.argv[1]); manifest=json.loads(Path('conf/images.json').read_text(encoding='utf-8')); manifest['images']['unused_extra']={'runtime_name':'','version':''}; p.write_text(json.dumps(manifest), encoding='utf-8')" "$$ignored_extra_manifest" && \
	nextflow run main.nf --help --image_manifest "$$ignored_extra_manifest" -ansi-log false && \
	rm -f "$$ignored_extra_manifest"

manifest-stub: clean-ci-artifacts
	nextflow run main.nf --input_file test_data/phage_smoke.csv --cpus 1 --email test@example.com -stub-run -ansi-log false
	grep -R --fixed-strings --quiet "docker.io/eoksen/fastp:1.3.0" work/*/*/.command.run

image-manifest-tests:
	bash scripts/test_image_manifest.sh

build-images-tests:
	bash scripts/test_build_images_orchestration.sh

clean-ci-artifacts:
	rm -rf work results .nextflow .nextflow.log .nextflow.log.*
