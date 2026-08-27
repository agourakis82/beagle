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

These are the two IPv4 literals conclave-search's `argv[1]`/`argv[2]`
should be pointed at, once it's actually deployed somewhere that can
reach the cluster network and trusts this CA.

## No deploy pipeline yet

There is currently no container-image build pipeline for
`conclave-search`'s own binary. Wiring it into Conclave's chat tool (a
separate, later spec) is where that pipeline will need to be created --
this directory only prepares the two backends and the CA root it will
need to trust.
