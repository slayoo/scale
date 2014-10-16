program nicam_trimmer
  !-----------------------------------------------------------------------------
  !> 2014/10/04: original (Ryuji Yoshida)
  !>
  !-----------------------------------------------------------------------------

  use netcdf
  use mod_netcdf

  use dc_log, only: &
     LogInit
  use scale_precision
  use scale_stdio
  use scale_const, only: &
     CONST_setup
  use scale_external_io, only: &
!     ExternalFileGetShape,     &
     ExternalFileRead,         &
     ExternalFileReadOffset
  use gtool_file, only: &
     FileGetShape,      &
     FileRead,          &
     FileCloseAll

  implicit none

  integer :: imax  = 2560
  integer :: jmax  = 1280
  integer :: kmax  = 40
  integer :: lkmax = 5
  integer :: tmax  = 5
  integer :: timelen
  integer :: dims(7)
  integer :: dummy(7)
  character(128) :: inputdir
  character(128) :: outputdir

  real(DP) :: start_lon =   0.0D0
  real(DP) :: start_lat = -90.0D0
  real(DP) :: end_lon   = 360.0D0
  real(DP) :: end_lat   =  90.0D0

  integer :: is = 1
  integer :: js = 1
  integer :: ie = 2560
  integer :: je = 1280

  real(DP), allocatable :: lon (:)
  real(DP), allocatable :: lat (:)
  real(DP), allocatable :: lev (:)
  real(DP), allocatable :: llev(:)
  real(DP), allocatable :: time(:)
  real(DP)              :: slev(2)

  real(DP), allocatable :: lon_trm(:)
  real(DP), allocatable :: lat_trm(:)
  real(SP), allocatable :: data_4d(:,:,:,:)
  real(SP), allocatable :: trimmed(:,:,:,:)

  real(DP),       parameter :: glevm5(1:6) = (/ 0.000, 0.050, 0.250, 1.000, 2.000, 4.000 /)
  integer,        parameter :: iNICAM  = 3
  character(128), parameter :: MODELNAME = "SCALE-LES ver. XXXX"

  integer :: i, j, k
  integer :: ii, jj
  !-----------------------------------------------------------------------------

  namelist /nicam_read/ imax,      &
                        jmax,      &
                        kmax,      &
                        lkmax,     &
                        tmax,      &
                        inputdir,  &
                        outputdir, &
                        start_lon, &
                        start_lat, &
                        end_lon,   &
                        end_lat

  !########## Initial setup ##########

  ! setup standard I/O
  call IO_setup( MODELNAME )

  ! setup Log
  call LogInit(IO_FID_CONF, IO_FID_LOG, IO_L)

  ! setup constants
  call CONST_setup

  open  ( 20, file="nicam_trimmer.conf", status='old', delim='apostrophe' )
  read  ( 20, nml=nicam_read )
  close ( 20 )
  lkmax = 5  ! fixed
  write ( *, * ) "IMAX  : ", imax
  write ( *, * ) "JMAX  : ", jmax
  write ( *, * ) "KMAX  : ", kmax
  write ( *, * ) "LKMAX : ", lkmax, " (fixed)"
  write ( *, * ) "TMAX  : ", tmax
  write ( *, * ) "DATA INPUT DIR  : ", trim(inputdir)
  write ( *, * ) "DATA OUTPUT DIR : ", trim(outputdir)
  write ( *, * ) "--------------------------------------------"
  write ( *, * ) " "

  dims(1) = imax
  dims(2) = jmax
  dims(3) = kmax
  dims(4) = lkmax
  dims(5) = tmax

  allocate( lon ( dims(1) ) )
  allocate( lat ( dims(2) ) )
  allocate( lev ( dims(3) ) )
  allocate( llev( dims(4) ) )
  allocate( time( dims(5) ) )

  ! preparing grid & set trimming area
  !call ExternalFileGetShape( dummy, timelen, iNICAM, trim(inputdir)//"/"//"ms_pres", 1, single=.true. )
  !call check_dimension( (/ dummy(1), dummy(2), dummy(3), timelen /), (/ dims(1),dims(2),dims(3),dims(4) /) )
  call nicamread_grid( lon, lat, lev, time, trim(inputdir)//"/"//"ms_pres" )
  do k = 1, dims(4)
     llev(k) = glevm5(k) + (glevm5(k+1) - glevm5(k))*0.5_RP
  enddo

  call trimming_latlon( is, js, ie, je, lon, lat,               &
                        start_lon, start_lat, end_lon, end_lat, &
                        (/ dims(1), dims(2) /)                  )

  dims(6) = ie - is + 1
  dims(7) = je - js + 1
  allocate( lon_trm ( dims(6) ) )
  allocate( lat_trm ( dims(7) ) )
  ii = 1
  do i = is, ie
     lon_trm(ii) = lon(i)
     ii = ii + 1
  enddo
  jj = 1
  do j = js, je
     lat_trm(jj) = lat(j)
     jj = jj + 1
  enddo

  deallocate( lon )
  deallocate( lat )
  allocate( data_4d( dims(1), dims(2), dims(3), dims(5) ) )
  allocate( trimmed( dims(6), dims(7), dims(3), dims(5) ) )

  !> pressure
  call nicamread_4D( data_4d, trim(inputdir)//"/"//"ms_pres", "ms_pres", &
                     (/ dims(1), dims(2), dims(3), dims(5) /), .false. )
  call trimming_4d( trimmed, data_4d, is, js, ie, je )
  call nicamwrite_4D( lon_trm, lat_trm, lev, time, trimmed, "ms_pres", &
                     (/ dims(6), dims(7), dims(3), dims(5) /), outputdir, .false. )

  !> temperature
  call nicamread_4D( data_4d, trim(inputdir)//"/"//"ms_tem", "ms_tem", &
                     (/ dims(1), dims(2), dims(3), dims(5) /), .true. )
  call trimming_4d( trimmed, data_4d, is, js, ie, je )
  call nicamwrite_4D( lon_trm, lat_trm, lev, time, trimmed, "ms_tem", &
                     (/ dims(6), dims(7), dims(3), dims(5) /), outputdir, .true. )

  !> zonal wind
  call nicamread_4D( data_4d, trim(inputdir)//"/"//"ms_u", "ms_u", &
                     (/ dims(1), dims(2), dims(3), dims(5) /), .true. )
  call trimming_4d( trimmed, data_4d, is, js, ie, je )
  call nicamwrite_4D( lon_trm, lat_trm, lev, time, trimmed, "ms_u", &
                     (/ dims(6), dims(7), dims(3), dims(5) /), outputdir, .true. )

  !> meridional wind
  call nicamread_4D( data_4d, trim(inputdir)//"/"//"ms_v", "ms_v", &
                     (/ dims(1), dims(2), dims(3), dims(5) /), .true. )
  call trimming_4d( trimmed, data_4d, is, js, ie, je )
  call nicamwrite_4D( lon_trm, lat_trm, lev, time, trimmed, "ms_v", &
                     (/ dims(6), dims(7), dims(3), dims(5) /), outputdir, .true. )

  !> mixing ratio of vapor
  call nicamread_4D( data_4d, trim(inputdir)//"/"//"ms_qv", "ms_qv", &
                     (/ dims(1), dims(2), dims(3), dims(5) /), .false. )
  call trimming_4d( trimmed, data_4d, is, js, ie, je )
  call nicamwrite_4D( lon_trm, lat_trm, lev, time, trimmed, "ms_qv", &
                     (/ dims(6), dims(7), dims(3), dims(5) /), outputdir, .false. )

  deallocate( data_4d )
  deallocate( trimmed )
  allocate( data_4d( dims(1), dims(2), dims(4), 1 ) )
  allocate( trimmed( dims(6), dims(7), dims(4), 1 ) )

  !> land temperature
  call nicamread_4D( data_4d, trim(inputdir)//"/"//"la_tg", "la_tg", &
                     (/ dims(1), dims(2), dims(4), 1 /), .true. )
  call trimming_4d( trimmed, data_4d, is, js, ie, je )
  call nicamwrite_4D( lon_trm, lat_trm, llev, time, trimmed, "la_tg", &
                     (/ dims(6), dims(7), dims(4), 1 /), outputdir, .true. )

  !> land water
  call nicamread_4D( data_4d, trim(inputdir)//"/"//"la_wg", "la_wg", &
                     (/ dims(1), dims(2), dims(4), 1 /), .true. )
  call trimming_4d( trimmed, data_4d, is, js, ie, je )
  call nicamwrite_4D( lon_trm, lat_trm, llev, time, trimmed, "la_wg", &
                     (/ dims(6), dims(7), dims(4), 1 /), outputdir, .true. )

  deallocate( data_4d )
  deallocate( trimmed )
  allocate( data_4d( dims(1), dims(2), 1, 1 ) )
  allocate( trimmed( dims(6), dims(7), 1, 1 ) )

  slev(:) = 0.0D0

  !> sea surface temperature
  call nicamread_4D( data_4d, trim(inputdir)//"/"//"oa_sst", "oa_sst", &
                     (/ dims(1), dims(2), 1, 1 /), .true. )
  call trimming_4d( trimmed, data_4d, is, js, ie, je )
  call nicamwrite_4D( lon_trm, lat_trm, slev, time, trimmed, "oa_sst", &
                     (/ dims(6), dims(7), 1, 1 /), outputdir, .true. )

  deallocate( data_4d )
  deallocate( trimmed )
  allocate( data_4d( dims(1), dims(2), 1, dims(5) ) )
  allocate( trimmed( dims(6), dims(7), 1, dims(5) ) )

  !> sea level pressure
  call nicamread_4D( data_4d, trim(inputdir)//"/"//"ss_slp", "ss_slp", &
                     (/ dims(1), dims(2), 1, dims(5) /), .true. )
  call trimming_4d( trimmed, data_4d, is, js, ie, je )
  call nicamwrite_4D( lon_trm, lat_trm, slev, time, trimmed, "ss_slp", &
                     (/ dims(6), dims(7), 1, dims(5) /), outputdir, .true. )

  !> surface temperature
  call nicamread_4D( data_4d, trim(inputdir)//"/"//"ss_tem_sfc", "ss_tem_sfc", &
                     (/ dims(1), dims(2), 1, dims(5) /), .false. )
  call trimming_4d( trimmed, data_4d, is, js, ie, je )
  call nicamwrite_4D( lon_trm, lat_trm, slev, time, trimmed, "ss_tem_sfc", &
                     (/ dims(6), dims(7), 1, dims(5) /), outputdir, .false. )

  slev(:) = 2.0D0

  !> temperature at 2m height
  call nicamread_4D( data_4d, trim(inputdir)//"/"//"ss_t2m", "ss_t2m", &
                     (/ dims(1), dims(2), 1, dims(5) /), .false. )
  call trimming_4d( trimmed, data_4d, is, js, ie, je )
  call nicamwrite_4D( lon_trm, lat_trm, slev, time, trimmed, "ss_t2m", &
                     (/ dims(6), dims(7), 1, dims(5) /), outputdir, .false. )

  !> mixing ratio of vapor at 2m height
  call nicamread_4D( data_4d, trim(inputdir)//"/"//"ss_q2m", "ss_q2m", &
                     (/ dims(1), dims(2), 1, dims(5) /), .false. )
  call trimming_4d( trimmed, data_4d, is, js, ie, je )
  call nicamwrite_4D( lon_trm, lat_trm, slev, time, trimmed, "ss_q2m", &
                     (/ dims(6), dims(7), 1, dims(5) /), outputdir, .false. )

  !> zonal wind at 10m
  call nicamread_4D( data_4d, trim(inputdir)//"/"//"ss_u10m", "ss_u10m", &
                     (/ dims(1), dims(2), 1, dims(5) /), .true. )
  call trimming_4d( trimmed, data_4d, is, js, ie, je )
  call nicamwrite_4D( lon_trm, lat_trm, slev, time, trimmed, "ss_u10m", &
                     (/ dims(6), dims(7), 1, dims(5) /), outputdir, .true. )

  !> meridional wind at 10m
  call nicamread_4D( data_4d, trim(inputdir)//"/"//"ss_v10m", "ss_v10m", &
                     (/ dims(1), dims(2), 1, dims(5) /), .true. )
  call trimming_4d( trimmed, data_4d, is, js, ie, je )
  call nicamwrite_4D( lon_trm, lat_trm, slev, time, trimmed, "ss_v10m", &
                     (/ dims(6), dims(7), 1, dims(5) /), outputdir, .true. )

  deallocate( data_4d )
  deallocate( trimmed )
  deallocate( lon_trm )
  deallocate( lat_trm )
  deallocate( lev     )
  deallocate( llev    )
  deallocate( time    )

  call FileCloseAll

  !-----------------------------------------------------------------------------
  !> END MAIN ROUTINE
  !-----------------------------------------------------------------------------
contains

  !-----------------------------------------------------------------------------
  !> Individual Procedures
  !-----------------------------------------------------------------------------

  !> read grid informations
  !---------------------------------------------------------------------------
  subroutine nicamread_grid( &
      lon,         & ! (out)
      lat,         & ! (out)
      lev,         & ! (out)
      time,        & ! (out)
      filename     ) ! (in)
    implicit none

    real(DP),         intent(out) :: lon(:)
    real(DP),         intent(out) :: lat(:)
    real(DP),         intent(out) :: lev(:)
    real(DP),         intent(out) :: time(:)
    character(LEN=*), intent(in)  :: filename
    !---------------------------------------------------------------------------

    call FileRead( lon(:),  trim(filename), "lon",  1, 1, single=.true. )
    call FileRead( lat(:),  trim(filename), "lat",  1, 1, single=.true. )
    call FileRead( lev(:),  trim(filename), "lev",  1, 1, single=.true. )
    call FileRead( time(:), trim(filename), "time", 1, 1, single=.true. )

    return
  end subroutine nicamread_grid


  !> read 4-dimension data
  !---------------------------------------------------------------------------
  subroutine nicamread_4D( &
      var,         & ! (out)
      filename,    & ! (in)
      varname,     & ! (in)
      dimens,      & ! (in)
      scoffset     ) ! (in)
    implicit none

    real(SP),         intent(out) :: var(:,:,:,:)
    character(LEN=*), intent(in)  :: filename
    character(LEN=*), intent(in)  :: varname
    integer,          intent(in)  :: dimens(:)  !1:x, 2:y, 3:z, 4:t
    logical,          intent(in)  :: scoffset

    integer :: i, j, k, t
    integer :: ts, te
    real(SP), allocatable :: read_4D(:,:,:,:)
    !---------------------------------------------------------------------------
    allocate( read_4d( dimens(3), dimens(1), dimens(2), dimens(4) ) )
    ts = 1
    te = dimens(4)

    write ( *, * ) " "
    write ( *, * ) "open file : ", trim(filename)
    if ( scoffset ) then
       call ExternalFileReadOffset( read_4d, trim(filename), trim(varname), ts, te, 1, iNICAM, single=.true. )
    else
       call ExternalFileRead( read_4d, trim(filename), trim(varname), ts, te, 1, iNICAM, single=.true. )
    endif

    do t=1, dimens(4)
    do j=1, dimens(2)
    do i=1, dimens(1)
    do k=1, dimens(3)
       var(i,j,k,t) = read_4d(k,i,j,t)
    enddo
    enddo
    enddo
    enddo

    write ( *, * ) "Input Value Range"
    write ( *, * ) "max: ", maxval(var(:,:,:,:)), "min: ", minval(var(:,:,:,:))
    write ( *, * ) "read_4d: ", maxval(read_4d(:,:,:,:)), "min: ", minval(read_4d(:,:,:,:))

    deallocate( read_4d )

    return
  end subroutine nicamread_4D


  !> write 4-dimension data
  !---------------------------------------------------------------------------
  subroutine nicamwrite_4D( &
      lon,         & ! (in)
      lat,         & ! (in)
      lev,         & ! (in)
      time,        & ! (in)
      var,         & ! (in)
      varname,     & ! (in)
      dimens,      & ! (in)
      outputdir,   & ! (in)
      scoffset     ) ! (in)
    implicit none

    real(DP),         intent(in) :: lon(:)
    real(DP),         intent(in) :: lat(:)
    real(DP),         intent(in) :: lev(:)
    real(DP),         intent(in) :: time(:)
    real(SP),         intent(in) :: var(:,:,:,:)
    character(LEN=*), intent(in) :: varname
    integer,          intent(in) :: dimens(:)  !1:x, 2:y, 3:z, 4:t
    character(LEN=*), intent(in) :: outputdir
    logical,          intent(in) :: scoffset

    integer,  parameter  :: iNICAM      = 3
    real(SP), parameter  :: CNST_UNDEF4 = -99.9E+33
    type(netcdf_handler) :: nc

    integer :: t
    !---------------------------------------------------------------------------

    call netcdf_open_for_write( &
       nc, &
       ncfile=trim(outputdir)//"/"//trim(varname)//'.nc', &
       count=(/  dimens(1), dimens(2), dimens(3), 1 /), &
       title='NICAM data output: TRIMMED', &
       imax=dimens(1), &
       jmax=dimens(2), &
       kmax=dimens(3), &
       tmax=dimens(4), &
       lon=lon, &
       lat=lat, &
       lev=lev, &
       time=time, &
       lev_units='m', &
       time_units='not available: see original file', &
       var_name=trim(varname), &
       var_desc='not available: see original file', &
       var_units='not available: see original file', &
       var_missing=CNST_UNDEF4 &
    )

    do t=1, dimens(4)
       call netcdf_write( nc, var(:,:,:,t), t=t )
    enddo

    call netcdf_close( nc )

    return
  end subroutine nicamwrite_4D


  !> search requested range
  !---------------------------------------------------------------------------
  subroutine trimming_latlon( &
      is,         & ! (out)
      js,         & ! (out)
      ie,         & ! (out)
      je,         & ! (out)
      lon,        & ! (in)
      lat,        & ! (in)
      start_lon,  & ! (in)
      start_lat,  & ! (in)
      end_lon,    & ! (in)
      end_lat,    & ! (in)
      dimens      ) ! (in)
    implicit none

    integer,  intent(out) :: is, js
    integer,  intent(out) :: ie, je
    real(DP), intent(in) :: lon(:)
    real(DP), intent(in) :: lat(:)
    real(DP), intent(in) :: start_lon, start_lat
    real(DP), intent(in) :: end_lon, end_lat
    integer,  intent(in)  :: dimens(:)  !1:x, 2:y

    integer :: i, j
    logical :: set_start, set_end
    !---------------------------------------------------------------------------

    !search range in longitude
    set_start = .true.
    set_end   = .true.
    do i=1, dimens(1)
       if ( set_start .and. lon(i) > start_lon ) then
          is = i - 1
          if ( is <= 0 ) is = 1
          set_start = .false.
       endif

       if ( set_end .and. lon(i) > end_lon ) then
          ie = i - 1
          set_end = .false.
       endif
    enddo

    !search range in latitude
    set_start = .true.
    set_end   = .true.
    do j=1, dimens(2)
       if ( set_start .and. lat(j) > start_lat ) then
          js = j - 1
          if ( js <= 0 ) js = 1
          set_start = .false.
       endif

       if ( set_end .and. lat(j) > end_lat ) then
          je = j - 1
          set_end = .false.
       endif
    enddo

    write ( *, * ) "Requested Longitude: ", start_lon, " - ", end_lon
    write ( *, * ) "  Trimmed Longitude: ", lon(is), " - ", lon(ie)
    write ( *, * ) "Requested Latitude : ", start_lat, " - ", end_lat
    write ( *, * ) "  Trimmed Latitude : ", lat(js), " - ", lat(je)

    return
  end subroutine trimming_latlon


  !> trimming 4-dimension data
  !---------------------------------------------------------------------------
  subroutine trimming_4d( &
      trm,      & ! (out)
      org,      & ! (in)
      is,       & ! (in)
      js,       & ! (in)
      ie,       & ! (in)
      je        ) ! (in)
    implicit none

    real(SP), intent(out) :: trm(:,:,:,:)
    real(SP), intent(in)  :: org(:,:,:,:)
    integer,  intent(in)  :: is, js
    integer,  intent(in)  :: ie, je

    integer :: i, ii, j, jj
    !---------------------------------------------------------------------------

    jj = 1
    do j = js, je
       ii = 1
       do i = is, ie
          trm(ii,jj,:,:) = org(i,j,:,:)
          ii = ii + 1
       enddo
       jj = jj + 1
    enddo

    write ( *, * ) "original data range: ",maxval(org), " - ", minval(org)
    write ( *, * ) "trimmed data range : ",maxval(trm), " - ", minval(trm)

    return
  end subroutine trimming_4d


  !> trimming 4-dimension data
  !---------------------------------------------------------------------------
  subroutine check_dimension( &
      nmlinput,     & ! (in)
      fromfile     ) ! (in)
    implicit none

    integer, intent(in) :: nmlinput(:)
    integer, intent(in) :: fromfile(:)
    !---------------------------------------------------------------------------

    if ( nmlinput(1) /= fromfile(1) ) then
       write ( *, * ) "### ERROR: dim size mismatch [ X-direction ]"
       write ( *, * ) "###          from namelist:", nmlinput(1)
       write ( *, * ) "###          from file:    ", fromfile(1)
       stop
    endif

    if ( nmlinput(2) /= fromfile(2) ) then
       write ( *, * ) "### ERROR: dim size mismatch [ Y-direction ]"
       write ( *, * ) "###          from namelist:", nmlinput(2)
       write ( *, * ) "###          from file:    ", fromfile(2)
       stop
    endif

    if ( nmlinput(3) /= fromfile(3) ) then
       write ( *, * ) "### ERROR: dim size mismatch [ Z-direction ]"
       write ( *, * ) "###          from namelist:", nmlinput(3)
       write ( *, * ) "###          from file:    ", fromfile(3)
       stop
    endif

    if ( nmlinput(4) /= fromfile(4) ) then
       write ( *, * ) "### WARNING: dim size mismatch [ Time-direction ]"
       write ( *, * ) "###          from namelist:", nmlinput(4)
       write ( *, * ) "###          from file:    ", fromfile(4)
    endif

    return
  end subroutine check_dimension

end program nicam_trimmer
