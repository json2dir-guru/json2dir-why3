# json2dir-why3

[json2dir](https://github.com/kitsunoff/awesome-json2dir) in WhyML: the UTF-8 check, JSON parser and document validation in `json2dir.mlw` are proved with Why3 (Z3, CVC4, Alt-Ergo) and extracted to OCaml; `driver.ml` only does the I/O.

    sh build.sh <runtimes dir>    # why3 prove, why3 extract, ocamlopt -> out/json2dir
    out/json2dir < document.json
