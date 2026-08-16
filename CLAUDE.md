# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

A Snakemake pipeline that builds a phased 1000 Genomes Project (1kGP) reference panel for low-pass sequencing imputation with GLIMPSE2. It follows the [GLIMPSE tutorial](https://odelaneau.github.io/GLIMPSE/docs/tutorials/getting_started/#3-split-the-genome-into-chunks) and uses the high-coverage integrated phased panel from [1kGP](http://ftp.1000genomes.ebi.ac.uk/vol1/ftp/data_collections/1000G_2504_high_coverage/working/20220422_3202_phased_SNV_INDEL_SV/).

There is no application code to build, lint, or test — this is a data pipeline whose "correctness" is validated by running (or dry-running) Snakemake. Everything lives at the repo root: `Snakefile`, `config.yaml`, `environment.yml`.

## Setup

- `environment.yml` is the conda env (snakemake, GLIMPSE2 via bioconda's `glimpse-bio` package, bcftools, GNU parallel, plus cython/numpy/pandas). Create it with `conda env create -f environment.yml`. No manual GLIMPSE2 install is required.
- `config.yaml` holds all pipeline paths/binaries and is loaded via Snakemake's `configfile:` directive, so it resolves correctly regardless of the working directory you invoke `snakemake` from.
  - `1KGP_DIR` / `MAPDIR` — where downloaded/derived files are written (default `outputs/1KGP`, `outputs/genetic_maps.b38`, relative to wherever you invoke snakemake).
  - `GLIMPSE2_CHUNK` / `GLIMPSE2_SPLIT_REFERENCE` / `BCFTOOLS` / `PARALLEL` default to bare command names (resolved via PATH from `environment.yml`); only override to point at a different install.
- Any config key can be overridden per-invocation instead of edited, e.g. `snakemake --config 1KGP_DIR=/scratch/1KGP`.

## Common commands

Run from the repo root:

- Dry run: `snakemake -n -p --reason --resources load=100`
- Full run: `snakemake -p --reason --cores all --resources load=100`
- Single target: `snakemake -p --cores 4 <path-to-output-file>` (paths are rooted at whatever `1KGP_DIR`/`MAPDIR` resolve to)

`--resources load=N` throttles concurrent download jobs (each requests `load=1`); it does not gate CPU-bound rules, which `--cores` governs directly.

## Pipeline architecture (`Snakefile`)

The DAG processes each autosome (chr1–22; **chrX is intentionally excluded** — see Known issues) through:

1. **`download_1kgp_chrom`** — one job per chromosome, downloads its VCF+index directly from a computed 1kGP URL (no URL list file to maintain; the autosome naming convention is fully deterministic).
2. **`download_map`** — downloads the GLIMPSE b38 genetic map for that chromosome.
3. **`qc_reference_panel_autosomes`** — normalizes multiallelic records with `bcftools norm -m -any --threads`, producing a BCF + index.
4. **`extract_sites`** — strips genotypes (`bcftools view -G`) to produce a sites-only VCF + index, used for chunking.
5. **`chunk_chromosome`** — runs `GLIMPSE2_chunk` against the sites file and genetic map to produce chunk coordinates (`1kGP.chunks.chr{chrom}.txt`).
6. **`split_reference`** — one Snakemake job per chromosome that fans out across all of that chromosome's chunks concurrently via `GNU parallel -j {threads}` (`threads: workflow.cores`), each invoking `GLIMPSE2_split_reference` to produce the binary reference panel under `1KGP_DIR/glimpse_split/`. Chunking a chromosome serially used to be the pipeline's biggest bottleneck since it ignored `--cores` entirely — parallelizing it here is the main performance win over the old design.

`rule all` (marked `localrules`) aggregates all four output types (reference panel BCFs, sites files, chunks, split reference markers) across all 22 autosomes.

## Known issues

- The X chromosome is excluded entirely (non-PAR and both PARs) due to an unresolved bug — do not add chrX to `CHROMS` without addressing this. Its remote filename also doesn't follow the autosome naming convention the pipeline computes URLs from (it has a `.v2` suffix), so re-adding it isn't just a range change.
- `split_reference` writes a placeholder "Done" marker file rather than checking for the actual expected `*_start_stop.bin` output files from `GLIMPSE2_split_reference` — it echoes a reminder to manually verify these exist. All shell blocks use `set -euo pipefail` so a failing `GLIMPSE2_split_reference`/`parallel` invocation still fails the Snakemake job (this was not previously true of the old serial loop).
