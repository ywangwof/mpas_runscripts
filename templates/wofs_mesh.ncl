load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/gsn_code.ncl"
load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/gsn_csm.ncl"

begin

  r2d = 57.2957795             ; radians to degrees

  maxedges = 6

  wks = gsn_open_wks("png","OUTFILENAME")
  gsn_define_colormap(wks,"BlAqGrYeOrReVi200")

  f = addfile("INPUTFILENAME","r")

  g = addfile("geo_em.d01.nc","r")

  xVertex = f->xVertex(:)
  yVertex = f->yVertex(:)
  zVertex = f->zVertex(:)
  verticesOnCell = f->verticesOnCell(:,:)
  verticesOnEdge = f->verticesOnEdge(:,:)
  x   = f->lonCell(:) * r2d
  y   = f->latCell(:) * r2d
  lonCell = f->lonCell(:) * r2d
  latCell = f->latCell(:) * r2d
  lonVertex = f->lonVertex(:) * r2d
  latVertex = f->latVertex(:) * r2d
  lonEdge = f->lonEdge(:) * r2d
  latEdge = f->latEdge(:) * r2d

  xlat = g->XLAT_C(0,:,:)
  xlon = g->XLONG_C(0,:,:)

  res                      = True
  ;res@gsnMaximize          = True
  ;res@gsnSpreadColors      = True

  ;res@sfXArray             = x
  ;res@sfYArray             = y

  ;res@cnFillOn             = False
  ;;res@cnFillMode           = "RasterFill"
  ;res@cnFillOpacityF        = 0.4
  ;res@cnLinesOn            = True
  ;res@cnLineLabelsOn       = False
  ;res@cnInfoLabelOn        = True
  ;res@cnFillPattern        = -1

  ;res@lbLabelAutoStride    = True
  ;res@lbBoxLinesOn         = False

  res@mpProjection      = "CylindricalEquidistant"
  res@mpDataBaseVersion = "MediumRes"
  res@mpOutlineBoundarySets   = "GeophysicalAndUSStates"          ; turn on state boundaries
  res@mpUSStateLineColor      = "black"
  res@mpOutlineDrawOrder      = "PostDraw"
  res@mpOceanFillColor       = "cyan"                        ; selects the light blue color from the colormap.
  res@mpLandFillColor        = "sienna"                       ;  selects the dark orange color from the colormap.
  res@mpInlandWaterFillColor = "cyan"                 ; selects the dark blue color from the colormap.
  res@mpCenterLatF                = 0
  res@mpCenterLonF                = -97
  res@mpMaxLatF                   = 55           ; choose subregion
  res@mpMinLatF                   = 22
  res@mpMaxLonF                   = -65
  res@mpMinLonF                   = -130
  res@mpGridAndLimbOn       = True
  ;res@mpGridLineColor       = "transparent"  ; trick ncl into drawing perimeter
  res@mpGridLonSpacingF  = 15.0
  res@mpGridLatSpacingF  = 15.0
  res@mpGridLineColor    = "lightgray"
  res@mpGridLineDashPattern = 1
  res@mpOutlineOn       = True
  res@mpFillOn          = True
  res@mpPerimOn         = False
  res@gsnFrame          = False

  res@tiMainString      = "WOFS Domain on DATESTRING"

  ;res@lbLabelBarOn      = False

  ;h   = f->areaCell(:)

  ;res@cnConstFLabelOn = False
  ;map = gsn_csm_contour_map(wks,h,res)
  map = gsn_csm_map(wks,res)

  lres = True
  lres@gsLineThicknessF = 0.10
  lres@gsLineColor      = "yellow"

  esizes = dimsizes(latEdge)
  ecx = new((/esizes(0),2/),double)
  ecy = new((/esizes(0),2/),double)
  do j=0,esizes(0)-1
     ecy(j,0) = latVertex(verticesOnEdge(j,0)-1)
     ecx(j,0) = lonVertex(verticesOnEdge(j,0)-1)
     ecy(j,1) = latVertex(verticesOnEdge(j,1)-1)
     ecx(j,1) = lonVertex(verticesOnEdge(j,1)-1)
  end do

  do j=0,esizes(0)-1
     if (abs(ecx(j,0) - ecx(j,1)) .gt. 180.0) then
        if (ecx(j,0) .gt. ecx(j,1)) then
           ecx(j,0) = ecx(j,0) - 360.0
        else
           ecx(j,1) = ecx(j,1) - 360.0
        end if
     end if
  end do

  ;print((esizes(0)-1)/4)
  do j=0,(esizes(0)-1)
     ;print("plotting "+j)
     gsn_polyline(wks,map,ecx(j,:),ecy(j,:),lres)
  end do

  ; draw virtual WRF output grid

  lres = True
  lres@gsLineThicknessF = 1.00
  lres@gsLineColor      = "blue"

  xsizes = dimsizes(xlat)
    gsn_polyline(wks,map,xlon(          0,:),xlat(          0,:),lres)
    gsn_polyline(wks,map,xlon(xsizes(0)-1,:),xlat(xsizes(0)-1,:),lres)
    gsn_polyline(wks,map,xlon(:,0          ),xlat(:,0          ),lres)
    gsn_polyline(wks,map,xlon(:,xsizes(1)-1),xlat(:,xsizes(1)-1),lres)

  frame(wks)

end

