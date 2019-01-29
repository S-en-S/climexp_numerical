program correlatefieldfield

!   program to correlate a field series to another field series on
!   the same grid to give fields of correlation coefficients,
!   probabilities that these are significant, and the fit
!   coefficients a, b and their errors.
!   when the option 'subtract' is given, the output consists of
!   the first field minus the best fit to the second one
!   If one of the two fields is 3D and one 2D, the 2D field is
!   used on all levels.

    implicit none
    include 'params.h'
    include 'netcdf.inc'
    include 'getopts.inc'
    integer,parameter :: ntmax=1000
    integer :: ncid1,ncid2,nx1,ny1,nz1,nt1,nper1,firstyr1,firstmo1, &
        nx2,ny2,nz2,nt2,nper2,firstyr2,firstmo2,nvars1,ivars1(6,1) &
        ,nvars2,ivars2(6,1),endian1,endian2,status,nxf,nyf,nzf &
        ,nperyear1,nperyear2,nperyear,firstyr,lastyr,lastyr1,lastyr2 &
        ,mens11,mens1,mens12,mens2,mens,imens(0:1)
    integer :: i,j,jj,k,n,lag,jx,jy,jz,mo,j1,j2,m,ii,l,yr,if,jm,jp,im &
        ,ip,nt,nrec,nvars,ivars(2,9),ldir,nx,ny,nz,ncid &
        ,ntvarid,itimeaxis(ntmax),iens,yrstart,yrstop &
        ,nens11,nens12,nens21,nens22,ndiffn
    real ::  xx1(nxmax),yy1(nymax),zz1(nzmax), &
        xx2(nxmax),yy2(nymax),zz2(nzmax), &
        undef1,undef2,alpha,a1,da1,b1,db1
    real, allocatable :: &
        field1(:,:,:,:,:,:), &
        field2(:,:,:,:,:,:), &
        r(:,:,:,:),prob(:,:,:,:), &
        a(:,:,:,:,:),b(:,:,:,:,:), &
        da(:,:,:,:,:),db(:,:,:,:,:), &
        cov(:,:,:,:),mean2(:,:,:,:), &
        relregr(:,:,:,:),xn(:,:,:,:)
    real,allocatable :: fxy1(:,:,:),fxy2(:,:,:)
    logical :: lexist

    real :: ddata(ndata),dindx(ndata),dddata(ndata),ddindx(ndata), &
        adata,sxx,aindx,syy,sxy,df,d,zd,z,probd,chi2,q,sum, &
        fac,xx(nxmax),yy(nymax),zz(nzmax),aa(2),x(ndata), &
        sig(ndata),u(ndata,2),v(2,2),w(2),daa(2,2)
    character :: infile1*256,infile2*256,datfile1*256,datfile2*256, &
        title1*256,title2*256,vars1(1)*40,lvars1(1)*128, &
        svars1(1)*128,vars2(1)*40,lvars2(1)*128,svars2(1)*128, &
        units1(1)*40,units2(1)*40
    character :: line*80,yesno*1,string*10,file*255,outfile*255, &
        datfile*255,title*255,vars(9)*10,lvars(9)*128,svars(9)*128 &
        ,dir*255,units(9)*40,lz1(3)*128,lz2(3)*128,ltime1*128, &
        ltime2*128,history1*20000,history2*20000,cell_methods1*100 &
        ,cell_methods2*100,metadata1(2,100)*2000, &
        metadata2(2,100)*2000
    external findx

!   check arguments

    lwrite = .false.
    n = command_argument_count()
    if ( n < 3 ) then
        print *,'usage: correlatefieldfield '// &
        'field1.[ctl|nc] field2.[ctl|nc] '// &
        '[lag n[:m]] [sum|ave|max|min|sel n] '// &
        '[log|sqrt|rank] '// &
        '[minfac r] [minnum n] [begin yr] [end yr] '// &
        '[lt cut] [gt cut] [diff [nyr]] [detrend] '// &
        '[subtract] [ens n1:n2] outfield'
        call exit(-1)
    end if
    call keepalive(0,0)
    call get_command_argument(1,infile1)
    call getmetadata(infile1,mens11,mens1,ncid1,datfile1,nxmax,nx1 &
        ,xx1,nymax,ny1,yy1,nzmax,nz1,zz1,lz1,nt1,nperyear1,firstyr1 &
        ,firstmo1,ltime1,undef1,endian1,title1,history1,1,nvars1 &
        ,vars1,ivars1,lvars1,svars1,units1,cell_methods1,metadata1 &
        ,lwrite)

    call get_command_argument(2,infile2)
    if ( infile2 == infile1 ) then
        nx2 = nx1
        ny2 = ny1
        nz2 = nz1
        xx2 = xx1
        yy2 = yy1
        zz2 = zz1
        firstyr2 = firstyr1
        nperyear2 = nperyear1
        nxf = nx1
        nyf = ny1
        nzf = nz1
        firstyr = firstyr1
        nperyear = nperyear1
        call getlastyr(firstyr1,firstmo1,nt1,nperyear,lastyr)
        mens12 = mens11
        mens2 = mens1
    else
        call getmetadata(infile2,mens12,mens2,ncid2,datfile2,nxmax &
            ,nx2,xx2,nymax,ny2,yy2,nzmax,nz2,zz2,lz2,nt2,nperyear2 &
            ,firstyr2,firstmo2,ltime2,undef2,endian2,title2 &
            ,history2,1,nvars2,vars2,ivars2,lvars2,svars2,units2 &
            ,cell_methods2,metadata2,lwrite)

        nxf = max(nx1,nx2)
        nyf = max(ny1,ny2)
        nzf = max(nz1,nz2)
        firstyr = max(firstyr1,firstyr2)
        if ( nperyear1 /= nperyear2 ) then
            write(0,*) 'correlatefieldfield: error: cannot &
            interpolate'//' in time yet',nperyear1,nperyear2
            write(*,*) 'correlatefieldfield: error: cannot &
            interpolate'//' in time yet',nperyear1,nperyear2
            call exit(-1)
        end if
        nperyear = nperyear1
        call getlastyr(firstyr1,firstmo1,nt1,nperyear1,lastyr1)
        call getlastyr(firstyr2,firstmo2,nt2,nperyear2,lastyr2)
        lastyr = min(lastyr1,lastyr2)
    end if

