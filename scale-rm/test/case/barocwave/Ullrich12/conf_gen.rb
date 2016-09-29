#!/bin/env ruby

# Computatinal domain
# - Lx=40000 km, Ly=6000 km, Lz=30 km
#

require 'fileutils'

TIME_DT_SEC              = "720.0D0"
TIME_DURATION_SEC        = "1296000.D0"
HISTORY_TINTERVAL_HOUR   = "12.D0" #"24.D0"
TIME_DURATION_SEC_STEADY        = "86400.D0"
HISTORY_TINTERVAL_HOUR_STEADY   = "1.D0"
ATMOS_DYN_TYPE           = "FVM-HEVI"  # FVM-HEVE, FVM-HEVI
CONF_GEN_RESOL_HASHLIST  = \
[ \
  #-----------------------------
  # grid:100x30x30, dt=12 min
  { "TAG"=>"400km", "DX"=>400.0E3, "DY"=>400.0E3, "DZ"=>1000.0, \
    "KMAX"=>30, "IMAX"=>20, "JMAX"=>15, "DTDYN"=>720.0E0, "NPRCX"=> 5, "NPRCY"=>1}, \
  # grid:100x30x60, dt=12 min
  { "TAG"=>"400kmL60", "DX"=>400.0E3, "DY"=>400.0E3, "DZ"=>500.0, \
    "KMAX"=>60, "IMAX"=>20, "JMAX"=>15, "DTDYN"=>360.0E0, "NPRCX"=> 5, "NPRCY"=>1}, \
  #-----------------------------
  # grid:200x60x30, dt=6 min
  { "TAG"=>"200km", "DX"=>200.0E3, "DY"=>200.0E3, "DZ"=>1000.0, \
    "KMAX"=>30, "IMAX"=>20, "JMAX"=>15, "DTDYN"=>360.0E0, "NPRCX"=> 10, "NPRCY"=>2}, \
  # grid:200x60x60, dt=6 min
  { "TAG"=>"200kmL60", "DX"=>200.0E3, "DY"=>200.0E3, "DZ"=>500.0, \
    "KMAX"=>60, "IMAX"=>20, "JMAX"=>15, "DTDYN"=>180.0E0, "NPRCX"=> 10, "NPRCY"=>2}, \
  # grid:200x60x120, dt=6 min
  { "TAG"=>"200kmL120", "DX"=>200.0E3, "DY"=>200.0E3, "DZ"=>250.0, \
    "KMAX"=>120, "IMAX"=>20, "JMAX"=>15, "DTDYN"=>360.0E0, "NPRCX"=> 10, "NPRCY"=>2}, \
  #-----------------------------
  # grid:400x120x30, dt=3 min
  { "TAG"=>"100km", "DX"=>100.0E3, "DY"=>100.0E3, "DZ"=>1000.0, \
    "KMAX"=>30, "IMAX"=>20, "JMAX"=>30, "DTDYN"=>180.0E0, "NPRCX"=> 20, "NPRCY"=>2}, \
  # grid:400x120x60, dt=3 min
  { "TAG"=>"100kmL60", "DX"=>100.0E3, "DY"=>100.0E3, "DZ"=>500.0, \
    "KMAX"=>60, "IMAX"=>20, "JMAX"=>30, "DTDYN"=>90.0E0, "NPRCX"=> 20, "NPRCY"=>2}, \
  #-----------------------------
  # grid:800x240x30, dt=1.2 min
  { "TAG"=>"050km", "DX"=> 50.0E3, "DY"=> 50.0E3, "DZ"=>1000.0, \
    "KMAX"=>30, "IMAX"=>40, "JMAX"=>30, "DTDYN"=> 72.0E0, "NPRCX"=>20, "NPRCY"=>4}, \
  # grid:800x240x60, dt=1.2 min
  { "TAG"=>"050kmL60", "DX"=> 50.0E3, "DY"=> 50.0E3, "DZ"=>500.0, \
    "KMAX"=>60, "IMAX"=>40, "JMAX"=>30, "DTDYN"=> 72.0E0, "NPRCX"=>20, "NPRCY"=>4}, \
  #-----------------------------
  # grid:1600x480x30, dt=0.75 min
  { "TAG"=>"025km", "DX"=> 25.0E3, "DY"=> 25.0E3, "DZ"=>1000.0, \
    "KMAX"=>30, "IMAX"=>80, "JMAX"=>60, "DTDYN"=> 36.0E0, "NPRCX"=>20, "NPRCY"=>4}, \
  # grid:1600x480x60, dt=0.75 min
  { "TAG"=>"025kmL60", "DX"=> 25.0E3, "DY"=> 25.0E3, "DZ"=>500.0, \
    "KMAX"=>60, "IMAX"=>80, "JMAX"=>60, "DTDYN"=> 36.0E0, "NPRCX"=>20, "NPRCY"=>4}, \
]
CONF_GEN_CASE_HASH_LIST = \
[ \
  {"TAG"=>"CTRL"},
  {"TAG"=>"STEADY"},  \
]
CONF_GEN_NUMERIC_HASHLIST = \
[ \
  {"TAG"=>"FVM_CD2"}, {"TAG"=>"FVM_CD4"}, {"TAG"=>"FVM_CD6"},  \
  {"TAG"=>"FVM_UD1"}, {"TAG"=>"FVM_UD3"}, {"TAG"=>"FVM_UD5"},  \
]

