"""
Builds a phased 1kGP reference panel for low-coverage imputation with GLIMPSE2,
following https://odelaneau.github.io/GLIMPSE/docs/tutorials/getting_started/

Usage (see README.md for setup):
    snakemake -n -p --reason --resources load=100           # dry run
    snakemake -p --reason --cores all --resources load=100  # full run
    snakemake -p --cores 4 <path/to/output/file>             # single target

All paths/binaries are read from config.yaml (see that file for details);
override any of them with `--config KEY=VALUE` instead of editing it.

Per chromosome (autosomes only -- see "Known issues" in README.md for chrX),
the pipeline:
  1. downloads the phased VCF + index                  (download_1kgp_chrom)
  2. downloads the GLIMPSE genetic map                  (download_map)
  3. splits multiallelic records into biallelic ones    (qc_reference_panel_autosomes)
  4. extracts a sites-only VCF for chunking             (extract_sites)
  5. computes imputation chunks                         (chunk_chromosome)
  6. builds GLIMPSE2's binary reference panel, one job
     per chromosome that fans out across chunks
     internally via GNU parallel                        (split_reference)
"""

import os

configfile: "config.yaml"

REFDIR = config["1KGP_DIR"]
MAPDIR = config["MAPDIR"]

CHROMS = list(range(1, 23))  # chrX is excluded, see README.md

BASE_1KGP_URL = (
    "http://ftp.1000genomes.ebi.ac.uk/vol1/ftp/data_collections/"
    "1000G_2504_high_coverage/working/20220422_3202_phased_SNV_INDEL_SV"
)
PANEL_PREFIX = "1kGP_high_coverage_Illumina.chr{chrom}.filtered.SNV_INDEL_SV_phased_panel"

localrules: all


rule all:
    input:
        expand(
            os.path.join(REFDIR, PANEL_PREFIX + ".bcf{ext}"),
            chrom=CHROMS, ext=["", ".csi"],
        ),
        expand(
            os.path.join(REFDIR, PANEL_PREFIX + ".sites.vcf.gz{ext}"),
            chrom=CHROMS, ext=["", ".csi"],
        ),
        expand(os.path.join(REFDIR, "1kGP.chunks.chr{chrom}.txt"), chrom=CHROMS),
        expand(os.path.join(REFDIR, "glimpse_split", "1kGP.chr{chrom}.txt"), chrom=CHROMS),


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Download reference + genetic maps
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# One job per chromosome (rather than one big parallel/wget batch) so Snakemake's own
# scheduler handles concurrency, retries, and resuming a partially-completed download.


rule download_1kgp_chrom:
    output:
        vcf=os.path.join(REFDIR, PANEL_PREFIX + ".vcf.gz"),
        tbi=os.path.join(REFDIR, PANEL_PREFIX + ".vcf.gz.tbi"),
    resources:
        load=1,  # throttle concurrent hits against the FTP server; raise with --resources load=N
    shell:
        """
        set -euo pipefail
        wget -q -O {output.vcf} {BASE_1KGP_URL}/$(basename {output.vcf})
        wget -q -O {output.tbi} {BASE_1KGP_URL}/$(basename {output.tbi})
        """


rule download_map:
    output:
        os.path.join(MAPDIR, "chr{chrom}.b38.gmap.gz"),
    params:
        url="https://github.com/odelaneau/GLIMPSE/raw/master/maps/genetic_maps.b38/chr{chrom}.b38.gmap.gz",
    resources:
        load=1,
    shell:
        "set -euo pipefail; wget -q {params.url} -O {output}"


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Split multiallelic records, then extract a sites-only VCF for chunking
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


rule qc_reference_panel_autosomes:
    input:
        vcf=os.path.join(REFDIR, PANEL_PREFIX + ".vcf.gz"),
    output:
        bcf=os.path.join(REFDIR, PANEL_PREFIX + ".bcf"),
        index=os.path.join(REFDIR, PANEL_PREFIX + ".bcf.csi"),
    params:
        bcftools=config["BCFTOOLS"],
    threads: 4
    shell:
        """
        set -euo pipefail
        {params.bcftools} norm -m -any --threads {threads} -Ob -o {output.bcf} {input.vcf}
        {params.bcftools} index -f --threads {threads} {output.bcf}
        """


rule extract_sites:
    input:
        bcf=os.path.join(REFDIR, PANEL_PREFIX + ".bcf"),
    output:
        sites=os.path.join(REFDIR, PANEL_PREFIX + ".sites.vcf.gz"),
        index=os.path.join(REFDIR, PANEL_PREFIX + ".sites.vcf.gz.csi"),
    params:
        bcftools=config["BCFTOOLS"],
    threads: 4
    shell:
        """
        set -euo pipefail
        {params.bcftools} view -G --threads {threads} -Oz -o {output.sites} {input.bcf}
        {params.bcftools} index -f --threads {threads} {output.sites}
        """


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Chunk the reference panel
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


rule chunk_chromosome:
    input:
        sites=os.path.join(REFDIR, PANEL_PREFIX + ".sites.vcf.gz"),
        gmap=os.path.join(MAPDIR, "chr{chrom}.b38.gmap.gz"),
    output:
        chunks=os.path.join(REFDIR, "1kGP.chunks.chr{chrom}.txt"),
    params:
        chrom="chr{chrom}",
        glimpse2_chunk=config["GLIMPSE2_CHUNK"],
    shell:
        """
        set -euo pipefail
        {params.glimpse2_chunk} \
            --input {input.sites} \
            --region {params.chrom} \
            --output {output.chunks} \
            --map {input.gmap} \
            --sequential
        """


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Create binary reference panel
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# GLIMPSE2_split_reference is run once per chunk. A chromosome can have hundreds of
# chunks, so these run concurrently via GNU parallel (-j {threads}) instead of the
# strictly serial loop this used to be -- that loop was the single biggest bottleneck
# in the whole pipeline, since it ignored --cores entirely.


rule split_reference:
    input:
        REF=os.path.join(REFDIR, PANEL_PREFIX + ".bcf"),
        MAP=os.path.join(MAPDIR, "chr{chrom}.b38.gmap.gz"),
        chunks=os.path.join(REFDIR, "1kGP.chunks.chr{chrom}.txt"),
    output:
        os.path.join(REFDIR, "glimpse_split", "1kGP.chr{chrom}.txt"),
    params:
        glimpse2_split=config["GLIMPSE2_SPLIT_REFERENCE"],
        parallel=config["PARALLEL"],
        prefix=os.path.join(REFDIR, "glimpse_split", "1kGP"),
    threads: workflow.cores
    shell:
        """
        set -euo pipefail
        {params.parallel} --colsep ' ' -j {threads} \
            {params.glimpse2_split} \
                --reference {input.REF} --map {input.MAP} \
                --input-region {{3}} --output-region {{4}} \
                --output {params.prefix} \
            :::: {input.chunks}
        echo "Done" > {output}
        echo "REMINDER: verify the expected {params.prefix}_*_start_stop.bin files exist."
        """
