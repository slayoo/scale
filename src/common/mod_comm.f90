!-------------------------------------------------------------------------------
!> module COMMUNICATION
!!
!! @par Description
!!          MPI module for SCALE3 (Communication Core)
!!
!! @author H.Tomita and SCALE developpers
!!
!! @par History
!! @li      2011-10-11 (R.Yoshida)  [new]
!! @li      2011-11-11 (H.Yashiro)  [mod] Integrate to SCALE3
!! @li      2012-01-10 (Y.Ohno)     [mod] Nonblocking communication (MPI)
!! @li      2012-01-23 (Y.Ohno)     [mod] Self unpacking (MPI)
!! @li      2012-03-12 (H.Yashiro)  [mod] REAL4(MPI)
!! @li      2012-03-12 (Y.Ohno)     [mod] RDMA communication
!! @li      2012-03-23 (H.Yashiro)  [mod] Explicit index parameter inclusion
!! @li      2012-03-27 (H.Yashiro)  [mod] Area/volume weighted total value report
!!
!<
!-------------------------------------------------------------------------------
module mod_comm
  !-----------------------------------------------------------------------------
  !
  !++ used modules
  !
  use mpi
  use mod_stdio, only: &
     IO_FID_LOG, &
     IO_L
  use mod_time, only: &
     TIME_rapstart, &
     TIME_rapend
  !-----------------------------------------------------------------------------
  implicit none
  private
  !-----------------------------------------------------------------------------
  !
  !++ Public procedure
  !
  public :: COMM_setup
  public :: COMM_vars
  public :: COMM_vars8
  public :: COMM_wait
  public :: COMM_vars_r4
  public :: COMM_vars8_r4
  public :: COMM_wait_r4
#ifdef _USE_RDMA
  public :: COMM_set_rdma_variable
  public :: COMM_rdma_vars
  public :: COMM_rdma_vars8
#endif
  public :: COMM_stats
  public :: COMM_total
  public :: COMM_horizontal_mean

  interface COMM_vars
     module procedure COMM_vars_2D
     module procedure COMM_vars_3D
  end interface COMM_vars
  interface COMM_vars8
     module procedure COMM_vars8_2D
     module procedure COMM_vars8_3D
  end interface COMM_vars8
  interface COMM_wait
     module procedure COMM_wait_2D
     module procedure COMM_wait_3D
  end interface COMM_WAIT

  !-----------------------------------------------------------------------------
  !
  !++ included parameters
  !
  include "inc_precision.h"
  include "inc_index.h"

  !-----------------------------------------------------------------------------
  !
  !++ Public parameters & variables
  !
  logical, public, save :: COMM_total_doreport  = .false.

  !-----------------------------------------------------------------------------
  !
  !++ Private procedure
  !
  !-----------------------------------------------------------------------------
  !
  !++ Private parameters & variables
  !
  integer, private, save :: COMM_vsize_max  = 250
  logical, private, save :: COMM_total_globalsum = .false.

  logical, private, save :: IsAllPeriodic

  integer, private, save :: datasize_NS4
  integer, private, save :: datasize_NS8
  integer, private, save :: datasize_WE
  integer, private, save :: datasize_4C

  integer, private, save :: datasize_2D_NS4
  integer, private, save :: datasize_2D_NS8
  integer, private, save :: datasize_2D_WE
  integer, private, save :: datasize_2D_4C

  integer, private, save :: datatype

  integer, private, save :: IREQ_CNT_NS
  integer, private, save :: IREQ_CNT_WE
  integer, private, save :: IREQ_CNT_4C
  integer, private, save :: IREQ_CNT_MAX

  real(RP), private, allocatable, save :: recvpack_W2P(:,:)
  real(RP), private, allocatable, save :: recvpack_E2P(:,:)
  real(RP), private, allocatable, save :: sendpack_P2W(:,:)
  real(RP), private, allocatable, save :: sendpack_P2E(:,:)
  real(4),  private, allocatable, save :: recvpack_W2P_r4(:,:)
  real(4),  private, allocatable, save :: recvpack_E2P_r4(:,:)
  real(4),  private, allocatable, save :: sendpack_P2W_r4(:,:)
  real(4),  private, allocatable, save :: sendpack_P2E_r4(:,:)

  integer, private, allocatable, save :: ireq_cnt(:)
  integer, private, allocatable, save :: ireq_list(:,:)

  !-----------------------------------------------------------------------------
contains

  !-----------------------------------------------------------------------------
  subroutine COMM_setup
    use mod_stdio, only: &
       IO_FID_CONF
    use mod_process, only: &
       PRC_MPIstop, &
       PRC_NEXT,    &
       PRC_W,       &
       PRC_N,       &
       PRC_E,       &
       PRC_S
    implicit none

    NAMELIST / PARAM_COMM / &
       COMM_vsize_max,      &
       COMM_total_doreport, &
       COMM_total_globalsum

    integer :: ierr
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '+++ Module[COMM]/Categ[COMMON]'

    !--- read namelist
    rewind(IO_FID_CONF)
    read(IO_FID_CONF,nml=PARAM_COMM,iostat=ierr)

    if( ierr < 0 ) then !--- missing
       if( IO_L ) write(IO_FID_LOG,*) '*** Not found namelist. Default used.'
    elseif( ierr > 0 ) then !--- fatal error
       write(*,*) 'xxx Not appropriate names in namelist PARAM_COMM. Check!'
       call PRC_MPIstop
    endif
    if( IO_L ) write(IO_FID_LOG,nml=PARAM_COMM)

    ! only for register
    call TIME_rapstart('COMM vars MPI')
    call TIME_rapend  ('COMM vars MPI')
    call TIME_rapstart('COMM wait MPI')
    call TIME_rapend  ('COMM wait MPI')
    call TIME_rapstart('COMM Bcast MPI')
    call TIME_rapend  ('COMM Bcast MPI')

    IREQ_CNT_NS  = 2 * JHALO !--- sendxJHALO recvxJHALO
    IREQ_CNT_WE  = 2         !--- sendx1 recvx1
    IREQ_CNT_4C  = 2 * JHALO !--- sendxJHALO recvxJHALO
    IREQ_CNT_MAX = 2 * IREQ_CNT_NS + 2 * IREQ_CNT_WE + 4 * IREQ_CNT_4C

    datasize_NS4 = IA   * KA * JHALO
    datasize_NS8 = IMAX * KA
    datasize_WE  = JMAX * KA * IHALO
    datasize_4C  =        KA * IHALO

    datasize_2D_NS4 = IA   * JHALO
    datasize_2D_NS8 = IMAX
    datasize_2D_WE  = JMAX * IHALO
    datasize_2D_4C  =        IHALO

    allocate( recvpack_W2P(datasize_WE,COMM_vsize_max) )
    allocate( recvpack_E2P(datasize_WE,COMM_vsize_max) )
    allocate( sendpack_P2W(datasize_WE,COMM_vsize_max) )
    allocate( sendpack_P2E(datasize_WE,COMM_vsize_max) )

    allocate( recvpack_W2P_r4(datasize_WE,COMM_vsize_max) )
    allocate( recvpack_E2P_r4(datasize_WE,COMM_vsize_max) )
    allocate( sendpack_P2W_r4(datasize_WE,COMM_vsize_max) )
    allocate( sendpack_P2E_r4(datasize_WE,COMM_vsize_max) )

    allocate( ireq_cnt(COMM_vsize_max) ) ;              ireq_cnt(:)   = 0
    allocate( ireq_list(IREQ_CNT_MAX,COMM_vsize_max) ); ireq_list(:,:) = 0

    if (     PRC_NEXT(PRC_N) == MPI_PROC_NULL &
        .or. PRC_NEXT(PRC_S) == MPI_PROC_NULL &
        .or. PRC_NEXT(PRC_W) == MPI_PROC_NULL &
        .or. PRC_NEXT(PRC_E) == MPI_PROC_NULL   ) IsAllPeriodic = .false.

#ifdef _USE_RDMA
    call rdma_setup(COMM_vsize_max,  &
                    IA,              &
                    JA,              &
                    KA,              &
                    IHALO,           &
                    JHALO,           &
                    IS,              &
                    IE,              &
                    JS,              &
                    JE,              &
                    PRC_NEXT(PRC_W), &
                    PRC_NEXT(PRC_N), &
                    PRC_NEXT(PRC_E), &
                    PRC_NEXT(PRC_S)  )