!   save time on the initialization - but not too much.
    nt = nperyear*(lastyr-firstyr+1)
    n = command_argument_count()
    call getopts(3,n-1,nperyear,yrbeg,yrend, .true. , &
    min(mens11,mens12),max(mens1,mens2))
    if ( lag1 < 0 ) print *,'(field1 leading field2)'
    if ( lag2 > 0 ) print *,'(field2 leading field1)'
    if ( dump ) write(0,*)'correlatefieldfield: dump not supported'
    if ( plot ) write(0,*)'correlatefieldfield: plot not supported'
    if ( lks ) write(0,*)'correlatefieldfield: K-S not supported'
    if ( lconting ) write(0,*)'correlatefieldfield: contingency tables not supported'
    if ( composite ) write(0,*)'composites not yet supported'
    do i=1,indxuse
        if ( lincl(i) ) write(0,*)'correlatefieldfield: what do ', &
        'you mean with ',strindx(i),'?'
    end do
    if ( m1 /= m2 .and. lag1 /= lag2 ) then
        print *,'Sorry, can only handle either lags varying or months varying, not both'
        print *,'(months:',m1,m2,', lags:',lag1,lag2,')'
        call exit(-1)
    end if
    if ( lag2-lag1 > npermax ) then
        print *,'Sorry, can only store ',npermax+1,' fields maximum'
        call exit(-1)
    end if
    if ( lag1 /= lag2 .and. lsubtract ) then
        print *,'Sorry, can only subtract one lag'
        call exit(-1)
    end if
    yr1 = max(yr1,firstyr,firstyr - (min(lag1,lag2)+nperyear-1)/nperyear)
    yr2 = min(yr2,lastyr,lastyr - (max(lag1,lag2)-nperyear+1)/nperyear)
    if ( mens1 == 0 ) then
        nens11 = 0
        nens21 = 0
    else
        nens11 = max(nens1,mens11)
        nens21 = min(nens2,mens1)
    end if
    if ( mens2 == 0 ) then
        nens12 = 0
        nens22 = 0
    else
        nens12 = max(nens1,mens12)
        nens22 = min(nens2,mens2)
    end if
    if ( lwrite ) then
        print *,'cfieldfield: correlating ',trim(infile1)
        print *,'                    with ',trim(infile2)
        print *,'years: ',yr1,yr2
    end if

!   allocate fields

    firstyr = yr1
    lastyr = yr2
    mens1 = min(mens1,nens2)
    mens2 = min(mens2,nens2)
    mens = max(mens1,mens2)
    if ( lwrite ) print *,'allocating fields ',nxf,nyf,nzf,nperyear &
        ,firstyr,lastyr,mens1,mens2,mens
    allocate(field1(nxf,nyf,nzf,nperyear,firstyr:lastyr,0:mens1))
    allocate(field2(nxf,nyf,nzf,nperyear,firstyr:lastyr,0:mens2))
    allocate(r(nxf,nyf,nzf,0:npermax))
    allocate(prob(nxf,nyf,nzf,0:npermax))
    allocate(a(nxf,nyf,nzf,0:npermax,2))
    allocate(b(nxf,nyf,nzf,0:npermax,2))
    allocate(da(nxf,nyf,nzf,0:npermax,2))
    allocate(db(nxf,nyf,nzf,0:npermax,2))
    allocate(cov(nxf,nyf,nzf,0:npermax))
    allocate(relregr(nxf,nyf,nzf,0:npermax))
    allocate(mean2(nxf,nyf,nzf,0:npermax))
    allocate(xn(nxf,nyf,nzf,0:npermax))
    allocate(fxy1(nperyear,firstyr:lastyr,0:mens))
    allocate(fxy2(nperyear,firstyr:lastyr,0:mens))

!   init

    call get_command_argument(n,outfile)
    inquire(file=outfile,exist=lexist)
    if ( lexist ) then
        print *,'output file ',outfile(1:index(outfile,' ')-1), &
            ' already exists, overwrite? [y/n]'
        read(*,'(a)') yesno
        if (  yesno /= 'y' .and. yesno /= 'Y' .and. &
        yesno /= 'j' .and. yesno /= 'J' ) then
            stop
        end if
        open(1,file=outfile)
        close(1,status='delete')
    end if
    print *,'init'
    do iens=0,mens
        call makeabsent(fxy1(1,firstyr,iens),nperyear,firstyr,lastyr)
        call makeabsent(fxy2(1,firstyr,iens),nperyear,firstyr,lastyr)
    end do

!   compute minfac if it has not been set explicitly

    if ( minfac < 0 .and. minnum < 0 ) then
!       heuristic, gives 0.25 for 150 yrs, 0.5 for 50 yrs, 0.75 for 20yrs
        minfac = max(0.1, &
        min(0.6, 1.5-log(1+real(min(nt,nperyear*(yr2-yr1+1))-1)/nperyear)/4))
    end if
    write(0,'(a,i2,a)') 'Requiring at least ',nint(100*minfac),'% valid points<p>'

