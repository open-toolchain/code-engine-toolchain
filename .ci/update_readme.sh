#!/usr/bin/env bash

# Update README.md 
# expecting tekton-catalog repository folder to be a sibling of this repository clone folder


python3 ../tekton-catalog/.ci/generate_pipeline_doc.py \
  --file "$(pwd)/.tekton/ci/*.yml" \
  --file "$(pwd)/.tekton/pr/*.yml" \
  --file "$(pwd)/.tekton/tasks/task-deploy-to-code-engine.yml" \
  --file "$(pwd)/.tekton/tasks/task-check-health.yml" \
  --file "$(pwd)/../tekton-catalog/git/*.yaml" \
  --file "$(pwd)/../tekton-catalog/container-registry/*.yaml" \
  --file "$(pwd)/../tekton-catalog/cra/*.yaml" \
  --file "$(pwd)/../tekton-catalog/toolchain/*.yaml" \
  --file "$(pwd)/../tekton-catalog/devops-insights/*.yaml" \
  --file "(pwd)/../tekton-catalog/linter/*.yaml" \
  --file "(pwd)/../tekton-catalog/tester/*.yaml" \
  --file "(pwd)/../tekton-catalog/utils/*.yaml" \
  --output "$(pwd)/README.md" \
  --anchor-output "### Build - Tekton Pipelines" \

python3 "../tekton-catalog/.ci/update_readme.py" \
  --output "$(pwd)/README.md" \
  --summary-anchor-output "### Build - Tekton Task(s)" \
  --details-anchor-output "### Build - Tekton Task(s)" \
  --file "$(pwd)/.tekton/tasks/task-deploy-to-code-engine.yml" \
  --file "$(pwd)/.tekton/tasks/task-publish-code-engine-deployable-mapping.yml" \
  --file "$(pwd)/.tekton/tasks/task-check-health.yml"

python3 ../tekton-catalog/.ci/generate_pipeline_doc.py \
  --file "$(pwd)/.tekton/cd/*.yml" \
  --file "$(pwd)/.deploy_rolling_kubernetes_pipeline/*.yaml" \
  --file "$(pwd)/../tekton-catalog/cra/*.yaml" \
  --file "$(pwd)/../tekton-catalog/toolchain/*.yaml" \
  --file "$(pwd)/../tekton-catalog/devops-insights/*.yaml" \
  --output "$(pwd)/README.md" \
  --anchor-output "### Deployment - Tekton Pipelines"

python3 "../tekton-catalog/.ci/update_readme.py" \
  --output "$(pwd)/README.md" \
  --summary-anchor-output "### Deployment - Tekton Task(s)" \
  --details-anchor-output "### Deployment - Tekton Task(s)" \
  --file "$(pwd)/.tekton/tasks/task-publish-code-engine-deployable-mapping.yml" \
  --file "$(pwd)/.tekton/tasks/task-fetch-component-information.yml" \
  --file "$(pwd)/.tekton/tasks/task-deploy-to-code-engine.yml" \
  --file "$(pwd)/.tekton/tasks/task-check-health.yml"
