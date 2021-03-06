/*
  Copyright (C) 2011, 2012 by Roger E Critchlow Jr, Santa Fe, NM, USA.

  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307 USA
*/
#ifndef RAMP_H
#define RAMP_H

#include "dspmath.h"
#include "window.h"
#include <stdlib.h>

/*
** Arbitrary window or window product function ramp
*/
typedef struct {
  int target;			/* sample length of ramp */
  int current;			/* current sample point in ramp */
  float *ramp;			/* ramp values */
} ramp_t;

static void ramp_update(ramp_t *r, int do_rise, float ms, int window, int window2, int samples_per_second) {
  // printf("ramp_update do_rise=%d, ms=%f, window=%d, sr=%d\n", do_rise, ms, window, samples_per_second);
  r->target = samples_per_second * (ms / 1000.0f);
  if (r->target < 1) r->target = 1;
  if ((r->target & 1) == 0) r->target += 1;
  r->current = 0;
  float *ramp = r->ramp = realloc(r->ramp, r->target*sizeof(float));
  int off = do_rise ? 0 : r->target-1;
  for (int i = 0; i < r->target; i += 1)
    ramp[i] = window_get2(window, window2, 2*r->target-1, i+off);
#if 0
  if (do_rise) {
    // torture the initial sample weight to be zero
    if (ramp[0] != 0) {
      float fudge = ramp[0];
      for (int i = 0; i < r->target; i += 1)
	ramp[i] -= fudge;
    }
    // torture the final sample weight to be 1
    if (ramp[r->target-1] != 1) {
      float fudge = 1.0 / ramp[r->target-1];
      for (int i = 0; i < r->target; i += 1)
	ramp[i] *= fudge;
    }
  } else {
    // torture the final sample into a 0
    if (ramp[r->target-1] != 0) {
      float fudge = ramp[r->target-1];
      for (int i = 0; i < r->target; i += 1)
	ramp[i] -= fudge;
    }
    if (ramp[0] != 1) {
      float fudge = 1 / ramp[0];
      for (int i = 0; i < r->target; i += 1)
	ramp[i] *= fudge;
    }
  }
#endif
}

static void ramp_init(ramp_t *r, int do_rise, float ms, int window, int window2, int samples_per_second) {
  r->ramp = NULL;
  ramp_update(r, do_rise, ms, window, window2, samples_per_second);
}

static void ramp_start(ramp_t *r) {
  r->current = 0;
}

static float ramp_next(ramp_t *r) {
  if (r->current >= r->target) r->current = r->target - 1;
  return r->ramp[r->current++];
}

static int ramp_done(ramp_t *r) {
  return r->current >= r->target;
}

static void ramp_free(ramp_t *r) {
  if (r->ramp != NULL) free(r->ramp);
}

#endif
