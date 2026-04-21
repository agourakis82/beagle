# B24.16 Known Limits

- B24.16 does not move `manuscript` off control by itself.
- B24.16 does not weaken operator visibility; approve, edit, and reject remain first-class.
- B24.16 depends on bounded manuscript shadow history already captured in B24.15; it does not create a second rollout plane.
- B24.16 can keep shadow or trigger rollback-shadow, but it does not supersede the existing implementation or analysis canary rollback paths.
- B24.16 records the first explicit manuscript alignment labels, but it still requires sufficient labeled evidence before any staged manuscript canary is considered.
