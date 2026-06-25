//
// CELLS2STATS: Generate cell-level statistics from spatial data
//

include { CELLS2STATS } from '../../../modules/elembio/cells2stats/main'

workflow CELLS2STATS_SUBWORKFLOW {

    take:
    ch_run_dir              // channel: [ [meta], run_dir ]
    ch_panel                // channel: panel file (optional)
    ch_run_manifest         // channel: run manifest file (optional)
    ch_segmentation         // channel: segmentation file (optional)
    ch_tca_manifest         // channel: TargetCellAssignmentManifest CSV (optional)

    main:

    ch_versions = Channel.empty()
    ch_multiqc_files = Channel.empty()

    // Run cells2stats process
    CELLS2STATS (
        ch_run_dir,
        ch_panel,
        ch_run_manifest,
        ch_segmentation,
        ch_tca_manifest
    )

    ch_versions = ch_versions.mix(CELLS2STATS.out.versions)

    emit:
    raw_cell_stats_parquet  = CELLS2STATS.out.raw_cell_stats_parquet       // channel: [ [meta], parquet ]
    raw_cell_stats_csv      = CELLS2STATS.out.raw_cell_stats_csv           // channel: [ [meta], csv ]
    run_stats_json          = CELLS2STATS.out.run_stats_json               // channel: [ [meta], json ]
    run_parameters_json     = CELLS2STATS.out.run_parameters_json          // channel: [ [meta], json ]
    panel_json              = CELLS2STATS.out.panel_json                   // channel: [ [meta], json ]
    run_manifest_json       = CELLS2STATS.out.run_manifest_json            // channel: [ [meta], json ]
    run_manifest_csv        = CELLS2STATS.out.run_manifest_csv             // channel: [ [meta], csv ]
    versions_json           = CELLS2STATS.out.versions_json                // channel: [ [meta], json ]
    wells_dir               = CELLS2STATS.out.wells_dir                    // channel: [ [meta], dir ]
    rawreads_files          = CELLS2STATS.out.rawreads_files               // channel: [ [meta], [files] ] per-tile rawreads parquets (glob-emit; group by (well,batch) downstream)
    cell_segmentation       = CELLS2STATS.out.cell_segmentation            // channel: [ [meta], dir ]
    analysis_region         = CELLS2STATS.out.analysis_region              // channel: [ [meta], dir ]
    program_logs            = CELLS2STATS.out.program_logs                 // channel: [ [meta], dir ]
    program_logs_tar        = CELLS2STATS.out.program_logs_tar             // channel: [ [meta], tar.gz ]
    spatial_data_dir        = CELLS2STATS.out.spatial_data_dir              // channel: [ [meta], dir ]
    spatial_data_zip        = CELLS2STATS.out.spatial_data_zip              // channel: [ [meta], zip ]
    spatial_data_zarr       = CELLS2STATS.out.spatial_data_zarr             // channel: [ [meta], zarr ]
    cyto_viz                = CELLS2STATS.out.cyto_viz                     // channel: [ [meta], viz ]
    viz_zip                 = CELLS2STATS.out.viz_zip                      // channel: [ [meta], zip ]
    viz_index_json_gz       = CELLS2STATS.out.viz_index_json_gz            // channel: [ [meta], json.gz ]
    target_cell_assignment_manifest_json = CELLS2STATS.out.target_cell_assignment_manifest_json // channel: [ [meta], json ]
    target_cell_assignment_manifest_csv  = CELLS2STATS.out.target_cell_assignment_manifest_csv  // channel: [ [meta], csv ]
    multiqc_report          = CELLS2STATS.out.multiqc_report               // channel: [ [meta], html ]
    metrics_dir             = CELLS2STATS.out.metrics_dir                  // channel: [ [meta], dir ] curated small-metadata (see module)
    versions                = ch_versions                                  // channel: versions.yml
}
