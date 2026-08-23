# Building FDCLEAN.COM

On Ubuntu 24.04 or another Debian-derived system with Pasmo available:

```sh
sudo apt install pasmo
git clone https://github.com/peclark1/cpm-disk-clean.git
cd cpm-disk-clean
make test
```

The generated CP/M transient program is:

```text
dist/FDCLEAN.COM
```

`make test` also runs static safety checks against the source and compiled binary.
