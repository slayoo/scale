!-------------------------------------------------------------------------------
!> Module Spectran Bin Microphysical Module in SCALE-LED ver. 3
!!
!! @par Description: 
!!      This module contains subroutines for the Spectral Bin Model
!!       
!! @author : Y.Sato of RIKEN, AICS
!!
!! @par History: Hbinw
!! @li  ver.0.00   2012-06-14 (Y.Sato) [new] Import from version 4.1 of original code
!! @li  ver.0.01   2012-09-14 (Y.Sato) [mod] add a stochastic method (Sato et al. 2009)
!! @li  ver.0.02   2012-10-18 (Y.Sato) [rev] extend to ice microphysics 
!<
!--------------------------------------------------------------------------------
!      Reference:  -- Journals 
!                   Suzuki et al.(2006): SOLA,vol.2,pp.116-119(original code)
!                   Suzuki et al.(2010): J.Atmos.Sci.,vol.67,pp.1126-1141
!                   Sato et al.  (2009): J.Geophys.Res.,vol.114,
!                                        doi:10.1029/2008JD011247
!-------------------------------------------------------------------------------
module mod_atmos_phy_mp
  !-----------------------------------------------------------------------------
  !
  !++ Used modules
  !
  use mod_stdio, only: &
     IO_FID_LOG,  &
     IO_L
  use mod_time, only: &
     TIME_rapstart, &
     TIME_rapend
  use mod_const, only: &
     pi => CONST_PI, &
     CONST_CPdry, &
     CONST_DWATR, &
     CONST_GRAV, &
     CONST_Rvap, &
     CONST_Rdry, &
     CONST_LH0, &
     CONST_LHS0, &
     CONST_EMELT, &
     CONST_TEM00, &
     CONST_TMELT, &
     CONST_PSAT0, &
     CONST_PRE00, &
     CONST_CPovCV, &
     CONST_RovCP
  !-----------------------------------------------------------------------------
  implicit none
  private
  !-----------------------------------------------------------------------------
  !
  !++ Public procedure
  !
  public :: ATMOS_PHY_MP_setup
  public :: ATMOS_PHY_MP

  !-----------------------------------------------------------------------------
  !
  !++ included parameters
  !
  include 'inc_precision.h'
  include 'inc_index.h'
  include 'inc_tracer.h'
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
  !++ Private parameters
  !
  !--- Indeces
  integer, parameter :: il = 1
  integer, parameter :: ic = 2
  integer, parameter :: ip = 3
  integer, parameter :: id = 4
  integer, parameter :: iss = 5
  integer, parameter :: ig = 6
  integer, parameter :: ih = 7

  !--- bin information of hydrometeors
  real(RP) :: xctr( nbin )         !--- log( m ) value of bin center 
  real(RP) :: xbnd( nbin+1 )       !--- log( m ) value of bin boundary
  real(RP) :: radc( nbin )         !--- radius of hydrometeor at bin center [m]
  real(RP) :: dxmic                !--- d( log(m) ) of hydrometeor bin
  real(RP) :: cctr( nspc,nbin )       !--- capacitance of hydrometeor at bin center
  real(RP) :: cbnd( nspc,nbin+1 )     !--- capacitance of hydrometeor at bin boundary
  real(RP) :: ck( nspc,nspc,nbin,nbin )  !-- collection kernel
  real(RP) :: vt( nspc,nbin )         !--- terminal velocity of hydrometeor [m/s]
  real(RP) :: br( nspc,nbin )         !--- bulk density of hydrometeor [kg/m^3] 
  integer  :: ifrsl( nspc,nspc )
  real(RP) :: sfc_precp( nspc ) 
  !--- constant for bin
  real(RP), parameter :: cldmin = 1.0E-10_RP, eps = 1.0E-30_RP
  real(RP), parameter :: OneovThird = 1.0_RP/3.0_RP, ThirdovForth = 3.0_RP/4.0_RP
  real(RP), parameter :: TwoovThird = 2.0_RP/3.0_RP
  logical :: flg_nucl=.false.              ! flag regeneration of aerosol
  logical :: flg_sf_aero =.false.          ! flag surface flux of aerosol
  integer, private, save :: rndm_flgp = 0  ! flag for sthastic integration for coll.-coag.
  logical, private, save :: doautoconversion = .true.
  logical, private, save :: doprecipitation  = .true.

  character(11),parameter :: fname_micpara="micpara.dat"
  integer(4) :: fid_micpara

  !--- Use for stochastic method
  integer, allocatable :: blrg( :,: ), bsml( :,: )
  real(RP) :: wgtbin
  integer  :: mspc = 49
  integer  :: mbin = nbin/2
  real(RP), private :: rndm(1,1,1)
  real(RP), private :: c_ccn = 100.E+6_RP
  real(RP), private :: kappa = 0.462_RP
  !-----------------------------------------------------------------------------
contains
  !-----------------------------------------------------------------------------
  !> Setup Cloud Microphysics
  !-----------------------------------------------------------------------------
  subroutine ATMOS_PHY_MP_setup
    use mod_stdio, only: &
      IO_get_available_fid, &
      IO_FID_CONF
    use mod_process, only: &
      PRC_MPIstop
    use mod_grid, only: &
      CDZ => GRID_CDZ, &
      CZ  => GRID_CZ,  &
      FZ  => GRID_FZ
    implicit none
    !---------------------------------------------------------------------------

    logical :: ATMOS_PHY_MP_FLAG_NUCLEAT !--- flag of regeneration
    integer :: ATMOS_PHY_MP_RNDM_FLGP  !--- flag of surface flux of aeorol
    integer :: ATMOS_PHY_MP_RNDM_MSPC  
    integer :: ATMOS_PHY_MP_RNDM_MBIN

    NAMELIST / PARAM_ATMOS_PHY_MP / &
       ATMOS_PHY_MP_FLAG_NUCLEAT, &
       ATMOS_PHY_MP_RNDM_FLGP, &
       ATMOS_PHY_MP_RNDM_MSPC, &
       ATMOS_PHY_MP_RNDM_MBIN, &
       doautoconversion, &
       doprecipitation,  &
       c_ccn, kappa

    integer :: nnspc, nnbin
    integer :: nn, mm, mmyu, nnyu
    integer :: myu, nyu, i, j, k, n, ierr

    ATMOS_PHY_MP_FLAG_NUCLEAT = flg_nucl
    ATMOS_PHY_MP_RNDM_FLGP = rndm_flgp
    ATMOS_PHY_MP_RNDM_MSPC = mspc
    ATMOS_PHY_MP_RNDM_MBIN = mbin

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '+++ Module[Cloud Microphisics]/Categ[ATMOS]'
    if( IO_L ) write(IO_FID_LOG,*) '*** Wrapper for SBM (mixed phase cloud)'

    rewind(IO_FID_CONF)
    read(IO_FID_CONF,nml=PARAM_ATMOS_PHY_MP,iostat=ierr)

    if( ierr < 0 ) then !--- missing
     if( IO_L ) write(IO_FID_LOG,*)  '*** Not found namelist. Default used.'
    elseif( ierr > 0 ) then !--- fatal error
     write(*,*) 'xxx Not appropriate names in namelist PARAM_ATMOS_PHY_MP, Check!'
     call PRC_MPIstop
    end if
    if( IO_L ) write(IO_FID_LOG,nml=PARAM_ATMOS_PHY_MP)

    flg_nucl = ATMOS_PHY_MP_FLAG_NUCLEAT
    rndm_flgp = ATMOS_PHY_MP_RNDM_FLGP
    mspc = ATMOS_PHY_MP_RNDM_MSPC 
    mbin = ATMOS_PHY_MP_RNDM_MBIN 

    fid_micpara = IO_get_available_fid()
    !--- open parameter of cloud microphysics
    open ( fid_micpara, file = fname_micpara, form = 'formatted', status = 'old' )

    read( fid_micpara,* ) nnspc, nnbin

    ! grid parameter
    if( IO_L ) write(IO_FID_LOG,*)  '*** Radius of cloud ****'
    do n = 1, nbin
      read( fid_micpara,* ) nn, xctr( n ), radc( n )
      if( IO_L ) write(IO_FID_LOG,'(a,1x,i3,1x,a,1x,e15.7,1x,a)')  "Radius of ", n, "th cloud bin (bin center)= ", radc( n ) , "[m]"
    end do
    do n = 1, nbin+1
      read( fid_micpara,* ) nn, xbnd( n )
    end do
    read( fid_micpara,* ) dxmic
    if( IO_L ) write(IO_FID_LOG,*)  '*** Width of Cloud SDF= ', dxmic

    ! capacity
    do myu = 1, nspc
     do n = 1, nbin
      read( fid_micpara,* ) mmyu, nn, cctr( myu,n )
     end do
     do n = 1, nbin+1
      read( fid_micpara,* ) mmyu, nn, cbnd( myu,n )
     end do
    end do

    ! collection kernel 
    do myu = 1, nspc
     do nyu = 1, nspc
      do i = 1, nbin
       do j = 1, nbin
        read( fid_micpara,* ) mmyu, nnyu, mm, nn, ck( myu,nyu,i,j )
       enddo
      enddo
     enddo
    enddo

    ! terminal velocity
    do myu = 1, nspc
     do n = 1, nbin
      read( fid_micpara,* ) mmyu, nn, vt( myu,n )
     enddo
    enddo

    ! bulk density
    do myu = 1, nspc
     do n = 1, nbin
      read( fid_micpara,* ) mmyu, nn, br( myu,n )
     enddo
    enddo

    close ( fid_micpara )

    !--- random number setup for stochastic method
    if( rndm_flgp > 0 ) then
     call random_setup( IA*JA*KA )
    endif
    sfc_precp( 1:nspc ) = 0.0_RP

    return
  end subroutine ATMOS_PHY_MP_setup

  !-----------------------------------------------------------------------------
  !> Cloud Microphysics
  !-----------------------------------------------------------------------------
  subroutine ATMOS_PHY_MP
    use mod_time, only: &
       TIME_DTSEC_ATMOS_PHY_MP, &
       TIME_NOWDAYSEC
    use mod_grid, only : &
       GRID_CZ,  &
       GRID_FZ,  &
       GRID_CDZ, &
       GRID_FDZ
    use mod_comm, only: &
       COMM_vars8, &
       COMM_wait
    use mod_atmos_vars, only: &
       ATMOS_vars_total,   &
       DENS, &
       MOMX, &
       MOMY, &
       MOMZ, &
       RHOT, &
       QTRC
    use mod_atmos_saturation, only : &
       pres2qsat_liq => ATMOS_SATURATION_pres2qsat_liq,   &
       pres2qsat_ice => ATMOS_SATURATION_pres2qsat_ice
    implicit none

    real(RP) :: dz (KA)
    real(RP) :: dzh(KA)
    real(RP) :: dt
    real(RP) :: ct

    real(RP) :: rho      (KA,IA,JA)
    real(RP) :: temp_mp  (KA,IA,JA)
    real(RP) :: pres_mp  (KA,IA,JA)
    real(RP) :: gdgc     (KA,IA,JA,nspc,nbin) !-- SDF of hydrometeors [kg/m^3/unit ln(r)]
    real(RP) :: qv_mp    (KA,IA,JA)      !-- Qv [kg/kg]
    real(RP) :: wfall( KA )  
    
    real(RP) :: ssliq, ssice, sum1, rtotal, sum2, sum3( nspc )
    integer :: m, n, k, i, j, iq, countbin

    real(RP) :: Uabs, bparam
    real(RP) :: tmp(KA)
    !---------------------------------------------------------------------------

