# Enabling Tailscale Funnel for beagle-core

The K8s side is fully configured:

- `beagle-core-tailnet` Service has both annotations:
  - `tailscale.com/funnel: "true"`
  - `tailscale.com/https: "true"`
- ProxyGroup `sounio-workspace-ingress` is `type: ingress`.
- Tailscale Operator v1.94.2 is reconciling the annotation.

What's left is **one change in the Tailscale admin console ACL**. Until
that's in place, the hostname `beagle-core.tail21cbc4.ts.net` is only
reachable from inside the tailnet. With it, ChatGPT Custom GPT Actions
(or any off-tailnet client) can reach the public HTTPS URL.

## Required ACL stanza

Open https://login.tailscale.com/admin/acls and add:

```hjson
{
  "groups": {
    "group:k8s": ["autogroup:admin"]
  },
  "tagOwners": {
    "tag:k8s": ["group:k8s"]
  },
  "nodeAttrs": [
    {
      "target": ["tag:k8s"],
      "attr":   ["funnel"]
    }
  ]
}
```

Tag `tag:k8s` is the one the proxy-group pods advertise (visible in
`kubectl get proxygroup sounio-workspace-ingress -o yaml`, under
`.spec.tags`). Granting `"attr": ["funnel"]` is the permission the
Tailscale Operator needs to turn the annotation into an actual public
endpoint.

## Verification after the ACL change

From off-tailnet (e.g. the phone on cellular, or any internet host):

```
curl -i https://beagle-core.tail21cbc4.ts.net/health
```

Expected: `200 OK` + JSON body `{"status":"ok",…}`. If you still get
connection refused, the ACL didn't propagate — check the operator logs:

```
kubectl -n tailscale logs deploy/operator --tail=40 | grep -i funnel
```

## Once live, ChatGPT Custom GPT setup

1. Import the OpenAPI spec: `https://beagle-core.tail21cbc4.ts.net/openapi.yaml`
   (served via cockpit at `sounio-cockpit.tail21cbc4.ts.net/openapi.yaml`
   — the GPT can fetch either).
2. Set the auth scheme to "API Key", header `Authorization`, value
   `Bearer <operator-token>`.
3. Also add the `X-Beagle-Consumer: beagle-operator` header via the
   operationId-level `x-authHeader` extension (or paste it into each
   operation's auth header field manually).

Operator token pulled once from the cockpit auth-bridge:

```
curl https://sounio-cockpit.tail21cbc4.ts.net/api/auth/beagle-token
```

Paste the `token` field into the GPT's API Key slot.