!   read fields

    do iens=nens11,nens21
        call keepalive1('Reading field1 ensemble member', &
        iens-nens11,2+nens21-nens11+nens22-nens12)
        if ( ncid1 == -1 ) then
            if ( iens > nens11 ) then
                file = infile1
                call filloutens(file,iens)
                call parsectl(file,datfile1,nxmax,nx1,xx1,nymax,ny1 &
                ,yy1,nzmax,nz1,zz1,nt1,nperyear1,firstyr1 &
                ,firstmo1,undef1,endian1,title,1,nvars1,vars1 &
                ,ivars1,lvars1,units1)
            end if
            call zreaddatfile(datfile1,field1(1,1,1,1,firstyr,iens) &
            ,nxf,nyf,nzf,nx1,ny1,nz1,nperyear,firstyr,lastyr &
            ,firstyr1,firstmo1,nt1,undef1,endian1,lwrite,yr1 &
            ,yr2,1,1)
        else
            if ( iens > nens11 ) then
                file = infile1
                call filloutens(file,iens)
                call parsenc(file,ncid1,nxmax,nx1,xx1,nymax,ny1 &
                ,yy1,nzmax,nz1,zz1,nt1,nperyear1,firstyr1 &
                ,firstmo1,undef1,title1,1,nvars1,vars1,ivars1 &
                ,lvars1,units1)
            end if
            call zreadncfile(ncid1,field1(1,1,1,1,firstyr,iens) &
                ,nxf,nyf,nzf,nx1,ny1,nz1,nperyear,firstyr,lastyr &
                ,firstyr1,firstmo1,nt1,undef1,lwrite,yr1,yr2,ivars1)
        end if
    end do
    if ( lwrite ) then
        print *,'field1 @ 0,60N'
        call dump060(xx1,yy1,zz1,field1,nxf,nyf,nzf,nx1,ny1,nz1 &
            ,nperyear,firstyr,lastyr)
    end if
    if ( infile2 == infile1 ) then
        field2 = field1
    else
        do iens=nens12,nens22
            call keepalive1('Reading field2 ensemble member', &
                iens-nens12+1+nens21-nens11,2+nens21-nens11+nens22-nens12)
            if ( ncid2 == -1 ) then
                if ( iens > nens12 ) then
                    file=infile2
                    call filloutens(file,iens)
                    call parsenc(file,ncid2,nxmax,nx2,xx2,nymax,ny2 &
                        ,yy2,nzmax,nz2,zz2,nt2,nperyear2,firstyr2 &
                        ,firstmo2,undef2,title2,1,nvars2,vars2 &
                        ,ivars2,lvars2,units2)
                end if
                write(0,*) 'correlatefieldfield: this must be wrong'
                call zreaddatfile(datfile2,field2(1,1,1,1,firstyr &
                    ,iens),nxf,nyf,nzf,nx2,ny2,nz2,nperyear,firstyr &
                    ,lastyr,firstyr2,firstmo2,nt2,undef2,endian2 &
                    ,lwrite,yr1,yr2,1,1)
            else
                if ( iens > nens12 ) then
                    file=infile2
                    call filloutens(file,iens)
                    call parsenc(file,ncid2,nxmax,nx2,xx2,nymax,ny2 &
                        ,yy2,nzmax,nz2,zz2,nt1,nperyear,firstyr2 &
                        ,firstmo2,undef2,title,1,nvars2,vars2 &
                        ,ivars2,lvars2,units2)
                end if
                call zreadncfile(ncid2,field2(1,1,1,1,firstyr,iens) &
                    ,nxf,nyf,nzf,nx2,ny2,nz2,nperyear,firstyr &
                    ,lastyr,firstyr2,firstmo2,nt2,undef2,lwrite,yr1 &
                    ,yr2,ivars2)
            end if
        end do
    end if
    if ( lwrite ) then
        print *,'field2 @ 0,60N'
        call dump060(xx2,yy2,zz2,field2,nxf,nyf,nzf,nx2,ny2,nz2,nperyear,firstyr,lastyr)
    end if
    call keepalive(0,0)

!   interpolate fields to common grid

    if ( infile2 /= infile1 ) then
        if ( nz1 > 1 .or. nz2 > 1 ) then
            if ( mens1 /= mens2 .or. mens11 /= mens12 ) then
                write(0,*) 'correlatefieldfield: cannot handle unequal 3D ensembles yet'
                write(*,*) 'correlatefieldfield: cannot handle unequal 3D ensembles yet'
                call exit(-1)
            end if
            if ( lwrite ) print *,'calling zinterpu'
            do iens=mens11,mens1
                call zinterpu( &
                    field1(1,1,1,1,yr1,iens),zz1,nx1,ny1,nz1, &
                    field2(1,1,1,1,yr1,iens),zz2,nx2,ny2,nz2, &
                    zz,nz,yr1,yr2,yr1,yr2,nxf,nyf,nzf,nperyear &
                    ,lwrite)
            end do
        else
            nz = 1
            zz(1) = zz1(1)
        end if
        if ( lwrite ) print *,'calling ensxyinterpu'
        call ensxyinterpu( &
            field1,xx1,nx1,yy1,ny1,mens11,mens1, &
            field2,xx2,nx2,yy2,ny2,mens12,mens2, &
            xx,nx,yy,ny,firstyr,lastyr,firstyr,lastyr,nxf,nyf,nzf &
            ,nz,nperyear,intertype,lwrite)
    else
        nx = nx1
        ny = ny1
        nz = nz1
        xx = xx1
        yy = yy1
        zz = zz1
    end if

!   loop over grid points

    print *,'correlating'
    yrstart = yr2
    yrstop  = yr1
    do jz=1,nz
        do jy=1,ny
            call keepalive1('Computing latitude',jy+(jz-1)*ny,ny*nz)
            do jx=1,nx
                do mo=0,npermax
                    r(jx,jy,jz,mo) = 3e33
                    cov(jx,jy,jz,mo) = 3e33
                    relregr(jx,jy,jz,mo) = 3e33
                    prob(jx,jy,jz,mo) = 3e33
                    a(jx,jy,jz,mo,1:2) = 3e33
                    b(jx,jy,jz,mo,1:2) = 3e33
                    da(jx,jy,jz,mo,1:2) = 3e33
                    db(jx,jy,jz,mo,1:2) = 3e33
                    xn(jx,jy,jz,mo) = 3e33
                end do