#ifdef _FPCOLL_
call START_COLLECTION("MICROPHYSICS")
#endif

    if( IO_L ) write(IO_FID_LOG,*) '*** Physics step: Microphysics(SBM-liquid only)'

    call TIME_rapstart('MPX ijkconvert')
    dz (:) = GRID_CDZ(:)
    dzh(1) = GRID_FDZ(1)
    dzh(2:KA) = GRID_FDZ(1:KA-1)

    dt = TIME_DTSEC_ATMOS_PHY_MP
    ct = TIME_NOWDAYSEC

    gdgc(:,:,:,:,:) = 0.0_RP
    pres_mp(:,:,:) = 0.0_RP
    temp_mp(:,:,:) = 0.0_RP
    qv_mp(:,:,:) = 0.0_RP
    do j = JS-1, JE
    do i = IS-1, IE
       do k = KS, KE
          rtotal = CONST_Rdry*( 1.0_RP-QTRC(k,i,j,I_QV) ) + CONST_Rvap*QTRC(k,i,j,I_QV)
          pres_mp(k,i,j) = CONST_PRE00 * &
             ( RHOT(k,i,j) * rtotal / CONST_PRE00 )**CONST_CPovCV
          temp_mp(k,i,j) = &
                  pres_mp(k,i,j)/( DENS(k,i,j)*rtotal )
          qv_mp(k,i,j)   = QTRC(k,i,j,I_QV)
          countbin = 1
          do m = 1, nspc
          do n = 1, nbin
           gdgc( k,i,j,m,n ) = &
               QTRC(k,i,j,countbin+1)*DENS(k,i,j)/dxmic
           countbin = countbin + 1
          end do
          end do
       enddo
       do k = 1, KS-1
          rtotal = CONST_Rdry*( 1.0_RP-QTRC(KS,i,j,I_QV) ) + CONST_Rvap*QTRC(KS,i,j,I_QV)
          pres_mp(k,i,j) = CONST_PRE00 * &
             ( RHOT(KS,i,j) * rtotal / CONST_PRE00 )**CONST_CPovCV
          temp_mp(k,i,j) = &
                  pres_mp(k,i,j)/( DENS(KS,i,j)*rtotal )
          qv_mp(k,i,j)   = QTRC(KS,i,j,I_QV)
          countbin = 1
          do m = 1, nspc
          do n = 1, nbin
           gdgc( k,i,j,m,n ) = &
                QTRC(KS,i,j,countbin+1)*DENS(KS,i,j)/dxmic
           countbin = countbin + 1
          end do
          end do
       enddo
       do k = KE+1, KA
          rtotal = CONST_Rdry*( 1.0_RP-QTRC(KE,i,j,I_QV) ) + CONST_Rvap*QTRC(KE,i,j,I_QV)
          pres_mp(k,i,j) = CONST_PRE00 * &
             ( RHOT(KE,i,j) * rtotal / CONST_PRE00 )**CONST_CPovCV
          temp_mp( k,i,j ) = &
                  pres_mp(k,i,j)/( DENS(KE,i,j)*rtotal )
          qv_mp(k,i,j) = QTRC(KE,i,j,I_QV)
          countbin = 1
          do m = 1, nspc
          do n = 1, nbin
           gdgc( k,i,j,m,n ) = &
              QTRC(KE,i,j,countbin+1)*DENS(KE,i,j)/dxmic
           countbin = countbin + 1
          end do
          end do
       enddo
    enddo
    enddo

    call TIME_rapend  ('MPX ijkconvert')

    do k = KS, KE
    do j = JS, JE
    do i = IS, IE

      call pres2qsat_liq( ssliq,temp_mp(k,i,j),pres_mp(k,i,j) )
      call pres2qsat_ice( ssice,temp_mp(k,i,j),pres_mp(k,i,j) )
      ssliq = qv_mp(k,i,j)/ssliq-1.0_RP
      ssice = qv_mp(k,i,j)/ssice-1.0_RP
      sum1 = 0.0_RP
      do m = 1, nspc
      do n = 1, nbin
        sum1 = sum1 + gdgc(k,i,j,m,n)*dxmic
      end do
      end do

      if( ssliq > 0.0_RP .or. ssice > 0.0_RP .or. sum1 > cldmin ) then
       call mp_hbinf_evolve                    &
            ( pres_mp(k,i,j), DENS(k,i,j), dt, &  !--- in
              gdgc(k,i,j,1:nspc,1:nbin),       &  !--- inout
              qv_mp(k,i,j), temp_mp(k,i,j)     )  !--- inout
      end if
    
    end do
    end do
    end do

    !--- gravitational falling
    if( doprecipitation ) then
     do j = JS, JE
      do i = IS, IE
       sum3( : ) = 0.0_RP
       sum1 = 0.0_RP
       do k = KS, KE
        do m = 1, nspc
        do n = 1, nbin
         sum3( m ) = sum3( m ) + gdgc(k,i,j,m,n)*dxmic
         sum1 = sum1 + gdgc(k,i,j,m,n)*dxmic
        end do
        end do
       end do
       if( sum1 > cldmin ) then
        countbin = 1
        do m = 1, nspc
        if( sum3( m ) > 0.0_RP ) then
         do n = 1, nbin
          wfall( 1:KA ) = -vt( m,n )
          call  advec_1d             &
               ( dz, dzh,            & !--- in
                 wfall,              & !--- in
                 dt, m,              & !--- in
                 gdgc( 1:KA,i,j,m,n )  ) !--- inout
!          do k = KS, KE
!           if( gdgc(k,i,j,(m-1)*nbin+n) < 0.0_RP ) then
!            gdgc(k,i,j,(m-1)*nbin+n) = max( gdgc(k,i,j,(m-1)*nbin+n),0.0_RP ) 
!           end if
!          end do
         end do
        end if
        end do
       end if
      end do
     end do
    end if

    call TIME_rapstart('MPX ijkconvert')
    do j = JS, JE
     do i = IS, IE
       do k = KS, KE
          RHOT(k,i,j) = temp_mp(k,i,j)* &
            ( CONST_PRE00/pres_mp(k,i,j) )**( CONST_RovCP )*DENS(k,i,j)
          QTRC(k,i,j,I_QV) = qv_mp(k,i,j)  
          countbin = 1
          do m = 1, nspc
          do n = 1, nbin
            countbin = countbin+1
            QTRC(k,i,j,countbin) = gdgc(k,i,j,m,n)/DENS(k,i,j)*dxmic
            if( QTRC(k,i,j,countbin) <= eps ) then 
              QTRC(k,i,j,countbin) = 0.0_RP
            end if
          end do
          end do
       enddo
     enddo
    enddo

    call TIME_rapend  ('MPX ijkconvert')

    call COMM_vars8( DENS(:,:,:), 1 )
    call COMM_vars8( MOMZ(:,:,:), 2 )
    call COMM_vars8( MOMX(:,:,:), 3 )
    call COMM_vars8( MOMY(:,:,:), 4 )
    call COMM_vars8( RHOT(:,:,:), 5 )
    call COMM_wait ( DENS(:,:,:), 1 )
    call COMM_wait ( MOMZ(:,:,:), 2 )
    call COMM_wait ( MOMX(:,:,:), 3 )
    call COMM_wait ( MOMY(:,:,:), 4 )
    call COMM_wait ( RHOT(:,:,:), 5 )

    do iq = 1, QA
       call COMM_vars8( QTRC(:,:,:,iq), iq )
    enddo
    do iq = 1, QA
       call COMM_wait ( QTRC(:,:,:,iq), iq )
    enddo

