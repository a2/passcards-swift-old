# Passcards

A simple Wallet (née Passbook) server. This is a Swift re-implementation of the original [Parse-backed version](https://github.com/a2/passcards-parse).

## Usage

```sh
$ swift build -c release
$ .build/release/Passcards \
    --database "mongodb://localhost:27017/passcards" \
    --key "/path/to/key.p8" \
    --passphrase "secretz" \
    --key-id "ABCDEFGHIJ"
    --team-id "KLMNOPQRST"
    --update-token "moarsecretz" \
    --port 6969
```

## Author

Alexsander Akers, me@a2.io

## License

Passcards is available under the MIT license. See the LICENSE file for more info.
