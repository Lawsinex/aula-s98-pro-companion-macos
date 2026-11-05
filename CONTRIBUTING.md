# Contributing

Bug reports, firmware reports and pull requests are all welcome.

## The hardware safety rule

**Never send an opcode to a real keyboard to see what it does.** The firmware programs flash directly from HID reports. On a related AULA model, that kind of guessing permanently overwrote the screen's menu graphics. Only send commands whose behaviour is already understood, and explain the evidence in your pull request. [`docs/PROTOCOL.md`](docs/PROTOCOL.md) lists what's known.

## Before you open a pull request

```bash
python3 -m pip install numpy pillow
./scripts/verify.sh
```

It must pass. It briefly opens real app windows, but those runs use an isolated test model: nothing is saved and nothing is sent to a keyboard. No keyboard is needed.

Keep the app small: no package dependencies, accounts, telemetry or network calls. A change that affects the keyboard should say which firmware version you tested it on.

## Support for other keyboards

The device ID, key layout and LED map are specific to the S98 Pro. If you have a related board, open an issue with its USB IDs (`aula-s98 info`, or System Information › USB) before writing code.