#ifdef _FPCOLL_
call STOP_COLLECTION("MICROPHYSICS")
#endif

    call ATMOS_vars_total
    return
  end subroutine ATMOS_PHY_MP
  !-----------------------------------------------------------------------------
  subroutine getsups        &
       ( qvap, temp, pres,  & !--- in
         ssliq, ssice )       !--- out
  !
  real(RP), intent(in) :: qvap  !  specific humidity [ kg/kg ]
  real(RP), intent(in) :: temp  !  temperature [ K ]
  real(RP), intent(in) :: pres  !  pressure [ Pa ]
  !
  real(RP), intent(out) :: ssliq
  real(RP), intent(out) :: ssice
  !
  real(RP) :: epsl, rr, evap, esatl, esati
  !
  epsl = CONST_Rdry/CONST_Rvap
  !
  rr = qvap / ( 1.0_RP-qvap )
  evap = rr*pres/( epsl+rr )

  esatl = fesatl( temp )
  esati = fesati( temp )

  ssliq = evap/esatl - 1.0_RP
  ssice = evap/esati - 1.0_RP

  return

  end subroutine getsups
  !-----------------------------------------------------------------------------
  subroutine mp_hbinf_evolve        &
      ( pres, dens,                 & !--- in
        dtime,                      & !--- in
        gc,                         & !--- inout
        qvap, temp                  ) !--- inout

  use mod_const, only: &
     CONST_TEM00
  real(RP), intent(in) :: pres   !  pressure
  real(RP), intent(in) :: dens   !  density
  real(RP), intent(in) :: dtime  !  time interval

  real(RP), intent(inout) :: gc( nspc,nbin )
  real(RP), intent(inout) :: qvap  !  specific humidity
  real(RP), intent(inout) :: temp  !  temperature
  !
  !
  !--- nucleat
  call nucleat                  &
         ( dens, pres, dtime,   & !--- in
           gc(il,1:nbin), qvap, temp )   !--- inout

  !--- freezing / melting
  if ( temp < CONST_TEM00 ) then
    call freezing               &
           ( dtime, dens,       & !--- in
             gc, temp           ) !--- inout
    call ice_nucleat            &
           ( dtime, dens, pres, & !--- in
             gc, qvap, temp     ) !--- inout
  else
    call melting                &
           ( dtime, dens,       & !--- in
             gc, temp           ) !--- inout
  end if

  !--- condensation / evaporation
  call cndevpsbl                &
         ( dtime,               & !--- in
           dens, pres,          & !--- in
           gc, qvap, temp       ) !--- inout

  !--- collision-coagulation
  call  collmain                &
          ( temp, dtime,        & !--- in
            gc                  ) !--- inout

  return

  end subroutine mp_hbinf_evolve 
  !-----------------------------------------------------------------------------
  subroutine nucleat        &
      ( dens, pres, dtime,  & !--- in
        gc, qvap, temp      ) !--- inout
  use mod_const, only: &
     cp    => CONST_CPdry, &
     rhow  => CONST_DWATR, &
     qlevp => CONST_LH0, &
     rvap  => CONST_Rvap
  use mod_atmos_saturation, only : &
       pres2qsat_liq => ATMOS_SATURATION_pres2qsat_liq,   &
       pres2qsat_ice => ATMOS_SATURATION_pres2qsat_ice
  !
  !  liquid nucleation from aerosol particle
  !
  !
  real(RP), intent(in) :: dens   !  density  [ kg/m3 ]
  real(RP), intent(in) :: pres   !  pressure [ Pa ]
  real(RP), intent(in) :: dtime
  !
  real(RP), intent(inout) :: gc( nbin )  !  SDF ( hydrometeors )
  real(RP), intent(inout) :: qvap  !  specific humidity [ kg/kg ]
  real(RP), intent(inout) :: temp  !  temperature [ K ]
  !
  !--- local
  real(RP) :: ssliq, ssice, delcld
  real(RP) :: sumold, sumnew, acoef, bcoef, xcrit, rcrit
  real(RP) :: ractr, rcld, xcld, part, vdmp, dmp
  real(RP) :: sumnum, n_c, gcn( nbin )
  integer :: n, nc, ncrit
  integer, allocatable, save :: ncld( : )
  !
  !--- supersaturation
  call pres2qsat_liq( ssliq,temp,pres )
  call pres2qsat_ice( ssice,temp,pres )
  ssliq = qvap/ssliq-1.0_RP
  ssice = qvap/ssice-1.0_RP

  if ( ssliq <= 0.0_RP ) return
  !--- use for aerosol coupled model
  !--- mass -> number
  do n = 1, nbin
    gcn( n ) = gc( n )/exp( xctr( n ) )
  end do

  sumnum = 0.0_RP
  do n = 1, nbin
    sumnum = sumnum + gcn( n )*dxmic
  enddo
  n_c = c_ccn * ( ssliq * 1.E+2_RP )**( kappa )
  if( n_c > sumnum ) then
    dmp = ( n_c - sumnum ) * exp( xctr( 1 ) )
    dmp = min( dmp,qvap*dens )
    gc( 1 ) = gc( 1 ) + dmp/dxmic
    qvap = qvap - dmp/dens
    qvap = max( qvap,0.0_RP )
    temp = temp + dmp/dens*qlevp/cp
  end if

  !
  return
  !
  end subroutine nucleat
  !-----------------------------------------------------------------------------
  subroutine ice_nucleat        &
           ( dtime, dens, pres, & !--- in
             gc, qvap, temp     ) !--- inout
  !
  use mod_const, only : rhow  => CONST_DWATR, &
                        tmlt  => CONST_TMELT, &
                        qlmlt => CONST_EMELT, &
                        cp    => CONST_CPdry
  use mod_atmos_saturation, only : &
       pres2qsat_liq => ATMOS_SATURATION_pres2qsat_liq,   &
       pres2qsat_ice => ATMOS_SATURATION_pres2qsat_ice
  !
  real(RP), intent(in) :: dtime, dens, pres
  real(RP), intent(inout) :: gc( nspc,nbin ), temp, qvap
  !--- local variables
  real(RP) :: ssliq, ssice
  real(RP) :: numin, tdel, qdel
  real(RP), parameter :: n0 = 1.E+3_RP
  real(RP), parameter :: acoef = -0.639_RP, bcoef = 12.96_RP
  real(RP), parameter :: tcolmu = 269.0_RP, tcolml = 265.0_RP
  real(RP), parameter :: tdendu = 257.0_RP, tdendl = 255.0_RP
  real(RP), parameter :: tplatu = 250.6_RP
  !
  !--- supersaturation
  call pres2qsat_liq( ssliq,temp,pres )
  call pres2qsat_ice( ssice,temp,pres )
  ssliq = qvap/ssliq-1.0_RP
  ssice = qvap/ssice-1.0_RP

  if( ssice <= 0.0_RP ) return
 
  numin = bcoef * exp( acoef + bcoef * ssice )
  numin = numin * exp( xctr( 1 ) )/dxmic
  numin = min( numin,qvap*dens )
  !--- -4 [deg] > T >= -8 [deg] and T < -22.4 [deg] -> column
  if( temp <= tplatu .or. ( temp >= tcolml .and. temp < tcolmu ) ) then
   gc( ic,1 ) = gc( ic,1 ) + numin 
  !--- -14 [deg] > T >= -18 [deg] -> dendrite
  elseif( temp <= tdendu .and. temp >= tdendl ) then
   gc( id,1 ) = gc( id,1 ) + numin 
  !--- else -> plate
  else
   gc( ip,1 ) = gc( ip,1 ) + numin
  endif

  tdel = numin/dens*qlmlt/cp
  temp = temp + tdel
  qdel = numin/dens
  qvap = qvap - qdel

  return
  !
  end subroutine ice_nucleat
  !-----------------------------------------------------------------------------
  subroutine  freezing       &
      ( dtime, dens,  & !--- in
        gc, temp  )            !--- inout
  !
  use mod_const, only : rhow  => CONST_DWATR,  &
                        tmlt  => CONST_TMELT,  &
                        qlmlt => CONST_EMELT, &
                        cp    => CONST_CPdry
  !
  real(RP), intent(in) :: dtime, dens
  real(RP), intent(inout) :: gc( nspc,nbin ), temp
  !
  !--- local variables
  integer :: nbound, n
  real(RP) :: xbound, tc, rate, dmp, frz, sumfrz, tdel
  real(RP), parameter :: coefa = 1.0E-01_RP, coefb = 0.66_RP
  real(RP), parameter :: rbound = 2.0E-04_RP, tthreth = 235.0_RP
  real(RP), parameter :: ncoefim = 1.0E+7_RP, gamm = 3.3_RP
  !
  !
!  if( temp <= tthreth ) then !--- Bigg (1975)
   xbound = log( rhow * 4.0_RP*pi/3.0_RP * rbound**3 )
   nbound = int( ( xbound-xbnd( 1 ) )/dxmic ) + 1
 
   tc = temp-tmlt
   rate = coefa*exp( -coefb*tc )

   sumfrz = 0.0_RP
   do n = 1, nbin
     dmp = rate*exp( xctr( n ) )
     frz = gc( il,n )*( 1.0_RP-exp( -dmp*dtime ) )
 
     gc( il,n ) = gc( il,n ) - frz
     gc( il,n ) = max( gc( il,n ),0.0_RP )
 
     if ( n >= nbound ) then
       gc( ih,n ) = gc( ih,n ) + frz
     else
       gc( ip,n ) = gc( ip,n ) + frz
     end if

     sumfrz = sumfrz + frz
   end do
