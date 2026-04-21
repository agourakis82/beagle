# B24.17 Known Limits

- B24.17 does not move `manuscript` off control by itself.
- B24.17 does not weaken operator visibility; approve, edit, and reject remain first-class.
- B24.17 depends on bounded manuscript shadow history already captured in B24.15/B24.16; it does not create a second rollout plane.
- B24.17 can keep shadow or trigger rollback-shadow, but it does not supersede the existing implementation or analysis canary rollback paths.
- B24.17 can reach full explicit label coverage and still remain `keep-shadow` when the evidence only confirms a blocked manuscript candidate posture rather than a canary-worthy one.
