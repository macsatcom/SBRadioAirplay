# Patches

Local changes to third-party sources. Never edit `third_party/` in place.

Name: `NNNN-<project>-<what>.patch`, where `<project>` is the directory under
`third_party/` (e.g. `0001-libraop-wolfssl-compat.patch`). Paths inside the
patch are relative to that directory. `build/fetch-deps.sh` applies them and
skips ones already applied.
