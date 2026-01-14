;----------------------------------------------------------------------
; David Dowell, 26 August 2025
; Plot observations, forecasts, or differences from JEDI jdiag files.
;----------------------------------------------------------------------

load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/gsn_code.ncl"
load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/gsn_csm.ncl"
load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/contributed.ncl"
load "$NCARG_ROOT/lib/ncarg/nclscripts/wrf/WRFUserARW.ncl"

;----------------------------------------------------------------------
; Procedure for adding a labelbar at a given NDC location, given
; the levels and colors to use.
; based on code in polyg_8_lbar.ncl
;----------------------------------------------------------------------
undef("add_labelbar")
procedure add_labelbar(wks,plot,levels,colors)
local lbres, labels
begin
  nlevels = dimsizes(levels)
;----------------------------------------------------------------------
; Draw a labelbar
;----------------------------------------------------------------------
  lbres                    = True
  lbres@vpWidthF           = 0.80             ; width
  lbres@vpHeightF          = 0.10             ; height
  lbres@lbPerimOn          = False            ; Turn off perimeter.
  lbres@lbOrientation      = "Horizontal"     ; Default is vertical.
  lbres@lbLabelAlignment   = "InteriorEdges"  ; Default is "BoxCenters"
  lbres@lbFillColors       = colors           ; Colors for boxes.
  lbres@lbMonoFillPattern  = True             ; Fill them all solid.
  lbres@lbLabelFontHeightF = 0.012            ; label font height

  labels = sprintf("%4.2f",levels)

  lbid = gsn_create_labelbar(wks,nlevels+1,labels,lbres)

  amres                  = True
  amres@amJust           = "TopCenter"
  amres@amParallelPosF   =  0.0   ; keep labelbar centered
  amres@amOrthogonalPosF =  0.56 ; 0.6   ; move down and outside of plot

  tmpid1 = "anno"+unique_string("id")
  tmpid2 = "lbar"+unique_string("id")

  plot@$tmpid1$ = gsn_add_annotation(plot,lbid,amres)
  plot@$tmpid2$ = lbid
end

begin
; -------------------------------------------------------------------------------
; ** BEGIN INPUT PARAMETERS ***

z_meters = 3000.0

ob_file = (/ "/mnt/lfs5/NAGAPE/hpc-wof1/ywang/MPAS-WoFS/run_dirs/20240508/dacycles_CADRE2_RUC_20260105/1900/getkf_observer/jdiag_mrms_refl.nc" /)
forecast = 1

;  ob_file = (/ "rrfs_getkf_post_13_v2.1.1/enkf/jdiag_mrms_refl.nc" /)
;  forecast = 0

ref_ob_file = "/mnt/lfs5/NAGAPE/hpc-wof1/ywang/MPAS-WoFS/run_dirs/20240508/dacycles_CADRE2_RUC_20260105/1900/getkf_post/jdiag_mrms_refl.nc"

levels = (/-5.0, 5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0, 45.0, 50.0, 55.0, 60.0, 65.0, 70.0, 75.0 /)
diff_levels = (/-5.0, -3.0, -2.0, -1.0, -0.5, 0.5, 1.0, 2.0, 3.0, 5.0/)
abs_diff_levels = (/ 2.0, 4.0, 6.0, 8.0, 10.0, 12.0/)

ob_colors = "prcp_1"
diff_colors = "CBR_coldhot"
;  diff_colors = "CBR_drywet"
abs_diff_colors = "drought_severity"

subtract_ref_ob = 0      ; plot difference between observations in ob_file and ref_ob_file? (0=no, 1=yes)

plot_max_bin_only = 0    ; plot markers only for the bin with the highest values?  (0=no, 1=yes)


; May 8
LeftCornerLatF  = 31.9
LeftCornerLonF  = -95.5
RightCornerLatF = 40.2
RightCornerLonF = -85.0

; HRRR CONUS
;LeftCornerLatF  = 21.1381
;LeftCornerLonF  = -122.72
;RightCornerLatF = 47.8578
;RightCornerLonF = -60.8495

; ** END INPUT PARAMETERS ***
; -------------------------------------------------------------------------------

n_ob_files = dimsizes(ob_file)

if (subtract_ref_ob .eq. 1) then
  rf = addfile(ref_ob_file,"r")
end if

mpres                       = True
mpres@gsnMaximize           = True             ; Maximize plot in frame.
mpres@gsnDraw               = False            ; Will draw later
mpres@gsnFrame              = False            ; Don't advance the frame
mpres@pmTickMarkDisplayMode = "Always"
mpres@mpProjection          = "LambertConformal"
mpres@mpOutlineDrawOrder    = "PostDraw"               ; draw continental outline last
mpres@mpDataBaseVersion = "MediumRes"
mpres@mpOutlineBoundarySets = "GeophysicalAndUSStates" ; state boundaries
;mpres@mpOutlineBoundarySets = "AllBoundaries"          ; state and county boundaries
mpres@mpUSStateLineThicknessF = 2.0
mpres@mpFillOn = False

