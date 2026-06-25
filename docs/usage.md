# Usage Guide

Practical examples for running the cells2stats-nf pipeline.

---

## Prerequisites

### Software Requirements

1. **Nextflow** (>= 21.10.3)
   ```bash
   curl -s https://get.nextflow.io | bash
   ```

2. **Container Runtime** (one of):
   - Docker
   - Singularity/Apptainer
   - Podman

### Data Requirements

The pipeline expects an AVITI run directory produced by the Element AVITI System.

---

## Basic Usage

### Local Run with Docker

```bash
nextflow run cells2stats-nf \
    --run_dir /path/to/aviti/run/directory \
    -profile docker
```

### AWS S3 Data

```bash
nextflow run cells2stats-nf \
    --run_dir s3://bucket/runs/AV123456/20240101_AV123456_WHTF-1234/ \
    -profile docker
```

The `run_id` is auto-extracted from the S3 path. To override:

```bash
nextflow run cells2stats-nf \
    --run_dir s3://bucket/runs/AV123456/20240101_AV123456_WHTF-1234/ \
    --id my_custom_run_id \
    -profile docker
```

---

## Test Run

Run with a minimal test dataset to verify installation:

```bash
git clone https://github.com/Elembio/cells2stats-nf.git
cd cells2stats-nf

nextflow run . -profile test,docker
```

The test profile:
- Uses a single tile (`L1R01C01S1`) for fast execution
- Enables the cells2stats HTML report
- Outputs to `results/` directory

---

## Subset by Tile

Process only specific tiles. The `tile` parameter is a list set via a config file or params file:

```groovy
// In a config file — single tile
params.tile = ["L1R17C04S1"]

// Multiple tiles
params.tile = ["L1R17C04S1", "L1R17C05S1"]
```

```bash
nextflow run cells2stats-nf \
    --run_dir /path/to/run \
    -params-file params.json \
    -profile docker
```

## Subset by Well

Filter to specific wells:

```groovy
// In a config file
params.c2s_well = ["A1", "B2"]
```

## Subset by Batch

Process only specific batches:

```bash
nextflow run cells2stats-nf \
    --run_dir /path/to/run \
    --filter_batch "B01,B02" \
    -profile docker
```

---

## Visualization and Spatial Data

The dedicated `--c2s_visualization*`, `--c2s_full_res`, `--c2s_spatial_data*`,
and `--c2s_unzip_spatial_data` flags were removed in cells2stats 1.4.0+. Any
remaining variants (e.g. for upcoming releases) should be added via a
`-c custom.config` overlay that extends the `ext.args` closure on
`withName: CELLS2STATS`:

```groovy
// custom.config
process {
    withName: CELLS2STATS {
        ext.args = { '--some-future-cells2stats-flag value' }
    }
}
```

```bash
nextflow run cells2stats-nf \
    --run_dir /path/to/run \
    -c custom.config \
    -profile docker
```

The legacy `--c2s_args` parameter still appends to the CLI but is **deprecated**
and will be removed in a future release.

---

## OPS / SpecializedTargeted Tuning

For SpecializedTargeted (including OPS) batches:

```bash
nextflow run cells2stats-nf \
    --run_dir /path/to/run \
    --c2s_target_mismatch_threshold 1 \
    --c2s_specialized_targeted_min_query_length 20 \
    --c2s_generate_specialized_targeted_bams true \
    -profile docker
```

---

## Custom Panel and Manifest

### Custom Panel.json

```bash
nextflow run cells2stats-nf \
    --run_dir /path/to/run \
    --c2s_panel_json /path/to/custom_Panel.json \
    -profile docker
```

### Custom Run Manifest

```bash
nextflow run cells2stats-nf \
    --run_dir /path/to/run \
    --c2s_run_manifest /path/to/RunManifest.csv \
    -profile docker
```

### Custom Segmentation

```bash
nextflow run cells2stats-nf \
    --run_dir /path/to/run \
    --segmentation_dir /path/to/segmentation/ \
    -profile docker
```

---

## AWS Batch Execution

### Using Seqera Tower (Platform)

```bash
nextflow run cells2stats-nf \
    --run_dir s3://bucket/runs/INSTRUMENT/RUNID/ \
    -profile tower \
    -with-tower
```

---

## Custom Output Directory

```bash
nextflow run cells2stats-nf \
    --run_dir /path/to/run \
    --outdir /path/to/output \
    -profile docker
```

---

## Resume Failed Runs

Nextflow automatically caches completed tasks. To resume a failed run:

```bash
nextflow run cells2stats-nf \
    --run_dir /path/to/run \
    -profile docker \
    -resume
```

---

## Resource Configuration

### Override Process Resources

Create a custom config file:

```groovy
// custom_resources.config
process {
    withName: 'CELLS2STATS' {
        cpus = 24
        memory = '96.GB'
        time = '4.h'
    }
}
```

```bash
nextflow run cells2stats-nf \
    --run_dir /path/to/run \
    -c custom_resources.config \
    -profile docker
```

### Global Resource Limits

```bash
nextflow run cells2stats-nf \
    --run_dir /path/to/run \
    --max_memory 128.GB \
    --max_cpus 24 \
    --max_time 8.h \
    -profile docker
```

---

## Passthrough Arguments

For cells2stats CLI flags not exposed as named parameters, the recommended
approach is a `-c custom.config` overlay that fully replaces the `ext.args`
closure on `withName: CELLS2STATS`:

```groovy
// custom.config — replaces the closure in conf/modules.config
process {
    withName: CELLS2STATS {
        ext.args = {
            [
                params.c2s_log_level ? "-l ${params.c2s_log_level}" : '-l info',
                '--some-advanced-flag value',
            ].findAll().join(' ')
        }
    }
}
```

```bash
nextflow run cells2stats-nf \
    --run_dir /path/to/run \
    -c custom.config \
    -profile docker
```

Closures specified later in the config chain replace earlier ones rather than
merging — if you want to keep all existing flags, copy the closure body from
[conf/modules.config](../conf/modules.config) before adding your own line(s).

The legacy `--c2s_args` parameter still appends to the CLI but is **deprecated**
and will be removed in a future release:

```bash
nextflow run cells2stats-nf \
    --run_dir /path/to/run \
    --c2s_args "--some-advanced-flag value" \
    -profile docker
```

---

## Debugging

### Enable Detailed Logging

```bash
nextflow run cells2stats-nf \
    --run_dir /path/to/run \
    -profile docker \
    -with-report \
    -with-timeline \
    -with-trace
```

### Increase cells2stats Log Level

```bash
nextflow run cells2stats-nf \
    --run_dir /path/to/run \
    --c2s_log_level debug \
    -profile docker
```
