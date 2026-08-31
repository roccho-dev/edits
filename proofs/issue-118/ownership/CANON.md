# Canon TDD — candidate rootfs ownership

The candidate image may pass only when the exact Docker and OCI archives record:

```text
/home/dev   uid=1000 gid=1000 mode=0700 type=directory
/work/repos uid=1000 gid=1000 mode=0755 type=directory
config.User = 1000:1000
```

Directory creation and mode remain ordinary deterministic layer operations. Numeric ownership must be recorded through `fakeRootCommands`; ordinary build-user `chown` is forbidden. Docker and OCI archive inspection must both fail closed on missing or mismatched ownership, group, mode, type, or runtime user. The existing writable-volume and persistence E2E remains mandatory.