!               create 1-D series from fields

                n = 0
                do iens=nens11,nens21
                    do i=yr1,yr2
                        do j=1,nperyear
                            fxy1(j,i,iens)=field1(jx,jy,jz,j,i,iens)
                            if ( fxy1(j,i,iens) < 1e30 ) n = n + 1
                        end do
                    end do
                end do
                if ( n < 3 ) then
                    if ( lwrite ) print '(a,4i5)','no valid points in field1 at ',jx,jy,jz,n
                    goto 800
                end if
                n = 0
                do iens = nens12,nens22
                    do i=yr1,yr2
                        do j=1,nperyear
                            fxy2(j,i,iens)=field2(jx,jy,jz,j,i,iens)
                            if ( fxy2(j,i,iens) < 1e30 ) n = n+1
                        end do
                    end do
                end do
                if ( n < 3 ) then
                    if ( lwrite ) print '(a,4i5)','no valid points in field2 at ',jx,jy,jz,n
                    goto 800
                end if
                do iens=nens11,nens21
                    if ( lsum > 1 ) then
                        call sumit(fxy1(1,firstyr,iens),nperyear &
                            ,nperyear,firstyr,lastyr,lsum,'v')
                    end if
                    if ( mdiff > 0 ) then
                        call mdiffit(fxy1(1,firstyr,iens),nperyear &
                            ,nperyear,firstyr,lastyr,mdiff)
                    end if
                    if ( logscale ) then
                        call takelog(fxy1(1,firstyr,iens),nperyear &
                            ,nperyear,firstyr,lastyr)
                    end if
                    if ( sqrtscale ) then
                        call takesqrt(fxy1(1,firstyr,iens),nperyear &
                            ,nperyear,firstyr,lastyr)
                    end if
                    if ( ldetrend ) then
                        if ( lwrite ) print *,'Detrending field'
                        if ( lag1 == 0 .and. lag2 == 0 .or. m1 == 0 &
                            .or. lsel == nperyear ) then
                            call detrend(fxy1(1,firstyr,iens) &
                                ,nperyear,nperyear,firstyr,lastyr &
                                ,yr1,yr2,m1,m2,lsel)
                        else
                            call detrend(fxy1(1,firstyr,iens) &
                                ,nperyear,nperyear,firstyr,lastyr &
                                ,yr1,yr2,1,12,lsel)
                        end if
                    end if
                    if ( ndiff /= 0 ) then
                        if ( lwrite ) print *,'Taking differences'
                        call ndiffit(fxy1(1,firstyr,iens),nperyear &
                            ,nperyear,firstyr,lastyr,ndiff &
                            ,minfacsum)
                    end if
                    if ( anom .or. (lsel > 1 .or. nfittime > 0 ) &
                            .and. ndiff == 0 )then
                        if ( lwrite ) print *,'Taking anomalies'
                        call anomal(fxy1(1,firstyr,iens),nperyear &
                            ,nperyear,firstyr,lastyr,yr1,yr2)
                    end if
                end do       ! loop over ensemble members
                do iens=nens12,nens22
                    if ( lsum2 > 1 ) then
                        call sumit(fxy2(1,firstyr,iens),nperyear &
                            ,nperyear,firstyr,lastyr,lsum2,'v')
                    end if
                    if ( mdiff2 > 0 ) then
                        call mdiffit(fxy2(1,firstyr,iens),nperyear &
                            ,nperyear,firstyr,lastyr,mdiff2)
                    end if
                    if ( logfield ) then
                        call takelog(fxy2(1,firstyr,iens),nperyear &
                            ,nperyear,firstyr,lastyr)
                    end if
                    if ( sqrtfield ) then
                        call takesqrt(fxy2(1,firstyr,iens),nperyear &
                            ,nperyear,firstyr,lastyr)
                    end if
                    if ( ldetrend ) then
                        if ( lwrite ) print *,'Detrending field'
                        if ( lag1 == 0 .and. lag2 == 0 .or. m1 == 0 &
                                .or. lsel == nperyear ) then
                            call detrend(fxy1(1,firstyr,iens) &
                                ,nperyear,nperyear,firstyr,lastyr &
                                ,yr1,yr2,m1,m2,lsel)
                        else
                            call detrend(fxy1(1,firstyr,iens) &
                                ,nperyear,nperyear,firstyr,lastyr &
                                ,yr1,yr2,1,12,lsel)
                        end if
                    end if
                    if ( ndiff /= 0 ) then
                        if ( lwrite ) print *,'Taking differences'
                        call ndiffit(fxy2(1,firstyr,iens),nperyear &
                            ,nperyear,firstyr,lastyr,ndiff &
                        ,minfacsum)
                    end if
                    if ( anom .or. (lsel > 1 .or. nfittime > 0 ) &
                            .and. ndiff == 0 )then
                        if ( lwrite ) print *,'Taking anomalies'
                        call anomal(fxy2(1,firstyr,iens),nperyear &
                            ,nperyear,firstyr,lastyr,yr1,yr2)
                    end if
                end do       ! loop over ensemble members

!               anomalies wrt ensemble mean

                if ( nens21 > nens11 .and. lensanom ) then
                    if ( lwrite ) print *,'Taking anomalies wrt ensemble mean 1'
                    call anomalensemble(fxy1,nperyear,nperyear, &
                        firstyr,lastyr,yr1,yr2,nens11,nens21)
                end if
                if ( nens22 > nens12 .and. lensanom ) then
                    if ( lwrite ) print *,'Taking anomalies wrt ensemble mean 2'
                    call anomalensemble(fxy2,nperyear,nperyear, &
                        firstyr,lastyr,yr1,yr2,nens12,nens22)
                end if

