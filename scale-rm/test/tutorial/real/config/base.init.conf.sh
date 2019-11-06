#!/bin/bash

cat << EOF > base.init.conf

#################################################
#
# model configuration: init.conf only
#
#################################################

&PARAM_TIME
 TIME_STARTDATE = ${TIME_STARTDATE},
 TIME_STARTMS   = ${TIME_STARTMS},
/

&PARAM_COMM_CARTESC_NEST
 COMM_CARTESC_NEST_INTERP_LEVEL = 5,
 LATLON_CATALOGUE_FNAME = "${LATLON_CATALOGUE}",
 OFFLINE_PARENT_BASENAME = "${PARENT_BASENAME}",
 OFFLINE_PARENT_PRC_NUM_X = ${PARENT_PRC_NUM_X},
 OFFLINE_PARENT_PRC_NUM_Y = ${PARENT_PRC_NUM_Y},
/

&PARAM_RESTART
 RESTART_OUTPUT       = .true.,
 RESTART_OUT_BASENAME = "${INIT_RESTART_OUT_BASENAME}",
/

&PARAM_TOPO
 TOPO_IN_BASENAME = "${INIT_TOPO_IN_BASENAME}",
/

&PARAM_LANDUSE
 LANDUSE_IN_BASENAME  = "${INIT_LANDUSE_IN_BASENAME}",
/

&PARAM_LAND_PROPERTY
 LAND_PROPERTY_IN_FILENAME = "param.bucket.conf",
/

&PARAM_MKINIT
 MKINIT_initname = "REAL",
/

&PARAM_MKINIT_REAL_ATMOS
 NUMBER_OF_FILES      = ${NUMBER_OF_FILES},
 NUMBER_OF_TSTEPS     = ${NUMBER_OF_TSTEPS},
 FILETYPE_ORG         = "${FILETYPE_ORG}",
 BASENAME_ORG         = "${BASENAME_ORG}",
 BASENAME_BOUNDARY    = "${BASENAME_BOUNDARY}",
 BOUNDARY_UPDATE_DT   = ${TIME_DT_BOUNDARY},
 USE_FILE_DENSITY     = ${USE_FILE_DENSITY},
/

&PARAM_MKINIT_REAL_OCEAN
 NUMBER_OF_FILES      = ${NUMBER_OF_FILES},
 NUMBER_OF_TSTEPS     = ${NUMBER_OF_TSTEPS},
 FILETYPE_ORG         = "${FILETYPE_ORG}",
 BASENAME_ORG         = "${BASENAME_ORG}",
 BASENAME_BOUNDARY    = "${BASENAME_BOUNDARY}",
 BOUNDARY_UPDATE_DT   = ${TIME_DT_BOUNDARY},
 INTRP_OCEAN_SFC_TEMP = "mask",
 INTRP_OCEAN_TEMP     = "mask",
/

&PARAM_MKINIT_REAL_LAND
 NUMBER_OF_FILES      = ${NUMBER_OF_FILES},
 NUMBER_OF_TSTEPS     = ${NUMBER_OF_TSTEPS},
 FILETYPE_ORG         = "${FILETYPE_ORG}",
 BASENAME_ORG         = "${BASENAME_ORG}",
 BASENAME_BOUNDARY    = "${BASENAME_BOUNDARY}",
 BOUNDARY_UPDATE_DT   = ${TIME_DT_BOUNDARY},
 USE_FILE_LANDWATER   = ${USE_FILE_LANDWATER},
 INTRP_LAND_TEMP      = "fill",
 INTRP_LAND_WATER     = "fill",
 INTRP_LAND_SFC_TEMP  = "fill",
/

&PARAM_IO
 IO_LOG_BASENAME = "${INIT_IO_LOG_BASENAME}",
/

&PARAM_STATISTICS
 STATISTICS_checktotal     = .true.,
 STATISTICS_use_globalcomm = .true.,
/
EOF
