#!/bin/bash

n="$(($(nproc --all) / 2))"
cores=${1:-n}

echo snakemake --printshellcmds --reason --jobs $n --cores $cores --resources load=100
snakemake --printshellcmds --reason --jobs $n --cores $cores --resources load=100
