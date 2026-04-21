# Registry Cache

These are pull-through caches built on the official OCI/Docker distribution
registry.

## Role

- warm frequently used OCI images close to the lab
- keep large repeated pulls off the hot paths
- give the cluster a stable mirror endpoint on the service edge

## Endpoints

- Docker Hub: `http://10.30.0.1:5000`
- GHCR: `http://10.30.0.1:5001`
- `registry.k8s.io`: `http://10.30.0.1:5002`
- management aliases:
  - `http://192.168.3.207:5000`
  - `http://192.168.3.207:5001`
  - `http://192.168.3.207:5002`

## Important caveat

Each upstream registry needs its own cache instance because the Distribution
proxy mode uses one `proxy.remoteurl` per service.

## References

- https://distribution.github.io/distribution/about/configuration/
- https://hub.docker.com/_/registry
