/* -*- mode: c++; tab-width: 8 -*- */
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
*/

#define FRAMEWORK_USES_JACK 1

#include "../sdrkit/noise.h"
#include "framework.h"

/*
** make noise, specified dB level
** this is uncorrelated noise, I and Q are different streams
** use iq_noise for correlated noise where Q is quadrature to I.
*/
typedef struct {
  float dBgain;
  float gain;
  noise_options_t n;
} options_t;

typedef struct {
  framework_t fw;
  int modified;
  options_t opts;
  noise_t noise;
  float gain;
} _t;

static void _update(_t *data) {
  if (data->modified) {
    data->modified = 0;
    // noise_configure(&data->noise, &data->opts.n);
    data->gain = powf(10.0f, data->opts.dBgain / 20.0f);
  }
}
  
static void *_init(void *arg) {
  _t *data = (_t *)arg;
  void *p = noise_init(&data->noise); if (p != &data->noise) return p;
  noise_configure(&data->noise, &data->opts.n);
  data->modified = 1;
  _update(data);
  return arg;
}

static int _process(jack_nframes_t nframes, void *arg) {
  _t *data = (_t *)arg;
  float *out0 = jack_port_get_buffer(framework_output(data,0), nframes);
  float *out1 = jack_port_get_buffer(framework_output(data,1), nframes);
  AVOID_DENORMALS;
  _update(data);
  for (int i = nframes; --i >= 0; ) {
    float _Complex z = data->gain * noise_process(&data->noise);
    *out0++ = creal(z);
    *out1++ = cimag(z);
  }
  return 0;
}

static int _command(ClientData clientData, Tcl_Interp *interp, int argc, Tcl_Obj* const *objv) {
  _t *data = (_t *)clientData;
  options_t save = data->opts;
  if (framework_command(clientData, interp, argc, objv) != TCL_OK) return TCL_ERROR;
  data->modified = data->opts.dBgain != save.dBgain;
  return TCL_OK;
}

static const fw_option_table_t _options[] = {
#include "framework_options.h"
  { "-level", "level", "Decibels", "-100.0", fw_option_float, 0,		   offsetof(_t, opts.dBgain), "average noise level in dB full scale" },
  { "-seed",  "seed",  "Seed",     "123456", fw_option_int,   fw_flag_create_only, offsetof(_t, opts.n.seed), "random number seed" },
  { NULL }
};

static const fw_subcommand_table_t _subcommands[] = {
#include "framework_subcommands.h"
  { NULL }
};

static const framework_t _template = {
  _options,			// option table
  _subcommands,			// subcommand table
  _init,			// initialization function
  _command,			// command function
  NULL,				// delete function
  NULL,				// sample rate function
  _process,			// process callback
  0, 2, 0, 0, 0,		// inputs,outputs,midi_inputs,midi_outputs,midi_buffers
  "a component which generates noise"
};

static int _factory(ClientData clientData, Tcl_Interp *interp, int argc, Tcl_Obj* const *objv) {
  return framework_factory(clientData, interp, argc, objv, &_template, sizeof(_t));
}

// the initialization function which installs the adapter factory
int DLLEXPORT Noise_Init(Tcl_Interp *interp) {
  return framework_init(interp, "sdrkit::noise", "1.0.0", "sdrkit::noise", _factory);
}
