# Branching Strategy — observability-talk

## Overview

This repository follows a **GitFlow-based strategy** adapted for a single-environment demo project with IaC (Terraform) and application code.

---

## Branch Model

```
main ──────────────────────────────────────────────────► production-ready, protected
  ▲                                                        tagged releases only
  │ PR (reviewed + CI passes)
  │
staging ──────────────────────────────────────────────► pre-production validation
  ▲                                                        mirrors demo AWS env
  │ PR (reviewed)
  │
develop ──────────────────────────────────────────────► integration branch
  ▲                                                        all features merge here
  │ PR
  │
feature/*, fix/*, chore/*, docs/*  ──────────────────► short-lived work branches
```

---

## Branch Definitions

| Branch      | Purpose                                          | Direct push | Merge via  |
|-------------|--------------------------------------------------|-------------|------------|
| `main`      | Production-ready code. Tagged releases.          | ❌ Never    | PR from staging |
| `staging`   | Pre-demo validation. Mirrors the AWS demo env.   | ❌ Never    | PR from develop |
| `develop`   | Active integration. All features land here.      | ❌ Never    | PR from feature/* |
| `feature/*` | New functionality                                | ✅ Author   | PR to develop |
| `fix/*`     | Bug fixes                                        | ✅ Author   | PR to develop |
| `chore/*`   | Dependency updates, tooling, CI changes          | ✅ Author   | PR to develop |
| `docs/*`    | Documentation-only changes                      | ✅ Author   | PR to develop |
| `hotfix/*`  | Critical fixes on production                     | ✅ Author   | PR to main AND develop |

---

## Naming Conventions

```
feature/add-xray-sampling-config
feature/ecs-adot-sidecar-integration
fix/lambda-cold-start-timeout
fix/sqs-dlq-alarm-threshold
chore/update-terraform-aws-provider
docs/adr-005-ecr-lifecycle-policy
hotfix/processor-memory-oom
```

---

## Workflow

### Standard feature work

```bash
# 1. Always branch from develop
git checkout develop
git pull origin develop
git checkout -b feature/my-feature

# 2. Work, commit with conventional commits
git commit -m "feat: add tail-based sampling config to ADOT collector"

# 3. Push and open PR to develop
git push -u origin feature/my-feature
# → Open PR: feature/my-feature → develop
```

### Promoting to staging

```bash
# When develop is stable and ready for demo validation
# Open PR: develop → staging
# Reviewer validates Terraform plan output before merge
```

### Releasing to main

```bash
# When staging has been validated end-to-end
# Open PR: staging → main
# Tag the release after merge
git tag -a v1.0.0 -m "Release v1.0.0: full demo stack ready"
git push origin v1.0.0
```

### Hotfix on production

```bash
# Branch from main, not develop
git checkout main
git pull origin main
git checkout -b hotfix/processor-timeout-fix

# Fix, commit, PR to main
git push -u origin hotfix/processor-timeout-fix
# → Open PR: hotfix/* → main

# After merge to main, also merge back to develop
# → Open PR: main → develop (or cherry-pick the commit)
```

---

## Commit Message Convention

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short description>

Types:  feat | fix | docs | chore | refactor | test | ci
Scope:  terraform | lambda | ecs | sqs | observability | iam | slides | demo

Examples:
feat(ecs): add ADOT sidecar container definition
fix(lambda): increase timeout for cold start under load
docs(adr): add ADR-005 ECR lifecycle policy decision
chore(terraform): pin AWS provider to ~> 5.0
ci: add terraform fmt check on PR
```

---

## Protection Rules (to configure in GitHub)

| Branch    | Require PR | Required reviews | Status checks | No force push | No direct push |
|-----------|-----------|------------------|---------------|---------------|----------------|
| `main`    | ✅        | 1                | terraform-validate, terraform-plan | ✅ | ✅ |
| `staging` | ✅        | 1                | terraform-validate | ✅ | ✅ |
| `develop` | ✅        | 1                | terraform-validate | ✅ | ✅ |

---

## Release Tagging

Tags follow [Semantic Versioning](https://semver.org/) scoped to demo milestones:

| Tag     | Milestone                                      |
|---------|------------------------------------------------|
| `v0.1.0` | Initial infra skeleton + app code             |
| `v0.2.0` | End-to-end flow validated (no observability)  |
| `v1.0.0` | Full demo stack ready (ADOT + X-Ray + alarms) |
| `v1.1.0` | Post-talk cleanup + public repo polish        |

---

*Last updated: 2026-10-04*