!               extend series to same length

                if ( nens21 > nens11 ) then ! field 1 is ensemble
                    if ( nens22 > nens12 ) then ! field 2 is also ensemble
                        if ( lmakeensfull ) then
                            write(0,*) 'cannot extend ensembles yet'
                            write(*,*) 'cannot extend ensembles yet'
                            call exit(-1)
                        else ! take the smallest subset
                            nens1 = max(nens11,nens12)
                            nens2 = min(nens21,nens22)
                        end if
                    else    ! only field 1 is ensemble
                        if ( nens1 /= nens11 ) write(0,*) 'internal '//'warning: nens1 != nens11' &
                            ,nens1,nens11
                        if ( nens2 /= nens21 ) write(0,*) 'internal '//'warning: nens2 != nens21' &
                            ,nens2,nens21
                        nens1 = nens11
                        nens2 = nens21
                        do iens=nens1,nens2
                            if ( iens /= nens12 ) then
                                fxy2(1:nperyear,firstyr:lastyr,iens) = &
                                    fxy2(1:nperyear,firstyr:lastyr,nens12)
                            end if
                        end do
                    end if
                else if ( nens22 > nens12 ) then ! only field2 is ensemble
                    if ( nens1 /= nens12 ) write(0,*) 'internal warning: nens1 != nens12',nens1,nens12
                    if ( nens2 /= nens22 ) write(0,*) 'internal warning: nens2 != nens22',nens2,nens22
                    nens1 = nens12
                    nens2 = nens22
                    do iens=nens1,nens2
                        if ( iens /= nens11 ) then
                            fxy1(1:nperyear,firstyr:lastyr,iens) = &
                                fxy1(1:nperyear,firstyr:lastyr,nens11)
                        end if
                    end do
                end if

!               correlate   !

                do mo=m1,m2
                    if ( mo == 0 ) then
                        j1 = 1
                        j2 = nperyear
                    else
                        j1 = mo
                        j2 = mo + lsel - 1
                    end if
                    do lag=lag1,lag2

!                       fill linear arrays without absent values
!                       and compute r

                        n = 0
                        mean2(jx,jy,jz,mo) = 0
                        do yr=yr1-1,yr2
                            do jj=j1,j2
                                if ( fix2 ) then
                                    j = jj+lag
                                else
                                    j = jj
                                end if
                                call normon(j,yr,i,nperyear)
                                if ( i < yr1 .or. i > yr2 ) goto 710
                                m = j-lag
                                call normon(m,i,ii,nperyear)
                                if ( ii < firstyr .or. ii > lastyr ) goto 710
                                if ( i == (yr1+yr2)/2 .and. jx == nx/2 .and. jy == ny/2 &
                                        .and. jz == 1 ) then
                                    print '(a,i3,i5,i3,i5,a)','Correlating months', &
                                        j,i,m,ii,' of fields 1 and 2'
                                end if
                                do iens=nens1,nens2
                                    if (  fxy1(j,i,iens) < 1e33 .and. ( &
                                         (fxy1(j,i,iens) <= maxdata) .eqv. &
                                         (fxy1(j,i,iens) >= mindata) .eqv. &
                                        (maxdata >= mindata) ) &
                                     .and. fxy2(m,ii,iens) < 1e33 &
                                     .and. ( (fxy2(m,ii,iens) <= maxindx) .eqv. &
                                             (fxy2(m,ii,iens) >= minindx) .eqv. &
                                        (maxindx >= minindx) ) ) then
                                        n = n+1
                                        if ( .false. .or. lwrite ) print &
                                            '(a,2i4,i3,a,g12.6)','found point fxy1(',j &
                                            ,i,iens,') = ',fxy1(j,i,iens),', fxy2(',m,ii,iens &
                                            ,') = ',fxy2(m,ii,iens)
                                        if ( n > ndata ) goto 909
                                        ddata(n) = fxy1(j,i,iens)
                                        dindx(n) = fxy2(m,ii,iens)
                                        yrstart = min(yrstart,i,ii)
                                        yrstop  = max(yrstop,i,ii)
                                        if ( nfittime > 0 ) then
                                            write(0,*) 'correlatefieldfield: error: time derivative no longer supported'
                                            call exit(-1)
                                        end if ! nfittime
                                        mean2(jx,jy,jz,mo) = &
                                        mean2(jx,jy,jz,mo) + &
                                        fxy2(j,i,iens)
                                    end if ! valid point
                                end do ! iens
                            710 continue
                            end do ! jj
                        end do ! yr
                        if ( m1 /= m2 ) then
                            m = mo-m1
                        else if ( .not. fix2 ) then
                            m = lag2-lag
                        else
                            m = lag-lag1
                        end if
                        if ( jx == nx/2 .and. jy == ny/2 .and. jz == 1 ) then
                            print '(a,i2)','and storing it at ',m
                        end if
                        xn(jx,jy,jz,m) = n
                        ndiffn = 1 + max(0,-ndiff)
                        if ( lwrite ) then
                            if ( mo == 0 ) then
                                print *,'Comparing n=',n,' with minfac*N = ',minfac, &
                                    min(nt,nperyear*(yr2-yr1+1))/ndiffn
                            else
                                print *,'Comparing n=',n,' with minfac*N = ',minfac &
                                    ,min(nt/nperyear,yr2-yr1+1)*lsel/ndiffn
                            end if
                        end if
                        if (  mo == 0 .and. n < minfac*min(nt,nperyear*(yr2-yr1+1))/ndiffn &
                            .or.  mo /= 0 .and. n < minfac*min(nt/nperyear,yr2-yr1+1)*lsel/ndiffn &
                            .or. n < minnum ) then
                            if ( lwrite ) print '(a,3i5,2i3,a,2i6)','not enough valid points at ', &
                                jx,jy,jz,mo,lag,': ',n,nt
                            goto 790
                        end if
                        mean2(jx,jy,jz,mo) = mean2(jx,jy,jz,mo)/n
                        call fit(ddata,dindx,n,sig,0,a1,b1,da1,db1,chi2,q)
                        noisetype = 1
                        imens(0) = nens2
                        imens(1) = nens2
                        if ( .false. ) then
                            do k=1,n
                                print *,k,dindx(k),ddata(k)
                            end do
                        end if
                        call getred(alpha,j1,j2,lag,1,nperyear &
                        ,imens,1,fxy1,fxy2,nperyear,firstyr &
                        ,lastyr,nensmax,a1,b1)
                        if ( lwrite ) then
                            print *,'j1,j2 = ',j1,j2
                            call getdf(df,mo,n,0,decor,max(lsum,lsum2),max(1,1-ndiff, &
                                1-ndiff2),nperyear)
                            print *,'df was',df,n,0
                        end if
                        if ( alpha == 1 .or. n <= 0 ) then
                            df = -2
                        else if ( alpha > 2/sqrt(real(n)) ) then
                            df = n/(1 - 1/(2*log(alpha))) - 2
                        else
                            df = n - 2
                        end if
                        if ( lwrite ) then
                            print *,'df  is',df,alpha
                        end if
                        if ( df < 1 ) then
                            df = 3e33
                        end if

                        if ( nfittime > 0 ) then
                            if ( n <= 4 ) then
                                print*,'not enough data for timefit'
                                goto 800
                            end if

