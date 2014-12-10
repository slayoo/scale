!-------------------------------------------------------------------------------
!> module User
!!
!! @par Description
!!      Put atmospheric data for urban test
!!      Test is based on Aoyagi et al. (2011,JAMC)
!!
!! @author Team SCALE
!<
!-------------------------------------------------------------------------------
module mod_user
  !-----------------------------------------------------------------------------
  !
  !++ used modules
  !
  use scale_precision
  use scale_stdio
  use scale_prof
  use scale_grid_index
  use scale_tracer
  !-----------------------------------------------------------------------------
  implicit none
  private
  !-----------------------------------------------------------------------------
  !
  !++ Public procedure
  !
  public :: USER_setup
  public :: USER_step

  !-----------------------------------------------------------------------------
  !
  !++ Public parameters & variables
  !
  !-----------------------------------------------------------------------------
  !
  !++ Private procedure
  !
  !-----------------------------------------------------------------------------
  !
  !++ Private parameters & variables
  !
  logical, private :: USER_do   = .false. !< do user step?

  !-----------------------------------------------------------------------------
contains
  !-----------------------------------------------------------------------------
  !> Setup
  subroutine USER_setup
    use scale_process, only: &
       PRC_MPIstop
    use mod_atmos_admin, only: &
       ATMOS_do,          &
       ATMOS_sw_dyn,      &
       ATMOS_sw_phy_mp,   &
       ATMOS_sw_phy_ae,   &
       ATMOS_sw_phy_ch,   &
       ATMOS_sw_phy_rd,   &
       ATMOS_sw_phy_sf,   &
       ATMOS_sw_phy_tb,   &
       ATMOS_sw_phy_cp
    implicit none

    namelist / PARAM_USER / &
       USER_do

    integer :: ierr
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '+++ Module[USER]/Categ[MAIN]'

    !--- read namelist
    rewind(IO_FID_CONF)
    read(IO_FID_CONF,nml=PARAM_USER,iostat=ierr)
    if( ierr < 0 ) then !--- missing
       if( IO_L ) write(IO_FID_LOG,*) '*** Not found namelist. Default used.'
    elseif( ierr > 0 ) then !--- fatal error
       write(*,*) 'xxx Not appropriate names in namelist PARAM_USER. Check!'
       call PRC_MPIstop
    endif
    if( IO_LNML ) write(IO_FID_LOG,nml=PARAM_USER)

    if( IO_L ) write(IO_FID_LOG,*)

    ! atmosphric model set to off
       ATMOS_do         = .false.
       ATMOS_sw_dyn     = .false.
       ATMOS_sw_phy_mp  = .false.
       ATMOS_sw_phy_ae  = .false.
       ATMOS_sw_phy_ch  = .false.
       ATMOS_sw_phy_rd  = .false.
       ATMOS_sw_phy_sf  = .false.
       ATMOS_sw_phy_tb  = .false.
       ATMOS_sw_phy_cp  = .false.

    return
  end subroutine USER_setup

  !-----------------------------------------------------------------------------
  !> Step
  subroutine USER_step
   use scale_const, only: &
       D2R   => CONST_D2R,   &
       TEM00 => CONST_TEM00, &
       LHV   => CONST_LHV,   &    ! ELL : latent heat of vaporization [J/kg]
       Rvap  => CONST_Rvap        !< gas constant (water vapor) [J/kg/K]
    use scale_grid_real, only: &
       REAL_lon
    use mod_cpl_vars, only: &
       RHOA  => CPL_fromAtm_ATM_DENS,    &
       UA    => CPL_fromAtm_ATM_U,       &
       VA    => CPL_fromAtm_ATM_V,       &
       WA    => CPL_fromAtm_ATM_W,       &
       TMPA  => CPL_fromAtm_ATM_TEMP,    &
       QVA   => CPL_fromAtm_ATM_QV,      &
       PRES  => CPL_fromAtm_SFC_PRES,    &
       PREC  => CPL_fromAtm_FLX_precip,  &
       LWD   => CPL_fromAtm_FLX_LW_dn,   &
       SWD   => CPL_fromAtm_FLX_SW_dn
    use scale_time, only:   &
       NOWSEC => TIME_NOWSEC,      & !< absolute sec
       dt_URB => TIME_DTSEC_URBAN, & !< time interval of urban step [sec]
       TIME_DOURBAN_step
    use scale_history, only: &
       HIST_in
    implicit none

    real(RP) :: WORK(IA,JA)
    real(RP) :: LON, LAT
    real(RP) :: dsec
    integer  :: tloc

    real(RP) :: ES
    real(RP) :: SW  (0:24)
    real(RP) :: PT  (0:24)
    real(RP) :: Wind(0:24)
    real(RP) :: Rain(0:24)
    real(RP) :: Qvapor(0:24) ! mixing ratio [kg/kg]


    data SW / 0.0, 0.0, 0.0, 0.0, 0.0, 11.0, 26.5, 161.5, 434.2, 694.6, 877.5, 807.4,     &
              907.4, 847.2, 725.2, 559.0, 357.9, 158.6, 14.7, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0/

    data PT / 296.6,296.6,296.7,296.5,296.4,296.3,295.9,296.1,296.7,298.0,299.2,300.0,     &
              300.6,301.7,302.2,302.4,302.0,301.1,300.5,299.8,299.1,298.9,298.6,298.3,296.6/

    data Wind / 3.4, 3.2, 3.2, 3.2, 3.2, 3.0, 3.8, 3.6, 3.5, 3.6, 4.0, 3.8,    &
                4.0, 3.9, 4.0, 4.1, 3.7, 3.6, 4.2, 3.9, 3.7, 3.4, 3.8, 4.0, 3.4/

    data Qvapor / 0.018,0.018,0.018,0.018,0.018,0.018,0.017,0.017,0.017,0.018,0.018,0.018,     &
                  0.018,0.017,0.017,0.016,0.017,0.018,0.018,0.017,0.018,0.018,0.018,0.018,0.018/

    data Rain / 0.0, 0.0, 0.0, 0.0, 0.1, 0.2, 3.0, 0.4, 0.0, 0.0, 0.0, 0.0,     &
                0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 /

    integer :: k, i, j
    !---------------------------------------------------------------------------

    if ( USER_do .AND. TIME_DOURBAN_step ) then

       VA  (:,:)  = 0.0_RP
       WA  (:,:)  = 0.0_RP
       RHOA(:,:)  = 1.13_RP
       LWD (:,:)  = 400.0_RP
       PRES(:,:)  = 101000.0_RP

       do j = 1, JA
       do i = 1, IA

          LON = REAL_lon(i,j) / D2R

          tloc = mod( int(NOWSEC/3600.0_RP)+int(LON/15.0_RP), 24 )

          dsec = mod(NOWSEC,3600.0_RP) / 3600.0_RP

          SWD (i,j) = ( ( 1.0_RP-dsec ) * SW(tloc  ) &
                      + (        dsec ) * SW(tloc+1) )

          TMPA(i,j) = ( ( 1.0_RP-dsec ) * PT(tloc  ) &
                      + (        dsec ) * PT(tloc+1) )

          UA  (i,j) = ( ( 1.0_RP-dsec ) * Wind(tloc  ) &
                      + (        dsec ) * Wind(tloc+1) )

          QVA (i,j) = ( ( 1.0_RP-dsec ) * Qvapor(tloc  ) &
                      + (        dsec ) * Qvapor(tloc+1) )
          QVA (i,j) = QVA(i,j)/(1.0_RP + QVA(i,j))

          PREC(i,j) = ( ( 1.0_RP-dsec ) * Rain(tloc  ) &
                      + (        dsec ) * Rain(tloc+1) )/3600.0_RP

!          if ( with_rain ) then
!             if (( tloc >= 1 ).and.( tloc < 10 )) then
!                PREC(i,j) = 5.0_RP / 3600.0_RP
!             endif
!                PREC(i,j) = 1.0_RP / 3600.0_RP
!          endif

       enddo
       enddo


       call HIST_in( TMPA (:,:), 'PT_urb',   'Air temperature',              'K'     )
       call HIST_in( QVA  (:,:), 'QA_urb',   'Specific humidity',            'kg/kg' )
       call HIST_in( UA   (:,:), 'UA_urb',   'Wind speed',                   'm/s'   )
       call HIST_in( SWD  (:,:), 'SWD_urb',  'Downward shortwave radiation', 'W/m2'  )
       call HIST_in( LWD  (:,:), 'LWD_urb',  'Downward longwave radiation',  'W/m2'  )

       WORK(:,:) = PREC(:,:) * dt_URB
       call HIST_in( WORK (:,:), 'RAIN_urb', 'Precipitation',                'kg/m2' )

    endif

    return
  end subroutine USER_step

end module mod_user