!  elseif( temp > tthreth ) then !--- Vali (1975)
!
!   tc = temp-tmlt
!   dmp = ncoefim * ( 0.1_RP * ( tmlt-temp )**gamm )
!   sumfrz = 0.0_RP
!   do n = 1, nbin
!    frz = gc( (il-1)*nbin+n )*dmp*xctr( n )/dens
!    frz = max( frz,gc( (il-1)*nbin+n )*dmp*xctr( n )/dens )
!    gc( (il-1)*nbin+n ) = gc( (il-1)*nbin+n ) - frz
!    if( n >= nbound ) then
!     gc( (ih-1)*nbin+n ) = gc( (ih-1)*nbin+n ) + frz
!    else
!     gc( (ip-1)*nbin+n ) = gc( (ip-1)*nbin+n ) + frz
!    end if
!
!    sumfrz = sumfrz + frz
!   end do
!  endif
  sumfrz = sumfrz*dxmic

  tdel = sumfrz/dens*qlmlt/cp
  temp = temp + tdel
  !
  return
  !
  end subroutine freezing
  !-----------------------------------------------------------------------------
  subroutine  melting  &
      ( dtime, dens,   & !--- in
        gc, temp       ) !--- inout
  !
  use mod_const, only : qlmlt => CONST_EMELT, &
                        cp    => CONST_CPdry
  !
  real(RP), intent(in) :: dtime, dens
  !
  real(RP), intent(inout) :: gc( nspc,nbin ), temp
  !
  !--- local variables
  integer :: n, m
  real(RP) :: summlt, sumice, tdel
  !
  !
  summlt = 0.0_RP
  do n = 1, nbin
   sumice = 0.0_RP
   do m = ic, ih
    sumice = sumice + gc( m,n )
    gc( m,n ) = 0.0_RP
   end do
   gc( il,n ) = gc( il,n ) + sumice
   summlt = summlt + sumice
  end do
  summlt = summlt*dxmic

  tdel = - summlt/dens*qlmlt/cp
  temp = temp + tdel
  !
  return
  !
  end subroutine melting
  !-----------------------------------------------------------------------------
  subroutine  cndevpsbl     &
      ( dtime,              & !--- in
        dens, pres,         & !--- in
        gc, qvap, temp       ) !--- inout
  !
  real(RP), intent(in) :: dtime
  real(RP), intent(in) :: dens   !  atmospheric density [ kg/m3 ]
  real(RP), intent(in) :: pres   !  atmospheric pressure [ Pa ]
  real(RP), intent(inout) :: gc( nspc,nbin )  ! Size Distribution Function
  real(RP), intent(inout) :: qvap    !  specific humidity [ kg/kg ]
  real(RP), intent(inout) :: temp    !  temperature [ K ]
  !
  !--- local variables
  integer :: iflg( nspc ), n, iliq, iice
  real(RP) :: csum( nspc )
  !
  !
  iflg( : ) = 0
  csum( : ) = 0.0_RP
  do n = 1, nbin
    csum( il ) = csum( il )+gc( il,n )*dxmic
    csum( ic ) = csum( ic )+gc( ic,n )*dxmic
    csum( ip ) = csum( ip )+gc( ip,n )*dxmic
    csum( id ) = csum( id )+gc( id,n )*dxmic
    csum( iss ) = csum( iss )+gc( iss,n )*dxmic
    csum( ig ) = csum( ig )+gc( ig,n )*dxmic
    csum( ih ) = csum( ih )+gc( ih,n )*dxmic
  end do

  if ( csum( il ) > cldmin ) iflg( il ) = 1
  if ( csum( ic ) > cldmin ) iflg( ic ) = 1
  if ( csum( ip ) > cldmin ) iflg( ip ) = 1
  if ( csum( id ) > cldmin ) iflg( id ) = 1
  if ( csum( iss ) > cldmin ) iflg( iss ) = 1
  if ( csum( ig ) > cldmin ) iflg( ig ) = 1
  if ( csum( ih ) > cldmin ) iflg( ih ) = 1

  iliq = iflg( il )
  iice = iflg( ic ) + iflg( ip ) + iflg( id ) &
       + iflg( iss ) + iflg( ig ) + iflg( ih )

  if ( iliq == 1 ) then
      call  liqphase            &
              ( dtime, iliq,    & !--- in
                dens, pres,     & !--- in
                gc(il,1:nbin), qvap, temp ) !--- inout
  elseif ( iliq == 0 .and. iice >= 1 ) then
      call  icephase            &
              ( dtime, iflg,    & !--- in
                dens, pres,     & !--- in
                gc, qvap, temp  ) !--- inout
  elseif ( iliq == 1 .and. iice >= 1 ) then
      call  mixphase            &
              ( dtime, iflg,    & !--- in
                dens, pres,     & !--- in
                gc, qvap, temp  ) !--- inout
  end if
  !
  end subroutine cndevpsbl
  !-----------------------------------------------------------------------------
  subroutine liqphase   &
      ( dtime, iflg,    & !--- in
        dens, pres,     & !--- in
        gc, qvap, temp  ) !--- inout
  use mod_const, only : rhow  => CONST_DWATR, &
                        qlevp => CONST_LH0, &
                        cp    => CONST_CPdry, &
                        rvap  => CONST_Rvap
  use mod_atmos_saturation, only : &
       pres2qsat_liq => ATMOS_SATURATION_pres2qsat_liq,   &
       pres2qsat_ice => ATMOS_SATURATION_pres2qsat_ice
  !
  real(RP), intent(in) :: dtime
  integer, intent(in) :: iflg
  real(RP), intent(in) :: dens, pres
  real(RP), intent(inout) :: gc( nbin ), qvap, temp
  !
  !--- local variables
  integer :: n, nloop, ncount
  real(RP) :: gclold, gclnew, gtliq, umax, dtcnd
  real(RP) :: sumliq, cefliq, a, sliqtnd, cndmss, ssliq, ssice
  real(RP) :: gcn( nbin ), gdu( nbin+1 ), gcnold( nbin )
  real(RP), parameter :: cflfct = 0.50_RP
  real(RP) :: old_sum_gcn, new_sum_gcn
  !
  gclold = 0.0_RP
  do n = 1, nbin
    gclold = gclold + gc( n )
  end do
  gclold = gclold * dxmic
  !
  !------- mass -> number
  gcn( 1:nbin ) = gc( 1:nbin ) / exp( xctr( 1:nbin ) )

  !
  !------- CFL condition
  call pres2qsat_liq( ssliq,temp,pres )
  call pres2qsat_ice( ssice,temp,pres )
  ssliq = qvap/ssliq-1.0_RP
  ssice = qvap/ssice-1.0_RP

  gtliq = gliq( pres,temp )
  umax = cbnd( il,1 )/exp( xbnd( 1 ) )*gtliq*abs( ssliq )
  dtcnd = cflfct*dxmic/umax
  nloop = int( dtime/dtcnd ) + 1
  dtcnd = dtime / nloop
  !
  ncount = 0
  !------- loop
  1000 continue

  !----- matrix for supersaturation tendency
  call pres2qsat_liq( ssliq,temp,pres )
  call pres2qsat_ice( ssice,temp,pres )
  ssliq = qvap/ssliq-1.0_RP
  ssice = qvap/ssice-1.0_RP

  gtliq = gliq( pres,temp )
  sumliq = 0.0_RP
  old_sum_gcn = 0.0_RP
  do n = 1, nbin
    sumliq = sumliq + gcn( n )*cctr( il,n )
  end do
  sumliq = sumliq * dxmic
  cefliq = ( ssliq+1.0_RP )*( 1.0_RP/qvap + qlevp*qlevp/cp/rvap/temp/temp )
  a = - cefliq*sumliq*gtliq/dens
  !
  !----- supersaturation tendency
  if ( abs( a*dtcnd ) >= 0.10_RP ) then
    sliqtnd = ssliq*( exp( a*dtcnd )-1.0_RP )/( a*dtcnd )
  else
    sliqtnd = ssliq
  end if
  !
  !----- change of SDF
  gdu( 1:nbin+1 ) = cbnd( il,1:nbin+1 )/exp( xbnd( 1:nbin+1 ) )*gtliq*sliqtnd
  gcnold( : ) = gcn( : )
  call  advection              &
          ( dtcnd,             & !--- in
            gdu( 1:nbin+1 ),   & !--- in
            gcn( 1:nbin )      ) !--- inout
  !
  !----- new mass
  gclnew = 0.0_RP
  new_sum_gcn = 0.0_RP
  do n = 1, nbin
    gclnew = gclnew + gcn( n )*exp( xctr( n ) )
    old_sum_gcn = old_sum_gcn + gcnold( n )*dxmic
    new_sum_gcn = new_sum_gcn + gcn( n )*dxmic
  end do
     
  gclnew = gclnew*dxmic
  !
  !----- change of humidity and temperature
  cndmss = gclnew - gclold
  qvap = qvap - cndmss/dens
  temp = temp + cndmss/dens*qlevp/cp
  !
  gclold = gclnew
  !
  !----- continue/end
  ncount = ncount + 1
  if ( ncount < nloop ) go to 1000
  !
  !------- number -> mass
  gc( 1:nbin ) = gcn( 1:nbin )*exp( xctr( 1:nbin ) )
  ! 
  end subroutine liqphase
  !-------------------------------------------------------------------------------
  subroutine icephase   &
      ( dtime, iflg,    & !--- in
        dens, pres,     & !--- in
        gc, qvap, temp  ) !--- inout
  !
  use mod_const, only : rhow   => CONST_DWATR,  &
                        qlevp  => CONST_LH0, &
                        qlsbl  => CONST_LHS0, &
                        rvap   => CONST_Rvap,  &
                        cp     => CONST_CPdry
  use mod_atmos_saturation, only : &
       pres2qsat_liq => ATMOS_SATURATION_pres2qsat_liq,   &
       pres2qsat_ice => ATMOS_SATURATION_pres2qsat_ice
  !
  real(RP), intent(in) :: dtime
  integer, intent(in) :: iflg( nspc )
  real(RP), intent(in) :: dens, pres
  real(RP), intent(inout) :: gc( nspc,nbin ), qvap, temp
  !
  !--- local variables
  integer :: myu, n, nloop, ncount
  real(RP) :: gciold, gtice, umax, uval, dtcnd
  real(RP) :: sumice, cefice, d, sicetnd, gcinew, sblmss, ssliq, ssice
  real(RP) :: gcn( nspc,nbin ), gdu( nbin+1 )
  real(RP), parameter :: cflfct = 0.50_RP
  real(RP) :: dumm_regene
  !
  !
  !----- old mass
  gciold = 0.0_RP
  do n = 1, nbin
  do myu = 2, nspc
    gciold = gciold + gc( myu,n )
  end do
  end do
  gciold = gciold*dxmic

  !----- mass -> number 
  do myu = 2, nspc
    gcn( myu,1:nbin ) = gc( myu,1:nbin )/exp( xctr( 1:nbin ) )
  end do

  !----- CFL condition
  call pres2qsat_liq( ssliq,temp,pres )
  call pres2qsat_ice( ssice,temp,pres )
  ssliq = qvap/ssliq-1.0_RP
  ssice = qvap/ssice-1.0_RP

  gtice = gice( pres,temp )
  umax = 0.0_RP
  do myu = 2, nspc
    uval = cbnd( myu,1 )/exp( xbnd( 1 ) )*gtice*abs( ssice )
    umax = max( umax,uval )
  end do

  dtcnd = cflfct*dxmic/umax
  nloop = int( dtime/dtcnd ) + 1
  dtcnd = dtime/nloop

