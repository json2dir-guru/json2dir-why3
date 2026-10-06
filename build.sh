#!/bin/sh
# Build json2dir: prove json2dir.mlw (fails if any goal is unproved), extract it to OCaml,
# and compile it with the I/O driver into out/json2dir.
# usage: build.sh <runtimes dir>   (needs runtimes/why3-1.5.1 and runtimes/ocaml-4.13.1)
set -e
runtimes=$(CDPATH= cd -- "$1" && pwd)
cd "$(dirname "$0")"
why3=$runtimes/why3-1.5.1/why3
sh ./prove.sh "$why3"
mkdir -p out
"$why3" extract -D "$runtimes/why3-1.5.1/usr/share/why3/drivers/ocaml64.drv" -L . --recursive \
  json2dir.Json2dir -o out/core.ml
cp driver.ml out/driver.ml
cd out
"$runtimes/ocaml-4.13.1/ocamlopt" unix.cmxa core.ml driver.ml -o json2dir
echo "built out/json2dir"