; HRRR / RRFS
;mpres@mpLambertParallel1F   = 38.5
;mpres@mpLambertParallel2F   = 38.5
;mpres@mpLambertMeridianF    = -97.5

; MPAS south3.5km
mpres@mpLambertParallel1F   = 34.0
mpres@mpLambertParallel2F   = 34.0
mpres@mpLambertMeridianF    = -91.5

mpres@mpLimitMode           = "Corners"            ; choose range of map
mpres@mpLeftCornerLatF      = LeftCornerLatF
mpres@mpLeftCornerLonF      = LeftCornerLonF
mpres@mpRightCornerLatF     = RightCornerLatF
mpres@mpRightCornerLonF     = RightCornerLonF

gsres               = True
gsres@gsMarkerIndex = 16

; -------------------------------------------------------------------------------

; Loop over number of files
do fi = 0, n_ob_files-1

  f = addfile(ob_file(fi),"r")

  g = f=>/MetaData
  lat = g->latitude
  lon = g->longitude
  height = g->height

  g = f=>/ObsError
  error = g->equivalentReflectivityFactor

  g = f=>/ObsValue
  if (subtract_ref_ob .eq. 1) then
    print("*** work on this section ***")
    exit
  else
    ob = g->equivalentReflectivityFactor
  end if

  g = f=>/PreQC
  qc = g->equivalentReflectivityFactor

  g = f=>/hofx0_1
  hofx_mem1 = g->equivalentReflectivityFactor

  g = f=>/hofx_y_mean_xb0
  hofx_mean = g->equivalentReflectivityFactor

  if (forecast .eq. 1) then
    g = f=>/ombg
    omb = g->equivalentReflectivityFactor
  else
    g = f=>/oman
    oma = g->equivalentReflectivityFactor
  end if

  npts = dimsizes(lat)

  do n_plots = 1, 6

    if (n_plots .eq. 1) then
      nlevels = dimsizes(levels)
      colors  = span_color_rgba(ob_colors,nlevels+1)
      q = ob
      mpres@tiMainString = "ob " + z_meters + " m AGL " + ob_file(fi)
      plot_name = "ob"
    end if
    if (n_plots .eq. 2) then
      nlevels = dimsizes(levels)
      colors  = span_color_rgba(ob_colors,nlevels+1)
      q = hofx_mem1
      if (forecast .eq. 1) then
        mpres@tiMainString = "mem1 forecast " + z_meters + " m AGL " + ob_file(fi)
        plot_name = "mem1f"
      else
        mpres@tiMainString = "mem1 analysis " + z_meters + " m AGL " + ob_file(fi)
        plot_name = "mem1a"
      end if
    end if
    if (n_plots .eq. 3) then
      nlevels = dimsizes(levels)
      colors  = span_color_rgba(ob_colors,nlevels+1)
      q = hofx_mean
      if (forecast .eq. 1) then
        mpres@tiMainString = "mean forecast " + z_meters + " m AGL " + ob_file(fi)
        plot_name = "meanf"
      else
        mpres@tiMainString = "mean analysis " + z_meters + " m AGL " + ob_file(fi)
        plot_name = "meana"
      end if
    end if
    if (n_plots .eq. 4) then
      nlevels = dimsizes(diff_levels)
      colors  = span_color_rgba(diff_colors,nlevels+1)
      if (forecast .eq. 1) then
        q = -omb
        mpres@tiMainString = "(F-O) " + z_meters + " m AGL " + ob_file(fi)
        plot_name = "fmo"
      else
        q = -oma
        mpres@tiMainString = "(A-O) " + z_meters + " m AGL " + ob_file(fi)
        plot_name = "amo"
      end if
    end	if
    if (n_plots .eq. 5) then
      nlevels = dimsizes(abs_diff_levels)
      colors  = span_color_rgba(abs_diff_colors,nlevels+1)
      if (forecast .eq. 1) then
        q = abs(omb)
        mpres@tiMainString = "|F-O| " + z_meters + " m AGL " + ob_file(fi)
        plot_name = "abs_fmo"
      else
        q = abs(oma)
        mpres@tiMainString = "|A-O| " + z_meters + " m AGL " + ob_file(fi)
        plot_name = "abs_amo"
      end if
    end if
    if (n_plots .eq. 6) then
      nlevels = dimsizes(abs_diff_levels)
      colors  = span_color_rgba(abs_diff_colors,nlevels+1)
      q = error
      q = where(ismissing(q), 100.0, q)
      mpres@tiMainString = "ob error " + z_meters + " m AGL " + ob_file(fi)
      plot_name = "ob_error"
    end if

 ;  mpres@tiMainString = ""
    mpres@tiMainFontHeightF = 0.010

    wks = gsn_open_wks("png",plot_name)       ; png, pdf

    map = gsn_csm_map(wks,mpres)

    num_distinct_markers = nlevels+1
    lat_new = new((/num_distinct_markers,npts/),double,-999)
    lon_new = new((/num_distinct_markers,npts/),double,-999)

    do i = 0, num_distinct_markers-1

      if ( (n_plots .eq. 1) .or. (n_plots .eq. 2) .or. (n_plots .eq. 3) ) then
        if (i.eq.0) then
          indexes = ind( (height.eq.z_meters) .and. (q.lt.levels(0)) )
        end if
        if (i.eq.num_distinct_markers-1) then
          indexes = ind( (height.eq.z_meters) .and. (q.ge.max(levels)) )
        end if
        if (i.gt.0.and.i.lt.num_distinct_markers-1) then       
          indexes = ind( (height.eq.z_meters) .and. (q.ge.levels(i-1)) .and. (q.lt.levels(i)) )
        end if
      end if
      if (n_plots .eq. 4) then
        if (i.eq.0) then
          indexes = ind( (height.eq.z_meters) .and. (q.lt.diff_levels(0)) )
        end if	
        if (i.eq.num_distinct_markers-1) then
          indexes = ind( (height.eq.z_meters) .and. (q.ge.max(diff_levels)) )
        end if
        if (i.gt.0.and.i.lt.num_distinct_markers-1) then
          indexes = ind( (height.eq.z_meters) .and. (q.ge.diff_levels(i-1)) .and. (q.lt.diff_levels(i)) )
        end if
      end if
      if ( (n_plots .eq. 5) .or. (n_plots .eq. 6) ) then
        if (i.eq.0) then
          indexes = ind( (height.eq.z_meters) .and. (q.lt.abs_diff_levels(0)) )
        end if
        if (i.eq.num_distinct_markers-1) then
          indexes = ind( (height.eq.z_meters) .and. (q.ge.max(abs_diff_levels)) )
        end if
        if (i.gt.0.and.i.lt.num_distinct_markers-1) then
          indexes = ind( (height.eq.z_meters) .and. (q.ge.abs_diff_levels(i-1)) .and. (q.lt.abs_diff_levels(i)) )
        end if
      end if

      if (.not.any(ismissing(indexes))) then 
        npts_range = dimsizes(indexes)   ; # of points in this range.
        lat_new(i,0:npts_range-1) = lat(indexes)
        lon_new(i,0:npts_range-1) = lon(indexes)
      end if

      print(i + ", " + dimsizes(indexes))

      delete(indexes)

    end do

