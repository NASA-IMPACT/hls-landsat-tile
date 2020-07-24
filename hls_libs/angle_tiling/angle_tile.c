/* Render the solar-view angle of a Landsat scene into an ovelapping 
 * Sentinel-2 tile. Both systems use UTM, but the zone numbers may be different. 
 * 
 * A nearest-neighbor resampling is sufficient. The sub-pixel geolocation error of 
 * L8 does not matter, i.e., no AROP needed. 
 * 
 * Note that Landsat data Y coordinate does not use a false northing for 
 * the southern hemisphere as the S2 does.
 */

#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include "l8ang.h"
#include "hls_commondef.h"
#include "hls_projection.h"
#include "error.h"
#include "util.h"

int main(int argc, char *argv[])
{
	char s2tileid[20];		/* The output S2 tile id. */
	double s2ulx;			
	double s2uly;	/* The uly of S2 observing the false northing standard for southern hemisphere */ 
	char fname_in[LINELEN];		/* angle in scene */
	char fname_out[LINELEN];	/* angle in tile */

	char s2numhem[10]; 	/* UTM zone number and the hemisphere spec. e.g. 13S,  13N*/
	int l8zone, s2zone;

	l8ang_t angin; 	/* Angle in scene */ 
	l8ang_t angout;	/* Angle in tile */

	int irow, icol;
	double lsatx, lsaty;
	double s2x, s2y;
	/* For southern hemisphere, use GCTP convention in resampling input; output is still in S2 standard */
	double s2ulyGCTP;   	
	int ib;
	int k;
	int ret;
	char *pos;

	char update_outfile;    /* For update or create new */
	char l1tsceneid[50];
	char message[MSGLEN];

	if (argc != 6) {
		fprintf(stderr, "%s s2tileid s2ulx s2uly angScene angTile \n", argv[0]);
		exit(1);
	}

	strcpy(s2tileid,         argv[1]);
	s2ulx  =            atof(argv[2]);
	s2uly  =            atof(argv[3]);
	strcpy(fname_in,         argv[4]);
	strcpy(fname_out,        argv[5]);
	
	/* Read the scene-based input */
	ret = read_l8ang_inpathrow(&angin, fname_in);
	if (ret != 0) {
		Error("Error in open_l8ang()");
		exit(1);
	}
	//fprintf(stderr, "numhem, ulx, uly = %s %.0lf %.0lf\n", angin.numhem, angin.ulx, angin.uly);

	/* Create tile-based output */
	s2zone = atoi(s2tileid);
	sprintf(s2numhem, "%02d%s",  s2zone, s2tileid[2] >= 'N'?  "N" : "S"); 
	strcpy(angout.fname, fname_out);
	strcpy(angout.numhem, s2numhem);
	angout.ulx = s2ulx;
	angout.uly = s2uly;
	angout.nrow = S2TILESZ/HLS_PIXSZ;	/* S2 tile of 30-m pixels */
	angout.ncol = angout.nrow;
	if (file_exist(fname_out)) {
		update_outfile = 1;
		ret = open_l8ang(&angout, DFACC_WRITE);
		if (ret != 0) {
			Error("Error in open_l8ang()");
			exit(1);
		}
	}
	else {
		update_outfile = 0;
		ret = open_l8ang(&angout, DFACC_CREATE);
		if (ret != 0) {
			Error("Error in open_l8ang()");
			exit(1);
		}
	}
	
	if (strstr(s2numhem, "S"))
		s2ulyGCTP = s2uly - 10000000;	/* Just accommodate GCTP. The output header uses the standard */
	else
		s2ulyGCTP = s2uly;

	l8zone = atoi(angin.numhem);
	if (l8zone == s2zone) {
		double ydiff;
		
		ydiff = (s2ulyGCTP-angin.uly);
		fprintf(stderr, "ulx.diff, uly.diff = %lf, %lf\n", (angout.ulx-angin.ulx)/30, ydiff/30);
	}
	else {
		//fprintf(stderr, "Zone different. %d, %d.  Reproject.\n", l8zone, s2zone);
		fprintf(stderr, "Zone different. Resample from the input zone \n");
	}

	if (update_outfile) 
		angout.tile_has_data = 1;
	else
		angout.tile_has_data = 0;
	int lsatrow, lsatcol;
	int kin, kout;
	double xinzone, yinzone; /* x, y in the input zone, which may be different from S2 zone */ 
	for (irow = 0; irow < angout.nrow; irow++) {
		s2y = s2ulyGCTP  - (irow+0.5) * HLS_PIXSZ;
		for (icol = 0; icol < angout.ncol; icol++) {
			s2x = s2ulx + (icol+0.5) * HLS_PIXSZ;

			if (l8zone != s2zone) {
				utm2utm(s2zone, s2x, s2y, l8zone, &xinzone, &yinzone);
				lsatx = xinzone;
				lsaty = yinzone;
			}
			else {
				lsatx = s2x;
				lsaty = s2y;
			}

			lsatrow = floor((angin.uly - lsaty) / HLS_PIXSZ); 
			lsatcol = floor((lsatx - angin.ulx) / HLS_PIXSZ); 
			if (lsatrow < 0 || lsatrow > angin.nrow-1 || lsatcol < 0 || lsatcol > angin.ncol-1)
				continue;
	
			kin = lsatrow * angin.ncol + lsatcol;
			kout = irow * angout.ncol + icol;
			
			if (angin.sz[kin] != LANDSAT_ANGFILL ) { 
				angout.sz[kout] = angin.sz[kin];
				angout.sa[kout] = angin.sa[kin];

				/* No pan, no cirrus */
				for (ib = 0; ib < L8NRB-1; ib++) {
					angout.vz[ib][kout] = angin.vz[ib][kin];
					angout.va[ib][kout] = angin.va[ib][kin];
				}
				
				angout.tile_has_data = 1;
			}
		}
	}

	/* Set L1T scene ID, 21 chars:   eg  LC81750822016057LGN00  
	 * Modification on Jun 7, 2017: Collection-base data uses a new file naming format.
 	 * Although scene ID remains the same as that in the pre-collection data, but it is
	 * no longer embedded in the filename and has to be found from the MTL file. So we 
	 * call the basename of the TOA file without the ".tar.gz" the scene ID.
	 * Since the angle input can be in two format, for simplity we just call the basename
	 * of the input angle file as scene ID; no need to be rigorous with names for this
	 * intermediate files. */
	/* If the output file already exists, append the current scene ID to the previous one */

	pos = strrchr(fname_in, '/');
	if (pos == NULL)
		pos = fname_in;
	else 
		pos++;
	strcpy(l1tsceneid, pos);
	l8ang_add_l1tsceneid(&angout, l1tsceneid);

	/*****/
	close_l8ang(&angout);

	return 0;
}
