/* Adjust Landsat surface reflectance to nadir view and annual mean solar 
 * zenith angle at the tile center.  Save output as HDF-EOS.
 * 
 * Save the c-factor in a separate hdf.
 */

#include "hls_commondef.h"
#include "lsat.h"
#include "l8ang.h"
#include "modis_brdf_coeff.h"
#include "rtls.h"
#include "cfactor.h"
#include "mean_solarzen.h"
#include "util.h"
#include "hls_hdfeos.h"

int main(int argc, char *argv[])
{
	/* Command line parameters */
	char fname_in[LINELEN]; 	/* Both input and output */ 
	char fname_ang[LINELEN];
	char fname_cfactor[LINELEN];

	l8ang_t l8ang;	/* 30-m angles */
	lsat_t lsatin;		/* Input and output reflectance */
	cfactor_t cfactor;	/* output BRDF ancillary; cfactor for each band */

	int ib, irow, icol, k; 

	float sz, sa, vz, va, ra;

	double msz;	/* Mean solar zenith for a location*/
	double rossthick_MSZ, lisparseR_MSZ;	/* kernels at nadir view and the mean solar zenith */
	double ratio;
	double tmpref;
	double cenlon, cenlat;
	char creationtime[100];

	int ret;

	if (argc != 4) {
		fprintf(stderr, "Usage: %s insr.hdf ang.hdf cfactor.hdf \n", argv[0]);
		exit(1);
	}

	strcpy(fname_in,      argv[1]);
	strcpy(fname_ang,     argv[2]);
	strcpy(fname_cfactor, argv[3]);

	/* Open input for update and save as output */
	strcpy(lsatin.fname, fname_in);
	ret = open_lsat(&lsatin, DFACC_WRITE);
	if (ret != 0) {
		Error("Error in open_lsat");	
		exit(1);
	}

	/* Read angles */
	strcpy(l8ang.fname, fname_ang);
	ret = open_l8ang(&l8ang, DFACC_READ);
	if (ret != 0) {
		Error("Error in open_l8ang");	
		exit(1);
	}
	
	/* Create the brdf ancillary file */
	strcpy(cfactor.fname, fname_cfactor);
	cfactor.nrow = lsatin.nrow;
	cfactor.ncol = lsatin.ncol;
	ret = open_cfactor(LANDSAT8, &cfactor, DFACC_CREATE);
	if (ret != 0) {
		Error("Error in open_cfactor");
		exit(1);
	}

	/* Solar zenith used in BRDF adjustment. */
	/* Example basename of filename: HLS.L30.T03VXH.2019202.v1.4.hdf */
	char *cp;	
	int yeardoy, year, doy;
	cp = strrchr(lsatin.fname, '/');	/* find basename */
	if (cp == NULL)
		cp = lsatin.fname;
	else
		cp++;
	/* Skip to yeardoy */
	cp = strchr(cp, '.'); cp++;
	cp = strchr(cp, '.'); cp++;
	cp = strchr(cp, '.'); cp++;
	yeardoy = atoi(cp);
	year = yeardoy / 1000;
	doy = yeardoy - year * 1000;

	msz = mean_solarzen(lsatin.zonehem, 
			    lsatin.ulx+(lsatin.ncol/2.0 * HLS_PIXSZ),
			    lsatin.uly-(lsatin.nrow/2.0 * HLS_PIXSZ),
			    year,
			    doy);

	SDsetattr(lsatin.sd_id, "NBAR_Solar_Zenith", DFNT_FLOAT64, 1, (VOIDP)&msz);

	/* Update processing time */
	getcurrenttime(creationtime);
	SDsetattr(lsatin.sd_id, "HLS_PROCESSING_TIME", DFNT_CHAR8, strlen(creationtime), (VOIDP)creationtime);

	/* Spatial and cloud cover */
	lsat_setcoverage(&lsatin);

	rossthick_MSZ = RossThick(msz, 0, 0);
	lisparseR_MSZ = LiSparseR(msz, 0, 0); 

	/* The index of a band in the BRDF coefficient array */
	int specidx = -1;

	/* The input granule definitely has reflectance data. 
	 * If not, it wouldn't appear here for BRDF correction. 
	 * Remember to set; otherwise the file will be deleted after closing*/
	lsatin.tile_has_data = 1;	

	for (ib = 0; ib < L8NRB-1; ib++) {
		/* ib = L8NRB-1 corresponds to cirrus; ignored. 
		 * Bug fix on Apr 6, 2017: Originally ib incorrectly started from 1,
		 * resulting in the neglect of coastal aerosol band but a change of 
		 * cirrus band too.
		 * 		for (ib = 1; ib <= L8NRB; ib++) {
		 */
		specidx = -1; 
		switch (ib) {
			case 0:  specidx =  0; break;   /* ultra-blue */
			case 1:  specidx =  0; break;	/* blue */
			case 2:  specidx =  1; break;	/* green */
			case 3:  specidx =  2; break;	/* red */
			/* Skip the 3 rows intended for the red-edge bands. Aug 8, 2019 */
			case 4:  specidx =  6; break;	/* nir */
			case 5:  specidx =  7; break;	/* swir 1. */
			case 6:  specidx =  8; break;	/* swir 2 */
		}
		if (specidx == -1) {
			Error("Something wrong with spectral band match between Landsat and MODIS");
			exit(1);
		}

		/* NBAR */
		for (irow = 0; irow < lsatin.nrow; irow++) {
			for (icol = 0; icol < lsatin.ncol; icol++) {
				k = irow * lsatin.ncol + icol;
				if (lsatin.ref[ib][k] == HLS_REFL_FILLVAL)
					continue;

				/* Apr 5, 2017
				 * Jun 8, 2017: That reflectance is available but geometry is missing can occur
				 * when two same-day scenes from adjacent WRS-2 rows both overlap with a tile but 
				 * geometry calculation for one of the scenes failed (Matlab failure). 
				 * If this occurs, set reflectance and thermal to fill values to flag this incidence.
				 * And the prominent "black hole" makes it easy to spot the missing geometry.
				 */
				if (l8ang.sz[k] == LANDSAT_ANGFILL) {
					lsatin.ref[ib][k] = HLS_REFL_FILLVAL;
					
					/* The same location is reset repeatedly and wastefully, but it's ok */
					lsatin.ref[7][k] = HLS_REFL_FILLVAL; /* Cirrus */
					lsatin.thm[0][k] = HLS_THM_FILLVAL; /* TIRS 1 */
					lsatin.thm[1][k] = HLS_THM_FILLVAL; /* TIRS 2 */
					lsatin.acmask[k] = HLS_MASK_FILLVAL;
					lsatin.fmask[k]  = HLS_MASK_FILLVAL; 
				}
				else {
					sz = l8ang.sz[k]/100.0;
					sa = l8ang.sa[k]/100.0;
					vz = l8ang.vz[ib][k]/100.0;
					va = l8ang.va[ib][k]/100.0;

					/* No need to do, because cosine is the same. Jun 14, 2017. Martin's 
					 * relative azimuth can be greater than 180 and it is essentially
					 * ra - 360; cosine is the same 
					 */
					if (va < 0) 
						va += 360;
					ra = sa - va;

					ratio = (coeff[specidx][0] + coeff[specidx][1] * rossthick_MSZ + coeff[specidx][2] * lisparseR_MSZ) / 
						(coeff[specidx][0] + coeff[specidx][1] * RossThick(sz, vz, ra) + coeff[specidx][2] * LiSparseR(sz, vz, ra));
					tmpref = lsatin.ref[ib][k] * ratio;
					lsatin.ref[ib][k] = asInt16(tmpref);

					cfactor.ratio[ib][k] = ratio;
				}
			}
		}
	}

	close_l8ang(&l8ang);

	/* Close reflectance*/
	ret = close_lsat(&lsatin);
	if (ret != 0) {
		Error("Error in close_lsat");
		exit(1);
	}

	/* Close cfactor */
	ret = close_cfactor(&cfactor);
	if (ret != 0) {
		Error("Error in close_cfactor");
		exit(1);
	}

	/* Make it hdfeos */
        sds_info_t all_sds[L8NRB+L8NTB+2];  /* ref + therm + 2 QA */
        ret = set_L30_sds_info(all_sds, L8NRB+L8NTB+2, &lsatin);
	if (ret != 0) {
		Error("Error in set_L30_sds_info");
		exit(1);
	}
        ret = L30_PutSpaceDefHDF(&lsatin, all_sds, L8NRB+L8NTB+2);
        if (ret != 0) {
                Error("Error in HLS_PutSpaceDefHDF");
                exit(1);
        }

	return 0;
}