#endif

    if ( RP == kind(0.0d0) ) then
       datatype = MPI_DOUBLE_PRECISION
    else if ( RP == kind(0.0) ) then
       datatype = MPI_REAL
    else
       write(*,*) 'xxx precision is not supportd'
       call PRC_MPIstop
    end if

    return
  end subroutine COMM_setup

  !-----------------------------------------------------------------------------
  subroutine COMM_vars_3D(var, vid)
    use mod_process, only : &
       PRC_next, &
       PRC_W,    &
       PRC_N,    &
       PRC_E,    &
       PRC_S
    implicit none

    real(RP), intent(inout) :: var(:,:,:)
    integer, intent(in)    :: vid

    integer :: ireqc, tag
    integer :: ierr
    integer :: i, j, k, n
    !---------------------------------------------------------------------------

    tag = vid * 100
    ireqc = 1

    call TIME_rapstart('COMM vars MPI')

    if( IsAllPeriodic ) then
    !--- periodic condition
        !-- From 4-Direction HALO communicate
        ! From S
        call MPI_IRECV( var(:,:,JS-JHALO:JS-1), datasize_NS4,         &
                        datatype, PRC_next(PRC_S), tag+1, &
                        MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr    )
        ireqc = ireqc + 1

        ! From N
        call MPI_IRECV( var(:,:,JE+1:JE+JHALO), datasize_NS4,         &
                        datatype, PRC_next(PRC_N), tag+2, &
                        MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr    )
        ireqc = ireqc + 1

        ! From E
        call MPI_IRECV( recvpack_E2P(:,vid), datasize_WE,             &
                        datatype, PRC_next(PRC_E), tag+3, &
                        MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr )
        ireqc = ireqc + 1

        ! From W
        call MPI_IRECV( recvpack_W2P(:,vid), datasize_WE,             &
                        datatype, PRC_next(PRC_W), tag+4, &
                        MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr )
        ireqc = ireqc + 1

        !-- To 4-Direction HALO communicate
        !--- packing packets to West
        do j = JS, JE
        do i = IS, IS+IHALO-1
        do k = 1, KA
            n =  (j-JS) * KA * IHALO &
               + (i-IS) * KA         &
               + k
            sendpack_P2W(n,vid) = var(k,i,j)
        enddo
        enddo
        enddo

        !--- packing packets to East
        do j = JS, JE
        do i = IE-IHALO+1, IE
        do k = 1, KA
            n =  (j-JS)         * KA * IHALO &
               + (i-IE+IHALO-1) * KA         &
               + k
            sendpack_P2E(n,vid) = var(k,i,j)
        enddo
        enddo
        enddo

        ! To W HALO communicate
        call MPI_ISEND( sendpack_P2W(:,vid), datasize_WE,             &
                        datatype, PRC_next(PRC_W), tag+3, &
                        MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr )
        ireqc = ireqc + 1

        ! To E HALO communicate
        call MPI_ISEND( sendpack_P2E(:,vid), datasize_WE,             &
                        datatype, PRC_next(PRC_E), tag+4, &
                        MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr )
        ireqc = ireqc + 1

        ! To N HALO communicate
        call MPI_ISEND( var(:,:,JE-JHALO+1:JE), datasize_NS4,         &
                        datatype, PRC_next(PRC_N), tag+1, &
                        MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr    )
        ireqc = ireqc + 1

        ! To S HALO communicate
        call MPI_ISEND( var(:,:,JS:JS+JHALO-1), datasize_NS4,         &
                        datatype, PRC_next(PRC_S), tag+2, &
                        MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr    )
        ireqc = ireqc + 1

    else
    !--- non-periodic condition
        !-- From 4-Direction HALO communicate
        ! From S
        if( PRC_next(PRC_S) /= MPI_PROC_NULL ) then
            call MPI_IRECV( var(:,:,JS-JHALO:JS-1), datasize_NS4,         &
                            datatype, PRC_next(PRC_S), tag+1, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr    )
            ireqc = ireqc + 1
        endif

        ! From N
        if( PRC_next(PRC_N) /= MPI_PROC_NULL ) then
            call MPI_IRECV( var(:,:,JE+1:JE+JHALO), datasize_NS4,         &
                            datatype, PRC_next(PRC_N), tag+2, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr    )
            ireqc = ireqc + 1
        endif

        ! From E
        if( PRC_next(PRC_E) /= MPI_PROC_NULL ) then
            call MPI_IRECV( recvpack_E2P(:,vid), datasize_WE,             &
                            datatype, PRC_next(PRC_E), tag+3, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr )
            ireqc = ireqc + 1
        endif

        ! From W
        if( PRC_next(PRC_W) /= MPI_PROC_NULL ) then
            call MPI_IRECV( recvpack_W2P(:,vid), datasize_WE,             &
                            datatype, PRC_next(PRC_W), tag+4, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr )
            ireqc = ireqc + 1
        endif

        !-- To 4-Direction HALO communicate
        !--- packing packets to West
        if( PRC_next(PRC_W) /= MPI_PROC_NULL ) then
            do j = JS, JE
            do i = IS, IS+IHALO-1
            do k = 1, KA
                n =  (j-JS) * KA * IHALO &
                   + (i-IS) * KA         &
                   + k
                sendpack_P2W(n,vid) = var(k,i,j)
            enddo
            enddo
            enddo
        endif

        !--- packing packets to East
        if( PRC_next(PRC_E) /= MPI_PROC_NULL ) then
            do j = JS, JE
            do i = IE-IHALO+1, IE
            do k = 1, KA
                n =  (j-JS)         * KA * IHALO &
                   + (i-IE+IHALO-1) * KA         &
                   + k
                sendpack_P2E(n,vid) = var(k,i,j)
            enddo
            enddo
            enddo
         endif

        ! To W HALO communicate
        if( PRC_next(PRC_W) /= MPI_PROC_NULL ) then
            call MPI_ISEND( sendpack_P2W(:,vid), datasize_WE,             &
                            datatype, PRC_next(PRC_W), tag+3, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr )
            ireqc = ireqc + 1
        endif

        ! To E HALO communicate
        if( PRC_next(PRC_E) /= MPI_PROC_NULL ) then
            call MPI_ISEND( sendpack_P2E(:,vid), datasize_WE,             &
                            datatype, PRC_next(PRC_E), tag+4, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr )
            ireqc = ireqc + 1
        endif

        ! To N HALO communicate
        if( PRC_next(PRC_N) /= MPI_PROC_NULL ) then
            call MPI_ISEND( var(:,:,JE-JHALO+1:JE), datasize_NS4,         &
                            datatype, PRC_next(PRC_N), tag+1, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr    )
            ireqc = ireqc + 1
        endif

        ! To S HALO communicate
        if( PRC_next(PRC_S) /= MPI_PROC_NULL ) then
            call MPI_ISEND( var(:,:,JS:JS+JHALO-1), datasize_NS4,         &
                            datatype, PRC_next(PRC_S), tag+2, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr    )
            ireqc = ireqc + 1
        endif

    endif

    ireq_cnt(vid) = ireqc - 1

    call TIME_rapend  ('COMM vars MPI')

    return
  end subroutine COMM_vars_3D

  !-----------------------------------------------------------------------------
  subroutine COMM_vars8_3D(var, vid)
    use mod_process, only : &
       PRC_next, &
       PRC_W,    &
       PRC_N,    &
       PRC_E,    &
       PRC_S,    &
       PRC_NW,   &
       PRC_NE,   &
       PRC_SW,   &
       PRC_SE
    implicit none

    real(RP), intent(inout) :: var(:,:,:)
    integer, intent(in)    :: vid

    integer :: ireqc, tag, tagc

    integer :: ierr
    integer :: i, j, k, n
    !---------------------------------------------------------------------------

    tag   = vid * 100
    ireqc = 1

    call TIME_rapstart('COMM vars MPI')

    if( IsAllPeriodic ) then
    !--- periodic condition
        !-- From 8-Direction HALO communicate
        ! From SE
        tagc = 0
        do j = JS-JHALO, JS-1
            call MPI_IRECV( var(1,IE+1,j), datasize_4C,                       &
                            datatype, PRC_next(PRC_SE), tag+tagc, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
            ireqc = ireqc + 1
            tagc  = tagc  + 1
        enddo
        ! From SW
        tagc = 10
        do j = JS-JHALO, JS-1
            call MPI_IRECV( var(1,IS-IHALO,j), datasize_4C,                   &
                            datatype, PRC_next(PRC_SW), tag+tagc, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
            ireqc = ireqc + 1
            tagc  = tagc  + 1
        enddo
        ! From NE
        tagc = 20
        do j = JE+1, JE+JHALO
            call MPI_IRECV( var(1,IE+1,j), datasize_4C,                       &
                            datatype, PRC_next(PRC_NE), tag+tagc, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
            ireqc = ireqc + 1
            tagc  = tagc  + 1
        enddo
        ! From NW
        tagc = 30
        do j = JE+1, JE+JHALO
            call MPI_IRECV( var(1,IS-IHALO,j), datasize_4C,                   &
                            datatype, PRC_next(PRC_NW), tag+tagc, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
            ireqc = ireqc + 1
            tagc  = tagc  + 1
        enddo
        ! From S
        tagc = 40
        do j = JS-JHALO, JS-1
            call MPI_IRECV( var(1,IS,j), datasize_NS8,                       &
                            datatype, PRC_next(PRC_S), tag+tagc, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr       )
             ireqc = ireqc + 1
             tagc  = tagc  + 1
        enddo
        ! From N
        tagc = 50
        do j = JE+1, JE+JHALO
            call MPI_IRECV( var(1,IS,j), datasize_NS8,                       &
                            datatype, PRC_next(PRC_N), tag+tagc, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr       )
            ireqc = ireqc + 1
            tagc  = tagc  + 1
        enddo
        ! From E
        call MPI_IRECV( recvpack_E2P(:,vid), datasize_WE,              &
                        datatype, PRC_next(PRC_E), tag+60, &
                        MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr     )
        ireqc = ireqc + 1
        ! From W
        call MPI_IRECV( recvpack_W2P(:,vid), datasize_WE,              &
                        datatype, PRC_next(PRC_W), tag+70, &
                        MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr     )
        ireqc = ireqc + 1

        !-- To 8-Direction HALO communicate
        !--- packing packets to West
        do j = JS, JE
        do i = IS, IS+IHALO-1
        do k = 1, KA
            n =  (j-JS) * KA * IHALO &
               + (i-IS) * KA         &
               + k
            sendpack_P2W(n,vid) = var(k,i,j)
        enddo
        enddo
        enddo

        !--- packing packets to East
        do j = JS, JE
        do i = IE-IHALO+1, IE
        do k = 1, KA
            n =  (j-JS)         * KA * IHALO &
               + (i-IE+IHALO-1) * KA         &
               + k
            sendpack_P2E(n,vid) = var(k,i,j)
        enddo
        enddo
        enddo

        ! To W HALO communicate
        call MPI_ISEND( sendpack_P2W(:,vid), datasize_WE,              &
                        datatype, PRC_next(PRC_W), tag+60, &
                        MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr     )
        ireqc = ireqc + 1

        ! To E HALO communicate
        call MPI_ISEND( sendpack_P2E(:,vid), datasize_WE,              &
                        datatype, PRC_next(PRC_E), tag+70, &
                        MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr     )
        ireqc = ireqc + 1

        ! To N HALO communicate
        tagc = 40
        do j = JE-JHALO+1, JE
            call MPI_ISEND( var(1,IS,j), datasize_NS8,                       &
                            datatype, PRC_next(PRC_N), tag+tagc, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr       )
            ireqc = ireqc + 1
            tagc  = tagc  + 1
        enddo

        ! To S HALO communicate
        tagc = 50
        do j = JS, JS+JHALO-1
            call MPI_ISEND( var(1,IS,j), datasize_NS8,                       &
                            datatype, PRC_next(PRC_S), tag+tagc, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr       )
            ireqc = ireqc + 1
            tagc  = tagc  + 1
        enddo

        ! To NW HALO communicate
        tagc = 0
        do j = JE-JHALO+1, JE
            call MPI_ISEND( var(1,IS,j), datasize_4C,                         &
                            datatype, PRC_next(PRC_NW), tag+tagc, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
            ireqc = ireqc + 1
            tagc  = tagc  + 1
        enddo

        ! To NE HALO communicate
        tagc = 10
        do j = JE-JHALO+1, JE
            call MPI_ISEND( var(1,IE-IHALO+1,j), datasize_4C,                 &
                            datatype, PRC_next(PRC_NE), tag+tagc, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
            ireqc = ireqc + 1
            tagc  = tagc  + 1
        enddo

        ! To SW HALO communicate
        tagc = 20
        do j = JS, JS+JHALO-1
            call MPI_ISEND( var(1,IS,j), datasize_4C,                         &
                            datatype, PRC_next(PRC_SW), tag+tagc, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
            ireqc = ireqc + 1
            tagc  = tagc  + 1
        enddo

        ! To SE HALO communicate
        tagc = 30
        do j = JS, JS+JHALO-1
            call MPI_ISEND( var(1,IE-IHALO+1,j), datasize_4C,                 &
                            datatype, PRC_next(PRC_SE), tag+tagc, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
            ireqc = ireqc + 1
            tagc  = tagc  + 1
        enddo
    else
    !--- non-periodic condition
        !-- From 8-Direction HALO communicate
        ! From SE
        if( PRC_next(PRC_SE) /= MPI_PROC_NULL ) then
            tagc = 0
            do j = JS-JHALO, JS-1
                call MPI_IRECV( var(1,IE+1,j), datasize_4C,                       &
                                datatype, PRC_next(PRC_SE), tag+tagc, &
                                MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
                ireqc = ireqc + 1
                tagc  = tagc  + 1
            enddo
        endif

        ! From SW
        if( PRC_next(PRC_SW) /= MPI_PROC_NULL ) then
            tagc = 10
            do j = JS-JHALO, JS-1
                call MPI_IRECV( var(1,IS-IHALO,j), datasize_4C,                   &
                                datatype, PRC_next(PRC_SW), tag+tagc, &
                                MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
                ireqc = ireqc + 1
                tagc  = tagc  + 1
            enddo
        endif

        ! From NE
        if( PRC_next(PRC_NE) /= MPI_PROC_NULL ) then
            tagc = 20
            do j = JE+1, JE+JHALO
                call MPI_IRECV( var(1,IE+1,j), datasize_4C,                       &
                                datatype, PRC_next(PRC_NE), tag+tagc, &
                                MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
                ireqc = ireqc + 1
                tagc  = tagc  + 1
            enddo
        endif

        ! From NW
        if( PRC_next(PRC_NW) /= MPI_PROC_NULL ) then
            tagc = 30
            do j = JE+1, JE+JHALO
                call MPI_IRECV( var(1,IS-IHALO,j), datasize_4C,                   &
                                datatype, PRC_next(PRC_NW), tag+tagc, &
                                MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
                ireqc = ireqc + 1
                tagc  = tagc  + 1
            enddo
        endif

        ! From S
        if( PRC_next(PRC_S) /= MPI_PROC_NULL ) then
            tagc = 40
            do j = JS-JHALO, JS-1
                call MPI_IRECV( var(1,IS,j), datasize_NS8,                       &
                                datatype, PRC_next(PRC_S), tag+tagc, &
                                MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr       )
                 ireqc = ireqc + 1
                 tagc  = tagc  + 1
            enddo
        endif

        ! From N
        if( PRC_next(PRC_N) /= MPI_PROC_NULL ) then
            tagc = 50
            do j = JE+1, JE+JHALO
                call MPI_IRECV( var(1,IS,j), datasize_NS8,                       &
                                datatype, PRC_next(PRC_N), tag+tagc, &
                                MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr       )
                ireqc = ireqc + 1
                tagc  = tagc  + 1
            enddo
        endif

        ! From E
        if( PRC_next(PRC_E) /= MPI_PROC_NULL ) then
            call MPI_IRECV( recvpack_E2P(:,vid), datasize_WE,              &
                            datatype, PRC_next(PRC_E), tag+60, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr     )
            ireqc = ireqc + 1
        endif

        ! From W
        if( PRC_next(PRC_W) /= MPI_PROC_NULL ) then
            call MPI_IRECV( recvpack_W2P(:,vid), datasize_WE,              &
                            datatype, PRC_next(PRC_W), tag+70, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr     )
            ireqc = ireqc + 1
        endif

        !-- To 8-Direction HALO communicate
        !--- packing packets to West
        if( PRC_next(PRC_W) /= MPI_PROC_NULL ) then
            do j = JS, JE
            do i = IS, IS+IHALO-1
            do k = 1, KA
                n =  (j-JS) * KA * IHALO &
                   + (i-IS) * KA         &
                   + k
                sendpack_P2W(n,vid) = var(k,i,j)
            enddo
            enddo
            enddo
        endif

        !--- packing packets to East
        if( PRC_next(PRC_E) /= MPI_PROC_NULL ) then
            do j = JS, JE
            do i = IE-IHALO+1, IE
            do k = 1, KA
                n =  (j-JS)         * KA * IHALO &
                   + (i-IE+IHALO-1) * KA         &
                   + k
                sendpack_P2E(n,vid) = var(k,i,j)
            enddo
            enddo
            enddo
        endif

        ! To W HALO communicate
        if( PRC_next(PRC_W) /= MPI_PROC_NULL ) then
            call MPI_ISEND( sendpack_P2W(:,vid), datasize_WE,              &
                            datatype, PRC_next(PRC_W), tag+60, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr     )
            ireqc = ireqc + 1
        endif

        ! To E HALO communicate
        if( PRC_next(PRC_E) /= MPI_PROC_NULL ) then
            call MPI_ISEND( sendpack_P2E(:,vid), datasize_WE,              &
                            datatype, PRC_next(PRC_E), tag+70, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr     )
            ireqc = ireqc + 1
        endif

        ! To N HALO communicate
        if( PRC_next(PRC_N) /= MPI_PROC_NULL ) then
            tagc = 40
            do j = JE-JHALO+1, JE
                call MPI_ISEND( var(1,IS,j), datasize_NS8,                       &
                                datatype, PRC_next(PRC_N), tag+tagc, &
                                MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr       )
                ireqc = ireqc + 1
                tagc  = tagc  + 1
            enddo
        endif

        ! To S HALO communicate
        if( PRC_next(PRC_S) /= MPI_PROC_NULL ) then
            tagc = 50
            do j = JS, JS+JHALO-1
                call MPI_ISEND( var(1,IS,j), datasize_NS8,                       &
                                datatype, PRC_next(PRC_S), tag+tagc, &
                                MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr       )
                ireqc = ireqc + 1
                tagc  = tagc  + 1
            enddo
        endif

        ! To NW HALO communicate
        if( PRC_next(PRC_NW) /= MPI_PROC_NULL ) then
            tagc = 0
            do j = JE-JHALO+1, JE
                call MPI_ISEND( var(1,IS,j), datasize_4C,                         &
                                datatype, PRC_next(PRC_NW), tag+tagc, &
                                MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
                ireqc = ireqc + 1
                tagc  = tagc  + 1
            enddo
        endif

        ! To NE HALO communicate
        if( PRC_next(PRC_NE) /= MPI_PROC_NULL ) then
            tagc = 10
            do j = JE-JHALO+1, JE
                call MPI_ISEND( var(1,IE-IHALO+1,j), datasize_4C,                 &
                                datatype, PRC_next(PRC_NE), tag+tagc, &
                                MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
                ireqc = ireqc + 1
                tagc  = tagc  + 1
            enddo
        endif

        ! To SW HALO communicate
        if( PRC_next(PRC_SW) /= MPI_PROC_NULL ) then
            tagc = 20
            do j = JS, JS+JHALO-1
                call MPI_ISEND( var(1,IS,j), datasize_4C,                         &
                                datatype, PRC_next(PRC_SW), tag+tagc, &
                                MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
                ireqc = ireqc + 1
                tagc  = tagc  + 1
            enddo
        endif

        ! To SE HALO communicate
        if( PRC_next(PRC_SE) /= MPI_PROC_NULL ) then
            tagc = 30
            do j = JS, JS+JHALO-1
                call MPI_ISEND( var(1,IE-IHALO+1,j), datasize_4C,                 &
                                datatype, PRC_next(PRC_SE), tag+tagc, &
                                MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
                ireqc = ireqc + 1
                tagc  = tagc  + 1
            enddo
        endif

    endif

    ireq_cnt(vid) = ireqc - 1

    call TIME_rapend  ('COMM vars MPI')

    return
  end subroutine COMM_vars8_3D

  !-----------------------------------------------------------------------------
  subroutine COMM_wait_3D(var, vid)
    use mod_process, only : &
       PRC_next, &
       PRC_W,    &
       PRC_N,    &
       PRC_E,    &
       PRC_S

    implicit none

    real(RP), intent(inout) :: var(:,:,:)
    integer, intent(in)    :: vid

    integer :: ierr
    integer :: i, j, k, n
    !---------------------------------------------------------------------------

    call TIME_rapstart('COMM wait MPI')

    !--- wait packets
    call MPI_WAITALL(ireq_cnt(vid), ireq_list(1:ireq_cnt(vid),vid), MPI_STATUSES_IGNORE, ierr)

    if( IsAllPeriodic ) then
    !--- periodic condition
        !--- unpacking packets from East
        do j = JS, JE
        do i = IE+1, IE+IHALO
        do k = 1, KA
           n = (j-JS)   * KA * IHALO &
             + (i-IE-1) * KA         &
             + k
           var(k,i,j) = recvpack_E2P(n,vid)
        enddo
        enddo
        enddo

        !--- unpacking packets from West
        do j = JS, JE
        do i = IS-IHALO, IS-1
        do k = 1, KA
           n = (j-JS)       * KA * IHALO &
             + (i-IS+IHALO) * KA         &
             + k
           var(k,i,j) = recvpack_W2P(n,vid)
        enddo
        enddo
        enddo

    else
    !--- non-periodic condition

        !--- copy inner data to HALO(North)
        if( PRC_next(PRC_N) == MPI_PROC_NULL ) then
            do j = JE+1, JE+JHALO
            do i = IS, IE
            do k = 1, KA
               var(k,i,j) = var(k,i,JE)
            enddo
            enddo
            enddo
        endif

        !--- copy inner data to HALO(South)
        if( PRC_next(PRC_S) == MPI_PROC_NULL ) then
            do j = JS-JHALO, JS-1
            do i = IS, IE
            do k = 1, KA
               var(k,i,j) = var(k,i,JS)
            enddo
            enddo
            enddo
        endif

        !--- unpacking packets from East / copy inner data to HALO(East)
        if( PRC_next(PRC_E) /= MPI_PROC_NULL ) then
            do j = JS, JE
            do i = IE+1, IE+IHALO
            do k = 1, KA
               n = (j-JS)   * KA * IHALO &
                 + (i-IE-1) * KA         &
                 + k
               var(k,i,j) = recvpack_E2P(n,vid)
            enddo
            enddo
            enddo
        else
            do j = JS, JE
            do i = IE+1, IE+IHALO
            do k = 1, KA
               var(k,i,j) = var(k,IE,j)
            enddo
            enddo
            enddo
        endif

        !--- unpacking packets from West / copy inner data to HALO(West)
        if( PRC_next(PRC_W) /= MPI_PROC_NULL ) then
            do j = JS, JE
            do i = IS-IHALO, IS-1
            do k = 1, KA
               n = (j-JS)       * KA * IHALO &
                 + (i-IS+IHALO) * KA         &
                 + k
               var(k,i,j) = recvpack_W2P(n,vid)
            enddo
            enddo
            enddo
        else
            do j = JS, JE
            do i = IS-IHALO, IS-1
            do k = 1, KA
               var(k,i,j) = var(k,IS,j)
            enddo
            enddo
            enddo
        endif

        !--- copy inner data to HALO(NorthWest)
        if( PRC_next(PRC_N) == MPI_PROC_NULL .and. PRC_next(PRC_W) == MPI_PROC_NULL) then
            do j = JE+1, JE+JHALO
            do i = IS-IHALO, IS-1
            do k = 1, KA
               var(k,i,j) = var(k,IS,JE)
            enddo
            enddo
            enddo
        else if ( PRC_next(PRC_N) == MPI_PROC_NULL) then
            do j = JE+1, JE+JHALO
            do i = IS-IHALO, IS-1
            do k = 1, KA
               var(k,i,j) = var(k,i,JE)
            enddo
            enddo
            enddo
        else if ( PRC_next(PRC_W) == MPI_PROC_NULL) then
            do j = JE+1, JE+JHALO
            do i = IS-IHALO, IS-1
            do k = 1, KA
               var(k,i,j) = var(k,IS,j)
            enddo
            enddo
            enddo
        endif

        !--- copy inner data to HALO(SouthWest)
        if( PRC_next(PRC_S) == MPI_PROC_NULL .and. PRC_next(PRC_W) == MPI_PROC_NULL) then
            do j = JS-IHALO, JS-1
            do i = IS-IHALO, IS-1
            do k = 1, KA
               var(k,i,j) = var(k,IS,JS)
            enddo
            enddo
            enddo
        else if ( PRC_next(PRC_S) == MPI_PROC_NULL) then
            do j = JS-IHALO, JS-1
            do i = IS-IHALO, IS-1
            do k = 1, KA
               var(k,i,j) = var(k,i,JS)
            enddo
            enddo
            enddo
        else if ( PRC_next(PRC_W) == MPI_PROC_NULL) then
            do j = JS-IHALO, JS-1
            do i = IS-IHALO, IS-1
            do k = 1, KA
               var(k,i,j) = var(k,IS,j)
            enddo
            enddo
            enddo
        endif

        !--- copy inner data to HALO(NorthEast)
        if( PRC_next(PRC_N) == MPI_PROC_NULL .and. PRC_next(PRC_E) == MPI_PROC_NULL) then
            do j = JE+1, JE+JHALO
            do i = IE+1, IE+IHALO
            do k = 1, KA
               var(k,i,j) = var(k,IE,JE)
            enddo
            enddo
            enddo
        else if ( PRC_next(PRC_N) == MPI_PROC_NULL) then
            do j = JE+1, JE+JHALO
            do i = IE+1, IE+IHALO
            do k = 1, KA
               var(k,i,j) = var(k,i,JE)
            enddo
            enddo
            enddo
        else if ( PRC_next(PRC_E) == MPI_PROC_NULL) then
            do j = JE+1, JE+JHALO
            do i = IE+1, IE+IHALO
            do k = 1, KA
               var(k,i,j) = var(k,IE,j)
            enddo
            enddo
            enddo
        endif

        !--- copy inner data to HALO(SouthEast)
        if( PRC_next(PRC_S) == MPI_PROC_NULL .and. PRC_next(PRC_E) == MPI_PROC_NULL) then
            do j = JS-IHALO, JS-1
            do i = IE+1, IE+IHALO
            do k = 1, KA
               var(k,i,j) = var(k,IE,JS)
            enddo
            enddo
            enddo
        else if ( PRC_next(PRC_S) == MPI_PROC_NULL) then
            do j = JS-IHALO, JS-1
            do i = IE+1, IE+IHALO
            do k = 1, KA
               var(k,i,j) = var(k,i,JS)
            enddo
            enddo
            enddo
        else if ( PRC_next(PRC_E) == MPI_PROC_NULL) then
            do j = JS-IHALO, JS-1
            do i = IE+1, IE+IHALO
            do k = 1, KA
               var(k,i,j) = var(k,IE,j)
            enddo
            enddo
            enddo
        endif

    endif


    call TIME_rapend  ('COMM wait MPI')

    return
  end subroutine COMM_wait_3D

  !-----------------------------------------------------------------------------
  subroutine COMM_vars_2D(var, vid)
    use mod_process, only : &
       PRC_next, &
       PRC_W,    &
       PRC_N,    &
       PRC_E,    &
       PRC_S
    implicit none

    real(RP), intent(inout) :: var(:,:)
    integer, intent(in)    :: vid

    integer :: ireqc, tag
    integer :: ierr
    integer :: i, j, n
    !---------------------------------------------------------------------------

    tag = vid * 100
    ireqc = 1

    call TIME_rapstart('COMM vars MPI')

    if( IsAllPeriodic ) then
    !--- periodic condition
        !-- From 4-Direction HALO communicate
        ! From S
        call MPI_IRECV( var(:,JS-JHALO:JS-1), datasize_2D_NS4,        &
                        datatype, PRC_next(PRC_S), tag+1, &
                        MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr    )
        ireqc = ireqc + 1

        ! From N
        call MPI_IRECV( var(:,JE+1:JE+JHALO), datasize_2D_NS4,        &
                        datatype, PRC_next(PRC_N), tag+2, &
                        MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr    )
        ireqc = ireqc + 1

        ! From E
        call MPI_IRECV( recvpack_E2P(:,vid), datasize_2D_WE,       &
                        datatype, PRC_next(PRC_E), tag+3, &
                        MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr )
        ireqc = ireqc + 1

        ! From W
        call MPI_IRECV( recvpack_W2P(:,vid), datasize_2D_WE,       &
                        datatype, PRC_next(PRC_W), tag+4, &
                        MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr )
        ireqc = ireqc + 1

        !-- To 4-Direction HALO communicate
        !--- packing packets to West
        do j = JS, JE
        do i = IS, IS+IHALO-1
            n =  (j-JS) * IHALO &
               + (i-IS) + 1
            sendpack_P2W(n,vid) = var(i,j)
        enddo
        enddo

        !--- packing packets to East
        do j = JS, JE
        do i = IE-IHALO+1, IE
            n =  (j-JS)         * IHALO &
               + (i-IE+IHALO-1) + 1
            sendpack_P2E(n,vid) = var(i,j)
        enddo
        enddo

        ! To W HALO communicate
        call MPI_ISEND( sendpack_P2W(:,vid), datasize_2D_WE,       &
                        datatype, PRC_next(PRC_W), tag+3, &
                        MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr )
        ireqc = ireqc + 1

        ! To E HALO communicate
        call MPI_ISEND( sendpack_P2E(:,vid), datasize_2D_WE,       &
                        datatype, PRC_next(PRC_E), tag+4, &
                        MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr )
        ireqc = ireqc + 1

        ! To N HALO communicate
        call MPI_ISEND( var(:,JE-JHALO+1:JE), datasize_2D_NS4,        &
                        datatype, PRC_next(PRC_N), tag+1, &
                        MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr    )
        ireqc = ireqc + 1

        ! To S HALO communicate
        call MPI_ISEND( var(:,JS:JS+JHALO-1), datasize_2D_NS4,        &
                        datatype, PRC_next(PRC_S), tag+2, &
                        MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr    )
        ireqc = ireqc + 1

    else
    !--- non-periodic condition
        !-- From 4-Direction HALO communicate
        ! From S
        if( PRC_next(PRC_S) /= MPI_PROC_NULL ) then
            call MPI_IRECV( var(:,JS-JHALO:JS-1), datasize_2D_NS4,        &
                            datatype, PRC_next(PRC_S), tag+1, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr    )
            ireqc = ireqc + 1
        endif

        ! From N
        if( PRC_next(PRC_N) /= MPI_PROC_NULL ) then
            call MPI_IRECV( var(:,JE+1:JE+JHALO), datasize_2D_NS4,        &
                            datatype, PRC_next(PRC_N), tag+2, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr    )
            ireqc = ireqc + 1
        endif

        ! From E
        if( PRC_next(PRC_E) /= MPI_PROC_NULL ) then
            call MPI_IRECV( recvpack_E2P(:,vid), datasize_2D_WE,       &
                            datatype, PRC_next(PRC_E), tag+3, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr )
            ireqc = ireqc + 1
        endif

        ! From W
        if( PRC_next(PRC_W) /= MPI_PROC_NULL ) then
            call MPI_IRECV( recvpack_W2P(:,vid), datasize_2D_WE,       &
                            datatype, PRC_next(PRC_W), tag+4, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr )
            ireqc = ireqc + 1
        endif

        !-- To 4-Direction HALO communicate
        !--- packing packets to West
        if( PRC_next(PRC_W) /= MPI_PROC_NULL ) then
            do j = JS, JE
            do i = IS, IS+IHALO-1
                n =  (j-JS) * IHALO &
                   + (i-IS) + 1
                sendpack_P2W(n,vid) = var(i,j)
            enddo
            enddo
        endif

        !--- packing packets to East
        if( PRC_next(PRC_E) /= MPI_PROC_NULL ) then
            do j = JS, JE
            do i = IE-IHALO+1, IE
                n =  (j-JS)         * IHALO &
                   + (i-IE+IHALO-1) + 1
                sendpack_P2E(n,vid) = var(i,j)
            enddo
            enddo
         endif

        ! To W HALO communicate
        if( PRC_next(PRC_W) /= MPI_PROC_NULL ) then
            call MPI_ISEND( sendpack_P2W(:,vid), datasize_2D_WE,       &
                            datatype, PRC_next(PRC_W), tag+3, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr )
            ireqc = ireqc + 1
        endif

        ! To E HALO communicate
        if( PRC_next(PRC_E) /= MPI_PROC_NULL ) then
            call MPI_ISEND( sendpack_P2E(:,vid), datasize_2D_WE,       &
                            datatype, PRC_next(PRC_E), tag+4, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr )
            ireqc = ireqc + 1
        endif

        ! To N HALO communicate
        if( PRC_next(PRC_N) /= MPI_PROC_NULL ) then
            call MPI_ISEND( var(:,JE-JHALO+1:JE), datasize_2D_NS4,        &
                            datatype, PRC_next(PRC_N), tag+1, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr    )
            ireqc = ireqc + 1
        endif

        ! To S HALO communicate
        if( PRC_next(PRC_S) /= MPI_PROC_NULL ) then
            call MPI_ISEND( var(:,JS:JS+JHALO-1), datasize_2D_NS4,        &
                            datatype, PRC_next(PRC_S), tag+2, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr    )
            ireqc = ireqc + 1
        endif

    endif

    ireq_cnt(vid) = ireqc - 1

    call TIME_rapend  ('COMM vars MPI')

    return
  end subroutine COMM_vars_2D

  !-----------------------------------------------------------------------------
  subroutine COMM_vars8_2D(var, vid)
    use mod_process, only : &
       PRC_next, &
       PRC_W,    &
       PRC_N,    &
       PRC_E,    &
       PRC_S,    &
       PRC_NW,   &
       PRC_NE,   &
       PRC_SW,   &
       PRC_SE
    implicit none

    real(RP), intent(inout) :: var(:,:)
    integer, intent(in)    :: vid

    integer :: ireqc, tag, tagc

    integer :: ierr
    integer :: i, j, n
    !---------------------------------------------------------------------------

    tag   = vid * 100
    ireqc = 1

    call TIME_rapstart('COMM vars MPI')

    if( IsAllPeriodic ) then
    !--- periodic condition
        !-- From 8-Direction HALO communicate
        ! From SE
        tagc = 0
        do j = JS-JHALO, JS-1
            call MPI_IRECV( var(IE+1,j), datasize_2D_4C,                      &
                            datatype, PRC_next(PRC_SE), tag+tagc, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
            ireqc = ireqc + 1
            tagc  = tagc  + 1
        enddo
        ! From SW
        tagc = 10
        do j = JS-JHALO, JS-1
            call MPI_IRECV( var(IS-IHALO,j), datasize_2D_4C,                  &
                            datatype, PRC_next(PRC_SW), tag+tagc, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
            ireqc = ireqc + 1
            tagc  = tagc  + 1
        enddo
        ! From NE
        tagc = 20
        do j = JE+1, JE+JHALO
            call MPI_IRECV( var(IE+1,j), datasize_2D_4C,                      &
                            datatype, PRC_next(PRC_NE), tag+tagc, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
            ireqc = ireqc + 1
            tagc  = tagc  + 1
        enddo
        ! From NW
        tagc = 30
        do j = JE+1, JE+JHALO
            call MPI_IRECV( var(IS-IHALO,j), datasize_2D_4C,                  &
                            datatype, PRC_next(PRC_NW), tag+tagc, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
            ireqc = ireqc + 1
            tagc  = tagc  + 1
        enddo
        ! From S
        tagc = 40
        do j = JS-JHALO, JS-1
            call MPI_IRECV( var(IS,j), datasize_2D_NS8,                      &
                            datatype, PRC_next(PRC_S), tag+tagc, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr       )
             ireqc = ireqc + 1
             tagc  = tagc  + 1
        enddo
        ! From N
        tagc = 50
        do j = JE+1, JE+JHALO
            call MPI_IRECV( var(IS,j), datasize_2D_NS8,                      &
                            datatype, PRC_next(PRC_N), tag+tagc, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr       )
            ireqc = ireqc + 1
            tagc  = tagc  + 1
        enddo
        ! From E
        call MPI_IRECV( recvpack_E2P(:,vid), datasize_2D_WE,           &
                        datatype, PRC_next(PRC_E), tag+60, &
                        MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr     )
        ireqc = ireqc + 1
        ! From W
        call MPI_IRECV( recvpack_W2P(:,vid), datasize_2D_WE,           &
                        datatype, PRC_next(PRC_W), tag+70, &
                        MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr     )
        ireqc = ireqc + 1

        !-- To 8-Direction HALO communicate
        !--- packing packets to West
        do j = JS, JE
        do i = IS, IS+IHALO-1
            n =  (j-JS) * IHALO &
               + (i-IS) + 1
            sendpack_P2W(n,vid) = var(i,j)
        enddo
        enddo

        !--- packing packets to East
        do j = JS, JE
        do i = IE-IHALO+1, IE
            n =  (j-JS)         * IHALO &
               + (i-IE+IHALO-1) + 1
            sendpack_P2E(n,vid) = var(i,j)
        enddo
        enddo

        ! To W HALO communicate
        call MPI_ISEND( sendpack_P2W(:,vid), datasize_2D_WE,            &
                        datatype, PRC_next(PRC_W), tag+60, &
                        MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr     )
        ireqc = ireqc + 1

        ! To E HALO communicate
        call MPI_ISEND( sendpack_P2E(:,vid), datasize_2D_WE,           &
                        datatype, PRC_next(PRC_E), tag+70, &
                        MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr     )
        ireqc = ireqc + 1

        ! To N HALO communicate
        tagc = 40
        do j = JE-JHALO+1, JE
            call MPI_ISEND( var(IS,j), datasize_2D_NS8,                      &
                            datatype, PRC_next(PRC_N), tag+tagc, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr       )
            ireqc = ireqc + 1
            tagc  = tagc  + 1
        enddo

        ! To S HALO communicate
        tagc = 50
        do j = JS, JS+JHALO-1
            call MPI_ISEND( var(IS,j), datasize_2D_NS8,                      &
                            datatype, PRC_next(PRC_S), tag+tagc, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr       )
            ireqc = ireqc + 1
            tagc  = tagc  + 1
        enddo

        ! To NW HALO communicate
        tagc = 0
        do j = JE-JHALO+1, JE
            call MPI_ISEND( var(IS,j), datasize_2D_4C,                        &
                            datatype, PRC_next(PRC_NW), tag+tagc, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
            ireqc = ireqc + 1
            tagc  = tagc  + 1
        enddo

        ! To NE HALO communicate
        tagc = 10
        do j = JE-JHALO+1, JE
            call MPI_ISEND( var(IE-IHALO+1,j), datasize_2D_4C,                &
                            datatype, PRC_next(PRC_NE), tag+tagc, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
            ireqc = ireqc + 1
            tagc  = tagc  + 1
        enddo

        ! To SW HALO communicate
        tagc = 20
        do j = JS, JS+JHALO-1
            call MPI_ISEND( var(IS,j), datasize_2D_4C,                        &
                            datatype, PRC_next(PRC_SW), tag+tagc, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
            ireqc = ireqc + 1
            tagc  = tagc  + 1
        enddo

        ! To SE HALO communicate
        tagc = 30
        do j = JS, JS+JHALO-1
            call MPI_ISEND( var(IE-IHALO+1,j), datasize_2D_4C,                &
                            datatype, PRC_next(PRC_SE), tag+tagc, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
            ireqc = ireqc + 1
            tagc  = tagc  + 1
        enddo
    else
    !--- non-periodic condition
        !-- From 8-Direction HALO communicate
        ! From SE
        if( PRC_next(PRC_SE) /= MPI_PROC_NULL ) then
            tagc = 0
            do j = JS-JHALO, JS-1
                call MPI_IRECV( var(IE+1,j), datasize_2D_4C,                      &
                                datatype, PRC_next(PRC_SE), tag+tagc, &
                                MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
                ireqc = ireqc + 1
                tagc  = tagc  + 1
            enddo
        endif

        ! From SW
        if( PRC_next(PRC_SW) /= MPI_PROC_NULL ) then
            tagc = 10
            do j = JS-JHALO, JS-1
                call MPI_IRECV( var(IS-IHALO,j), datasize_2D_4C,                  &
                                datatype, PRC_next(PRC_SW), tag+tagc, &
                                MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
                ireqc = ireqc + 1
                tagc  = tagc  + 1
            enddo
        endif

        ! From NE
        if( PRC_next(PRC_NE) /= MPI_PROC_NULL ) then
            tagc = 20
            do j = JE+1, JE+JHALO
                call MPI_IRECV( var(IE+1,j), datasize_2D_4C,                      &
                                datatype, PRC_next(PRC_NE), tag+tagc, &
                                MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
                ireqc = ireqc + 1
                tagc  = tagc  + 1
            enddo
        endif

        ! From NW
        if( PRC_next(PRC_NW) /= MPI_PROC_NULL ) then
            tagc = 30
            do j = JE+1, JE+JHALO
                call MPI_IRECV( var(IS-IHALO,j), datasize_2D_4C,                  &
                                datatype, PRC_next(PRC_NW), tag+tagc, &
                                MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
                ireqc = ireqc + 1
                tagc  = tagc  + 1
            enddo
        endif

        ! From S
        if( PRC_next(PRC_S) /= MPI_PROC_NULL ) then
            tagc = 40
            do j = JS-JHALO, JS-1
                call MPI_IRECV( var(IS,j), datasize_2D_NS8,                      &
                                datatype, PRC_next(PRC_S), tag+tagc, &
                                MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr       )
                 ireqc = ireqc + 1
                 tagc  = tagc  + 1
            enddo
        endif

        ! From N
        if( PRC_next(PRC_N) /= MPI_PROC_NULL ) then
            tagc = 50
            do j = JE+1, JE+JHALO
                call MPI_IRECV( var(IS,j), datasize_2D_NS8,                      &
                                datatype, PRC_next(PRC_N), tag+tagc, &
                                MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr       )
                ireqc = ireqc + 1
                tagc  = tagc  + 1
            enddo
        endif

        ! From E
        if( PRC_next(PRC_E) /= MPI_PROC_NULL ) then
            call MPI_IRECV( recvpack_E2P(:,vid), datasize_2D_WE,             &
                            datatype, PRC_next(PRC_E), tag+60, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr     )
            ireqc = ireqc + 1
        endif

        ! From W
        if( PRC_next(PRC_W) /= MPI_PROC_NULL ) then
            call MPI_IRECV( recvpack_W2P(:,vid), datasize_2D_WE,           &
                            datatype, PRC_next(PRC_W), tag+70, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr     )
            ireqc = ireqc + 1
        endif

        !-- To 8-Direction HALO communicate
        !--- packing packets to West
        if( PRC_next(PRC_W) /= MPI_PROC_NULL ) then
            do j = JS, JE
            do i = IS, IS+IHALO-1
                n =  (j-JS) * IHALO &
                   + (i-IS) + 1
                sendpack_P2W(n,vid) = var(i,j)
            enddo
            enddo
        endif

        !--- packing packets to East
        if( PRC_next(PRC_E) /= MPI_PROC_NULL ) then
            do j = JS, JE
            do i = IE-IHALO+1, IE
                n =  (j-JS)         * IHALO &
                   + (i-IE+IHALO-1) + 1
                sendpack_P2E(n,vid) = var(i,j)
            enddo
            enddo
        endif

        ! To W HALO communicate
        if( PRC_next(PRC_W) /= MPI_PROC_NULL ) then
            call MPI_ISEND( sendpack_P2W(:,vid), datasize_2D_WE,           &
                            datatype, PRC_next(PRC_W), tag+60, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr     )
            ireqc = ireqc + 1
        endif

        ! To E HALO communicate
        if( PRC_next(PRC_E) /= MPI_PROC_NULL ) then
            call MPI_ISEND( sendpack_P2E(:,vid), datasize_2D_WE,           &
                            datatype, PRC_next(PRC_E), tag+70, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr     )
            ireqc = ireqc + 1
        endif

        ! To N HALO communicate
        if( PRC_next(PRC_N) /= MPI_PROC_NULL ) then
            tagc = 40
            do j = JE-JHALO+1, JE
                call MPI_ISEND( var(IS,j), datasize_2D_NS8,                      &
                                datatype, PRC_next(PRC_N), tag+tagc, &
                                MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr       )
                ireqc = ireqc + 1
                tagc  = tagc  + 1
            enddo
        endif

        ! To S HALO communicate
        if( PRC_next(PRC_S) /= MPI_PROC_NULL ) then
            tagc = 50
            do j = JS, JS+JHALO-1
                call MPI_ISEND( var(IS,j), datasize_2D_NS8,                      &
                                datatype, PRC_next(PRC_S), tag+tagc, &
                                MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr       )
                ireqc = ireqc + 1
                tagc  = tagc  + 1
            enddo
        endif

        ! To NW HALO communicate
        if( PRC_next(PRC_NW) /= MPI_PROC_NULL ) then
            tagc = 0
            do j = JE-JHALO+1, JE
                call MPI_ISEND( var(IS,j), datasize_2D_4C,                        &
                                datatype, PRC_next(PRC_NW), tag+tagc, &
                                MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
                ireqc = ireqc + 1
                tagc  = tagc  + 1
            enddo
        endif

        ! To NE HALO communicate
        if( PRC_next(PRC_NE) /= MPI_PROC_NULL ) then
            tagc = 10
            do j = JE-JHALO+1, JE
                call MPI_ISEND( var(IE-IHALO+1,j), datasize_2D_4C,                &
                                datatype, PRC_next(PRC_NE), tag+tagc, &
                                MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
                ireqc = ireqc + 1
                tagc  = tagc  + 1
            enddo
        endif

        ! To SW HALO communicate
        if( PRC_next(PRC_SW) /= MPI_PROC_NULL ) then
            tagc = 20
            do j = JS, JS+JHALO-1
                call MPI_ISEND( var(IS,j), datasize_2D_4C,                        &
                                datatype, PRC_next(PRC_SW), tag+tagc, &
                                MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
                ireqc = ireqc + 1
                tagc  = tagc  + 1
            enddo
        endif

        ! To SE HALO communicate
        if( PRC_next(PRC_SE) /= MPI_PROC_NULL ) then
            tagc = 30
            do j = JS, JS+JHALO-1
                call MPI_ISEND( var(IE-IHALO+1,j), datasize_2D_4C,                &
                                datatype, PRC_next(PRC_SE), tag+tagc, &
                                MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
                ireqc = ireqc + 1
                tagc  = tagc  + 1
            enddo
        endif

    endif

    ireq_cnt(vid) = ireqc - 1

    call TIME_rapend  ('COMM vars MPI')

    return
  end subroutine COMM_vars8_2D

  !-----------------------------------------------------------------------------
  subroutine COMM_wait_2D(var, vid)
    use mod_process, only : &
       PRC_next, &
       PRC_W,    &
       PRC_N,    &
       PRC_E,    &
       PRC_S

    implicit none

    real(RP), intent(inout) :: var(:,:)
    integer, intent(in)    :: vid

    integer :: ierr
    integer :: i, j, n
    !---------------------------------------------------------------------------

    call TIME_rapstart('COMM wait MPI')

    !--- wait packets
    call MPI_WAITALL(ireq_cnt(vid), ireq_list(1:ireq_cnt(vid),vid), MPI_STATUSES_IGNORE, ierr)

    if( IsAllPeriodic ) then
    !--- periodic condition
        !--- unpacking packets from East
        do j = JS, JE
        do i = IE+1, IE+IHALO
           n = (j-JS)   * IHALO &
             + (i-IE-1) + 1
           var(i,j) = recvpack_E2P(n,vid)
        enddo
        enddo

        !--- unpacking packets from West
        do j = JS, JE
        do i = IS-IHALO, IS-1
           n = (j-JS)       * IHALO &
             + (i-IS+IHALO) + 1
           var(i,j) = recvpack_W2P(n,vid)
        enddo
        enddo

    else
    !--- non-periodic condition

        !--- copy inner data to HALO(North)
        if( PRC_next(PRC_N) == MPI_PROC_NULL ) then
            do j = JE+1, JE+JHALO
            do i = IS, IE
               var(i,j) = var(i,JE)
            enddo
            enddo
        endif

        !--- copy inner data to HALO(South)
        if( PRC_next(PRC_S) == MPI_PROC_NULL ) then
            do j = JS-JHALO, JS-1
            do i = IS, IE
               var(i,j) = var(i,JS)
            enddo
            enddo
        endif

        !--- unpacking packets from East / copy inner data to HALO(East)
        if( PRC_next(PRC_E) /= MPI_PROC_NULL ) then
            do j = JS, JE
            do i = IE+1, IE+IHALO
               n = (j-JS)   * IHALO &
                 + (i-IE-1) + 1
               var(i,j) = recvpack_E2P(n,vid)
            enddo
            enddo
        else
            do j = JS, JE
            do i = IE+1, IE+IHALO
               var(i,j) = var(IE,j)
            enddo
            enddo
        endif

        !--- unpacking packets from West / copy inner data to HALO(West)
        if( PRC_next(PRC_W) /= MPI_PROC_NULL ) then
            do j = JS, JE
            do i = IS-IHALO, IS-1
               n = (j-JS)       * IHALO &
                 + (i-IS+IHALO) + 1
               var(i,j) = recvpack_W2P(n,vid)
            enddo
            enddo
        else
            do j = JS, JE
            do i = IS-IHALO, IS-1
               var(i,j) = var(IS,j)
            enddo
            enddo
        endif

        !--- copy inner data to HALO(NorthWest)
        if( PRC_next(PRC_N) == MPI_PROC_NULL .and. PRC_next(PRC_W) == MPI_PROC_NULL) then
            do j = JE+1, JE+JHALO
            do i = IS-IHALO, IS-1
               var(i,j) = var(IS,JE)
            enddo
            enddo
        else if ( PRC_next(PRC_N) == MPI_PROC_NULL) then
            do j = JE+1, JE+JHALO
            do i = IS-IHALO, IS-1
               var(i,j) = var(i,JE)
            enddo
            enddo
        else if ( PRC_next(PRC_W) == MPI_PROC_NULL) then
            do j = JE+1, JE+JHALO
            do i = IS-IHALO, IS-1
               var(i,j) = var(IS,j)
            enddo
            enddo
        endif

        !--- copy inner data to HALO(SouthWest)
        if( PRC_next(PRC_S) == MPI_PROC_NULL .and. PRC_next(PRC_W) == MPI_PROC_NULL) then
            do j = JS-IHALO, JS-1
            do i = IS-IHALO, IS-1
               var(i,j) = var(IS,JS)
            enddo
            enddo
        else if ( PRC_next(PRC_S) == MPI_PROC_NULL) then
            do j = JS-IHALO, JS-1
            do i = IS-IHALO, IS-1
               var(i,j) = var(i,JS)
            enddo
            enddo
        else if ( PRC_next(PRC_W) == MPI_PROC_NULL) then
            do j = JS-IHALO, JS-1
            do i = IS-IHALO, IS-1
               var(i,j) = var(IS,j)
            enddo
            enddo
        endif

        !--- copy inner data to HALO(NorthEast)
        if( PRC_next(PRC_N) == MPI_PROC_NULL .and. PRC_next(PRC_E) == MPI_PROC_NULL) then
            do j = JE+1, JE+JHALO
            do i = IE+1, IE+IHALO
               var(i,j) = var(IE,JE)
            enddo
            enddo
        else if ( PRC_next(PRC_N) == MPI_PROC_NULL) then
            do j = JE+1, JE+JHALO
            do i = IE+1, IE+IHALO
               var(i,j) = var(i,JE)
            enddo
            enddo
        else if ( PRC_next(PRC_E) == MPI_PROC_NULL) then
            do j = JE+1, JE+JHALO
            do i = IE+1, IE+IHALO
               var(i,j) = var(IE,j)
            enddo
            enddo
        endif

        !--- copy inner data to HALO(SouthEast)
        if( PRC_next(PRC_S) == MPI_PROC_NULL .and. PRC_next(PRC_E) == MPI_PROC_NULL) then
            do j = JS-IHALO, JS-1
            do i = IE+1, IE+IHALO
               var(i,j) = var(IE,JS)
            enddo
            enddo
        else if ( PRC_next(PRC_S) == MPI_PROC_NULL) then
            do j = JS-IHALO, JS-1
            do i = IE+1, IE+IHALO
               var(i,j) = var(i,JS)
            enddo
            enddo
        else if ( PRC_next(PRC_E) == MPI_PROC_NULL) then
            do j = JS-IHALO, JS-1
            do i = IE+1, IE+IHALO
               var(i,j) = var(IE,j)
            enddo
            enddo
        endif

    endif


    call TIME_rapend  ('COMM wait MPI')

    return
  end subroutine COMM_wait_2D

  !-----------------------------------------------------------------------------
  subroutine COMM_vars_r4(var, vid)
    use mod_process, only : &
       PRC_next, &
       PRC_W,    &
       PRC_N,    &
       PRC_E,    &
       PRC_S
    implicit none

    real(4), intent(inout) :: var(:,:,:)
    integer, intent(in)    :: vid

    integer :: ireqc, tag

    integer :: ierr
    integer :: i, j, k, n
    !---------------------------------------------------------------------------

    tag = vid * 100
    ireqc = 1

    call TIME_rapstart('COMM vars(real4) MPI')

    if( IsAllPeriodic ) then
    !--- periodic condition
        !-- From 4-Direction HALO communicate
        ! From S
        call MPI_IRECV( var(:,:,JS-JHALO:JS-1), datasize_NS4,         &
                        MPI_REAL            , PRC_next(PRC_S), tag+1, &
                        MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr    )
        ireqc = ireqc + 1

        ! From N
        call MPI_IRECV( var(:,:,JE+1:JE+JHALO), datasize_NS4,         &
                        MPI_REAL            , PRC_next(PRC_N), tag+2, &
                        MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr    )
        ireqc = ireqc + 1

        ! From E
        call MPI_IRECV( recvpack_E2P_r4(:,vid), datasize_WE,          &
                        MPI_REAL            , PRC_next(PRC_E), tag+3, &
                        MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr    )
        ireqc = ireqc + 1

        ! From W
        call MPI_IRECV( recvpack_W2P_r4(:,vid), datasize_WE,          &
                        MPI_REAL            , PRC_next(PRC_W), tag+4, &
                        MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr    )
        ireqc = ireqc + 1

        !-- To 4-Direction HALO communicate
        !--- packing packets to West
        do j = JS, JE
        do i = IS, IS+IHALO-1
        do k = 1, KA
            n =  (j-JS) * KA * IHALO &
               + (i-IS) * KA         &
               + k
            sendpack_P2W_r4(n,vid) = var(k,i,j)
        enddo
        enddo
        enddo

        !--- packing packets to East
        do j = JS, JE
        do i = IE-IHALO+1, IE
        do k = 1, KA
            n =  (j-JS)         * KA * IHALO &
               + (i-IE+IHALO-1) * KA         &
               + k
            sendpack_P2E_r4(n,vid) = var(k,i,j)
        enddo
        enddo
        enddo

        ! To W HALO communicate
        call MPI_ISEND( sendpack_P2W_r4(:,vid), datasize_WE,          &
                        MPI_REAL            , PRC_next(PRC_W), tag+3, &
                        MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr    )
        ireqc = ireqc + 1

        ! To E HALO communicate
        call MPI_ISEND( sendpack_P2E_r4(:,vid), datasize_WE,          &
                        MPI_REAL            , PRC_next(PRC_E), tag+4, &
                        MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr    )
        ireqc = ireqc + 1

        ! To N HALO communicate
        call MPI_ISEND( var(:,:,JE-JHALO+1:JE), datasize_NS4,         &
                        MPI_REAL            , PRC_next(PRC_N), tag+1, &
                        MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr    )
        ireqc = ireqc + 1

        ! To S HALO communicate
        call MPI_ISEND( var(:,:,JS:JS+JHALO-1), datasize_NS4,         &
                        MPI_REAL            , PRC_next(PRC_S), tag+2, &
                        MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr    )
        ireqc = ireqc + 1
    else
    !--- non-periodic condition
        !-- From 4-Direction HALO communicate
        ! From S
        if( PRC_next(PRC_S) /= MPI_PROC_NULL ) then
            call MPI_IRECV( var(:,:,JS-JHALO:JS-1), datasize_NS4,         &
                            MPI_REAL            , PRC_next(PRC_S), tag+1, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr    )
            ireqc = ireqc + 1
        endif

        ! From N
        if( PRC_next(PRC_N) /= MPI_PROC_NULL ) then
            call MPI_IRECV( var(:,:,JE+1:JE+JHALO), datasize_NS4,         &
                            MPI_REAL            , PRC_next(PRC_N), tag+2, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr    )
            ireqc = ireqc + 1
        endif

        ! From E
        if( PRC_next(PRC_E) /= MPI_PROC_NULL ) then
            call MPI_IRECV( recvpack_E2P_r4(:,vid), datasize_WE,          &
                            MPI_REAL            , PRC_next(PRC_E), tag+3, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr    )
            ireqc = ireqc + 1
        endif

        ! From W
        if( PRC_next(PRC_W) /= MPI_PROC_NULL ) then
            call MPI_IRECV( recvpack_W2P_r4(:,vid), datasize_WE,          &
                            MPI_REAL            , PRC_next(PRC_W), tag+4, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr    )
            ireqc = ireqc + 1
        endif

        !-- To 4-Direction HALO communicate
        !--- packing packets to West
        if( PRC_next(PRC_W) /= MPI_PROC_NULL ) then
            do j = JS, JE
            do i = IS, IS+IHALO-1
            do k = 1, KA
                n =  (j-JS) * KA * IHALO &
                   + (i-IS) * KA         &
                   + k
                sendpack_P2W_r4(n,vid) = var(k,i,j)
            enddo
            enddo
            enddo
        endif

        !--- packing packets to East
        if( PRC_next(PRC_E) /= MPI_PROC_NULL ) then
            do j = JS, JE
            do i = IE-IHALO+1, IE
            do k = 1, KA
                n =  (j-JS)         * KA * IHALO &
                   + (i-IE+IHALO-1) * KA         &
                   + k
                sendpack_P2E_r4(n,vid) = var(k,i,j)
            enddo
            enddo
            enddo
        endif

        ! To W HALO communicate
        if( PRC_next(PRC_W) /= MPI_PROC_NULL ) then
            call MPI_ISEND( sendpack_P2W_r4(:,vid), datasize_WE,          &
                            MPI_REAL            , PRC_next(PRC_W), tag+3, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr    )
            ireqc = ireqc + 1
        endif

        ! To E HALO communicate
        if( PRC_next(PRC_E) /= MPI_PROC_NULL ) then
            call MPI_ISEND( sendpack_P2E_r4(:,vid), datasize_WE,          &
                            MPI_REAL            , PRC_next(PRC_E), tag+4, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr    )
            ireqc = ireqc + 1
        endif

        ! To N HALO communicate
        if( PRC_next(PRC_N) /= MPI_PROC_NULL ) then
            call MPI_ISEND( var(:,:,JE-JHALO+1:JE), datasize_NS4,         &
                            MPI_REAL            , PRC_next(PRC_N), tag+1, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr    )
            ireqc = ireqc + 1
        endif

        ! To S HALO communicate
        if( PRC_next(PRC_S) /= MPI_PROC_NULL ) then
            call MPI_ISEND( var(:,:,JS:JS+JHALO-1), datasize_NS4,         &
                            MPI_REAL            , PRC_next(PRC_S), tag+2, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr    )
            ireqc = ireqc + 1
        endif

    endif

    ireq_cnt(vid) = ireqc - 1

    call TIME_rapend  ('COMM vars(real4) MPI')

    return
  end subroutine COMM_vars_r4

  !-----------------------------------------------------------------------------
  subroutine COMM_vars8_r4(var, vid)
    use mod_process, only : &
       PRC_next, &
       PRC_W,    &
       PRC_N,    &
       PRC_E,    &
       PRC_S,    &
       PRC_NW,   &
       PRC_NE,   &
       PRC_SW,   &
       PRC_SE
    implicit none

    real(4), intent(inout) :: var(:,:,:)
    integer, intent(in)    :: vid

    integer :: ireqc, tag, tagc

    integer :: ierr
    integer :: i, j, k, n
    !---------------------------------------------------------------------------

    tag   = vid * 100
    ireqc = 1

    call TIME_rapstart('COMM vars(real4) MPI')

    if( IsAllPeriodic ) then
    !--- periodic condition
        !-- From 8-Direction HALO communicate
        ! From SE
        tagc = 0
        do j = JS-JHALO, JS-1
            call MPI_IRECV( var(1,IE+1,j), datasize_4C,                       &
                            MPI_REAL            , PRC_next(PRC_SE), tag+tagc, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
            ireqc = ireqc + 1
            tagc  = tagc  + 1
        enddo
        ! From SW
        tagc = 10
        do j = JS-JHALO, JS-1
            call MPI_IRECV( var(1,IS-IHALO,j), datasize_4C,                   &
                            MPI_REAL            , PRC_next(PRC_SW), tag+tagc, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
            ireqc = ireqc + 1
            tagc  = tagc  + 1
        enddo
        ! From NE
        tagc = 20
        do j = JE+1, JE+JHALO
            call MPI_IRECV( var(1,IE+1,j), datasize_4C,                       &
                            MPI_REAL            , PRC_next(PRC_NE), tag+tagc, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
            ireqc = ireqc + 1
            tagc  = tagc  + 1
        enddo
        ! From NW
        tagc = 30
        do j = JE+1, JE+JHALO
            call MPI_IRECV( var(1,IS-IHALO,j), datasize_4C,                   &
                            MPI_REAL            , PRC_next(PRC_NW), tag+tagc, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
            ireqc = ireqc + 1
            tagc  = tagc  + 1
        enddo
        ! From S
        tagc = 40
        do j = JS-JHALO, JS-1
            call MPI_IRECV( var(1,IS,j), datasize_NS8,                       &
                            MPI_REAL            , PRC_next(PRC_S), tag+tagc, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr       )
             ireqc = ireqc + 1
             tagc  = tagc  + 1
        enddo
        ! From N
        tagc = 50
        do j = JE+1, JE+JHALO
            call MPI_IRECV( var(1,IS,j), datasize_NS8,                       &
                            MPI_REAL            , PRC_next(PRC_N), tag+tagc, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr       )
            ireqc = ireqc + 1
            tagc  = tagc  + 1
        enddo
        ! From E
        call MPI_IRECV( recvpack_E2P_r4(:,vid), datasize_WE,           &
                        MPI_REAL            , PRC_next(PRC_E), tag+60, &
                        MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr     )
        ireqc = ireqc + 1
        ! From W
        call MPI_IRECV( recvpack_W2P_r4(:,vid), datasize_WE,           &
                        MPI_REAL            , PRC_next(PRC_W), tag+70, &
                        MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr     )
        ireqc = ireqc + 1

        !-- To 8-Direction HALO communicate
        !--- packing packets to West
        do j = JS, JE
        do i = IS, IS+IHALO-1
        do k = 1, KA
            n =  (j-JS) * KA * IHALO &
               + (i-IS) * KA         &
               + k
            sendpack_P2W_r4(n,vid) = var(k,i,j)
        enddo
        enddo
        enddo

        !--- packing packets to East
        do j = JS, JE
        do i = IE-IHALO+1, IE
        do k = 1, KA
            n =  (j-JS)         * KA * IHALO &
               + (i-IE+IHALO-1) * KA         &
               + k
            sendpack_P2E_r4(n,vid) = var(k,i,j)
        enddo
        enddo
        enddo

        ! To W HALO communicate
        call MPI_ISEND( sendpack_P2W_r4(:,vid), datasize_WE,           &
                        MPI_REAL            , PRC_next(PRC_W), tag+60, &
                        MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr     )
        ireqc = ireqc + 1

        ! To E HALO communicate
        call MPI_ISEND( sendpack_P2E_r4(:,vid), datasize_WE,           &
                        MPI_REAL            , PRC_next(PRC_E), tag+70, &
                        MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr     )
        ireqc = ireqc + 1

        ! To N HALO communicate
        tagc = 40
        do j = JE-JHALO+1, JE
            call MPI_ISEND( var(1,IS,j), datasize_NS8,                       &
                            MPI_REAL            , PRC_next(PRC_N), tag+tagc, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr       )
            ireqc = ireqc + 1
            tagc  = tagc  + 1
        enddo

        ! To S HALO communicate
        tagc = 50
        do j = JS, JS+JHALO-1
            call MPI_ISEND( var(1,IS,j), datasize_NS8,                       &
                            MPI_REAL            , PRC_next(PRC_S), tag+tagc, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr       )
            ireqc = ireqc + 1
            tagc  = tagc  + 1
        enddo

        ! To NW HALO communicate
        tagc = 0
        do j = JE-JHALO+1, JE
            call MPI_ISEND( var(1,IS,j), datasize_4C,                         &
                            MPI_REAL            , PRC_next(PRC_NW), tag+tagc, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
            ireqc = ireqc + 1
            tagc  = tagc  + 1
        enddo

        ! To NE HALO communicate
        tagc = 10
        do j = JE-JHALO+1, JE
            call MPI_ISEND( var(1,IE-IHALO+1,j), datasize_4C,                 &
                            MPI_REAL            , PRC_next(PRC_NE), tag+tagc, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
            ireqc = ireqc + 1
            tagc  = tagc  + 1
        enddo

        ! To SW HALO communicate
        tagc = 20
        do j = JS, JS+JHALO-1
            call MPI_ISEND( var(1,IS,j), datasize_4C,                         &
                            MPI_REAL            , PRC_next(PRC_SW), tag+tagc, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
            ireqc = ireqc + 1
            tagc  = tagc  + 1
        enddo

        ! To SE HALO communicate
        tagc = 30
        do j = JS, JS+JHALO-1
            call MPI_ISEND( var(1,IE-IHALO+1,j), datasize_4C,                 &
                            MPI_REAL            , PRC_next(PRC_SE), tag+tagc, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
            ireqc = ireqc + 1
            tagc  = tagc  + 1
        enddo
    else
    !--- non-periodic condition
        !-- From 8-Direction HALO communicate
        ! From SE
        if( PRC_next(PRC_SE) /= MPI_PROC_NULL ) then
            tagc = 0
            do j = JS-JHALO, JS-1
                call MPI_IRECV( var(1,IE+1,j), datasize_4C,                       &
                                MPI_REAL            , PRC_next(PRC_SE), tag+tagc, &
                                MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
                ireqc = ireqc + 1
                tagc  = tagc  + 1
            enddo
        endif

        ! From SW
        if( PRC_next(PRC_SW) /= MPI_PROC_NULL ) then
            tagc = 10
            do j = JS-JHALO, JS-1
                call MPI_IRECV( var(1,IS-IHALO,j), datasize_4C,                   &
                                MPI_REAL            , PRC_next(PRC_SW), tag+tagc, &
                                MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
                ireqc = ireqc + 1
                tagc  = tagc  + 1
            enddo
        endif

        ! From NE
        if( PRC_next(PRC_NE) /= MPI_PROC_NULL ) then
            tagc = 20
            do j = JE+1, JE+JHALO
                call MPI_IRECV( var(1,IE+1,j), datasize_4C,                       &
                                MPI_REAL            , PRC_next(PRC_NE), tag+tagc, &
                                MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
                ireqc = ireqc + 1
                tagc  = tagc  + 1
            enddo
        endif

        ! From NW
        if( PRC_next(PRC_NW) /= MPI_PROC_NULL ) then
            tagc = 30
            do j = JE+1, JE+JHALO
                call MPI_IRECV( var(1,IS-IHALO,j), datasize_4C,                   &
                                MPI_REAL            , PRC_next(PRC_NW), tag+tagc, &
                                MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
                ireqc = ireqc + 1
                tagc  = tagc  + 1
            enddo
        endif

        ! From S
        if( PRC_next(PRC_S) /= MPI_PROC_NULL ) then
            tagc = 40
            do j = JS-JHALO, JS-1
                call MPI_IRECV( var(1,IS,j), datasize_NS8,                       &
                                MPI_REAL            , PRC_next(PRC_S), tag+tagc, &
                                MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr       )
                 ireqc = ireqc + 1
                 tagc  = tagc  + 1
            enddo
        endif

        ! From N
        if( PRC_next(PRC_N) /= MPI_PROC_NULL ) then
            tagc = 50
            do j = JE+1, JE+JHALO
                call MPI_IRECV( var(1,IS,j), datasize_NS8,                       &
                                MPI_REAL            , PRC_next(PRC_N), tag+tagc, &
                                MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr       )
                ireqc = ireqc + 1
                tagc  = tagc  + 1
            enddo
        endif

        ! From E
        if( PRC_next(PRC_E) /= MPI_PROC_NULL ) then
            call MPI_IRECV( recvpack_E2P_r4(:,vid), datasize_WE,           &
                            MPI_REAL            , PRC_next(PRC_E), tag+60, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr     )
            ireqc = ireqc + 1
        endif

        ! From W
        if( PRC_next(PRC_W) /= MPI_PROC_NULL ) then
            call MPI_IRECV( recvpack_W2P_r4(:,vid), datasize_WE,           &
                            MPI_REAL            , PRC_next(PRC_W), tag+70, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr     )
            ireqc = ireqc + 1
        endif


        !-- To 8-Direction HALO communicate
        !--- packing packets to West
        if( PRC_next(PRC_W) /= MPI_PROC_NULL ) then
            do j = JS, JE
            do i = IS, IS+IHALO-1
            do k = 1, KA
                n =  (j-JS) * KA * IHALO &
                   + (i-IS) * KA         &
                   + k
                sendpack_P2W_r4(n,vid) = var(k,i,j)
            enddo
            enddo
            enddo
        endif

        !--- packing packets to East
        if( PRC_next(PRC_E) /= MPI_PROC_NULL ) then
            do j = JS, JE
            do i = IE-IHALO+1, IE
            do k = 1, KA
                n =  (j-JS)         * KA * IHALO &
                   + (i-IE+IHALO-1) * KA         &
                   + k
                sendpack_P2E_r4(n,vid) = var(k,i,j)
                n = n + 1
            enddo
            enddo
            enddo
        endif

        ! To W HALO communicate
        if( PRC_next(PRC_W) /= MPI_PROC_NULL ) then
            call MPI_ISEND( sendpack_P2W_r4(:,vid), datasize_WE,           &
                            MPI_REAL            , PRC_next(PRC_W), tag+60, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr     )
            ireqc = ireqc + 1
        endif

        ! To E HALO communicate
        if( PRC_next(PRC_E) /= MPI_PROC_NULL ) then
            call MPI_ISEND( sendpack_P2E_r4(:,vid), datasize_WE,           &
                            MPI_REAL            , PRC_next(PRC_E), tag+70, &
                            MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr     )
            ireqc = ireqc + 1
        endif

        ! To N HALO communicate
        if( PRC_next(PRC_N) /= MPI_PROC_NULL ) then
            tagc = 40
            do j = JE-JHALO+1, JE
                call MPI_ISEND( var(1,IS,j), datasize_NS8,                       &
                                MPI_REAL            , PRC_next(PRC_N), tag+tagc, &
                                MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr       )
                ireqc = ireqc + 1
                tagc  = tagc  + 1
            enddo
        endif

        ! To S HALO communicate
        if( PRC_next(PRC_S) /= MPI_PROC_NULL ) then
            tagc = 50
            do j = JS, JS+JHALO-1
                call MPI_ISEND( var(1,IS,j), datasize_NS8,                       &
                                MPI_REAL            , PRC_next(PRC_S), tag+tagc, &
                                MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr       )
                ireqc = ireqc + 1
                tagc  = tagc  + 1
            enddo
        endif

        ! To NW HALO communicate
        if( PRC_next(PRC_NW) /= MPI_PROC_NULL ) then
            tagc = 0
            do j = JE-JHALO+1, JE
                call MPI_ISEND( var(1,IS,j), datasize_4C,                         &
                                MPI_REAL            , PRC_next(PRC_NW), tag+tagc, &
                                MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
                ireqc = ireqc + 1
                tagc  = tagc  + 1
            enddo
        endif

        ! To NE HALO communicate
        if( PRC_next(PRC_NE) /= MPI_PROC_NULL ) then
            tagc = 10
            do j = JE-JHALO+1, JE
                call MPI_ISEND( var(1,IE-IHALO+1,j), datasize_4C,                 &
                                MPI_REAL            , PRC_next(PRC_NE), tag+tagc, &
                                MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
                ireqc = ireqc + 1
                tagc  = tagc  + 1
            enddo
        endif

        ! To SW HALO communicate
        if( PRC_next(PRC_SW) /= MPI_PROC_NULL ) then
            tagc = 20
            do j = JS, JS+JHALO-1
                call MPI_ISEND( var(1,IS,j), datasize_4C,                         &
                                MPI_REAL            , PRC_next(PRC_SW), tag+tagc, &
                                MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
                ireqc = ireqc + 1
                tagc  = tagc  + 1
            enddo
        endif

        ! To SE HALO communicate
        if( PRC_next(PRC_SE) /= MPI_PROC_NULL ) then
            tagc = 30
            do j = JS, JS+JHALO-1
                call MPI_ISEND( var(1,IE-IHALO+1,j), datasize_4C,                 &
                                MPI_REAL            , PRC_next(PRC_SE), tag+tagc, &
                                MPI_COMM_WORLD, ireq_list(ireqc,vid), ierr        )
                ireqc = ireqc + 1
                tagc  = tagc  + 1
            enddo
        endif

    endif

    ireq_cnt(vid) = ireqc - 1

    call TIME_rapend  ('COMM vars(real4) MPI')

    return
  end subroutine COMM_vars8_r4

  !-----------------------------------------------------------------------------
  subroutine COMM_wait_r4(var, vid)
    use mod_process, only : &
       PRC_next, &
       PRC_W,    &
       PRC_N,    &
       PRC_E,    &
       PRC_S

    implicit none

    real(4), intent(inout) :: var(:,:,:)
    integer, intent(in)    :: vid

    integer :: ierr
    integer :: i, j, k, n
    !---------------------------------------------------------------------------

    call TIME_rapstart('COMM wait(real4) MPI')

    !--- wait packets
    call MPI_WAITALL(ireq_cnt(vid), ireq_list(1:ireq_cnt(vid),vid), MPI_STATUSES_IGNORE, ierr)

    if( IsAllPeriodic ) then
    !--- periodic condition
        !--- unpacking packets from East
        do j = JS, JE
        do i = IE+1, IE+IHALO
        do k = 1,  KA
           n = (j-JS)   * KA * IHALO &
             + (i-IE-1) * KA         &
             + k

           var(k,i,j) = recvpack_E2P_r4(n,vid)
        enddo
        enddo
        enddo

        !--- unpacking packets from West
        do j = JS, JE
        do i = IS-IHALO, IS-1
        do k = 1,  KA
           n = (j-JS)       * KA * IHALO &
             + (i-IS+IHALO) * KA         &
             + k

           var(k,i,j) = recvpack_W2P_r4(n,vid)
        enddo
        enddo
        enddo

    else
    !--- non-periodic condition

        !--- copy inner data to HALO(North)
        if( PRC_next(PRC_N) == MPI_PROC_NULL ) then
            do j = JE+1, JE+JHALO
            do i = IS, IE
            do k = 1, KA
               var(k,i,j) = var(k,i,JE)
            enddo
            enddo
            enddo
        endif

        !--- copy inner data to HALO(South)
        if( PRC_next(PRC_S) == MPI_PROC_NULL ) then
            do j = JS-JHALO, JS-1
            do i = IS, IE
            do k = 1, KA
               var(k,i,j) = var(k,i,JS)
            enddo
            enddo
            enddo
        endif

        !--- unpacking packets from East / copy inner data to HALO(East)
        if( PRC_next(PRC_E) /= MPI_PROC_NULL ) then
            do j = JS, JE
            do i = IE+1, IE+IHALO
            do k = 1, KA
               n = (j-JS)   * KA * IHALO &
                 + (i-IE-1) * KA         &
                 + k
               var(k,i,j) = recvpack_E2P_r4(n,vid)
            enddo
            enddo
            enddo
        else
            do j = JS, JE
            do i = IE+1, IE+IHALO
            do k = 1, KA
               var(k,i,j) = var(k,IE,j)
            enddo
            enddo
            enddo
        endif

        !--- unpacking packets from West / copy inner data to HALO(West)
        if( PRC_next(PRC_W) /= MPI_PROC_NULL ) then
            do j = JS, JE
            do i = IS-IHALO, IS-1
            do k = 1, KA
               n = (j-JS)       * KA * IHALO &
                 + (i-IS+IHALO) * KA         &
                 + k
               var(k,i,j) = recvpack_W2P_r4(n,vid)
            enddo
            enddo
            enddo
        else
            do j = JS, JE
            do i = IS-IHALO, IS-1
            do k = 1, KA
               var(k,i,j) = var(k,IS,j)
            enddo
            enddo
            enddo
        endif

        !--- copy inner data to HALO(NorthWest)
        if( PRC_next(PRC_N) == MPI_PROC_NULL .and. PRC_next(PRC_W) == MPI_PROC_NULL) then
            do j = JE+1, JE+JHALO
            do i = IS-IHALO, IS-1
            do k = 1, KA
               var(k,i,j) = var(k,IS,JE)
            enddo
            enddo
            enddo
        else if ( PRC_next(PRC_N) == MPI_PROC_NULL) then
            do j = JE+1, JE+JHALO
            do i = IS-IHALO, IS-1
            do k = 1, KA
               var(k,i,j) = var(k,i,JE)
            enddo
            enddo
            enddo
        else if ( PRC_next(PRC_W) == MPI_PROC_NULL) then
            do j = JE+1, JE+JHALO
            do i = IS-IHALO, IS-1
            do k = 1, KA
               var(k,i,j) = var(k,IS,j)
            enddo
            enddo
            enddo
        endif

        !--- copy inner data to HALO(SouthWest)
        if( PRC_next(PRC_S) == MPI_PROC_NULL .and. PRC_next(PRC_W) == MPI_PROC_NULL) then
            do j = JS-IHALO, JS-1
            do i = IS-IHALO, IS-1
            do k = 1, KA
               var(k,i,j) = var(k,IS,JS)
            enddo
            enddo
            enddo
        else if ( PRC_next(PRC_S) == MPI_PROC_NULL) then
            do j = JS-IHALO, JS-1
            do i = IS-IHALO, IS-1
            do k = 1, KA
               var(k,i,j) = var(k,i,JS)
            enddo
            enddo
            enddo
        else if ( PRC_next(PRC_W) == MPI_PROC_NULL) then
            do j = JS-IHALO, JS-1
            do i = IS-IHALO, IS-1
            do k = 1, KA
               var(k,i,j) = var(k,IS,j)
            enddo
            enddo
            enddo
        endif

        !--- copy inner data to HALO(NorthEast)
        if( PRC_next(PRC_N) == MPI_PROC_NULL .and. PRC_next(PRC_E) == MPI_PROC_NULL) then
            do j = JE+1, JE+JHALO
            do i = IE+1, IE+IHALO
            do k = 1, KA
               var(k,i,j) = var(k,IE,JE)
            enddo
            enddo
            enddo
        else if ( PRC_next(PRC_N) == MPI_PROC_NULL) then
            do j = JE+1, JE+JHALO
            do i = IE+1, IE+IHALO
            do k = 1, KA
               var(k,i,j) = var(k,i,JE)
            enddo
            enddo
            enddo
        else if ( PRC_next(PRC_E) == MPI_PROC_NULL) then
            do j = JE+1, JE+JHALO
            do i = IE+1, IE+IHALO
            do k = 1, KA
               var(k,i,j) = var(k,IE,j)
            enddo
            enddo
            enddo
        endif

        !--- copy inner data to HALO(SouthEast)
        if( PRC_next(PRC_S) == MPI_PROC_NULL .and. PRC_next(PRC_E) == MPI_PROC_NULL) then
            do j = JS-IHALO, JS-1
            do i = IE+1, IE+IHALO
            do k = 1, KA
               var(k,i,j) = var(k,IE,JS)
            enddo
            enddo
            enddo
        else if ( PRC_next(PRC_S) == MPI_PROC_NULL) then
            do j = JS-IHALO, JS-1
            do i = IE+1, IE+IHALO
            do k = 1, KA
               var(k,i,j) = var(k,i,JS)
            enddo
            enddo
            enddo
        else if ( PRC_next(PRC_E) == MPI_PROC_NULL) then
            do j = JS-IHALO, JS-1
            do i = IE+1, IE+IHALO
            do k = 1, KA
               var(k,i,j) = var(k,IE,j)
            enddo
            enddo
            enddo
        endif


    endif

    call TIME_rapend  ('COMM wait(real4) MPI')

    return
  end subroutine COMM_wait_r4

#ifdef _USE_RDMA
  !-----------------------------------------------------------------------------
  subroutine COMM_set_rdma_variable(var, vid)
    implicit none

    real(RP), intent(in) :: var(:,:,:)
    integer, intent(in) :: vid
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*) '*** set RDMA ID:', vid-1

    call set_rdma_variable(var, vid-1);

    return
  end subroutine
#endif

#ifdef _USE_RDMA
  !-----------------------------------------------------------------------------
  subroutine COMM_rdma_vars(vid, num)
    implicit none

    integer, intent(in) :: vid
    integer, intent(in) :: num
    !---------------------------------------------------------------------------

    call TIME_rapstart('COMM RDMA')

    !--- put data
    call rdma_put(vid-1, num)

    call TIME_rapend  ('COMM RDMA')

    return
  end subroutine COMM_rdma_vars
#endif

#ifdef _USE_RDMA
  !-----------------------------------------------------------------------------
  subroutine COMM_rdma_vars8(vid, num)
    implicit none

    integer, intent(in) :: vid
    integer, intent(in) :: num
    !---------------------------------------------------------------------------

    call TIME_rapstart('COMM RDMA')

    !--- put data
    call rdma_put8(vid-1, num)

    call TIME_rapend  ('COMM RDMA')

    return
  end subroutine COMM_rdma_vars8
#endif

  !-----------------------------------------------------------------------------
  subroutine COMM_stats(var, varname)
    use mod_process, only : &
       PRC_nmax,   &
       PRC_myrank
    use mod_const, only : &
       CONST_UNDEF8, &
       CONST_UNDEF2
    implicit none

    real(RP),         intent(inout) :: var(:,:,:,:)
    character(len=*), intent(in)    :: varname(:)

    logical :: halomask(KA,IA,JA)

    real(RP), allocatable :: statval   (:,:,:)
    integer,  allocatable :: statidx   (:,:,:,:)
    real(RP), allocatable :: allstatval(:,:)
    integer,  allocatable :: allstatidx(:,:,:)
    integer               :: vsize

    integer :: ierr
    integer :: v, p
    !---------------------------------------------------------------------------

    vsize = size(var(:,:,:,:),4)

    halomask(:,:,:) = .false.
    halomask(KS:KE,IS:IE,JS:JE) = .true.

    allocate( statval(  vsize,2,0:PRC_nmax-1) ); statval(:,:,:)   = CONST_UNDEF8
    allocate( statidx(3,vsize,2,0:PRC_nmax-1) ); statidx(:,:,:,:) = CONST_UNDEF2

    allocate( allstatval(  vsize,2) ); allstatval(:,:)   = CONST_UNDEF8
    allocate( allstatidx(1,vsize,2) ); allstatidx(:,:,:) = CONST_UNDEF2

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '*** Variable Statistics ***'
    do v = 1, vsize
       statval(  v,1,PRC_myrank) = maxval(var(:,:,:,v),mask=halomask)
       statval(  v,2,PRC_myrank) = minval(var(:,:,:,v),mask=halomask)
       statidx(:,v,1,PRC_myrank) = maxloc(var(:,:,:,v),mask=halomask)
       statidx(:,v,2,PRC_myrank) = minloc(var(:,:,:,v),mask=halomask)

! statistics on each node
!       if( IO_L ) write(IO_FID_LOG,*) '*** [', trim(varname(v)), ']'
!       if( IO_L ) write(IO_FID_LOG,'(1x,A,E17.10,A,3(I5,A))') '*** MAX = ', &
!                                             statval(  v,1,PRC_myrank),'(', &
!                                             statidx(1,v,1,PRC_myrank),',', &
!                                             statidx(2,v,1,PRC_myrank),',', &
!                                             statidx(3,v,1,PRC_myrank),')'
!       if( IO_L ) write(IO_FID_LOG,'(1x,A,E17.10,A,3(I5,A))') '*** MIN = ', &
!                                             statval(  v,2,PRC_myrank),'(', &
!                                             statidx(1,v,2,PRC_myrank),',', &
!                                             statidx(2,v,2,PRC_myrank),',', &
!                                             statidx(3,v,2,PRC_myrank),')'
    enddo

    ! MPI broadcast
    do p = 0, PRC_nmax-1
       call MPI_Bcast( statval(1,1,p),       &
                       vsize*2,              &
                       datatype,             &
                       p,                    &
                       MPI_COMM_WORLD,       &
                       ierr                  )
       call MPI_Bcast( statidx(1,1,1,p),     &
                       3*vsize*2,            &
                       MPI_INTEGER,          &
                       p,                    &
                       MPI_COMM_WORLD,       &
                       ierr                  )
    enddo

    do v = 1, vsize
       allstatval(v,1)   = maxval(statval(v,1,:))
       allstatval(v,2)   = minval(statval(v,2,:))
       allstatidx(:,v,1) = maxloc(statval(v,1,:))-1
       allstatidx(:,v,2) = minloc(statval(v,2,:))-1
       if( IO_L ) write(IO_FID_LOG,*) '[', trim(varname(v)), ']'
       if( IO_L ) write(IO_FID_LOG,'(1x,A,E17.10,A,4(I5,A))') '  MAX =', &
                                                    allstatval(  v,1), '(', &
                                                    allstatidx(1,v,1), ',', &
                                      statidx(1,v,1,allstatidx(1,v,1)),',', &
                                      statidx(2,v,1,allstatidx(1,v,1)),',', &
                                      statidx(3,v,1,allstatidx(1,v,1)),')'
       if( IO_L ) write(IO_FID_LOG,'(1x,A,E17.10,A,4(I5,A))') '  MIN =', &
                                                    allstatval(  v,2), '(', &
                                                    allstatidx(1,v,2), ',', &
                                      statidx(1,v,2,allstatidx(1,v,2)),',', &
                                      statidx(2,v,2,allstatidx(1,v,2)),',', &
                                      statidx(3,v,2,allstatidx(1,v,2)),')'
    enddo

    deallocate( statval )
    deallocate( statidx )

    deallocate( allstatval )
    deallocate( allstatidx )

    return
  end subroutine COMM_stats

  !-----------------------------------------------------------------------------
  subroutine COMM_total( allstatval, var, varname )
    use mod_process, only: &
       PRC_MPIstop
    use mod_geometrics, only: &
       area    => GEOMETRICS_area,    &
       vol     => GEOMETRICS_vol
    implicit none

    real(RP),         intent(out) :: allstatval
    real(RP),         intent(in)  :: var(KA,IA,JA)
    character(len=*), intent(in)  :: varname

    real(RP) :: statval
    integer  :: ksize

    integer :: ierr
    integer :: k, i, j
    !---------------------------------------------------------------------------

    ksize = size(var(:,:,:),1)

    statval = 0.0_RP
    if ( ksize == KA ) then ! 3D
       do j = JS, JE
       do i = IS, IE
       do k = KS, KE
          statval = statval + var(k,i,j) * vol(k,i,j)
       enddo
       enddo
       enddo
    elseif( ksize == 1 ) then ! 2D
       do j = JS, JE
       do i = IS, IE
          statval = statval + var(1,i,j) * area(1,i,j)
       enddo
       enddo
    endif

    if ( COMM_total_globalsum ) then
       call TIME_rapstart('COMM MPIAllreduce')
       ! All reduce
       call MPI_Allreduce( statval,              &
                           allstatval,           &
                           1,                    &
                           datatype,             &
                           MPI_SUM,              &
                           MPI_COMM_WORLD,       &
                           ierr                  )

       call TIME_rapend  ('COMM MPIAllreduce')

       ! statistics over the all node
       if ( varname /= "" ) then ! if varname is empty, suppress output
          if( IO_L ) write(IO_FID_LOG,'(1x,A,A8,A,1PE24.17)') &
                     '[', varname, '] SUM(global) =', allstatval
       endif
    else
       allstatval = statval

       ! statistics on each node
       if ( varname /= "" ) then ! if varname is empty, suppress output
          if( IO_L ) write(IO_FID_LOG,'(1x,A,A8,A,1PE24.17)') &
                     '[', varname, '] SUM(local)  =', statval
       endif
    endif

    if ( .not. ( allstatval > -1.0_RP .or. allstatval < 1.0_RP ) ) then ! must be NaN
       write(*,*) 'xxx NaN is detected'
       call PRC_MPIstop
    end if

    return
  end subroutine COMM_total

  !-----------------------------------------------------------------------------
  subroutine COMM_horizontal_mean( varmean, var )
    use mod_process, only: &
       PRC_nmax
    implicit none

    real(RP), intent(out) :: varmean(KA)
    real(RP), intent(in)  :: var    (KA,IA,JA)

    real(RP) :: statval   (KA)
    real(RP) :: allstatval(KA)

    integer :: ierr
    integer :: k, i, j
    !---------------------------------------------------------------------------

    statval(:) = 0.0_RP
    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       statval(k) = statval(k) + var(k,i,j)
    enddo
    enddo
    enddo

    do k = KS, KE
       statval(k) = statval(k) / real(IMAX*JMAX,kind=RP)
    enddo

!    if ( COMM_total_globalsum ) then ! always communicate globally
       call TIME_rapstart('COMM MPIAllreduce')
       ! All reduce
       call MPI_Allreduce( statval(1),           &
                           allstatval(1),        &
                           KA,                   &
                           datatype,             &
                           MPI_SUM,              &
                           MPI_COMM_WORLD,       &
                           ierr                  )

       call TIME_rapend  ('COMM MPIAllreduce')
!    else
!       allstatval(:) = statval(:)
!    endif

    do k = KS, KE
       varmean(k) = allstatval(k) / real(PRC_nmax,kind=RP) 
    enddo
    varmean(   1:KS-1) = 0.0_RP
    varmean(KE+1:KA  ) = 0.0_RP

    return
  end subroutine COMM_horizontal_mean

end module mod_comm
