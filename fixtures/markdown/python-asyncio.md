# `asyncio` — Asynchronous I/O¶

---

asyncio is a library to write **concurrent** code using the **async/await** syntax.

asyncio is used as a foundation for multiple Python asynchronous frameworks that provide high-performance network and web-servers, database connection libraries, distributed task queues, etc.

asyncio is often a perfect fit for IO-bound and high-level **structured** network code.

See also

[A conceptual overview of asyncio](../howto/a-conceptual-overview-of-asyncio.html#a-conceptual-overview-of-asyncio)

asyncio provides a set of **high-level** APIs to:

- [run Python coroutines](asyncio-task.html#coroutine) concurrently and have full control over their execution;
- perform [network IO and IPC](asyncio-stream.html#asyncio-streams);
- control [subprocesses](asyncio-subprocess.html#asyncio-subprocess);
- distribute tasks via [queues](asyncio-queue.html#asyncio-queues);
- [synchronize](asyncio-sync.html#asyncio-sync) concurrent code;

For **introspection**, asyncio provides APIs and tools for:

- inspecting the [async call graph](asyncio-graph.html#asyncio-graph) of tasks and futures;
- inspecting tasks in another running Python process with [command-line tools](asyncio-tools.html#asyncio-introspection-tools);

Additionally, there are **low-level** APIs for *library and framework developers* to:

- create and manage [event loops](asyncio-eventloop.html#asyncio-event-loop), which provide asynchronous APIs for [networking](asyncio-eventloop.html#loop-create-server), running [subprocesses](asyncio-eventloop.html#loop-subprocess-exec), handling [OS signals](asyncio-eventloop.html#loop-add-signal-handler), etc;
- implement efficient protocols using [transports](asyncio-protocol.html#asyncio-transports-protocols);
- [bridge](asyncio-future.html#asyncio-futures) callback-based libraries and code with async/await syntax.

[Availability](intro.html#availability): not WASI.

This module does not work or is not available on WebAssembly. See [WebAssembly platforms](intro.html#wasm-availability) for more information.

asyncio REPL

You can experiment with an `asyncio` concurrent context in the [REPL](../glossary.html#term-REPL):

```
$ python -m asyncio
asyncio REPL ...
Use "await" directly instead of "asyncio.run()".
Type "help", "copyright", "credits" or "license" for more information.
>>> import asyncio
>>> await asyncio.sleep(10, result='hello')
'hello'

```

This REPL provides limited compatibility with [`PYTHON_BASIC_REPL`](../using/cmdline.html#envvar-PYTHON_BASIC_REPL). It is recommended that the default REPL is used for full functionality and the latest features.

Raises an [auditing event](sys.html#auditing) `cpython.run_stdin` with no arguments.

Changed in version 3.12.5:(also 3.11.10, 3.10.15, 3.9.20, and 3.8.20) Emits audit events.

Changed in version 3.13:Uses PyREPL if possible, in which case [`PYTHONSTARTUP`](../using/cmdline.html#envvar-PYTHONSTARTUP) is also executed. Emits audit events.

Reference

High-level APIs

- [Runners](asyncio-runner.html)
- [Coroutines and tasks](asyncio-task.html)
- [Streams](asyncio-stream.html)
- [Synchronization Primitives](asyncio-sync.html)
- [Subprocesses](asyncio-subprocess.html)
- [Queues](asyncio-queue.html)
- [Exceptions](asyncio-exceptions.html)

Introspection APIs

- [Call graph introspection](asyncio-graph.html)
- [Command-line introspection tools](asyncio-tools.html)

Low-level APIs

- [Event loop](asyncio-eventloop.html)
- [Futures](asyncio-future.html)
- [Transports and Protocols](asyncio-protocol.html)
- [Policies](asyncio-policy.html)
- [Platform Support](asyncio-platforms.html)
- [Extending](asyncio-extending.html)

Note

The source code for asyncio can be found in [Lib/asyncio/](https://github.com/python/cpython/tree/3.15/Lib/asyncio/).

