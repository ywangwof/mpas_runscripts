#!/usr/bin/env python3

import math

EARTH_RADIUS = 6371  # KM

########################################################################

def km2radian(x_in_km):
    ''' Computer localization_cutoffs'''

    #radians=(x_in_km / EARTH_RADIUS) / 2.

    cut_off = 2*math.pi*x_in_km/40000
    return cut_off

########################################################################

def vert_norm_height(y_in_km,cut_off):
    '''Compute vert_normalization_heights '''

    vnh = y_in_km*1000./cut_off

    return vnh

########################################################################

def vnh2Y(vnh,cut_off):
    '''Compute vert_normalization_heights '''

    y_in_km = vnh * cut_off/1000.

    return y_in_km

########################################################################

def radian2km(radian):

    x_in_km = radian*2.0*EARTH_RADIUS
    return x_in_km

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

if __name__ == "__main__":

    for x in [3,4,6,8,9,10,20]:             # the maximum horizontal distance that an observation
                                            # can possibly influence something in the model state. X km
        cut_off = km2radian(x)
        vnh = vert_norm_height(x,cut_off)
        print(f"{x} km -> cut_off = {cut_off}")

    for x in [3,9]:
        cut_off = km2radian(x)
        for y in [2.945,3,4.5]:             # The maximum vertical separation of y km (if localizing in height)
            vnh = vert_norm_height(y,cut_off)
            print(f"x= {x} km, y = {y} km -> cut_off = {cut_off}; VNH = {vnh}")

        for h in [2083333.2,3183098.9]:      # the vertical distances translated to radians
            hgt = vnh2Y(h,cut_off)
            print(f"x= {x} km, vnh = {h} rads -> cut_off = {cut_off}; heights = {hgt}")
