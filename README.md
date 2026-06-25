**cells2stats-nf** is a Nextflow pipeline that assigns reads and generates cell-level statistics from AVITI System run data using the [Cells2Stats](https://docs.elembio.io/docs/cells2stats/setup/) tool.

## Quick Start

```bash
nextflow run Elembio/cells2stats-nf \
    --run_dir /path/to/aviti/run/directory \
    -profile docker
```

Or from S3:

```bash
nextflow run Elembio/cells2stats-nf \
    --run_dir s3://bucket/runs/AV123456/20240101_AV123456_WHTF-1234/ \
    -profile docker
```

## Container

| Registry | Repository | Tag |
|----------|-----------|-----|
| Amazon ECR Public | `904220683607.dkr.ecr.us-west-2.amazonaws.com/cells2stats-release` | `1.4.0-beta` |

## Profiles

| Profile | Description |
|---------|-------------|
| `docker` | Run with Docker |
| `test` | Minimal single-tile test run (public dataset) |
| `local` | Local compute with reduced resources |
| `tower` | Seqera Platform (Tower) |
| `fusion` | Seqera Fusion file system |
| `notaskdir` | Flat publish directory |

Combine profiles: `-profile docker,tower`

## Test Run

```bash
git clone https://github.com/Elembio/cells2stats-nf.git
cd cells2stats-nf

nextflow run . -profile test,docker
```

## Documentation

- [Parameter Reference](docs/parameters.md) — all pipeline parameters
- [Usage Guide](docs/usage.md) — examples and advanced usage
- [Pipeline Specification](docs/specification.md) — full technical specification
- [Cells2Stats Docs](https://docs.elembio.io/docs/cells2stats/setup/) — upstream tool documentation

## License

Use subject to the license available at [go.elembio.link/eula](https://go.elembio.link/eula).