!                           fit to data = a*d(data)/dt + b*indx

                            do j=1,n
                                x(j) = j
                            end do
                            do j=1,n
                                sig(j) = 1
                            end do
                            call svdfit(x,ddata,sig,n,aa,2,u,v,w, &
                            ndata,2,chi2,findx)
                            call svdvar(v,2,2,w,daa,2)
                            a(jx,jy,jz,m,1) = aa(1)
                            b(jx,jy,jz,m,1) = aa(2)
                            da(jx,jy,jz,m,1) = sqrt(daa(1,1))
                            db(jx,jy,jz,m,1) = sqrt(daa(2,2))
                            do j=1,n
                                x(j) = aa(1)*dddata(j) + aa(2)*dindx(j)
                            end do
                            call pearsncross(ddata,x,n,r(jx,jy,jz,m) &
                                ,prob(jx,jy,jz,m),z,adata,sxx,aindx &
                                ,syy,sxy,df,ncrossvalidate)
                        else if ( lrank ) then
                            if ( df < 1e33 ) then
                                sum = n/(df+2) ! note that this is currently disregarded
                            else
                                sum = 3e33
                            end if
                            call spearx(dindx,ddata,n,ddindx,dddata, &
                                d,zd,probd,r(jx,jy,jz,m), &
                                prob(jx,jy,jz,m),sum,adata,sxx &
                                ,aindx,syy)
                        else
                            call pearsncross(dindx,ddata,n, &
                                r(jx,jy,jz,m),prob(jx,jy,jz,m),z, &
                                aindx,syy,adata,sxx,sxy,df &
                                ,ncrossvalidate)
                            if ( sxx == 0 .or. syy == 0 ) then
                                r(jx,jy,jz,m) = 3e33
                                prob(jx,jy,jz,m) = 3e33
                            else
                                call fit(dindx,ddata,n,sig,0, &
                                    a(jx,jy,jz,m,1),b(jx,jy,jz,m,1) &
                                    ,da(jx,jy,jz,m,1),db(jx,jy,jz,m &
                                    ,1),chi2,q)
                                cov(jx,jy,jz,m) = sxy/(n-1)
                                if ( abs(aindx) > 1e-33 ) then
                                    relregr(jx,jy,jz,m) = b(jx,jy,jz,m,1)/aindx
                                else
                                    relregr(jx,jy,jz,m) = 3e33
                                end if
                            end if
                        end if
                        if (lwrite) print '(a,3i5,2i3,a,i6,a,6f9.4)' &
                            ,'point ',jx,jy,jz,mo,lag,' OK (',n &
                            ,'): ',r(jx,jy,jz,m),prob(jx,jy,jz,m) &
                            ,a(jx,jy,jz,m,1),da(jx,jy,jz,m,1),b(jx &
                            ,jy,jz,m,1),db(jx,jy,jz,m,1)
                    790 continue ! valid point/month
                    end do   ! lag
                end do       ! month
            800 continue    ! valid point
            end do           ! nx
        end do               ! ny
    end do                   ! nz
    if ( index(outfile,'.ctl') /= 0 ) then
        i = index(outfile,'.ctl')
        datfile = outfile(:i-1)//'.grd'
        open(unit=2,file=datfile,form='unformatted',access='direct',recl=4*nx*ny*nz,err=920)
    end if
    if ( .not. lsubtract ) then
        call getenv('DIR',dir)
        ldir = len_trim(dir)
        if ( ldir == 0 ) ldir=1
        if ( dir(ldir:ldir) /= '/' ) then
            ldir = ldir + 1
            dir(ldir:ldir) = '/'
        end if
        call args2title(title)
        vars(1) = 'corr'
        vars(2) = 'prob'
        if ( nfittime == 0 ) then
            nvars = 9
            vars(3) = 'intercept'
            vars(4) = 'regr'
            vars(5) = 'errorintercept'
            vars(6) = 'errorregr'
            vars(7) = 'cov'
            vars(8) = 'relregr'
            vars(9) = 'n'
        else
            nvars = 7
            vars(3) = 'relaxation'
            vars(4) = 'relation'
            vars(5) = 'drelaxation'
            vars(6) = 'drelation'
            vars(7) = 'n'
        end if
        do i=1,nvars
            ivars(1,i) = nz
            ivars(2,i) = 99
        end do
        lvars(1) = 'correlation'
        lvars(2) = 'p-value'
        if ( nfittime == 0) then
            lvars(3) = 'intercept'
            lvars(4) = 'regression coefficient'
            lvars(5) = 'error on intercept'
            lvars(6) = 'error on regression coefficient'
            lvars(7) = 'covariance'
            lvars(8) = 'relative regression'
            lvars(9) = 'number of valid time steps'
        else
            lvars(3) = 'relaxation'
            lvars(4) = 'error on relaxation'
            lvars(5) = 'relation'
            lvars(6) = 'error on relation'
            lvars(7) = 'number of valid time steps'
        end if
