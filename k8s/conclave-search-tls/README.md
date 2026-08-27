# conclave-search TLS backends

This directory's manifests make SearXNG and beagle-core reachable over
HTTPS at stable, literal IPv4 addresses that conclave-search's TLS stack
(dotted-decimal-IP-only host, IP-SAN certificate checking, single
hardcoded system trust bundle) can validate. See
`docs/superpowers/specs/2026-08-26-conclave-search-tls-backends-design.md`
for the full design.

## What's here

- `00-internal-ca.yaml` -- a self-signed internal CA (ECDSA P-256 root --
  deliberately not P-384, see the spec for why), exposed cluster-wide as
  `ClusterIssuer/internal-ip-ca-issuer`.
- `10-searxng.yaml` -- SearXNG, deployed behind its own HTTPS front at
  `10.96.250.10:443`.
- `20-beagle-core-https-front.yaml` -- a separate HTTPS front for the
  EXISTING beagle-core service (never modifies it), at
  `10.96.250.20:443`.
- `extract-ca-root.sh` -- prints the internal CA's root certificate PEM to
  stdout. Run this, then feed the output into whatever future
  container-image build produces conclave-search's runtime image, so its
  `/etc/ssl/certs/ca-certificates.crt` trusts this CA.

## Pinned addresses

| What | Address |
|---|---|
| SearXNG HTTPS front | `10.96.250.10:443` |
| beagle-core HTTPS front | `10.96.250.20:443` |

These are the two IPv4 literals conclave-search needs to reach and trust,
once it's actually deployed somewhere that can reach the cluster network.
They are **not** passed as `argv[1]`/`argv[2]` -- Task 5's end-to-end
verification (see `verification-report.md`) found that both of
conclave-search's own live interop tests take the host from a compile-time
`const` instead: `SEARXNG_HOST` in `tests/interop/discovery_searxng_live.sio`
and `BEAGLE_CORE_HOST` in `tests/interop/memory_context_beagle_core_live.sio`.
Point those constants (or whatever config replaces them once conclave-search
has a real deploy pipeline) at the two addresses above.

## Known limitations (live as of Task 5's verification, 2026-08-26/27)

Both backends are reachable and their TLS chains validate correctly, but
two unrelated, unfixed gaps sit past the TLS layer:

- **SearXNG returns 403** on `format=json` requests -- SearXNG's own
  `settings.yml` has JSON output disabled by default, and this directory's
  `10-searxng.yaml` deployment does not currently enable it. Needs a
  `formats:` entry under `search:` in SearXNG's config.
- **beagle-core returns 401** -- conclave-search's interop test sends no
  bearer/consumer credentials, and beagle-core correctly rejects the
  unauthenticated request. Either the test needs to send credentials, or a
  credential-free internal path needs to be added.

Neither gap is a TLS/trust problem; both are outside this plan's scope.

## Scope of the internal CA

`ClusterIssuer/internal-ip-ca-issuer` exists to satisfy exactly one need:
conclave-search's TLS stack requires an IP-SAN certificate it can validate
against a single hardcoded trust bundle, and no public CA will issue for
private RFC 1918 addresses. It is deliberately narrow -- it issues exactly
the two certificates in this directory. Despite its cluster-scoped,
generic-sounding name, **it should not be reused as a general-purpose
internal CA for unrelated services** without deliberately reconsidering
this scope first. The cluster's public-facing certs (`agourakis.com` and
friends) stay on `letsencrypt-production`; this CA is not a replacement
for that.

## No deploy pipeline yet

There is currently no container-image build pipeline for
`conclave-search`'s own binary. Wiring it into Conclave's chat tool (a
separate, later spec) is where that pipeline will need to be created --
this directory only prepares the two backends and the CA root it will
need to trust.