# The maximum amplitude of zonal wind perturbation
Up = 1.0

#########################################################

def gen_init_conf( conf_name,
                   nprocx, nprocy, imax, jmax, kmax, dx, dy, dz, u0_p )

  f = File.open(conf_name, "w")
  f.print <<EOS
#####
#
# SCALE-RM mkinit configulation for baroclinic wave test in a channel
# (following experimental setup in Ullrich and Jablonowsski 2012)
#
#####

&PARAM_IO
 IO_LOG_BASENAME = 'init_LOG',
/

&PARAM_PRC
 PRC_NUM_X       = #{nprocx},  
 PRC_NUM_Y       = #{nprocy},
 PRC_PERIODIC_Y  = .false.,
/

&PARAM_INDEX
 KMAX = #{kmax}, 
 IMAX = #{imax}, IHALO = 3, 
 JMAX = #{jmax}, JHALO = 3,
/

&PARAM_GRID
 DZ =  #{dz}, 
 DX =  #{dx},  
 DY =  #{dy}, 
/

&PARAM_TIME
 TIME_STARTDATE             = 0000, 1, 1, 0, 0, 0,
 TIME_STARTMS               = 0.D0,
/

&PARAM_STATISTICS
 STATISTICS_checktotal     = .true.,
 STATISTICS_use_globalcomm = .true.,
/

&PARAM_TRACER
 TRACER_TYPE = 'DRY',
/

&PARAM_ATMOS_VARS
 ATMOS_RESTART_OUTPUT         = .true.,
 ATMOS_RESTART_OUT_BASENAME   = "init",
/

&PARAM_MKINIT
 MKINIT_initname = "BAROCWAVE",
/

&PARAM_MKINIT_BAROCWAVE
 REF_TEMP   = 288.D0,
 REF_PRES   = 1.D5,
 LAPSE_RATE = 5.D-3,
 Phi0Deg    = 45.D0,
 U0         = 35.D0,
 b          = 2.D0,
 Up         = #{u0_p},
/
EOS
  f.close
  
end

def gen_run_conf( conf_name,
                  nprocx, nprocy,
                  imax, jmax, kmax, dx, dy, dz, dtsec_dyn,
                  flxEvalType, fctFlag, dataDir, time_duration, hst_interval )


  f = File.open(conf_name, "w")
  f.print <<EOS
