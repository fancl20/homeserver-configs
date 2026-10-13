# image-controller

A small Flux-native controller that builds container images from Flux
`GitRepository` artifacts and pushes them to the local registry.

Each `ContainerImage` (d20.fan/v1alpha1) declares an image that must exist:
a source artifact revision, a build context inside it, a tag template, and an
optional update command and schedule. The controller reconciles it into a
rootless buildkit Job (`prepare` init container + `build` container) and reads
the pushed reference back from the pod's termination message — the build pod
needs no RBAC. Tag bumps then flow through the existing
ImageRepository/ImagePolicy/ImageUpdateAutomation machinery.

There is no CI. Development happens in this directory:

```sh
go generate ./...   # deepcopy + CRD (emits ../d20.fan_containerimages.yaml)
go build ./...
go vet ./...
go test ./...       # includes running internal/build/prepare.py via python3
```

The CRD is emitted one level up (`../d20.fan_containerimages.yaml`) because
every `.yaml` under `99-services/` is applied by Flux's auto-generated
kustomization — keep this directory free of yaml files.

## Manual operations

```sh
# trigger a rebuild
kubectl -n continuous annotate containerimage/<name> \
  reconcile.fluxcd.io/requestedAt="$(date +%s)"

# inspect
kubectl -n continuous get containerimages
kubectl -n continuous get jobs,pods -l d20.fan/container-image=continuous.<name>
kubectl -n continuous logs job/<name>-<hash> -c build
```

## Self-hosting

The controller's own image is built outside the controller itself: the
nightly `image-controller-build` CronJob (`../image-controller-build.yaml`)
builds the pinned `VERSION` from the artifact only when the registry is
missing that tag, so unchanged nights are seconds-long no-ops and a present
tag is never re-pushed (re-pushing would silently mutate its digest).

Releasing = bump `VERSION` in that manifest: the next nightly run — or an
immediate manual one, `kubectl -n continuous create job
--from=cronjob/image-controller-build <name>` — builds the new tag, the
image-controller ImagePolicy selects it, and image-automation re-pins the
Deployment (expect ~30-45 min end to end after the build). Source changes
never deploy without a version bump, and a broken build leaves the last
good controller running. On a fresh cluster or after a registry wipe the
same machinery re-seeds the tag: within a day on schedule, or ~1.5h via the
manual trigger (build + 1h policy scan + 30m update).

## Reconcile behavior

- Triggers: first observation, spec change, artifact revision change, manual
  `reconcile.fluxcd.io/requestedAt`, schedule tick, base tag change. First
  match wins. Static-version images skip artifact revisions that would
  re-render the last pushed tag.
- Triggers are consumed on success, not when the Job is created: a failed
  manual or nightly build keeps retrying (up to `--max-attempts`) and stays
  `Ready=False` instead of being repainted from the stale image ref. A
  burned-out schedule tick seeds the next one with a fresh attempt budget.
- One Job at a time per image; a newer trigger *replaces* a running Job.
- Job names are `<name>-<7 hex>` of a deterministic trigger key (the key
  includes the schedule tick, so every night builds even with unchanged
  inputs); retries bump the attempts component for a fresh name (Jobs are
  immutable; failed Jobs are deleted).
- Artifact fetch/digest failures — reported by the prepare init container's
  termination message — clear `lastBuiltRevision` so the retry targets the
  current artifact (source-controller GCs old revisions quickly;
  `00-stage/flux` raises its retention).
