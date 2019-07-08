#!/bin/bash
clang++ -flto -fuse-ld=gold -frandom-seed=42 -g -O0 -Wl,--plugin-opt,-random-seed=42 -Wl,--plugin-opt,-randomize-function-list  -o $2 $1