#####
#
# SCALE-RM run configulation for baroclinic wave test in a channel
# (following experimental setup in Ullrich and Jablonowsski 2012)
#
#####

&PARAM_PRC
 PRC_NUM_X       = #{nprocx},  
 PRC_NUM_Y       = #{nprocy},
 PRC_PERIODIC_Y  = .false.,
/

&PARAM_INDEX
 KMAX = #{kmax}, 
 IMAX = #{imax}, IHALO = 3, 
 JMAX = #{jmax}, JHALO = 3,
/

&PARAM_GRID
 DZ =  #{dz}, 
 DX =  #{dx},  
 DY =  #{dy}, 
 BUFFER_DZ = 5000.D0,  
 BUFFFACT  =   1.D0,
/
&PARAM_TIME
 TIME_STARTDATE             = 0000, 1, 1, 0, 0, 0,
 TIME_STARTMS               = 0.D0,
 TIME_DURATION              = #{time_duration},
 TIME_DURATION_UNIT         = "SEC",
 TIME_DT                    = #{dtsec_dyn}, !#{TIME_DT_SEC},
 TIME_DT_UNIT               = "SEC",
 TIME_DT_ATMOS_DYN          = #{dtsec_dyn}, 
 TIME_DT_ATMOS_DYN_UNIT     = "SEC",
/

&PARAM_STATISTICS
 STATISTICS_checktotal     = .false.,
 STATISTICS_use_globalcomm = .true.,
/

&PARAM_TRACER
 TRACER_TYPE = 'DRY',
/

&PARAM_ATMOS
 ATMOS_DYN_TYPE    = "#{ATMOS_DYN_TYPE}",
/

&PARAM_ATMOS_VARS
 ATMOS_RESTART_IN_BASENAME      = "init_00000101-000000.000",
 ATMOS_RESTART_OUTPUT           = .false.,
 ATMOS_VARS_CHECKRANGE          = .true.,
/

&PARAM_ATMOS_REFSTATE
! ATMOS_REFSTATE_IN_BASENAME = "REFSTATE", 
 ATMOS_REFSTATE_TYPE        = "INIT",
/

&PARAM_ATMOS_BOUNDARY
 ATMOS_BOUNDARY_TYPE       = "INIT",
 ATMOS_BOUNDARY_USE_VELX   = .true.,
 ATMOS_BOUNDARY_USE_VELY   = .true.,
 ATMOS_BOUNDARY_USE_VELZ   = .true.,
 ATMOS_BOUNDARY_TAUZ       = 900.D0,
/

&PARAM_ATMOS_DYN
 ATMOS_DYN_TINTEG_LARGE_TYPE    = "EULER",
 ATMOS_DYN_TINTEG_SHORT_TYPE    = "RK3WS2002",
 ATMOS_DYN_TINTEG_TRACER_TYPE   = "RK3WS2002",
 ATMOS_DYN_FVM_FLUX_TYPE        = "#{flxEvalType}",             
 ATMOS_DYN_FVM_FLUX_TRACER_TYPE = "#{flxEvalType}", 
 ATMOS_DYN_NUMERICAL_DIFF_COEF  = 0.D0,
 ATMOS_DYN_DIVDMP_COEF          = 0.D0,
 ATMOS_DYN_FLAG_FCT_TRACER      = #{fctFlag}, 
 ATMOS_DYN_ENABLE_CORIOLIS      = T
/

&PARAM_USER
 USER_do = .true., 
 Phi0Deg = 45.D0, 
/

&PARAM_HISTORY
 HISTORY_DEFAULT_BASENAME  = "history",
 HISTORY_DEFAULT_TINTERVAL = #{hst_interval},
 HISTORY_DEFAULT_TUNIT     = "HOUR",
 HISTORY_DEFAULT_TAVERAGE  = .false.,
 HISTORY_DEFAULT_DATATYPE  = "REAL4",
 HISTORY_DEFAULT_ZINTERP   = .true.,
 HISTORY_OUTPUT_STEP0      = .true.,