!  ncount = 0
  !----- loop
!  1000 continue
  do ncount = 1, nloop
  !----- matrix for supersaturation tendency
  call pres2qsat_liq( ssliq,temp,pres )
  call pres2qsat_ice( ssice,temp,pres )
  ssliq = qvap/ssliq-1.0_RP
  ssice = qvap/ssice-1.0_RP

  gtice = gice( pres,temp )

  sumice = 0.0_RP
  do n = 1, nbin
    sumice = sumice + gcn( ic,n )*cctr( ic,n ) &
                    + gcn( ip,n )*cctr( ip,n ) &
                    + gcn( id,n )*cctr( id,n ) &
                    + gcn( iss,n )*cctr( iss,n ) &
                    + gcn( ig,n )*cctr( ig,n ) &
                    + gcn( ih,n )*cctr( ih,n )
  end do
  sumice = sumice*dxmic
  cefice = ( ssice+1.0_RP )*( 1.0_RP/qvap + qlsbl*qlsbl/cp/rvap/temp/temp )
  d = - cefice*sumice*gtice/dens

  !----- supersaturation tendency
  if ( abs( d*dtcnd ) >= 0.10_RP ) then
    sicetnd = ssice*( exp( d*dtcnd )-1.0_RP )/( d*dtcnd )
  else
    sicetnd = ssice
  end if
  !
  !----- change of SDF
  do myu = 2, nspc
    if ( iflg( myu ) == 1 ) then
      gdu( 1:nbin+1 ) = cbnd( myu,1:nbin+1 )/exp( xbnd( 1:nbin+1 ) )*gtice*sicetnd
      call  advection                                    &
              ( dtcnd, gdu( 1:nbin+1 ),                  & !--- in
                gcn( myu,1:nbin )                        ) !--- inout
    end if
  end do
  !
  !----- new mass
  gcinew = 0.0_RP
  do n = 1, nbin
  do myu = 2, nspc
    gcinew = gcinew + gcn( myu,n )*exp( xctr( n ) )
  end do
  end do
  gcinew = gcinew * dxmic
  !
  !----- change of humidity and temperature
  sblmss = gcinew - gciold
  qvap = qvap - sblmss/dens
  temp = temp + sblmss/dens*qlsbl/cp

  gciold = gcinew

  !
  !----- continue / end
  end do
!  ncount = ncount + 1
!  if ( ncount < nloop ) go to 1000
  !
  !------- number -> mass
  do myu = 2, nspc
    gc( myu,1:nbin ) = &
                  gcn( myu,1:nbin )*exp( xctr( 1:nbin ) )
  end do
  !
  end subroutine icephase
  !-------------------------------------------------------------------------------
  subroutine mixphase     &
      ( dtime, iflg,      & !--- in
        dens, pres,       & !--- in
        gc, qvap, temp    )!--- inout 
  !
  use mod_const, only : rhow   => CONST_DWATR,  &
                        qlevp  => CONST_LH0, &
                        qlsbl  => CONST_LHS0, &
                        rvap   => CONST_Rvap,  &
                        cp     => CONST_CPdry
  use mod_atmos_saturation, only : &
       pres2qsat_liq => ATMOS_SATURATION_pres2qsat_liq,   &
       pres2qsat_ice => ATMOS_SATURATION_pres2qsat_ice
  !
  real(RP), intent(in) :: dtime
  integer, intent(in) :: iflg( nspc )
  real(RP), intent(in) :: dens, pres
  !
  real(RP), intent(inout) :: gc( nspc,nbin )
  real(RP), intent(inout) :: qvap, temp
  !
  !--- local variables
  integer :: n, myu, nloop, ncount
  real(RP) :: gclold, gclnew, gciold, gcinew, cndmss, sblmss
  real(RP) :: gtliq, gtice, umax, uval, dtcnd
  real(RP) :: cef1, cef2, cef3, cef4, a, b, c, d
  real(RP) :: rmdplus, rmdmins, ssplus, ssmins, tplus, tmins
  real(RP) :: sliqtnd, sicetnd, ssliq, ssice, sumliq, sumice
  real(RP) :: gcn( nspc,nbin ), gdu( nbin+1 )
  real(RP), parameter :: cflfct = 0.50_RP
  real(RP) :: dumm_regene
  !
  !
  !----- old mass
  gclold = 0.0_RP
  do n = 1, nbin
    gclold = gclold + gc( il,n )
  end do
  gclold = gclold*dxmic

  gciold = 0.0_RP
  do n = 1, nbin
  do myu = 2, nspc
    gciold = gciold + gc( myu,n )
  end do
  end do
  gciold = gciold * dxmic

  !----- mass -> number
  do myu = 1, nspc
    gcn( myu,1:nbin ) = &
         gc( myu,1:nbin ) / exp( xctr( 1:nbin ) )
  end do

  !----- CFL condition
  call pres2qsat_liq( ssliq,temp,pres )
  call pres2qsat_ice( ssice,temp,pres )
  ssliq = qvap/ssliq-1.0_RP
  ssice = qvap/ssice-1.0_RP

  gtliq = gliq( pres,temp )
  gtice = gice( pres,temp )

  umax = cbnd( il,1 )/exp( xbnd( 1 ) )*gtliq*abs( ssliq )
  do myu = 2, nspc
    uval = cbnd( myu,1 )/exp( xbnd( 1 ) )*gtice*abs( ssice )
    umax = max( umax,uval )
  end do

  dtcnd = cflfct*dxmic/umax
  nloop = int( dtime/dtcnd ) + 1
  dtcnd = dtime/nloop

!  ncount = 0
  !----- loop
!  1000 continue
  do ncount = 1, nloop

  !-- matrix for supersaturation tendency
  call pres2qsat_liq( ssliq,temp,pres )
  call pres2qsat_ice( ssice,temp,pres )
  ssliq = qvap/ssliq-1.0_RP
  ssice = qvap/ssice-1.0_RP

  gtliq = gliq( pres,temp )
  gtice = gice( pres,temp )

  sumliq = 0.0_RP
  do n = 1, nbin
    sumliq = sumliq + gcn( il,n )*cctr( il,n )
  end do
  sumliq = sumliq*dxmic

  sumice = 0.0_RP
  do n = 1, nbin
    sumice = sumice + gcn( ic,n )*cctr( ic,n )  &
                    + gcn( ip,n )*cctr( ip,n )  &
                    + gcn( id,n )*cctr( id,n )  &
                    + gcn( iss,n )*cctr( iss,n )  &
                    + gcn( ig,n )*cctr( ig,n )  &
                    + gcn( ih,n )*cctr( ih,n )
  end do
  sumice = sumice*dxmic

  cef1 = ( ssliq+1.0_RP )*( 1.0_RP/qvap + qlevp/rvap/temp/temp*qlevp/cp )
  cef2 = ( ssliq+1.0_RP )*( 1.0_RP/qvap + qlevp/rvap/temp/temp*qlsbl/cp )
  cef3 = ( ssice+1.0_RP )*( 1.0_RP/qvap + qlsbl/rvap/temp/temp*qlevp/cp )
  cef4 = ( ssice+1.0_RP )*( 1.0_RP/qvap + qlsbl/rvap/temp/temp*qlsbl/cp )

  a = - cef1*sumliq*gtliq/dens
  b = - cef2*sumice*gtice/dens
  c = - cef3*sumliq*gtliq/dens
  d = - cef4*sumice*gtice/dens

  !--- eigenvalues
  rmdplus = ( ( a+d ) + sqrt( ( a-d )**2 + 4.0_RP*b*c ) ) * 0.50_RP
  rmdmins = ( ( a+d ) - sqrt( ( a-d )**2 + 4.0_RP*b*c ) ) * 0.50_RP

  !--- supersaturation tendency
  ssplus = ( ( rmdmins-a )*ssliq - b*ssice )/b/( rmdmins-rmdplus )
  ssmins = ( ( a-rmdplus )*ssliq + b*ssice )/b/( rmdmins-rmdplus )

  if ( abs( rmdplus*dtcnd ) >= 0.10_RP ) then
    tplus = ( exp( rmdplus*dtcnd )-1.0_RP )/( rmdplus*dtcnd )
  else
    tplus = 1.0_RP
  end if

  if ( abs( rmdmins*dtcnd ) >= 0.10_RP ) then
    tmins = ( exp( rmdmins*dtcnd )-1.0_RP )/( rmdmins*dtcnd )
  else
    tmins = 1.0_RP
  end if

  sliqtnd = b*tplus*ssplus + b*tmins*ssmins
  sicetnd = ( rmdplus-a )*tplus*ssplus  &
          + ( rmdmins-a )*tmins*ssmins

  !--- change of SDF
  !- liquid
  if ( iflg( il ) == 1 ) then
    gdu( 1:nbin+1 ) = cbnd( il,1:nbin+1 )/exp( xbnd( 1:nbin+1 ) )*gtliq*sliqtnd
    call  advection                                  &
            ( dtcnd, gdu( 1:nbin+1 ),                & !--- in
              gcn( il,1:nbin )                       ) !--- inout
  end if

  !- ice
  do myu = 2, nspc
    if ( iflg( myu ) == 1 ) then
      gdu( 1:nbin+1 ) = cbnd( myu,1:nbin+1 )/exp( xbnd( 1:nbin+1 ) )*gtice*sicetnd
      call  advection                                    &
              ( dtcnd, gdu( 1:nbin+1 ),                  & !--- in
                gcn( myu,1:nbin )                        ) !--- inout 
    end if
  end do

  !--- new mass
  gclnew = 0.0_RP
  do n = 1, nbin
    gclnew = gclnew + gcn( il,n )*exp( xctr( n ) )
  end do
  gclnew = gclnew*dxmic

  gcinew = 0.0_RP
  do n = 1, nbin
  do myu = 2, nspc
    gcinew = gcinew + gcn( myu,n )*exp( xctr( n ) )
  end do
  end do
  gcinew = gcinew*dxmic

  !--- change of humidity and temperature
  cndmss = gclnew - gclold
  sblmss = gcinew - gciold

  qvap = qvap - ( cndmss+sblmss )/dens
  temp = temp + ( cndmss*qlevp+sblmss*qlsbl )/dens/cp

  gclold = gclnew
  gciold = gcinew

  !--- continue/end
  end do
