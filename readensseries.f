        subroutine readensseries(file,data,npermax,yrbeg,yrend,nensmax
     +        ,nperyear,mens1,mens,var,units,lstandardunits,lwrite)
*       
*       read a data file or an ensemble of data files in the array data
*       also returns the number of ensemble members in mens, 0=not an
*       ensemble
*       
        implicit none
        integer npermax,yrbeg,yrend,nperyear,nensmax,mens1,mens
        real data(npermax,yrbeg:yrend,0:nensmax)
        logical lstandardunits,lwrite
        character file*(*),var*(*),units*(*)
        integer iens
        logical lexist
        character ensfile*255,line*10
        integer llen
        external llen

        if ( lwrite ) then
            print *,'readensseries: file = ',trim(file)
            print *,'               npermax,yrbeg,yrend = ',npermax
     +           ,yrbeg,yrend
        endif
*       
*       ensembles are denoted by a '%' or '++' in the file name
*
        if ( index(file,'%').eq.0 .and. index(file,'++').eq.0 ) then
            mens = 0
            mens1 = 0
            if ( lwrite ) print *,'not an ensemble, calling readseries'
            call readseries(file,data(1,yrbeg,0),npermax,yrbeg,yrend
     +           ,nperyear,var,units,lstandardunits,lwrite)
        else
            mens = -1
            mens1 = 0
            do iens=0,nensmax
                ensfile = file
                call filloutens(ensfile,iens)
                !!!if ( lwrite) print *,'looking for file ',trim(ensfile)
                inquire(file=ensfile,exist=lexist)
                if ( .not.lexist ) then
                    if ( mens.eq.-1 ) then
                        mens1 = iens + 1
                    end if
                else
                    mens = iens
                end if
            end do
            if ( mens.lt.0 ) then
                write(0,*)
     +                'readensseries: error: could not find ensemble '
     +                ,trim(file),trim(ensfile)
                call abort
            endif
            do iens=mens1,mens
                ensfile = file
                call filloutens(ensfile,iens)
                inquire(file=ensfile,exist=lexist)
                if ( .not.lexist ) then
                    data(:,:,iens) = 3e33
                else
                    if ( lwrite) print *,'reading file ',trim(ensfile)
                    call keepalive1('Reading ensemble member',iens,mens)
                    call readseries(ensfile,data(1,yrbeg,iens),npermax
     +                   ,yrbeg,yrend,nperyear,var,units,lstandardunits
     +                   ,.false.)
                end if
            enddo
        endif
        end
