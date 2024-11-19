#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

log.info """\
 =============================================
 C E L L S 2 S T A T S - N F   P I P E L I N E
 =============================================
 run_dir: ${params.run_dir}
 container_url: ${params.container_url}
 container_tag: ${params.container_tag}
 """

// Check mandatory parameters
if (!params.run_dir) {
    error "An input AVITI24 cytoprofiling result directory is required."
}

// Check if optional inputs were provided
def run_panel = params.panel ? params.panel : []
def run_manifest = params.run_manifest ? params.run_manifest : []
def segmentation = params.segmentation ? params.segmentation : []

// Import local modules
include { CELLS2STATS } from './modules/local/cells2stats'

workflow {
    CELLS2STATS (
        params.id,
        params.run_dir,
        run_panel,
        run_manifest,
        segmentation,
     )
}