!  ncount = ncount + 1
!  if ( ncount < nloop ) go to 1000

  !----- number -> mass
  do myu = 1, nspc
    gc( myu,1:nbin ) = &
         gcn( myu,1:nbin )*exp( xctr( 1:nbin ) )
  end do

  end subroutine mixphase
  !-------------------------------------------------------------------------------
  subroutine advection  &
       ( dtime,         & !--- in
         gdu,           & !--- in
         gdq            ) !--- inout
  !
  real(RP), intent(in) :: dtime, gdu( 1:nbin+1 )
  real(RP), intent(inout) :: gdq( 1:nbin )
  !
  !--- local variables
  real(RP) :: delx 
  real(RP) :: qadv( -1:nbin+2 ), uadv( 0:nbin+2 )
  real(RP) :: flq( 1:nbin+1 )
  integer, parameter :: ldeg = 2
  real(RP), parameter :: epsl = 1.E-10_RP
  real(RP) :: acoef( 0:nbin+1,0:ldeg ), sum
  real(RP) :: crn( 0:nbin+2 )
  real(RP) :: aip( 0:nbin+1 ), aim( 0:nbin+1 ), ai( 0:nbin+1 )
  real(RP) :: cmins, cplus
  integer :: i, n
  !
  !
  delx = dxmic
  do i = 1, nbin
    qadv( i ) = gdq( i )
  end do
  qadv( -1 )     = 0.0_RP
  qadv( 0  )     = 0.0_RP
  qadv( nbin+1 ) = 0.0_RP
  qadv( nbin+2 ) = 0.0_Rp

  do i = 1, nbin+1
    uadv( i ) = gdu( i )
  end do
  uadv( 0  ) = 0.0_RP
  uadv( nbin+2 ) = 0.0_RP

  !--- flux
  do i = 0, nbin+1
    acoef( i,0 ) = - ( qadv( i+1 )-26.0_RP*qadv( i )+qadv( i-1 ) ) / 24.0_RP
    acoef( i,1 ) = ( qadv( i+1 )-qadv( i-1 ) ) * 0.50_RP
    acoef( i,2 ) = ( qadv( i+1 )-2.0_RP*qadv( i )+qadv( i-1 ) ) * 0.50_RP
  end do

  crn( 0:nbin+2 ) = uadv( 0:nbin+2 )*dtime/delx

  do i = 0, nbin+1
    cplus = ( crn( i+1 ) + abs( crn( i+1 ) ) ) * 0.50_RP
    sum = 0.0_RP
    do n = 0, ldeg
      sum = sum + acoef( i,n )/( n+1 )/2.0_RP**( n+1 )  &
                *( 1.0_RP-( 1.0_RP-2.0_RP*cplus )**( n+1 ) )
    end do
    aip( i ) = max( sum,0.0_RP )
  end do

  do i = 0, nbin+1
    cmins = - ( crn( i ) - abs( crn( i ) ) ) * 0.50_RP
    sum = 0.0_RP
    do n = 0, ldeg
      sum = sum + acoef( i,n )/( n+1 )/2.0_RP**( n+1 ) * (-1)**n &
                *( 1.0_RP-( 1.0_RP-2.0_RP*cmins )**( n+1 ) )
    end do
    aim( i ) = max( sum,0.0_RP )
  end do

  do i = 0, nbin+1
    sum = 0.0_RP
    do n = 0, ldeg
      sum = sum + acoef( i,n )/( n+1 )/2.0_RP**( n+1 ) * ( (-1)**n+1 )
    end do
    ai( i ) = max( sum,aip( i )+aim( i )+epsl )
  end do

  do i = 1, nbin+1
    flq( i ) = ( aip( i-1 )/ai( i-1 )*qadv( i-1 )  &
                -aim( i   )/ai( i   )*qadv( i   ) )*delx/dtime
  end do

  do i = 1, nbin
    gdq( i ) = gdq( i ) - ( flq( i+1 )-flq( i ) )*dtime/delx
  end do

  end subroutine advection
  !-------------------------------------------------------------------------------
  function  gliq( pres,temp )
  !
  use mod_const, only : rair  => CONST_Rdry,  &
                        rvap  => CONST_Rvap,  &
                        qlevp => CONST_LH0
  !
  real(RP), intent(in) :: pres, temp
  real(RP) :: gliq
  !
  real(RP) :: emu, dens, cefd, cefk, f1, f2
  real(RP), parameter :: fct = 1.4E+3_RP
  !
  emu = fmyu( temp )
  dens = pres/rair/temp
  cefd = emu/dens
  cefk = fct*emu

  f1 = rvap*temp/fesatl( temp )/cefd
  f2 = qlevp/cefk/temp*( qlevp/rvap/temp - 1.0_RP )

  gliq = 4.0_RP*pi/( f1+f2 )

  end function gliq
  !-------------------------------------------------------------------------------
  function gice ( pres, temp )
  !
  use mod_const, only : rair  => CONST_Rdry,  &
                        rvap  => CONST_Rvap,  &
                        qlsbl => CONST_LHS0
  !
  real(RP), intent(in) :: pres, temp
  real(RP) :: gice
  !
  real(RP) :: emu, dens, cefd, cefk, f1, f2
  real(RP), parameter :: fct = 1.4E+3_RP
  !
  emu = fmyu( temp )
  dens = pres/rair/temp
  cefd = emu/dens
  cefk = fct*emu

  f1 = rvap*temp/fesati( temp )/cefd
  f2 = qlsbl/cefk/temp*( qlsbl/rvap/temp - 1.0_RP )

  gice = 4.0_RP*pi/( f1+f2 )

  end function gice
  !------------------------------------------------------------------------
  function fmyu( temp )
  !
  !
  real(RP), intent(in) :: temp
  real(RP) :: fmyu
  real(RP), parameter :: tmlt = CONST_TMELT
  !
  real(RP), parameter :: a = 1.72E-05_RP, b = 3.93E+2_RP, c = 1.2E+02_RP
  !
  fmyu = a*( b/( temp+c ) )*( temp/tmlt )**1.50_RP
  !
  end function fmyu
  !-------------------------------------------------------------------------------
  function fesatl( temp )
  !
  real(RP), intent(in) :: temp
  real(RP) :: fesatl
  !
  real(RP), parameter :: qlevp = CONST_LH0
  real(RP), parameter :: rvap  = CONST_Rvap
  real(RP), parameter :: esat0 = CONST_PSAT0
  real(RP), parameter :: temp0 = CONST_TEM00
  !
  fesatl = esat0*exp( qlevp/rvap*( 1.0_RP/temp0 - 1.0_RP/temp ) )
  !
  return

  end function fesatl
  !-----------------------------------------------------------------------
  function fesati( temp )
  !
  real(RP), intent(in) :: temp
  real(RP) :: fesati
  !
  real(RP), parameter :: qlsbl = CONST_LHS0
  real(RP), parameter :: rvap  = CONST_Rvap
  real(RP), parameter :: esat0 = CONST_PSAT0
  real(RP), parameter :: temp0 = CONST_TEM00
  !
  fesati = esat0*exp( qlsbl/rvap*( 1.0_RP/temp0 - 1.0_RP/temp ) )
  !
  return

  end function fesati
  !-------------------------------------------------------------------------------
 subroutine collmain &
      ( temp, dtime, & !--- in
        gc           ) !--- inout

  use mod_process, only: &
     PRC_MPIstop
  !
  real(RP), intent(in) :: dtime, temp
  real(RP), intent(inout) :: gc( nspc,nbin )
  !
  !--- local variables
  integer :: iflg( nspc ), n, irsl, ilrg, isml
  real(RP) :: csum( nspc )
  real(RP), parameter :: tcrit = 271.15_RP
  !
  !--- judgement of particle existence
    iflg( : ) = 0
    csum( : ) = 0.0_RP
    do n = 1, nbin
      csum( il ) = csum( il ) + gc( il,n )*dxmic
      csum( ic ) = csum( ic ) + gc( ic,n )*dxmic
      csum( ip ) = csum( ip ) + gc( ip,n )*dxmic
      csum( id ) = csum( id ) + gc( id,n )*dxmic
      csum( iss ) = csum( iss ) + gc( iss,n )*dxmic
      csum( ig ) = csum( ig ) + gc( ig,n )*dxmic
      csum( ih ) = csum( ih ) + gc( ih,n )*dxmic
    end do
    if ( csum( il ) > cldmin ) iflg( il ) = 1
    if ( csum( ic ) > cldmin ) iflg( ic ) = 1
    if ( csum( ip ) > cldmin ) iflg( ip ) = 1
    if ( csum( id ) > cldmin ) iflg( id ) = 1
    if ( csum( iss ) > cldmin ) iflg( iss ) = 1
    if ( csum( ig ) > cldmin ) iflg( ig ) = 1
    if ( csum( ih ) > cldmin ) iflg( ih ) = 1
  !
  !--- rule of interaction
    call  getrule    &
            ( temp,  & !--- in
              ifrsl  ) !--- out
  !
  !--- interaction
  do isml = 1, nspc
   if ( iflg( isml ) == 1 ) then
    do ilrg = 1, nspc
     if ( iflg( ilrg ) == 1 ) then
      irsl = ifrsl( isml, ilrg )
      if ( rndm_flgp == 1 ) then  !--- stochastic method
        call r_collcoag         &
            ( isml, ilrg, irsl, & !--- in
              dtime,  wgtbin,   & !--- in
              gc                ) !--- inout
      else  !--- default method
        call  collcoag          &
            ( isml, ilrg, irsl, & !--- in
              dtime,            & !--- in
              gc                ) !--- inout

      end if
     end if
    end do
   end if
  end do
  !
  !
  return
  !
  end subroutine collmain
  !-------------------------------------------------------------------------------
  subroutine  collcoag( isml,ilrg,irsl,dtime,gc )
  !------------------------------------------------------------------------------
  !--- reference paper
  !    Bott et al. (1998) J. Atmos. Sci. vol.55, pp. 2284-
  !------------------------------------------------------------------------------
  !
  integer,  intent(in) :: isml, ilrg, irsl
  real(RP), intent(in) :: dtime
  real(RP), intent(inout) :: gc( nspc,nbin )
  !
  !--- local variables
  integer :: i, j, k, l
  real(RP) :: xi, xj, xnew, dmpi, dmpj, frci, frcj
  real(RP) :: gprime, gprimk, wgt, crn, sum, flux
  integer, parameter :: ldeg = 2
  real(RP) :: acoef( 0:ldeg )
  real(RP), parameter :: dmpmin = 1.E-01_RP
  real(RP) :: suri, surj
  !
  small : do i = 1, nbin-1
    if ( gc( isml,i ) <= cldmin ) cycle small
  large : do j = i+1, nbin
    if ( gc( ilrg,j ) <= cldmin ) cycle large

    xi = exp( xctr( i ) )
    xj = exp( xctr( j ) )
    xnew = log( xi+xj )
    k = int( ( xnew-xctr( 1 ) )/dxmic ) + 1
    k = max( max( k,j ),i )
    if ( k >= nbin ) cycle small

    dmpi = ck( isml,ilrg,i,j )*gc( ilrg,j )/xj*dxmic*dtime
    dmpj = ck( ilrg,isml,i,j )*gc( isml,i )/xi*dxmic*dtime

    if ( dmpi <= dmpmin ) then
      frci = gc( isml,i )*dmpi
    else
      frci = gc( isml,i )*( 1.0_RP-exp( -dmpi ) )
    end if

    if ( dmpj <= dmpmin ) then
      frcj = gc( ilrg,j )*dmpj
    else
      frcj = gc( ilrg,j )*( 1.0_RP-exp( -dmpj ) )
    end if

    gprime = frci+frcj
    if ( gprime <= 0.0_RP ) cycle large

    suri = gc( isml,i )
    surj = gc( ilrg,j )
    gc( isml,i ) = gc( isml,i )-frci
    gc( ilrg,j ) = gc( ilrg,j )-frcj
    gc( isml,i ) = max( gc( isml,i )-frci, 0.0_RP )
    gc( ilrg,j ) = max( gc( ilrg,j )-frcj, 0.0_RP )
    frci = suri - gc( isml,i )
    frcj = surj - gc( ilrg,j )
    gprime = frci+frcj

    gprimk = gc( irsl,k ) + gprime
    wgt = gprime / gprimk
    crn = ( xnew-xctr( k ) )/( xctr( k+1 )-xctr( k ) )

    acoef( 0 ) = -( gc( irsl,k+1 )-26.0_RP*gprimk+gc( irsl,k-1 ) )/24.0_RP
    acoef( 1 ) =  ( gc( irsl,k+1 )-gc( irsl,k-1 ) ) *0.50_RP
    acoef( 2 ) =  ( gc( irsl,k+1 )-2.0_RP*gprimk+gc( irsl,k-1 ) ) *0.50_RP

    sum = 0.0_RP
    do l = 0, ldeg
      sum = sum + acoef( l )/( l+1 )/2.0_RP**( l+1 )   &
                *( 1.0_RP-( 1.0_RP-2.0_RP*crn )**( l+1 ) )
    end do

    flux = wgt*sum
    flux = min( max( flux,0.0_RP ),gprime )

    gc( irsl,k ) = gprimk - flux
    gc( irsl,k+1 ) = gc( irsl,k+1 ) + flux

  end do large
  end do small
  !  
  return
  !
  end subroutine collcoag
  !-------------------------------------------------------------------------------
  subroutine  advec_1d     &
      ( delxa, delxb,      & !--- in
        gdu,               & !--- in
        dtime, spc,        & !--- in
        gdq              )   !--- inout

  real(RP), intent(in) :: delxa( KA ), delxb( KA )
  real(RP), intent(in) :: gdu( KA )
  real(RP), intent(in) :: dtime
  integer, intent(in)  :: spc
  real(RP), intent(inout) :: gdq( KA )

  !--- local
  integer :: i
  real(RP) :: fq( KS:KE+1 )
  real(RP) :: dqr, dql, dq, qstar
  !
  !
  !--- reset of fluxes
  fq( : ) = 0.0_RP

  !--- tracer flux
  !--- terminal velocity is always negative
  do i = KS, KE
      dqr = ( gdq( i+1 )-gdq( i   ) )/delxb( i )
      dql = ( gdq( i   )-gdq( i-1 ) )/delxb( i-1 )
      if ( dqr*dql > 0.0_RP ) then
        dq = 2.0_RP / ( 1.0_RP/dqr+1.0_RP/dql )
      else
        dq = 0.0_RP
      end if
      qstar = gdq( i )-( delxa( i )+gdu( i-1 )*dtime )*dq*0.50_RP
      fq( i ) = qstar*gdu( i-1 )
  end do

  !--- change of concentration by flux convergence
  do i = KS, KE
    gdq( i ) = gdq( i ) - dtime/delxa( i )*( fq( i+1 )-fq( i ) )
    if( i == KS ) then
     sfc_precp( spc ) = dtime/delxa( i )*( -fq( i ) )
    endif
  end do
  !
  return

  end subroutine  advec_1d
  !-------------------------------------------------------------------------------
  !
  ! + Y. Sato added for stochastic method 
  ! + Reference Sato et al. (2009) JGR, doi:10.1029/2008JD011247
  !
  !-------------------------------------------------------------------------------
  subroutine random_setup( mset ) !--- in

   use mod_random, only: &
       RANDOM_get
   use mod_process, only: &
       PRC_MPIstop

   integer, intent(in) :: mset

   !--- local ----
   integer :: n
   real(RP) :: nbinr, tmp1
   real(RP) :: rans( mbin ), ranl( mbin )
   integer, parameter :: pq = nbin*(nbin-1)/2
   real(RP) :: ranstmp( pq )
   real(RP) :: ranltmp( pq )
   integer :: p, q
   integer :: k, temp
   integer :: orderb( pq )
   real(RP) :: abq1
   real(RP) :: a
   real(RP) :: randnum(1,1,pq)
  !-------------------------------------------------------
   allocate( blrg( mset, mbin ) )
   allocate( bsml( mset, mbin ) )
 
   a = real( nbin )*real( nbin-1 )*0.50_RP
   if( a < mbin ) then
    write(*,*) "mbin should be smaller than {nbin}_C_{2}"
    call PRC_MPIstop
   end if
 
   wgtbin = a/real( mbin )
   nbinr = real( nbin )
 
    do p = 1, pq
      orderb( p ) = p
    end do
 
    do p = 1, nbin-1
      ranstmp( (p-1)*nbin-(p*(p-1))/2+1 : p*nbin-(p*(p+1))/2 ) = p
     do q = 1, nbin-p
        ranltmp( (p-1)*nbin-(p*(p-1))/2+q ) = p+q
      end do
   end do
 
    do n = 1, mset
      call RANDOM_get( randnum )
       do p = 1, pq
        abq1 = randnum( 1,1,p )
        k = int( abq1*( pq-p-1 ) ) + p
        temp = orderb( p )
        orderb( p ) = orderb( k )
        orderb( k ) = temp
       end do
 
       do p = 1, mbin
        if( p <= pq ) then
         rans( p ) = ranstmp( orderb( p ) )
         ranl( p ) = ranltmp( orderb( p ) )
        else
         rans( p ) = ranstmp( orderb( p-pq ) )
         ranl( p ) = ranltmp( orderb( p-pq ) )
        end if
         if( rans( p ) >= ranl( p ) ) then
          tmp1 = rans( p )
          rans( p ) = ranl( p )
          ranl( p ) = tmp1
         end if
       end do
         blrg( n,1:mbin ) = int( ranl( 1:mbin ) )
         bsml( n,1:mbin ) = int( rans( 1:mbin ) )
    end do
 
  end subroutine random_setup
 !-------------------------------------------------------------------------------
  subroutine  r_collcoag( isml, ilrg, irsl, dtime, swgt, gc )
  !-------------------------------------------------------------------------------
  !--- reference paper
  !    Bott et al. (1998) J. Atmos. Sci. vol.55, pp. 2284-
  !    Bott et al. (2000) J. Atmos. Sci. Vol.57, pp. 284-
  !-------------------------------------------------------------------------------
  !
  use mod_random, only: &
      RANDOM_get

  integer,  intent(in) :: isml, ilrg, irsl
  real(RP), intent(in) :: dtime
  real(RP), intent(in) :: swgt
  real(RP), intent(inout) :: gc( nspc,nbin )
  !
  !--- local variables
  integer :: i, j, k, l
  real(RP) :: xi, xj, xnew, dmpi, dmpj, frci, frcj
  real(RP) :: gprime, gprimk, wgt, crn, sum, flux
  integer, parameter :: ldeg = 2
  real(RP), parameter :: dmpmin = 1.E-01_RP, cmin = 1.E-10_RP
  real(RP) :: acoef( 0:ldeg )
  !
  !--- Y.sato added to use code6
  integer :: nums( mbin ), numl( mbin )
  real(RP), parameter :: gt = 1.0_RP
  integer :: s, det
  real(RP) :: nbinr, mbinr        ! use to weight
