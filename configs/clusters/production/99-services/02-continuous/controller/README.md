# image-controller

A small Flux-native controller that builds container images from Flux
`GitRepository` artifacts and pushes them to the local registry, replacing the
image-building role of the Argo Workflows `CronWorkflow`.

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

The controller's own image is built by itself (`container-images.yaml`,
`image-controller` CR). Releasing = bump `spec.version` on that CR: the new
tag lands in the registry, image-automation commits the new setter tag, and
Flux rolls the Deployment (expect ~30-45 min end to end). A broken build
leaves the last good controller running. With a static version, revision
changes alone do not rebuild — the rendered tag would not change, so the
push would silently mutate the existing tag's digest.

On a fresh cluster (or a wiped registry) apply the bootstrap Job by hand
(`kubectl apply -f ../bootstrap.yaml`; Flux ignores it) to build the
controller image from the artifact tarball once. The bootstrap pushes the
sentinel `0.0.0-testing-00000000`: the ImagePolicy only selects it when the
registry holds no real tag, so recovery rides one automation cycle (1h scan
+ 30m update, ~1.5h worst case) and the first real build outranks it
immediately.

## Reconcile behavior

- Triggers: first observation, spec change, artifact revision change, manual
  `reconcile.fluxcd.io/requestedAt`, schedule tick, base tag change. First
  match wins. Static-version images skip artifact revisions that would
  re-render the last pushed tag (see Self-hosting).
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
