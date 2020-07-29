#ifndef L8ANG_H
#define L8ANG_H

#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include "mfhdf.h"
#include "hls_commondef.h"
#include "hdfutility.h"
#include "util.h"
#include "fillval.h"
#include "lsat.h"    /* only for constant L8NRB */

#ifndef L1TSCENEID
#define L1TSCENEID "L1T_SceneID"
#endif

#define SZ "solar_zenith"
#define SA "solar_azimuth"
#define VZ "view_zenith"	/* VZ and VA are part of the SDS name for a band. */
#define VA "view_azimuth"

/* SDS name for the tiled angle */ 
static char *L8_SZ = "solar_zenith";
static char *L8_SA = "solar_azimuth";
static char *L8_VZ = "view_zenith";
static char *L8_VA = "view_azimuth";

typedef struct {
	char fname[NAMELEN];
	intn access_mode;
	double ulx;
	double uly;	
	char numhem[20]; 	/* UTM zone number and hemisphere spec */
	int nrow;
	int ncol;
	char l1tsceneid[200];	/* The L1T scene ID for an S2 tile */

	int32 sd_id;
	int32 sds_id_sz;
	int32 sds_id_sa;
	int32 sds_id_vz;
	int32 sds_id_va; 

	int16 *sz;
	int16 *sa;
	int16 *vz;	
	int16 *va;

	char tile_has_data; /* A scene and a tile may overlap so little that there is no data at all */  
} l8ang_t;

/* Read scene-based L8 sun/view zenith/azimuth angle into a structure described in l8ang_t.
 * This is needed for the gridding of the scene-based angle into MGRS tiles.
 *
 * There are four types of angles in four files: solar zenith, solar azimuth,
 * band 4 (red) view zenith and azimuth. The red band angle is representative 
 * of all spectral bands. 
 *
 * The angle is produced by USGS in COG format, and HLS converts it to plain binary 
 * for easier read, for example:
 * convert 
 *   LC08_L1TP_140041_20130503_20200330_02_T1_SZA.TIF
 * to
 *   LC08_L1TP_140041_20130503_20200330_02_T1_SZA.img
 * The parameter filename of this function is the one for SZA , from which filenames 
 * for SZA, VZA, VAA can be inferred.
 *
 * A related function is open_l8ang(l8ang_t  *l8ang, intn access_mode) which
 * reads or writes the angle in the tiled format described in l8ang.h.
 * 
 * USGS code saves azimuth that is greater 180 as (azimuth-360). 
 */
int read_l8ang_inpathrow(l8ang_t  *l8ang, char *fname);

/* Open tile-based L8 angle for READ, CREATE, or WRITE. */
int open_l8ang(l8ang_t  *l8ang, intn access_mode); 

/* Add sceneID as an HDF attribute. A sceneID is added to the angle output HDF when it is
 * first created.  And a second scene can fall on the scame S2 tile (adjacent row in the same orbit), 
 * and this function adds the sceneID of the second scene.
 * lsat.h has a similar function.
 */
int l8ang_add_l1tsceneid(l8ang_t *l8ang, char *l1tsceneid);

/* close */
int close_l8ang(l8ang_t  *l8ang);

#endif
