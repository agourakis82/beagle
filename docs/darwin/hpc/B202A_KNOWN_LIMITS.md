# B20.2a — Known Limits

- The native attach path is `cluster-internal` and currently uses `kubectl port-forward` plus `Remote-SSH`; there is still no external ingress or Coder Connect layer.
- `Cursor` remains a premium client, not a canonical state owner.
- The attach path depends on an operator-supplied `authorized_keys` secret for the workspace `ssh` sidecar.
- The browser habitat remains `OpenVSCode Server`; this phase does not replace or redesign it.
