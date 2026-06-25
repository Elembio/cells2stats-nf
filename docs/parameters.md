# Parameter Reference

Complete reference for all cells2stats-nf parameters.

---

## Input/Output Parameters

### Required

| Parameter | Type | Description |
|-----------|------|-------------|
| `run_dir` | Path | Path to AVITI run directory. Can be local filesystem or S3 path. |

### Optional

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `id` | String | Auto-detected | Run identifier. If not set: analysis-path rule when `run_dir` matches `.../runs/<instrument>/<run_id>/analysis/<analysis_id>/...`, else last path segment of `run_dir`. |
| `outdir` | Path | `./results` | Output directory. |

---

## Shared Filtering Parameters

These parameters control data subsetting:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `filter_batch` | String | `null` | Restrict to specific batch(es), comma-delimited (e.g., `B01,B02,B03`). |
| `tile` | List | `[]` | Tile regex pattern(s) (e.g., `["L1R17C04S1"]`). Restricts processing to matching tiles. |
| `segmentation_dir` | Path | `null` | Custom cell segmentation directory. Passed to cells2stats via `--segmentation`. |

---

## cells2stats (c2s) Parameters

### General Options

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `c2s_panel_json` | Path | `null` | Path to custom Panel.json file. Staged as channel input and passed via `--panel`. |
| `c2s_run_manifest` | Path | `null` | Path to custom run manifest (.csv or .json). Staged as channel input and passed via `--run-manifest`. |
| `c2s_tca_manifest_csv` | Path | `null` | Path to Target Cell Assignment manifest CSV. Staged as channel input and passed via `--tca-manifest` (SpecializedTargeted / OPS only). |
| `c2s_well` | List | `[]` | Well filter(s) (e.g., `["A1", "B2"]`). Restricts processing to matching wells. |

### Processing Options

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `c2s_error_on_missing` | Boolean | `false` | Terminate on missing files. |
| `c2s_no_error_on_invalid` | Boolean | `false` | Skip invalid files instead of erroring. |
| `c2s_skip_cellprofiler` | Boolean | `false` | Skip CellProfiler execution. |
| `c2s_skip_html_report` | Boolean | `false` | Skip MultiQC HTML report generation. |
| `c2s_tar_program_logs` | Boolean | `true` | Tar/gz the Logs directory; when false, publish as directory. |
| `c2s_max_unassigned` | Integer | `null` | Maximum unassigned sequences to report (1-10000). |
| `c2s_log_level` | String | `info` | Log level: debug, info, warning, error. |

### OPS / SpecializedTargeted Options

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `c2s_target_mismatch_threshold` | Integer | `null` | `--target-mismatch-threshold N` (0-3); overrides per-batch TCA manifest setting. |
| `c2s_specialized_targeted_min_query_length` | Integer | `null` | `--specialized-targeted-min-query-length LENGTH` (>=12). |
| `c2s_generate_specialized_targeted_bams` | Boolean | `false` | `--generate-specialized-targeted-bams`. |

### Custom Arguments

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `c2s_args` | String | `""` | **Deprecated.** Catch-all string appended to the cells2stats CLI. Prefer overriding `withName: CELLS2STATS { ext.args = { ... } }` in a `-c custom.config` overlay; see [conf/modules.config](../conf/modules.config) for the canonical closure. Will be removed in a future release. |

---

## Container Configuration

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `c2s_container_url` | String | `904220683607.dkr.ecr.us-west-2.amazonaws.com/cells2stats-release` | cells2stats container repository. |
| `c2s_container_tag` | String | `1.4.0-beta` | cells2stats container version. |

---

## Resource Limits

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `max_memory` | String | `192.GB` | Maximum memory per process. |
| `max_cpus` | Integer | `48` | Maximum CPUs per process. |
| `max_time` | String | `8.h` | Maximum time per process. |

---

## Publishing Options

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `publish_dir_mode` | String | `copy` | How to publish output files: `copy`, `symlink`, `move`, etc. |
| `tracedir` | Path | `{outdir}/pipeline_info` | Directory for Nextflow trace/timeline/report files. |
