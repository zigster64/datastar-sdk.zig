

## Requirements

This package requires Go 1.24 or later.
# Datastar SDK for Zig v0.16

A small, framework-agnostic Zig 0.16 SDK for [Datastar](https://data-star.dev) — patch DOM elements, patch signals, and execute scripts on the browser from your backend over SSE.

The whole API is four functions. Each transformer takes an arena allocator and returns a ready-to-ship `event: ...\ndata: ...\n\n` SSE block.

Write it to any response body with `Content-Type: text/event-stream` and you're done — works with the stdlib HTTP server, [`http.zig`](https://github.com/karlseguin/http.zig), [`dusty`](https://github.com/lalinsky/dusty), `zap`, `jetzig`, `tokamak`, or whatever else.

Passes the official Datastar SDK validation suite (see `tests/validation.zig` — a self-contained harness on top of `std.http.Server`).

## Zig Version

Requires Zig **0.16.0** or newer.

## License

This package is licensed for free under the [MIT License](LICENSE).

## Quick Start

To download the repo, and do a test compile
```
git clone https://github.com/zigster64/datastar-sdk.zig.git
cd datastar-sdk.zig
zig build test
```

Now to run the hello world example
```
cd hello_world
zig build run
```

This will run the standard Hello World Datastar example, using the Zig SDK


## Installation

For using the SDK in your Zig web app project ...


```bash
zig fetch --save="datastar" "git+https://github.com/zigster64/datastar-sdk.zig"
```

In `build.zig`:

```zig
const datastar = b.dependency("datastar", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("datastar", datastar.module("datastar"));
```

In your code:

```zig
const datastar = @import("datastar");
```

Then apply the SDK to do Datastar things in your code !

## The SDK

```zig
// Read Datastar signals from a request — GET pulls them from the
// `datastar` query param, POST/PUT/PATCH/DELETE from the body.
datastar.readSignals(comptime T: type, arena: Allocator, req: *std.http.Server.Request) !T

// Patch DOM elements
datastar.patchElements(arena, html, opts) ![]const u8
datastar.patchElementsFmt(arena, comptime fmt, args, opts) ![]const u8

// Patch signals (any JSON-serializable value)
datastar.patchSignals(arena, value, opts) ![]const u8

// Execute a script on the client (wraps the script in a <script> tag and patches it into body)
datastar.executeScript(arena, script, opts) ![]const u8
datastar.executeScriptFmt(arena, comptime fmt, args, opts) ![]const u8

// Helper — re-exported for framework adapters that need to decode the `datastar=...` query param
datastar.urlDecode(allocator, input) ![]u8
```

Each transformer hands you back a fully-formed SSE event block — concatenate as many as you like in a single response.

Options:

```zig
PatchElementsOptions { mode, selector, view_transition, event_id, retry_duration, namespace }
PatchSignalsOptions  { only_if_missing, event_id, retry_duration }
ExecuteScriptOptions { auto_remove, attributes, event_id, retry_duration }

PatchMode = .inner | .outer | .replace | .prepend | .append | .before | .after | .remove
NameSpace = .html | .svg | .mathml
```

`.{}` is almost always the right value for the options argument. See `src/datastar.zig` for the full option fields and defaults.

## Quick Example

```zig
const datastar = @import("datastar");

// Inside an SSE handler, with `req.arena` and a `res` from your framework:

// 1. Patch DOM elements
const a = try datastar.patchElements(req.arena, "<div id='hello'>Hi</div>", .{});

// 2. Patch signals
const b = try datastar.patchSignals(req.arena, .{ .foo = 42, .bar = "Datastar Rocks" }, .{});

// 3. Run a script on the client
const c = try datastar.executeScriptFmt(req.arena, "alert('hello {s}')", .{name}, .{});

res.header("Content-Type", "text/event-stream");
res.body = try std.mem.concat(req.arena, u8, &.{ a, b, c });

// And to read Datastar signals on the way in:
const Signals = struct { name: []const u8, count: u32 };
const signals = try datastar.readSignals(Signals, req.arena, req);
```

## Plug it into your framework

Wiring is two lines per response: set `Content-Type: text/event-stream`, then write the bytes returned by the transformer:

```zig
fn myHandler(req: *anyframework.Request, res: *anyframework.Response) !void {
    const body = try datastar.patchElements(req.arena, "<div id='x'>hi</div>", .{});
    try res.header("Content-Type", "text/event-stream");
    res.body = body;
}
```

How you do this may be entirely different depending on which Zig web framework you are using.


## Kitchen Sink Examples

In the `examples` directory, there is an additional example app that demonstrates all aspects of using Datastar, including SVG morphs, etc.



For long-lived streaming (animations, multi-frame morphs, keepalive pings), grab the raw stream from your framework and write blocks as you produce them.

Two complete reference ports are in `examples/`:

| Target               | Output binary       | Framework                                                       | Source                          |
| -------------------- | ------------------- | --------------------------------------------------------------- | ------------------------------- |
| `zig build stdlib`   | `example_1_stdlib`  | Zig vanilla StdLib HTTP Server                                  | `examples/01_basic_stdlib.zig`   |
| `zig build http.zig` | `example_1_httpz`   | [`karlseguin/http.zig`](https://github.com/karlseguin/http.zig) | `examples/01_basic_httpz.zig`   |
| `zig build dusty`    | `example_1_dusty`   | [`lalinsky/dusty`](https://github.com/lalinsky/dusty)           | `examples/01_basic_dusty.zig`   |

Both serve the same kitchen-sink UI on `:8081`. The navbar shows which web server is driving the page.

### `readSignals` in frameworks that hide the underlying request

`datastar.readSignals` currently expects a `*std.http.Server.Request`. If your framework wraps the request, parse the signals JSON yourself — they arrive as `?datastar=<url-encoded-json>` on a GET, or as the raw JSON body on POST/PUT/PATCH/DELETE:

```zig
const Signals = struct { foo: u32, bar: []const u8 };

fn readSignalsAnyFramework(
    arena: Allocator,
    method: std.http.Method,
    query_string: ?[]const u8, // everything after the '?' in the URL, or null
    body: ?[]const u8,         // request body bytes, or null
) !Signals {
    const json = switch (method) {
        .GET => blk: {
            const qs = query_string orelse return error.MissingDatastarKey;
            var it = std.mem.tokenizeScalar(u8, qs, '&');
            while (it.next()) |pair| {
                if (std.mem.startsWith(u8, pair, "datastar=")) {
                    break :blk try datastar.urlDecode(arena, pair["datastar=".len..]);
                }
            }
            return error.MissingDatastarKey;
        },
        else => body orelse return error.MissingBody,
    };

    return std.json.parseFromSliceLeaky(
        Signals,
        arena,
        json,
        .{ .ignore_unknown_fields = true },
    );
}
```

## Build, Run, Test

```bash
zig build                       # builds zig-out/bin/validation-test and zig-out/bin/hello_world
zig build test                  # run SDK unit tests
zig build stdlib                # build the kitchen-sink demo using Zig stdlb
zig build http.zig              # build the http.zig kitchen-sink demo
zig build dusty                 # build the dusty kitchen-sink demo
./zig-out/bin/validation-test   # serve the Datastar SDK conformance harness on :7331
```

To prove the SDK conforms to the Datastar wire protocol, run the validation harness and point the official validator at it:

```bash
./zig-out/bin/validation-test &
go run github.com/starfederation/datastar/sdk/tests/cmd/datastar-sdk-tests@latest
```

The harness in `tests/validation.zig` is itself a reference for "how to use the SDK with `std.http.Server`" — about 250 lines, no extra dependencies.

## Looking for a bundled HTTP server too?

This repo is SDK-only.

If you want a Datastar-aware HTTP server bundled with the SDK — with a router, batched + sync SSE, hot reload, pub/sub message bus for CQRS — see the sibling repo [`datastar.zig`](https://github.com/zigster64/datastar.zig).

## More on Datastar

- [data-star.dev](https://data-star.dev) — official site and reference
- [Datastar SDK ADR](https://github.com/starfederation/datastar/blob/develop/sdk/ADR.md)
- [Datastar Discord](https://discord.gg/YfFn7pKx)
- [Zig Discord](https://discord.gg/Chk5WKM5)

## Contributing

PRs welcome. Please open an issue first to discuss non-trivial changes.