;    base_size = 0.010
    base_size = 0.005

    pmid = new(num_distinct_markers,graphic)

    if (plot_max_bin_only .eq. 1) then
      i_min = num_distinct_markers-1
      i_max = num_distinct_markers-1
    else
      i_min = 0
      i_max = num_distinct_markers-1
    end if

   do i = i_min, i_max

     if (.not.ismissing(lat_new(i,0))) then
;      if ( .not.ismissing(lat_new(i,0)) .and. (i.ne.(nlevels/2)) ) then   ; don't plot dots for middle of contour levels

        gsres@gsMarkerColor      = colors(i,:)
        gsres@gsMarkerSizeF      = base_size
        gsres@gsMarkerThicknessF = 1.0
        pmid(i) = gsn_add_polymarker(wks,map,lon_new(i,:),lat_new(i,:),gsres)

      end if
    end do

    if ( (n_plots .eq. 1) .or. (n_plots .eq. 2) .or. (n_plots .eq. 3)  ) then
      add_labelbar(wks,map,levels,colors)
    end if
    if (n_plots .eq. 4) then
      add_labelbar(wks,map,diff_levels,colors)
    end if
    if ( (n_plots .eq. 5) .or. (n_plots .eq. 6) ) then
      add_labelbar(wks,map,abs_diff_levels,colors)
    end if
    draw(map)

    txres                              = True
    txres@txFont                       = 21
    txres@txFontHeightF                = 0.015
;    gsn_text_ndc(wks,ob_file(fi),0.5,0.85,txres)

    frame(wks)

    delete(lat_new)
    delete(lon_new)
    delete(pmid)
    delete(colors)
    delete(map)
    delete(q)

  end do    ; do n_plots

  delete(lat)
  delete(lon)
  delete(height)
  delete(qc)
  delete(ob)
  delete(f)

end do      ; do fi = 0, n_ob_files-1

if (subtract_ref_ob .eq. 1) then
  delete(rf)
end if

print("")
print("Plotting completed")
print("")

end

