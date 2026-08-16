# GLIMPSE2_setup

A Snakemake pipeline to build a phased reference panel from 1kGP for imputation with GLIMPSE2. It follows the GLIMPSE [tutorial](https://odelaneau.github.io/GLIMPSE/docs/tutorials/getting_started/#3-split-the-genome-into-chunks) and uses the most recent high coverage integrated phased panel from [1kGP](http://ftp.1000genomes.ebi.ac.uk/vol1/ftp/data_collections/1000G_2504_high_coverage/working/20220422_3202_phased_SNV_INDEL_SV/).

## Setup

Create the conda environment (installs snakemake, GLIMPSE2, bcftools, and GNU parallel):
```
conda env create -f environment.yml
conda activate snakemake
```

By default, output is written to `outputs/` alongside this repo; edit `1KGP_DIR`/`MAPDIR` in `config.yaml` to change that, or to point at a different GLIMPSE2/bcftools/parallel install than the one on PATH.

## Running

```
snakemake -n -p --reason --resources load=100           # dry run
snakemake -p --reason --cores all --resources load=100  # full run
```

`--resources load=N` caps how many downloads run concurrently (each download job requests `load=1`); it doesn't limit CPU-bound steps, which are governed by `--cores`. To build a single file instead of everything, pass its path in place of the full run's flags, e.g. `snakemake -p --cores 4 outputs/1KGP/1kGP.chunks.chr21.txt`.

## Known issues

The X chromosome is bugged, and I have not yet figured out how to fix it. For now, I am just excluding it entirely (both non-PAR and the two PARs).
