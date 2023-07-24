#!/bin/bash

# Performs a dry run to do a quick sanity check that commands are correct.
echo snakemake --dryrun --printshellcmds --reason --jobs 1 --resources load=100

snakemake --dryrun --printshellcmds --reason --jobs 1 --resources load=100