/

&HISTITEM item='U'    /
&HISTITEM item='V'    /
&HISTITEM item='W'    /
&HISTITEM item='VOR' /
&HISTITEM item='PT'   /
&HISTITEM item='PRES'   /
&HISTITEM item='T' /
&HISTITEM item='DENS'    /
!&HISTITEM item='MOMY'    /
!&HISTITEM item='RHOT'    /

!&HISTITEM item='DENS_t_advch'    /
!&HISTITEM item='DENS_t_advcv'    /
!&HISTITEM item='MOMZ_t_pg'    /
!&HISTITEM item='MOMZ_t_advch'    /
!&HISTITEM item='MOMZ_t_advcv'    /
!&HISTITEM item='MOMY_t_pg'    /
!&HISTITEM item='MOMY_t_cf'    /
!&HISTITEM item='MOMY_t_advch'    /
!&HISTITEM item='MOMY_t_advcv'    /

&PARAM_MONITOR
 MONITOR_STEP_INTERVAL = 30,
/

&MONITITEM item='QDRY' /
&MONITITEM item='QTOT' /
&MONITITEM item='ENGT' /
&MONITITEM item='ENGP' /
&MONITITEM item='ENGK' /
&MONITITEM item='ENGI' /
EOS
f.close
end

initParam_hash = {}
initParam_hash["STEADY"] = {"u0_p"=>0.0}
initParam_hash["CTRL"]   = {"u0_p"=>Up}

runParam_hash = {}
runParam_hash["STEADY"] = {"DURATION_SEC"=>TIME_DURATION_SEC_STEADY,
                           "HIST_TINTERVAL_HOUR"=>HISTORY_TINTERVAL_HOUR_STEADY }
runParam_hash["CTRL"] = {"DURATION_SEC"=>TIME_DURATION_SEC,
                         "HIST_TINTERVAL_HOUR"=>HISTORY_TINTERVAL_HOUR }

CONF_GEN_RESOL_HASHLIST.each{|resol_hash|
  CONF_GEN_CASE_HASH_LIST.each{|case_hash|
    CONF_GEN_NUMERIC_HASHLIST.each{|numeric_hash|

      initParam = initParam_hash[case_hash["TAG"]]
      
      ["F", "T"].each{|fct_flag|

        dataDir = "./#{resol_hash["TAG"]}/#{case_hash["TAG"]}/"
        dataDir += fct_flag=="T" ? "#{numeric_hash["TAG"]}_FCT/" : "#{numeric_hash["TAG"]}/"

        puts "Generate init.conf and run.conf (Dir=#{dataDir}) .."
        if !File.exists?(dataDir) then
          puts "Create directory .."
          FileUtils.mkdir_p(dataDir)
        end
      
        init_conf_name = "#{dataDir}init.conf" 
        gen_init_conf(init_conf_name, 
                      resol_hash["NPRCX"], resol_hash["NPRCY"], resol_hash["IMAX"], resol_hash["JMAX"], resol_hash["KMAX"], 
                      resol_hash["DX"], resol_hash["DY"], resol_hash["DZ"],  initParam["u0_p"] )

        runParam = runParam_hash[case_hash["TAG"]]
        run_conf_name = "#{dataDir}run.conf"
        gen_run_conf(run_conf_name, 
                     resol_hash["NPRCX"], resol_hash["NPRCY"], resol_hash["IMAX"], resol_hash["JMAX"], resol_hash["KMAX"], 
                     resol_hash["DX"], resol_hash["DY"], resol_hash["DZ"], resol_hash["DTDYN"], 
                     numeric_hash["TAG"].sub("FVM_",""), fct_flag, dataDir, runParam["DURATION_SEC"],
                     runParam["HIST_TINTERVAL_HOUR"] )
      }
    }
  }
}