!  real(RP) :: beta
  real(RP) :: tmpi, tmpj
 !-----------------------------------------------------
  call RANDOM_get( rndm )
  det = int( rndm(1,1,1)*IA*JA*KA )
  nbinr = real( nbin )
  mbinr = real( mbin )
  nums( 1:mbin ) = bsml( det,1:mbin )
  numl( 1:mbin ) = blrg( det,1:mbin )

   do s = 1, mbin
    i = nums( s )
    j = numl( s )

    if ( gc( isml,i ) <= cmin ) cycle !small
    if ( gc( ilrg,j ) <= cmin ) cycle !large

    xi = exp( xctr( i ) )
    xj = exp( xctr( j ) )
    xnew = log( xi+xj )
    k = int( ( xnew-xctr( 1 ) )/dxmic ) + 1
    k = max( max( k,j ),i )
    if( k>= nbin ) cycle

    dmpi = ck( isml,ilrg,i,j )*gc( ilrg,j )/xj*dxmic*dtime
    dmpj = ck( ilrg,isml,i,j )*gc( isml,i )/xi*dxmic*dtime

    if ( dmpi <= dmpmin ) then
      frci = gc( isml,i )*dmpi
    else
      frci = gc( isml,i )*( 1.0_RP-exp( -dmpi ) )
    end if

    if ( dmpj <= dmpmin ) then
      frcj = gc( ilrg,j )*dmpj
    else
      frcj = gc( ilrg,j )*( 1.0_RP-exp( -dmpj ) )
    end if
    tmpi = gc( isml,i )
    tmpj = gc( ilrg,j )

    gc( isml,i ) = gc( isml,i )-frci*swgt
    gc( ilrg,j ) = gc( ilrg,j )-frcj*swgt

    if( j /= k ) then
     gc( ilrg,j ) = max( gc( ilrg,j ), 0.0_RP )
    end if
     gc( isml,i ) = max( gc( isml,i ), 0.0_RP )

    frci = tmpi - gc( isml,i )
    frcj = tmpj - gc( ilrg,j )

    gprime = frci+frcj

    !-----------------------------------------------
    !--- Exponential Flux Method (Bott, 2000, JAS)
    !-----------------------------------------------
