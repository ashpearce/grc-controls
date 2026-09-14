# grc-controls

Companion repository for the GRC Engineering Playbook on [GRC Playground](https://grcplayground.com/playbook).
Every control in the playbook is a folder here, and every folder is proven to work in three layers.

## Layout

```
controls/<slug>/
  control.json        manifest: id, policy queries, sandbox variables
  terraform/          the control, as code
  policy/plan.rego    preventive: refuses a bad Terraform plan
  policy/live.rego    detective: judges what AWS says is true right now
  evidence/collect.sh read-only script that gathers live state
  tests/              unit tests for both policies, plus break.sh / restore.sh
.github/workflows/
  ci.yml              fast checks on every push (no AWS)
  verify-control.yml  full build / break / restore / destroy in a sandbox account
  hb-<id>-*.yml       the daily evidence job for each control
evidence/             written by the daily jobs, one dated JSON per control per day
verification/         written by the verify workflow, one JSON per control
bootstrap/            one-time setup for the sandbox verifier role
```

## The three layers of "it works"

**Layer 1, seconds, no cloud.** `make test` runs the Rego unit tests, formats, Terraform validate,
and shellcheck, and checks every control folder has every required file. CI runs the same thing
on every push. Red means not done.

**Layer 2, minutes, sandbox account.** `make verify CONTROL=<slug>` builds the control for real in
a throwaway AWS account, confirms the live policy passes, deliberately breaks the control the way
a careless admin would, confirms the policy catches it, repairs it, and destroys everything.
The verdict lands in `verification/<slug>.json`. The verify workflow does this weekly for every control.

**Layer 3, daily, your real account.** Each control's evidence workflow runs the live policy against
your actual environment every morning and commits the result to `evidence/`. This is the layer auditors read.

## Local setup

Install terraform, opa, awscli, jq, and shellcheck. Then:

```
make test
```

To run Layer 2 locally, sign in to your sandbox account and set `HB_SANDBOX_ACCOUNT_ID` to its
account number. The script refuses to run against any other account.

```
export HB_SANDBOX_ACCOUNT_ID=123456789012
make verify CONTROL=aws-cloudtrail-all-regions
```

## Adding a control

Copy an existing control folder, change the slug in `control.json`, write the four steps, write the
tests, add its evidence workflow, and run `make test`. The layout check tells you what is missing.
