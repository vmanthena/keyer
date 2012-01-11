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
/*
** Phase locked loop - rewritten from dttsp
** Copyright (C) 2004, 2005, 2006, 2007, 2008 by Frank Brickle, AB2KT and Bob McGwier, N4HY
*/

#ifndef PLL_H
#define PLL_H

#include <complex.h>
#include <math.h>

#ifndef TWOPI
#define TWOPI (2.0*M_PI)
#endif

typedef struct {
    float alpha, beta;
    struct { float f, l, h; } freq;
    float phs;
    struct { float alpha; } iir;
    float _Complex delay;
} pll_t;

static void *pll_init(const pll_t *p, const int sample_rate, const float f_initial, const float f_lobound, const float f_hibound, const float f_bandwid) {
  float fac = (TWOPI / sample_rate);
  p->freq.f = f_initial * fac;
  p->freq.l = f_lobound * fac;
  p->freq.h = f_hibound * fac;
  p->phs = 0.0f;
  p->delay = 0.0f + I * 1.0f;

  p->iir.alpha = f_bandwid * fac;	 /* arm filter */
  p->alpha = p->iir.alpha * 0.3f;	 /* pll bandwidth */
  p->beta = p->alpha * p->alpha * 0.25f; /* second order term */
  return p;
}

static void pll(pll_t *p, float _Complex sig, float wgt) {
  float _Complex z = cosf(p->phs) + I * sinf(p->phs);
  float diff;

  p->delay = (creal(z) * creal(sig) + cimag(z) * cimag(sig)) +
    I * (-cimag(z) * creal(sig) + creal(z) * cimag(sig));
  diff = wgt * carg(p->delay);

  p->freq.f += p->beta * diff;

  if (p->freq.f < p->freq.l) p->freq.f = p->freq.l;
  if (p->freq.f > p->freq.h) p->freq.f = p->freq.h;

  p->phs += p->freq.f + p->alpha * diff;

  while (p->phs >= TWOPI) p->phs -= TWOPI;
  while (p->phs < 0) p->phs += TWOPI;
}
