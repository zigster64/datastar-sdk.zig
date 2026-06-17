# Validation test backend

Build and run the validation backend on port 7331

```
zig build run
```

Then run the official test harness against this backend

```
go run github.com/starfederation/datastar/sdk/tests/cmd/datastar-sdk-tests@latest
```
