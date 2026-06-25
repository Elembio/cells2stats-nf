#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

// `params.run_dir` is required, but the strict checks happen inside `workflow {}`
// below so that `nextflow inspect` (which loads main.nf without params being set)
// can succeed during e.g. `nf-core modules update` container-config regeneration.
def run_dir = (params.run_dir ?: '').replaceAll(/\/$/, '')

// run_id extraction — keep in sync with bases2fastq-nf / elembio-tetonatlas-nf main.nf
def analysisRunMatch = (run_dir =~ /.*\/runs\/[^\/]+\/([^\/]+)\/analysis\/[^\/]+(?:\/|$)/)
def run_id = params.id ?: (analysisRunMatch ? analysisRunMatch[0][1] : (run_dir ? file(run_dir).name : 'unset'))

// Parse Panel.json to get batch -> AssayType mapping.
// Guarded on params.run_dir so `nextflow inspect` can load main.nf without panel
// staging; the workflow{} block re-validates run_dir presence before execution.
def batch_assay_map = [:]
if (params.run_dir) {
    def panel_json_path = params.c2s_panel_json ?: "${run_dir.replaceAll('/analysis/.*\$', '')}/Panel.json"
    def panel_json_file = file(panel_json_path, checkIfExists: true)
    def panel_json = new groovy.json.JsonSlurper().parse(panel_json_file)

    panel_json.DISSPrimerTubes?.each { tube ->
        if (tube.BatchName && tube.AssayType) {
            batch_assay_map[tube.BatchName] = tube.AssayType
        }
    }

    panel_json.BarcodingPrimerTubes?.each { tube ->
        if (tube.BatchName) {
            batch_assay_map[tube.BatchName] = "Barcoding"
        }
    }

    panel_json.ImagingPrimerTubes?.each { tube ->
        if (tube.BatchName) {
            batch_assay_map[tube.BatchName] = tube.Type ?: "Imaging"
        }
    }
}

// Nextflow unwraps single-element JSON arrays to a scalar; guard before list operations
def asList = { param -> param instanceof List ? param : (param ? [param] : []) }

// Parse assay type category lists for batch logging
def three_prime_types = asList(params.three_prime_types)
def specialized_types = asList(params.specialized_types)
def targeted_tx_types = asList(params.targeted_tx_types)

def batch_info_lines = batch_assay_map.collect { batch, assay_type ->
    def channel = "other"
    if (three_prime_types.contains(assay_type)) channel = "3prime"
    else if (specialized_types.contains(assay_type)) channel = "specialized"
    else if (targeted_tx_types.contains(assay_type)) channel = "targeted_tx"
    def marker = (channel == "other") ? "─" : "▸"
    "   ${marker} ${batch.padRight(5)} ${assay_type.padRight(30)} → ${channel}"
}.join('\n')

log.info """\
 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   C E L L S 2 S T A T S - N F
 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 ▸ Run Info
 ──────────────────────────────────────────────────────────────────────
   run_dir:  ${run_dir}
   run_id:   ${run_id}
   outdir:   ${params.outdir}

 ▸ Data Filtering
 ──────────────────────────────────────────────────────────────────────
   filter_batch: ${params.filter_batch ?: '*'}
   tile:         ${params.tile ? params.tile : '*'}
   c2s_well:     ${params.c2s_well ? params.c2s_well : '*'}

 ▸ Panel.json Batches
 ──────────────────────────────────────────────────────────────────────
${batch_info_lines}

 ▸ cells2stats (c2s)
 ──────────────────────────────────────────────────────────────────────
   container:           ${params.c2s_container_url}:${params.c2s_container_tag}
   c2s_run_manifest:    ${params.c2s_run_manifest ?: 'N/A'}
   c2s_panel_json:      ${params.c2s_panel_json ?: 'N/A'}
   c2s_tca_manifest:    ${params.c2s_tca_manifest_csv ?: 'N/A'}
   c2s_log_level:       ${params.c2s_log_level ?: 'info'}
   c2s_tar_program_logs: ${params.c2s_tar_program_logs}
   c2s_args:            ${params.c2s_args ? "${params.c2s_args} (deprecated; use ext.args in conf/modules.config)" : 'N/A'}

 ▸ Config
 ──────────────────────────────────────────────────────────────────────
   custom_config_version: ${params.custom_config_version}
   custom_config_base:    ${params.custom_config_base}
 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 """

// Import local modules
include { CELLS2STATS_SUBWORKFLOW } from './subworkflows/elembio/cells2stats/main'

// Build channels
def meta = [id: run_id]
ch_run_dir        = Channel.value([meta, run_dir])
ch_panel          = params.c2s_panel_json ? Channel.value(file(params.c2s_panel_json, checkIfExists: true)) : Channel.value([])
ch_run_manifest   = params.c2s_run_manifest ? Channel.value(file(params.c2s_run_manifest, checkIfExists: true)) : Channel.value([])
ch_segmentation   = params.segmentation_dir ? Channel.value(file(params.segmentation_dir, checkIfExists: true)) : Channel.value([])
ch_tca_manifest   = params.c2s_tca_manifest_csv ? Channel.value(file(params.c2s_tca_manifest_csv, checkIfExists: true)) : Channel.value([])

workflow {

    if (!params.run_dir) {
        exit 1, "ERROR: 'params.run_dir' must be set."
    }
    if (!file(params.run_dir).exists()) {
        exit 1, "ERROR: Specified 'params.run_dir' does not exist: ${params.run_dir}"
    }

    CELLS2STATS_SUBWORKFLOW (
        ch_run_dir,
        ch_panel,
        ch_run_manifest,
        ch_segmentation,
        ch_tca_manifest,
    )
}
