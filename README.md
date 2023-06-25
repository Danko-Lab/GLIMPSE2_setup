# GLIMPSE2_setup

 This repo contains a snakemake pipeline to create a phased reference panel from 1kGP for imputation with GLIMPSE2.

## Requirements

 Software requirements are detailed in the conda environment file (`spec/snakemake.yml`). Paths to the base directory where everything will be downloaded/written and to GLIMPSE should be set by editing `spec/file_spec.json`. The genetic maps generated for GLIMPSE must be separately downloaded by cloning the [GLIMPSE repo](https://github.com/odelaneau/GLIMPSE/). The file path to the hg38 maps must then be supplied in `spec/file_spec.json`.

 Note that the X chromosome is bugged (some issue with the genotyping), and I have not yet figured out how to fix it. For now, I am just excluding it from downstream analyses.