!    if ( gprime <= 0.0_RP ) cycle !large
!    gprimk = gc( (irsl-1)*nbin+k ) + gprime
!
!    beta = log( gc( (irsl-1)*nbin+k+1 )/gprimk+1.E-60_RP )
!    crn = ( xnew-xctr( k ) )/( xctr( k+1 )-xctr( k ) )
!
!    flux = ( gprime/beta )*( exp( beta*0.50_RP ) -exp( beta*( 0.50_RP-crn ) ) )
!    flux = min( gprimk ,gprime )
!
!    gc( (irsl-1)*nbin+k ) = gprimk - flux
!    gc( (irsl-1)*nbin+k+1 ) = gc( (irsl-1)*nbin+k+1 ) + flux

    !-----------------------------------------------
    !--- Flux Method (Bott, 1998, JAS)
    !-----------------------------------------------
    if ( gprime <= 0.0_RP ) cycle !large
    gprimk = gc( irsl,k ) + gprime
    wgt = gprime / gprimk
    crn = ( xnew-xctr( k ) )/( xctr( k+1 )-xctr( k ) )

    acoef( 0 ) = -( gc( irsl,k+1 )-26.0_RP*gprimk+gc( irsl,k-1 ) )/24.0_RP
    acoef( 1 ) =  ( gc( irsl,k+1 )-gc( irsl,k-1 ) ) *0.5_RP
    acoef( 2 ) =  ( gc( irsl,k+1 )-2.0_RP*gprimk+gc( irsl,k-1 ) ) *0.50_RP

    sum = 0.0_RP
    do l = 0, ldeg
      sum = sum + acoef( l )/( l+1 )/2.0_RP**( l+1 )   &
                *( 1.0_RP-( 1.0_RP-2.0_RP*crn )**( l+1 ) )
    end do

    flux = wgt*sum
    flux = min( max( flux,0.0_RP ),gprime )

    gc( irsl,k ) = gprimk - flux
    gc( irsl,k+1 ) = gc( irsl,k+1 ) + flux

   end do

  !  
  return
  !
  end subroutine r_collcoag
  !-------------------------------------------------------------------
  subroutine  getrule   &
      ( temp,           & !--- in
        ifrsl           ) !--- out
  !
  real(RP), intent(in) :: temp
  integer, intent(out) :: ifrsl( nspc,nspc )
  !
  real(RP), parameter :: tcrit = 271.15_RP
  !
  !--- liquid + liquid -> liquid
  ifrsl( il,il ) = il
  !
  !--- liquid + column -> ( graupel, hail ) + column
  ifrsl( il,ic ) = ic
  if ( temp < tcrit ) then
    ifrsl( ic,il ) = ig
  else
    ifrsl( ic,il ) = ih
  end if
  !
  !--- liquid + plate -> ( graupel, hail ) + plate
  ifrsl( il,ip ) = ip
  if ( temp < tcrit ) then
    ifrsl( ip,il ) = ig
  else
    ifrsl( ip,il ) = ih
  end if
  !
  !--- liquid + dendrite -> ( graupel, hail ) + dendrite
  ifrsl( il,id ) = id
  if ( temp < tcrit ) then
    ifrsl( id,il ) = ig
  else
    ifrsl( id,il ) = ih
  end if
  !
  !--- liquid + snowflake -> ( graupel, hail ) + snowflake
  ifrsl( il,iss ) = iss
  if ( temp < tcrit ) then
    ifrsl( iss,il ) = ig
  else
    ifrsl( iss,il ) = ih
  end if
  !
  !--- liquid + graupel -> ( graupel, hail )
  ifrsl( il,ig ) = ig
  if ( temp < tcrit ) then
    ifrsl( ig,il ) = ig
  else
    ifrsl( ig,il ) = ih
  end if
  !
  !--- liquid + hail -> ( graupel, hail )
  ifrsl( il,ih ) = ih
  if ( temp < tcrit ) then
    ifrsl( ih,il ) = ig
  else
    ifrsl( ih,il ) = ih
  end if
  !
  !
  !--- column + column -> snowflake
  ifrsl( ic,ic ) = iss
  !
  !--- column + plate -> snowflake
  ifrsl( ic,ip ) = iss
  ifrsl( ip,ic ) = iss
  !
  !--- column + dendrite -> snowflake
  ifrsl( ic,id ) = iss
  ifrsl( id,ic ) = iss
  !
  !--- column + snowflake -> snowflake
  ifrsl( ic,iss ) = iss
  ifrsl( iss,ic ) = iss
  !
  !--- column + graupel -> column + graupel
  ifrsl( ic,ig ) = ig
  ifrsl( ig,ic ) = ic
  !
  !--- column + hail -> column + ( graupel, hail )
  ifrsl( ih,ic ) = ic
  if ( temp < tcrit ) then
    ifrsl( ic,ih ) = ig
  else
    ifrsl( ic,ih ) = ih
  end if
  !
  !
  !--- plate + plate -> snowflake
  ifrsl( ip,ip ) = iss
  !
  !--- plate + dendrite -> snowflake
  ifrsl( ip,id ) = iss
  ifrsl( id,ip ) = iss
  !
  !--- plate + snowflake -> snowflake
  ifrsl( ip,iss ) = iss
  ifrsl( iss,ip ) = iss
  !
  !--- plate + graupel -> plate + graupel
  ifrsl( ip,ig ) = ig
  ifrsl( ig,ip ) = ip
  !
  !--- plate + hail -> plate + ( graupel, hail )
  ifrsl( ih,ip ) = ip
  if ( temp < tcrit ) then
    ifrsl( ip,ih ) = ig
  else
    ifrsl( ip,ih ) = ih
  end if
  !
  !
  !--- dendrite + dendrite -> snowflake
  ifrsl( id,id ) = iss
  !
  !--- dendrite + snowflake -> snowflake
  ifrsl( id,iss ) = iss
  ifrsl( iss,id ) = iss
  !
  !--- dendrite + graupel -> dendrite + graupel
  ifrsl( id,ig ) = ig
  ifrsl( ig,id ) = id
  !
  !--- dendrite + hail -> dendrite + ( graupel, hail )
  ifrsl( ih,id ) = id
  if ( temp < tcrit ) then
    ifrsl( id,ih ) = ig
  else
    ifrsl( id,ih ) = ih
  end if
  !
  !
  !--- snowflake + snowflake -> snowflake
  ifrsl( iss,iss ) = iss
  !
  !--- snowflake + graupel -> snowflake + graupel
  ifrsl( iss,ig ) = ig
  ifrsl( ig,iss ) = iss
  !
  !--- snowflake + hail -> snowflake + ( graupel, hail )
  ifrsl( ih,iss ) = iss
  if ( temp < tcrit ) then
    ifrsl( iss,ih ) = ig
  else
    ifrsl( iss,ih ) = ih
  end if
  !
  !
  !--- graupel + graupel -> graupel
  ifrsl( ig,ig ) = ig
  !
  !--- graupel + hail -> ( graupel, hail )
  if ( temp < tcrit ) then
    ifrsl( ig,ih ) = ig
    ifrsl( ih,ig ) = ig
  else
    ifrsl( ig,ih ) = ih
    ifrsl( ih,ig ) = ih
  end if
  !
  !--- hail + hail -> hail
  ifrsl( ih,ih ) = ih
  !
  !
  return
  !
  end subroutine getrule
 !-------------------------------------------------------------------------------
end module mod_atmos_phy_mp
!-------------------------------------------------------------------------------