!       for the time being...
        units = ' '
!       give correlations dates in 0-1
        if ( m1 == 0 ) then
            i = 0
        else
            i = 1
        end if
        j = m1-lag2
        if ( j <= 0 ) then
            j = j + nperyear*(1-j/nperyear)
        else if ( j > nperyear ) then
            j = j - nperyear*((j-1)/nperyear)
        end if
        if ( index(outfile,'.ctl') /= 0 ) then
            call writectl(outfile,datfile,nx,xx,ny,yy,nz,zz &
                ,1+(m2-m1)+(lag2-lag1),nperyear,i,j,3e33,title &
                ,nvars,vars,ivars,lvars,units)
        else
            call writenc(outfile,ncid,ntvarid,itimeaxis,ntmax,nx,xx &
                ,ny,yy,nz,zz,1+(m2-m1)+(lag2-lag1),nperyear,i,j &
                ,3e33,title,nvars,vars,ivars,lvars,units,0,0)
        end if

!       write output field in GrADS or netCDF format

        print *,'writing output'
        do lag=lag2,lag1,-1
            do mo=m1,m2
                if ( m1 /= m2 ) then
                    m = mo-m1
                else
                    m = lag2-lag
                end if
                if ( index(outfile,'.ctl') /= 0 ) then
                    if ( lwrite ) then
                        print *,'writing records ',6*m+1,'-',6*m+6 &
                        ,' of fields ',m,' of size ',nx*ny*nz*4
                        do jz=1,nz
                            do jy=1,ny
                                do jx = 1,nx
                                    if ( abs(r(jx,jy,jz,m)) <= 1 ) &
                                    then
                                        i = i + 1
                                        d = d + abs(r(jx,jy,jz,m))
                                    end if
                                end do
                            end do
                        end do
                        print *,'there are ',i &
                            ,' valid values in record ',m &
                            ,' with mean value ',d/i
                    end if
                    write(2,rec=nvars*m+1) &
                    (((r(jx,jy,jz,m),jx=1,nx),jy=1,ny),jz=1,nz)
                    write(2,rec=nvars*m+2) &
                    (((prob(jx,jy,jz,m),jx=1,nx),jy=1,ny),jz=1,nz)
                    write(2,rec=nvars*m+3) &
                    (((a(jx,jy,jz,m,1),jx=1,nx),jy=1,ny),jz=1,nz)
                    write(2,rec=nvars*m+4) &
                    (((b(jx,jy,jz,m,1),jx=1,nx),jy=1,ny),jz=1,nz)
                    write(2,rec=nvars*m+5) &
                    (((da(jx,jy,jz,m,1),jx=1,nx),jy=1,ny),jz=1,nz)
                    write(2,rec=nvars*m+6) &
                    (((db(jx,jy,jz,m,1),jx=1,nx),jy=1,ny),jz=1,nz)
                    if ( nfittime == 0 ) then
                        write(2,rec=nvars*m+7) &
                        (((cov(jx,jy,jz,m),jx=1,nx),jy=1,ny),jz &
                        =1,nz)
                        write(2,rec=nvars*m+8) &
                        (((relregr(jx,jy,jz,m),jx=1,nx),jy=1,ny &
                        ),jz=1,nz)
                    end if
                    write(2,rec=nvars*(m+1)) &
                    (((xn(jx,jy,jz,m),jx=1,nx),jy=1,ny &
                    ),jz=1,nz)
                else
!                   netCDF file
                    call writencslice(ncid,0,0,0,ivars(1,1) &
                        ,r(1,1,1,m),nxf,nyf,nzf,nx,ny,nz,m+1,1)
                    call writencslice(ncid,0,0,0,ivars(1,2) &
                        ,prob(1,1,1,m),nxf,nyf,nzf,nx,ny,nz,m+1,1)
                    call writencslice(ncid,0,0,0,ivars(1,3) &
                        ,a(1,1,1,m,1),nxf,nyf,nzf,nx,ny,nz,m+1,1)
                    call writencslice(ncid,0,0,0,ivars(1,4) &
                        ,b(1,1,1,m,1),nxf,nyf,nzf,nx,ny,nz,m+1,1)
                    call writencslice(ncid,0,0,0,ivars(1,5), &
                        da(1,1,1,m,1),nxf,nyf,nzf,nx,ny,nz,m+1,1)
                    call writencslice(ncid,0,0,0,ivars(1,6), &
                        db(1,1,1,m,1),nxf,nyf,nzf,nx,ny,nz,m+1,1)
                    if ( nfittime == 0 ) then
                        call writencslice(ncid,0,0,0,ivars(1,7) &
                            ,cov(1,1,1,m),nxf,nyf,nzf,nx,ny,nz,m+1 &
                            ,1)
                        call writencslice(ncid,0,0,0,ivars(1,8) &
                            ,relregr(1,1,1,m),nxf,nyf,nzf,nx,ny,nz &
                            ,m+1,1)
                    end if
                    call writencslice(ncid,0,0,0,ivars(1,nvars), &
                        xn(1,1,1,m),nxf,nyf,nzf,nx,ny,nz,m+1,1)
                end if
            end do
        end do
        if ( index(outfile,'.ctl') == 0 ) then
            i = nf_close(ncid)
        end if
    else                    ! subtract

