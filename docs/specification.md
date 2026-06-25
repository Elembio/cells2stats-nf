# Specification: cells2stats-nf

This document is the definitive reference for the `cells2stats-nf` pipeline.
It describes every input file, every output artifact, every convention,
and every assumption required to run or consume outputs produced by this pipeline.

---

## Table of Contents

- [1. Pipeline Overview](#1-pipeline-overview)
- [2. Input Files](#2-input-files)
  - [2.1 AVITI Run Directory](#21-aviti-run-directory)
  - [2.2 Panel.json](#22-paneljson)
  - [2.3 RunManifest.csv](#23-runmanifestcsv)
  - [2.4 Optional Inputs](#24-optional-inputs)
- [3. Conventions](#3-conventions)
  - [3.1 Naming Conventions](#31-naming-conventions)
  - [3.2 Assay Type Logging](#32-assay-type-logging)
  - [3.3 Tile, Well, and Batch Filtering](#33-tile-well-and-batch-filtering)
  - [3.4 Run ID Extraction](#34-run-id-extraction)
- [4. Process Specification: CELLS2STATS](#4-process-specification-cells2stats)
- [5. Output Directory Structure](#5-output-directory-structure)
- [6. Channel Data Flow](#6-channel-data-flow)
- [7. Configuration Profiles](#7-configuration-profiles)
  - [7.1 Profile Summary](#71-profile-summary)
  - [7.2 Base Configuration](#72-base-configuration)
  - [7.3 Test Profile](#73-test-profile)
  - [7.4 Other Profiles](#74-other-profiles)
  - [7.5 Container Version](#75-container-version)
  - [7.6 Resource Capping](#76-resource-capping)
  - [7.6 Other Profiles](#76-other-profiles)
  - [7.7 Container Version](#77-container-version)
  - [7.8 Resource Capping](#78-resource-capping)
- [8. Failure Modes and Recovery](#8-failure-modes-and-recovery)
  - [8.1 Retry Behavior](#81-retry-behavior)
  - [8.2 CPU Step-Down Retry Strategy](#82-cpu-step-down-retry-strategy)
  - [8.3 Resume Behavior](#83-resume-behavior)
  - [8.4 Skip Options](#84-skip-options)
- [9. Parameter Schema](#9-parameter-schema)
  - [9.1 Schema Organization](#91-schema-organization)
  - [9.2 Array Type Convention](#92-array-type-convention)

---

## 1. Pipeline Overview

The pipeline runs the Element Biosciences
[Cells2Stats](https://docs.elembio.io/docs/cells2stats/setup/) tool on raw
AVITI imaging data, producing cell segmentation masks, per-cell spatial
coordinates (X, Y, Z), and run-level QC statistics. Starting from a single
AVITI run directory, it executes a single Nextflow process that wraps the
`cells2stats` CLI.

```
  ┌──────────┐       ┌─────────────────────────────────────────────────┐
  │  AVITI   │──────▶│ CELLS2STATS                                    │
  │  Run     │       │  • Cell segmentation (boundary masks)           │
  │  Dir     │       │  • Spatial coordinate extraction (X, Y, Z)      │
  │          │       │  • Per-well statistics                          │
  │          │       │  • QC reports (MultiQC HTML)                    │
  │          │       │  • RawCellStats.parquet / .csv                  │
  │          │       │  • Optional: visualization, spatial data (zarr) │
  └──────────┘       └─────────────────────────────────────────────────┘
```

The pipeline validates inputs at launch (run directory existence, Panel.json
parsing), constructs filtering and option flags from parameters, and delegates
all analysis to the `cells2stats` container image. The `CELLS2STATS` module is
wrapped in a `CELLS2STATS_SUBWORKFLOW` sourced from
elembio-nf-modules,
enabling shared maintenance across standalone and combined pipelines (e.g.
`elembio-tetonatlas-nf`).

**Requirements:** Nextflow >= 21.10.3, a container runtime (Docker, Singularity,
or Podman).

---

## 2. Input Files

### 2.1 AVITI Run Directory

**Required.** The root input to the pipeline, specified via `--run_dir`.

The path must point to the AVITI run directory (local filesystem or S3). The
pipeline expects imaging data and instrument metadata files at known relative
locations within this directory.

**Path normalization:** Trailing slashes are stripped at launch:
```
run_dir = params.run_dir.replaceAll(/\/$/, '')
```

**Validation at launch:**
- `params.run_dir` must be set (non-null).
- The path must exist at pipeline start (`file(params.run_dir).exists()`).

**Run ID extraction** (same rule as bases2fastq-nf / elembio-tetonatlas-nf): If
`params.id` is set, it is used. Else if `run_dir` matches
`.../runs/<instrument>/<run_id>/analysis/<analysis_id>/...`, that `run_id` is
used. Otherwise `run_id` is the last path segment of `run_dir`.

**S3 paths** are supported natively via Nextflow's S3 integration.

---

### 2.2 Panel.json

**Required.** Defines assay batches and their types. The pipeline parses this
file at launch to build the `batch_assay_map` used for startup logging (see
[3.2](#32-assay-type-logging)).

**Resolution:** Looked up at `{run_dir_base}/Panel.json`, where `{run_dir_base}`
is `run_dir` with any `/analysis/...` suffix stripped:
```
panel_json_path = params.c2s_panel_json ?: "${run_dir.replaceAll('/analysis/.*$', '')}/Panel.json"
```

Override via `--c2s_panel_json`.

The file contains three tube arrays, each contributing to the batch-to-assay mapping:

**DISSPrimerTubes[]:**

| Field | Type | Description |
|-------|------|-------------|
| `BatchName` | string | e.g. `"B01"` |
| `AssayType` | string | `"ThreePrimeUntargeted"`, `"SpecializedTargeted"`, or `"TargetedTranscriptomeProfiling"` |

**BarcodingPrimerTubes[]:**

| Field | Type | Description |
|-------|------|-------------|
| `BatchName` | string | e.g. `"B01"` |

**ImagingPrimerTubes[]:**

| Field | Type | Description |
|-------|------|-------------|
| `BatchName` | string | e.g. `"CP01"` |
| `Type` | string | `"PreAmp"`, `"PostAmp"`, or `"Stain"` |

**Mapping rules:**
- `DISSPrimerTubes`: `BatchName` -> `AssayType` (e.g. `B01` -> `ThreePrimeUntargeted`)
- `BarcodingPrimerTubes`: `BatchName` -> `"Barcoding"`
- `ImagingPrimerTubes`: `BatchName` -> `Type` value (e.g. `"PreAmp"`) or `"Imaging"` if `Type` is absent

**Constraints:**
- The file must exist at the resolved path (`checkIfExists: true`).
- When `--c2s_panel_json` is set, it is passed to the CELLS2STATS process via
  `--panel` and also used for batch_assay_map construction.

---

### 2.3 RunManifest.csv

Per-well sample metadata. Not parsed by the pipeline itself; passed through to
the `cells2stats` CLI as-is when provided via `--c2s_run_manifest`.

Default behavior: cells2stats discovers the manifest from the run directory
automatically. Override via `--c2s_run_manifest`.

---

### 2.4 Optional Inputs

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `c2s_panel_json` | path | `null` | Override Panel.json for cells2stats (also used for batch_assay_map). |
| `c2s_run_manifest` | path | `null` | Override run manifest (.csv or .json). |
| `c2s_tca_manifest_csv` | path | `null` | Target Cell Assignment manifest CSV (SpecializedTargeted only). |
| `segmentation_dir` | path | `null` | Custom cell segmentation directory. |

---

## 3. Conventions

### 3.1 Naming Conventions

| Entity | Pattern | Examples |
|--------|---------|----------|
| Tile ID | `L{lane}R{row}C{col}S{site}` | `L2R01C01S1`, `L1R17C04S1` |
| Well ID | `{plate_row}{plate_col}` | `A1`, `B2`, `F12` |
| Imaging batch | `CP{nn}` | `CP01`, `CP02` |
| DISS/Barcoding batch | `B{nn}` | `B01`, `B05` |

---

### 3.2 Assay Type Logging

At pipeline launch, the `batch_assay_map` is used to print a summary of all
batches and their assay type classifications. Each batch is classified into one
of four channels for informational purposes:

| Channel | Assay types | Marker |
|---------|-------------|--------|
| `3prime` | `ThreePrimeUntargeted`, `Transcript` | `▸` |
| `specialized` | `SpecializedTargeted` | `▸` |
| `targeted_tx` | `TargetedTranscriptomeProfiling` | `▸` |
| `other` | All remaining (e.g. `Barcoding`, `Imaging`, `PreAmp`, `PostAmp`, `Stain`) | `─` |

The channel classification lists are configurable:

| Parameter | Default |
|-----------|---------|
| `three_prime_types` | `["ThreePrimeUntargeted", "Transcript"]` |
| `specialized_types` | `["SpecializedTargeted"]` |
| `targeted_tx_types` | `["TargetedTranscriptomeProfiling"]` |

These parameters accept either a Groovy list or a comma-separated string. They
are used only for startup logging in this pipeline; all batches are processed by
cells2stats regardless of classification.

---

### 3.3 Tile, Well, and Batch Filtering

Three parameters restrict which data is processed. They are translated into
cells2stats CLI flags.

| Parameter | Type | Default | CLI flag | Behavior |
|-----------|------|---------|----------|----------|
| `tile` | list[string] | `[]` (all tiles) | `--tile {pattern}` (one per pattern) | Regex filter on tile IDs |
| `c2s_well` | list[string] | `[]` (all wells) | `--well {pattern}` (one per pattern) | Filter on well IDs |
| `filter_batch` | string | `null` (all batches) | `--batch {value}` | Comma-delimited batch names |

**Tile filtering:** Each element in the `tile` list is passed as a separate
`--tile` argument:
```
params.tile = ["L1R17C04S1", "L1R17C05S1"]
→ --tile L1R17C04S1 --tile L1R17C05S1
```

**Well filtering:** Each element in the `c2s_well` list is passed as a separate
`--well` argument:
```
params.c2s_well = ["A1", "B2"]
→ --well A1 --well B2
```

**Batch filtering:** The `filter_batch` string is passed directly:
```
params.filter_batch = "B01,B02"
→ --batch B01,B02
```

---

### 3.4 Run ID Extraction

The `run_id` is derived from the `run_dir` path using the following precedence:

1. `params.id` if explicitly provided.
2. Else if `run_dir` matches `.../runs/<instrument>/<run_id>/analysis/<analysis_id>/...`,
   use that `run_id` (regex: `.*\/runs\/[^\/]+\/([^\/]+)\/analysis\/[^\/]+(?:\/|$)`).
3. Else the last path segment of `run_dir`.

Examples:

- `s3://bucket/runs/AV233101/20250820_AV222902_WHTF-1078/` →
  `run_id = "20250820_AV222902_WHTF-1078"` (last segment).
- `s3://bucket/runs/AV233101/20250820_AV222902_WHTF-1078/analysis/custom123/` →
  same `run_id` (not `custom123`).

If `run_dir` ends exactly at `.../analysis` with no `analysis_id` segment, the
last segment may be `analysis`; pass `--id` explicitly in that case.

---

## 4. Process Specification: CELLS2STATS

**Purpose:** Process AVITI imaging data to identify cell boundaries, extract
spatial coordinates (X, Y, Z) for each cell, produce cell segmentation masks,
and generate run-level QC statistics.

**Container:** `{c2s_container_url}:{c2s_container_tag}` (default: `904220683607.dkr.ecr.us-west-2.amazonaws.com/cells2stats-release:1.4.0-beta`)

**Label:** `process_high`

**Scratch:** `true` (global setting; uses local scratch storage)

### Inputs

| Input | Type | Channel | Description |
|-------|------|---------|-------------|
| `meta` | val | `ch_run_dir` | Run metadata map (`{id: run_id}`) |
| `run_dir` | val | `ch_run_dir` | Path to AVITI run directory |
| `run_panel` | path | `ch_panel` | Optional custom Panel.json (empty list `[]` if not provided) |
| `run_manifest` | path | `ch_run_manifest` | Optional custom run manifest (empty list `[]` if not provided) |
| `segmentation` | path | `ch_segmentation` | Optional custom segmentation directory (empty list `[]` if not provided) |
| `tca_manifest` | path | `ch_tca_manifest` | Optional TargetCellAssignmentManifest CSV — empty list `[]` if not provided (SpecializedTargeted / OPS only) |

### Outputs

| Output | Format | Optional | Emit name | Description |
|--------|--------|----------|-----------|-------------|
| `AverageNormWellStats.csv` | CSV | Yes | `average_norm_well_stats_csv` | Normalized well-level statistics |
| `RawCellStats.csv` | CSV | No | `raw_cell_stats_csv` | Per-cell spatial coordinates and metadata |
| `RawCellStats.parquet` | Parquet | No | `raw_cell_stats_parquet` | Per-cell spatial coordinates and metadata (columnar) |
| `RunStats.json` | JSON | Yes | `run_stats_json` | Run-level QC statistics |
| `RunParameters.json` | JSON | Yes | `run_parameters_json` | Instrument parameters (copy from run dir) |
| `Panel.json` | JSON | Yes | `panel_json` | Assay panel configuration (copy from run dir) |
| `RunManifest.json` | JSON | Yes | `run_manifest_json` | Run manifest (JSON format) |
| `RunManifest.csv` | CSV | Yes | `run_manifest_csv` | Run manifest (CSV format) |
| `Versions.json` | JSON | Yes | `versions_json` | cells2stats tool version information |
| `Wells/` | Directory | Yes | `wells_dir` | Per-well output directory |
| `Wells/**/*_rawreads.parquet` | Parquet | Yes | `rawreads_files` | Per-tile rawreads parquets (glob-emit; group by `(well, batch)` downstream) |
| `CellSegmentation/` | Directory | Yes | `cell_segmentation` | Cell boundary masks |
| `AnalysisRegion/` | Directory | Yes | `analysis_region` | Per-tile analysis region masks |
| `Logs.tar.gz` | tar.gz | Yes | `program_logs_tar` | Tarred program logs (when `c2s_tar_program_logs=true`) |
| `Logs/` | Directory | Yes | `program_logs` | Program logs (when `c2s_tar_program_logs=false`) |
| `TargetCellAssignmentManifest.csv` | CSV | Yes | `target_cell_assignment_manifest_csv` | TCA manifest (SpecializedTargeted only) |
| `TargetCellAssignmentManifest.json` | JSON | Yes | `target_cell_assignment_manifest_json` | TCA manifest (SpecializedTargeted only) |
| `TargetCounts.json` | JSON | Yes | `target_counts_json` | Target counts (SpecializedTargeted only) |
| `cyto.viz` | Binary | Yes | `cyto_viz` | Visualization data file |
| `visualization.zip` | ZIP | Yes | `viz_zip` | Visualization archive |
| `visualization-index.json.gz` | gzip JSON | Yes | `viz_index_json_gz` | Visualization index |
| `SpatialData/` | Directory | Yes | `spatial_data_dir` | SpatialData parent directory |
| `SpatialData/*.zip` | ZIP | Yes | `spatial_data_zip` | Spatial data zarr (zipped) |
| `SpatialData/*.zarr` | Zarr | Yes | `spatial_data_zarr` | Spatial data zarr (unzipped) |
| `multiqc_report.html` | HTML | Yes | `multiqc_report` | cells2stats QC report |
| `metrics/` | Directory | No | `metrics_dir` | Curated small-metadata mirror (top-level files, denylisted bulk extensions, 100 MB cap, plus `info/`) — consumed by `build-spatialdata --c2s-dir` |
| `versions.yml` | YAML | No | `versions` | Nextflow-standard version tracking (bare path, not `tuple val(meta), ...`) |
| `run.log` | Text | No | `run_log` | Full stdout/stderr log of the process |

### Module CLI Flag Mapping

The mapping from pipeline parameters to cells2stats CLI flags is composed in
**[`conf/modules.config`](../conf/modules.config)** via a `task.ext.args` closure
on the `withName: CELLS2STATS` block — per the nf-core convention adopted by the
upstream module registry. The module itself reads only `task.ext.args`,
`task.ext.tar_logs`, and the named channel inputs declared in its `input:` block
— it does **not** read `params.*` directly (except the container directive, which
is the standard nf-core escape hatch).

For the canonical `ext.args` pattern (with consumer-side examples, override
mechanism, and conventions for grouping / shared filters), see the upstream
README section
[Module configuration via `task.ext.args`](https://github.com/Elembio/cells2stats-nf#module-configuration-via-taskextargs).

To **override** any flag in this pipeline without forking, drop a `-c
custom.config` file with your own `withName: CELLS2STATS { ext.args = { ... } }`
closure that fully replaces the closure in `conf/modules.config`. Closures
specified later in the config chain replace earlier ones rather than merging.

The four path-flags (`--panel`, `--run-manifest`, `--segmentation`,
`--tca-manifest`) are **not** in the closure — they are composed inside the
module from the staged channel-input paths (see `Inputs` table above and
[§6.1](#61-input-channel-construction)).

### CLI Construction

```
cells2stats -l {log_level} -j {cpus} --output . \
    [--batch {filter_batch}] \
    [--error-on-missing] [--max-unassigned {n}] [--no-error-on-invalid] \
    [--panel {panel}] [--run-manifest {manifest}] [--segmentation {dir}] \
    [--tca-manifest {tca_manifest}] \
    [--skip-cellprofiler] [--skip-html-report] \
    [--tile {pattern}]... [--well {pattern}]... \
    [--target-mismatch-threshold {n}] \
    [--specialized-targeted-min-query-length {len}] \
    [--generate-specialized-targeted-bams] \
    [{c2s_args}] {run_dir}
```

**Parameter-to-flag mapping:**

| Parameter | Condition | CLI flag |
|-----------|-----------|----------|
| `c2s_log_level` | Always (default `info`) | `-l {value}` |
| (cpus) | Always | `-j {task.cpus}` |
| `filter_batch` | Non-null | `--batch {value}` |
| `c2s_error_on_missing` | `true` | `--error-on-missing` |
| `c2s_max_unassigned` | Non-null | `--max-unassigned {value}` |
| `c2s_no_error_on_invalid` | `true` | `--no-error-on-invalid` |
| `c2s_panel_json` | Non-null (staged as `run_panel`) | `--panel {run_panel}` |
| `c2s_run_manifest` | Non-null (staged as `run_manifest`) | `--run-manifest {run_manifest}` |
| `segmentation_dir` | Non-null (staged as `segmentation`) | `--segmentation {segmentation}` |
| `c2s_skip_cellprofiler` | `true` | `--skip-cellprofiler` |
| `c2s_skip_html_report` | `true` | `--skip-html-report` |
| `tile` | Non-empty list | `--tile {pattern}` (one per element) |
| `c2s_well` | Non-empty list | `--well {pattern}` (one per element) |
| `c2s_tca_manifest_csv` | Non-null (staged as `tca_manifest`) | `--tca-manifest {tca_manifest}` |
| `c2s_target_mismatch_threshold` | Non-null (OPS / SpecializedTargeted) | `--target-mismatch-threshold {value}` |
| `c2s_specialized_targeted_min_query_length` | Non-null (OPS / SpecializedTargeted) | `--specialized-targeted-min-query-length {value}` |
| `c2s_generate_specialized_targeted_bams` | `true` (OPS / SpecializedTargeted) | `--generate-specialized-targeted-bams` |
| `c2s_args` | Non-empty | Appended verbatim (deprecated — prefer `withName: CELLS2STATS { ext.args = { ... } }` overlay) |

### Post-Processing Steps

After cells2stats completes:

1. **Ensure directory outputs exist:** `mkdir -p Wells CellSegmentation Logs`
   (cells2stats may not create all directories depending on run content).

2. **Clean up bowtie-build logs:** `rm -rf Logs/bowtie-build/` removes empty
   bowtie-build log directories.

3. **Optional log tarring:** When `c2s_tar_program_logs=true` (default), the Logs
   directory is archived (`tar czf Logs.tar.gz Logs/`) and the original directory
   removed. When `false`, the directory is published as-is.

4. **Curated small-metadata mirror:** A `metrics/` directory is populated with
   top-level files (`*.json`, `*.csv`, etc.) using a denylist for bulk extensions
   (parquet, bam/bai, cram/crai, sam, fastq.gz, fq.gz) and a 100 MB per-file size
   cap. Used downstream by `build-spatialdata --c2s-dir`.

5. **Version capture:** The cells2stats version is extracted and written to
   `versions.yml` in nf-core standard format.

### Logging

All stdout and stderr are captured to `run.log` via `exec > >(tee $logfile)`.
The log includes the container image reference and the full cells2stats output.

---

## 5. Output Directory Structure

All outputs are published to `{outdir}/` (flat structure). The publish directory
mode is controlled by `params.publish_dir_mode` (default: `copy`).

```
{outdir}/
├── RawCellStats.parquet              Per-cell spatial coordinates & metadata
├── RawCellStats.csv                  CSV version of cell stats
├── AverageNormWellStats.csv          Normalized well-level statistics
├── RunStats.json                     Run-level statistics
├── RunParameters.json                Instrument parameters (copy)
├── Panel.json                        Assay panel configuration (copy)
├── RunManifest.json                  Run manifest (JSON format)
├── RunManifest.csv                   Run manifest (CSV format)
├── Versions.json                     cells2stats tool versions
├── multiqc_report.html               cells2stats QC report
├── multiqc/                          MultiQC data subdirectory (if produced)
├── run.log                           Process stdout/stderr log
├── Wells/                            Per-well output directory (incl. **/*_rawreads.parquet)
├── CellSegmentation/                 Cell segmentation masks
├── AnalysisRegion/                   Per-tile analysis region masks
├── Logs/                             Program logs (directory)
│   (or Logs.tar.gz)                  Program logs (tar, if c2s_tar_program_logs=true)
├── SpatialData/                      Spatial data zarr stores (if produced)
│   └── *.zarr or *.zip
├── cyto.viz                          Visualization data (if produced)
├── visualization.zip                 Visualization archive (if produced)
├── visualization-index.json.gz       Visualization index (if produced)
├── TargetCellAssignmentManifest.csv  TCA manifest (SpecializedTargeted / OPS only)
├── TargetCellAssignmentManifest.json TCA manifest (SpecializedTargeted / OPS only)
├── TargetCounts.json                 Target counts (SpecializedTargeted / OPS only)
│
└── pipeline_info/
    ├── execution_trace.txt           Task-level trace
    └── execution_report.html         Interactive execution report
```

The module also emits an unpublished `metrics/` directory (curated small-metadata
mirror) for consumption by downstream tools — it lives in the Nextflow work
directory and is not copied into `{outdir}/`.

**Publish rules (from modules.config):**

| Pattern | Condition | Description |
|---------|-----------|-------------|
| `*.{json,csv,log,parquet,viz,zip,json.gz}` | Always | All flat file outputs |
| `multiqc_report.html` | Always | QC report |
| `multiqc/**` | Always | MultiQC data subdirectory |
| `Wells/` | Always | Per-well directory |
| `CellSegmentation/` | Always | Segmentation masks |
| `AnalysisRegion/` | Always | Analysis region masks |
| `Logs{,.tar.gz}` | Always | Logs directory or tar |
| `SpatialData/` | Always | Spatial data outputs |

The `versions.yml` file is excluded from publishing (`saveAs: null`).

---

## 6. Channel Data Flow

The pipeline constructs five input channels from parameters at launch and
passes them to the single CELLS2STATS process via `CELLS2STATS_SUBWORKFLOW`.

### 6.1 Input Channel Construction

```
meta = [id: run_id]

ch_run_dir      = Channel.value([meta, run_dir])
ch_panel        = params.c2s_panel_json      ? Channel.value(file(path)) : Channel.value([])
ch_run_manifest = params.c2s_run_manifest    ? Channel.value(file(path)) : Channel.value([])
ch_segmentation = params.segmentation_dir    ? Channel.value(file(path)) : Channel.value([])
ch_tca_manifest = params.c2s_tca_manifest_csv ? Channel.value(file(path)) : Channel.value([])
```

When optional inputs are not provided, an empty list `[]` is passed. The
CELLS2STATS process checks for truthiness of the staged path to decide whether
to include the corresponding CLI flag.

### 6.2 Workflow

```groovy
include { CELLS2STATS_SUBWORKFLOW } from './subworkflows/elembio/cells2stats/main'

workflow {
    CELLS2STATS_SUBWORKFLOW (
        ch_run_dir,
        ch_panel,
        ch_run_manifest,
        ch_segmentation,
        ch_tca_manifest,
    )
}
```

The `CELLS2STATS_SUBWORKFLOW` is sourced from
elembio-nf-modules
and installed via `nf-core subworkflows install`. It wraps the `CELLS2STATS`
module, passing through all inputs unchanged.

### 6.3 Output Channels

Data outputs are emitted as `tuple val(meta), path(file)` channels. Each output
has a named emit (e.g. `raw_cell_stats_parquet`, `wells_dir`). Optional outputs
use `optional: true` and emit `null` if the file was not produced.

The required outputs (always present) are:
- `raw_cell_stats_csv` -- `RawCellStats.csv`
- `raw_cell_stats_parquet` -- `RawCellStats.parquet`
- `metrics_dir` -- curated small-metadata mirror (used by `build-spatialdata --c2s-dir`)
- `run_log` -- per-process `run.log`
- `versions` -- `versions.yml` (emitted as a **bare path**, not a per-sample tuple,
  per nf-core convention; downstream consumers feed it directly into
  `softwareVersionsToYAML` without `.map { v -> v[-1] }`)

All other outputs are optional and depend on the assay types (e.g. SpecializedTargeted /
OPS produces `TargetCellAssignmentManifest.*`, `TargetCounts.json`), parameters, and
cells2stats behavior.

---

## 7. Configuration Profiles

### 7.1 Profile Summary

| Profile | Purpose | Config file |
|---------|---------|-------------|
| `docker` | Enable Docker container engine | Inline in `nextflow.config` |
| `test` | Minimal test dataset (single tile) | `conf/test.config` |
| `local` | Local compute with reduced resources | `conf/local.config` |
| `tower` | Seqera Platform (Tower) | `conf/tower.config` |
| `fusion` | Seqera Fusion file system | `conf/fusion.config` |
| `notaskdir` | Flat publish directory (no task subdirs) | `conf/notaskdir.config` |

Profiles are combined: `-profile docker,test` or `-profile tower,docker`.

---

### 7.2 Base Configuration

Default resource allocations (from `conf/base.config`), always loaded:

| Label | CPUs | Memory | Time |
|-------|------|--------|------|
| (default) | 1 * attempt | 6 GB * attempt | 4 h * attempt |
| `process_low` | 2 * attempt | 12 GB * attempt | 4 h * attempt |
| `process_medium` | 6 * attempt | 36 GB * attempt | 8 h * attempt |
| `process_high` | 12 * attempt | 72 GB * attempt | 16 h * attempt |
| `process_long` | -- | -- | 20 h * attempt |
| `process_high_memory` | -- | 200 GB * attempt | -- |

**CELLS2STATS-specific override (base.config):**

| Property | Value |
|----------|-------|
| CPUs | Step-down: `[48, 24, 12]` (attempt 1 = 48, attempt 2 = 24, attempt 3+ = 12) |
| Memory | 180 GB (constant across attempts) |
| Time | 2 h * attempt |
| maxRetries | 4 |

**Error strategy:** Retry on all exit codes except 127 (command not found).
Maximum 5 retries (base label default), unlimited total errors (`maxErrors = -1`).

**Docker:** Enabled by default in `base.config` (`docker.enabled = true`).

---

### 7.3 Test Profile

Designed for quick validation with minimal resources:

| Setting | Value |
|---------|-------|
| `id` | `"20250820_AV222902_WHTF-1078"` |
| `run_dir` | `s3://element-public-data/cytoprofiling/20250820_AV222902_WHTF-1078_20251112T053054Z/` |
| `tile` | `["L1R01C01S1"]` (single tile) |
| `c2s_skip_html_report` | `false` |
| Container | `904220683607.dkr.ecr.us-west-2.amazonaws.com/cells2stats-release:1.4.0-beta` |

**Process resources (reduced):**

| Property | Value |
|----------|-------|
| CPUs | 8 |
| Memory | 15 GB |
| Time | 2 h |
| maxRetries | 2 |

**Global caps:** `max_cpus = 2`, `max_memory = 6.GB`, `max_time = 6.h`.

`cleanup = false` (preserve work directories for debugging).

---

### 7.4 Other Profiles

**local** -- Local compute with minimal resources:

| Property | Value |
|----------|-------|
| CPUs | 2 |
| Memory | 6 GB |
| `cleanup` | `false` |
| `fusion.enabled` | `false` |
| `process.scratch` | `true` |

**tower** -- Includes the nf-core AWS Tower config and sets profile metadata:
```
includeConfig "https://raw.githubusercontent.com/nf-core/configs/master/conf/aws_tower.config"
```

**fusion** -- Enables Seqera Fusion and Wave, disables scratch:
```
fusion.enabled = true
wave.enabled = true
process.scratch = false
```

**notaskdir** -- Overrides the default `publishDir` to publish all outputs to
`{outdir}/` without task-specific subdirectories.

---

### 7.5 Container Version

| Tool | Default Image | Default Tag |
|------|---------------|-------------|
| cells2stats | `904220683607.dkr.ecr.us-west-2.amazonaws.com/cells2stats-release` | `1.4.0-beta` |

Controlled by two parameters:

| Parameter | Default |
|-----------|---------|
| `c2s_container_url` | `904220683607.dkr.ecr.us-west-2.amazonaws.com/cells2stats-release` |
| `c2s_container_tag` | `1.4.0-beta` |

The container reference is assembled as `${params.c2s_container_url}:${params.c2s_container_tag}`.

---

### 7.6 Resource Capping

All resources are capped by global maximums via the `check_max()` function
defined in `nextflow.config`:

| Parameter | Default |
|-----------|---------|
| `max_memory` | `192.GB` |
| `max_cpus` | `48` |
| `max_time` | `8.h` |

The `check_max()` function compares the requested resource against the cap and
returns the lesser value. If the cap is invalid, the original value is used with
a warning.

---

## 8. Failure Modes and Recovery

### 8.1 Retry Behavior

The base configuration retries failed tasks (from `base.config`):

| Exit code | Strategy |
|-----------|----------|
| 127 (command not found) | `finish` (terminate immediately) |
| All other codes | `retry` (retry up to `maxRetries`) |

Resources scale with attempt number for label-based defaults (e.g.
`memory = 6.GB * task.attempt`), so retries get progressively more resources up
to the global caps.

### 8.2 CPU Step-Down Retry Strategy

The CELLS2STATS process uses a unique CPU step-down strategy rather than scaling
up. This reflects the observation that cells2stats may encounter thread
contention or memory pressure issues with high parallelism:

| Attempt | CPUs | Memory | Time |
|---------|------|--------|------|
| 1 | 48 | 180 GB | 2 h |
| 2 | 24 | 180 GB | 4 h |
| 3 | 12 | 180 GB | 6 h |
| 4+ | 12 | 180 GB | 2 h * attempt |

Memory remains constant at 180 GB across all attempts. Time scales linearly
with attempt number.

This strategy applies in the base profile. The test profile overrides it with fixed resource allocations.

### 8.3 Resume Behavior

Nextflow's `-resume` flag enables work directory caching. Successfully completed
tasks are skipped on re-run. Only failed or new tasks execute.

```bash
nextflow run cells2stats-nf --run_dir /path/to/run -profile docker -resume
```

Cached results are stored in the `work/` directory. The cache is keyed on:
- Process name and script hash
- Input file hashes (content-based)
- Container image
- Parameter values (via CLI flag assembly)

### 8.4 Skip Options

| Parameter | Default | Effect |
|-----------|---------|--------|
| `c2s_skip_cellprofiler` | `false` | Skip CellProfiler in cells2stats (faster, fewer outputs) |
| `c2s_skip_html_report` | `false` | Skip MultiQC report generation |

---

## 9. Parameter Schema

The file `nextflow_schema.json` provides a JSON Schema definition of all pipeline
parameters. It is used by nf-schema for parameter validation, Seqera Platform
(Tower) launch form generation, and `nextflow run --help` output.

### 9.1 Schema Organization

The schema is organized into `$defs` sections that group related parameters:

| Section | Parameters | Description |
|---------|------------|-------------|
| `input_output_options` | `run_dir`, `outdir`, `id` | Required inputs and output directory |
| `shared_filters` | `tile`, `filter_batch`, `segmentation_dir` | Data subsetting filters |
| `assay_types` | `three_prime_types`, `specialized_types`, `targeted_tx_types` | Assay type classification lists for batch logging |
| `cells2stats` | `c2s_*` parameters | All cells2stats process options |
| `docker_containers` | `c2s_container_url`, `c2s_container_tag` | Container image configuration |
| `infrastructure` | `max_cpus`, `max_memory`, `max_time`, `publish_dir_mode`, `tracedir`, `custom_config_*`, `config_profile_*`, `enable_conda` | Resource limits and pipeline infrastructure |

All sections are referenced via `allOf` so every parameter is validated.

### 9.2 Array Type Convention

Nextflow parameters that are Groovy lists in `nextflow.config` (e.g.
`tile = []`, `c2s_well = []`, `three_prime_types = ["ThreePrimeUntargeted", "Transcript"]`)
cannot be represented as JSON Schema arrays because nf-schema does not natively
support array types when passed via the command line or `-params-file`.

These parameters are declared as `"type": "string"` in the schema with their
default set to the stringified list representation:

```json
"tile": {
  "type": "string",
  "default": "[]"
},
"three_prime_types": {
  "type": "string",
  "default": "['ThreePrimeUntargeted', 'Transcript']"
}
```

At runtime, Nextflow parses the Groovy list syntax from `nextflow.config` and
the pipeline code handles both native lists and comma-separated strings:

```groovy
def three_prime_types = params.three_prime_types instanceof List ?
    params.three_prime_types : params.three_prime_types.toString().split(',').collect{ it.trim() }
```

The affected parameters are:

| Parameter | Config default | Schema default |
|-----------|---------------|----------------|
| `tile` | `[]` | `"[]"` |
| `c2s_well` | `[]` | `"[]"` |
| `three_prime_types` | `["ThreePrimeUntargeted", "Transcript"]` | `"['ThreePrimeUntargeted', 'Transcript']"` |
| `specialized_types` | `["SpecializedTargeted"]` | `"['SpecializedTargeted']"` |
| `targeted_tx_types` | `["TargetedTranscriptomeProfiling"]` | `"['TargetedTranscriptomeProfiling']"` |
