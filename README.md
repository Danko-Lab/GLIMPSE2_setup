# GLIMPSE2_setup

 This repo contains a snakemake pipeline to create a phased reference panel from 1kGP for imputation with GLIMPSE2.

## Requirements

 Software requirements are detailed in the conda environment file (`spec/snakemake.yml`). Paths to the base directory where everything will be downloaded/written and to GLIMPSE should be set by editing `spec/file_spec.json`. GLIMPSE uses genetic maps to help decide how to chunk the genome to. These can be separately downloaded from the [GLIMPSE repo](https://github.com/odelaneau/GLIMPSE/). The file path to the hg38 maps must then be supplied in `spec/file_spec.json`. Similarly, the install path for GLIMPSE must be provided in the spec file.

 Note that the X chromosome is bugged, and I have not yet figured out how to fix it. For now, I am just excluding it entirely (both non-PAR and the two PARs).
