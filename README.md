# Passcards

A simple Wallet (née Passbook) server. This is a Swift re-implementation of the original [Parse-backed version](https://github.com/a2/passcards-parse).

## Usage

```sh
$ swift build -c release
$ .build/release/App \
    --database "mongodb://localhost:27017/passcards" \
    --cert "/path/to/cert.p12" \
    --passphrase "secretz" \
    --updateToken "moarsecretz" \
    --port 6969
```

## Author

Alexsander Akers, me@a2.io

## License

Passcards is available under the MIT license. See the LICENSE file for more info.