!       subtract best fit from field1 and give this as output

        if ( mens > 0 ) then
            write(0,*) 'correlatefieldfield: cannot subtract ensembles (yet)'
            call exit(-1)
        end if
        nrec = 0
        fac = 1
        if ( lsum > 1 .and. oper == '+' ) fac = fac/lsum
        do yr=firstyr1,firstyr1 + (nt1-1)/nperyear
            if ( yr < firstyr2 .or. yr > firstyr2 + (nt2-1)/nperyear ) then
                if ( lwrite ) print *,'Invalid field at ',yr
                do mo=1,nperyear
                    do jz=1,nz
                        do jy=1,ny
                            do jx=1,nx
                                field1(jx,jy,jz,mo,yr,0) = 3e33
                            end do
                        end do
                    end do
                end do
            else            ! overlap with field2
                do mo=1,nperyear
                    if ( mo >= m1 .and. mo <= m2 ) then
                        m = mo-m1
                    else if (  mo > m2 .and. mo < m2+lsel .or. &
                        mo+nperyear > m2 .and. mo < m2+lsel ) then
                        m = m2-m1
                    else
                        m = -1
                    end if
                    if ( lwrite ) print *,'Using m=',m,' at mo=',mo
                    do jz=1,nz
                        do jy=1,ny
                            do jx=1,nx
                                if ( m >= 0 ) then
                                    if ( r(jx,jy,jz,m) < 1e33 .and. &
                                    field1(jx,jy,jz,mo,yr,0) &
                                     < 1e33 .and. &
                                    field2(jx,jy,jz,mo,yr,0) &
                                     < 1e33 ) then
                                        field1(jx,jy,jz,mo,yr,0) = &
                                        field1(jx,jy,jz,mo,yr,0) &
                                        - b(jx,jy,jz,m,1)*fac* &
                                        (field2(jx,jy,jz,mo,yr,0))
                                    !**     +                                        - mean2(jx,jy,jz,mo))
                                    else ! invalid point
                                        field1(jx,jy,jz,mo,yr,0) = &
                                        &                                             3e33
                                    end if
                                else ! invalid point
                                    field1(jx,jy,jz,mo,yr,0) = 3e33
                                end if
                            end do ! jy
                        end do ! jx
                    end do   ! jz
                end do       ! m
            end if           ! year OK
            do mo=1,nperyear
                nrec = nrec + 1
                if ( lwrite ) print *,'Writing new field1 for ',yr,mo
                write(2,rec=nrec) (((field1(jx,jy,jz,mo,yr,0),jx=1,nx),jy=1,ny),jz=1,nz)
            end do
        end do               ! yr
        if ( index(outfile,'.ctl') /= 0 ) then
            title = 'Data of '//datfile1(1:index(datfile1,' ')-1)// &
                ' with the effect of '//datfile2(1:index(datfile2,' ')-1)// &
                ' subtracted'
            nvars = 1
            vars(1) = 'var'
            ivars(1,1) = 0
            ivars(2,1) = 99
            lvars(1) = 'unknown, should be fixed'
            zz(1) = 0
            call writectl(outfile,datfile,nx,xx,ny,yy,1,zz &
                ,nt1,nperyear,firstyr1,1,3e33,title, &
                nvars,vars,ivars,lvars,units)
        end if
    end if                   ! subtract
    close(2)
    call savestartstop(yrstart,yrstop)

!   error messages

    goto 999
903 print *,'error reading date from file ',line(1:index(line,' ')-1),' at record ',k
    call exit(-1)
909 write(0,*) 'correlatefield: error: array too small ',n
    call exit(-1)
920 print *,'error cannot open new correlations file ' &
        ,datfile(1:index(datfile,' ')-1),' with record length ' &
        ,4*nx*ny*nz,4,nx,ny,nz
    call exit(-1)
999 continue
end program correlatefieldfield

subroutine findx(xi,f,n)

!   used by the multiple-parameter fitting routine (lfittime)

    implicit none
    include 'params.h'
    integer :: n
    real :: xi,f(n)
    real :: dddata(ndata),dindx(ndata)
    common /c_findx/ dddata,dindx
    integer :: i,j

    if ( n /= 2 ) goto 901
    i = nint(xi)
    if ( abs(xi-i) > 0.01 ) goto 902
    f(1) = dddata(i)
    f(2) = dindx(i)
    return
901 print *,'findx: should be called with n=2, not ',n
    call exit(-1)
902 print *,'findx: wrong input! ',xi
    call exit(-1)
end subroutine findx

subroutine dump060(xx,yy,zz,field,nxf,nyf,nzf,nx,ny,nz,nperyear,firstyr,lastyr)

!   dumps the field at 0,60N

    implicit none
    include 'params.h'
    integer :: nxf,nyf,nzf,nx,ny,nz,nperyear,firstyr,lastyr
    real :: xx(nx),yy(ny),zz(nz),field(nxf,nyf,nzf,nperyear,firstyr:lastyr)
    integer :: x1,x2,y1,y2,i,j,yr,mo
    real :: lon1,lat1,lon2,lat2,lon1c,lat1c,lon2c,lat2c,data(npermax,yrbeg:yrend)

    lon1 = 0
    lat1 = 60
    lon2 = 0
    lat2 = 60
    call getlonwindow(lon1,lon2,x1,x2,xx,nx,lon1c,lon2c, .false. )
    call getlatwindow(lat1,lat2,y1,y2,yy,ny,lat1c,lat2c, .false. )
    if ( lon1c > 1e33 .or. lat1c >= 1e33 ) then
        x1 = 1
        lon1c = xx(1)
        y1 = 1
        lat1c = yy(1)
    end if
    print *,'cutting out longitude ',x1,x2,lon1c,lon2c
    print *,'cutting out latitude  ',y1,y2,lat1c,lat2c
    call makeabsent (data,npermax,yrbeg,yrend)
    do yr=max(yrbeg,firstyr),min(lastyr,yrend)
        do mo=1,nperyear
            data(mo,yr) = field(x1,y1,1,mo,yr)
        end do
    end do
    call printdatfile(6,data,npermax,nperyear,yrbeg,yrend)
end subroutine dump060
