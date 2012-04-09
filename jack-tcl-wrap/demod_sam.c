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

#include "../sdrkit/demod_sam.h"
#include "framework.h"

/*
** demodulate AM synchronously.
*/
typedef struct {
  framework_t fw;
  demod_sam_t sam;
} _t;

static void *_init(void *arg) {
  _t *data = (_t *)arg;
  void *e = demod_sam_init(&data->sam, sdrkit_sample_rate(&data->fw)); if (e != &data->sam) return e;
  return arg;
}

static int _process(jack_nframes_t nframes, void *arg) {
  _t *data = (_t *)arg;
  float *in0 = jack_port_get_buffer(framework_input(arg,0), nframes);
  float *in1 = jack_port_get_buffer(framework_input(arg,1), nframes);
  float *out0 = jack_port_get_buffer(framework_output(arg,0), nframes);
  AVOID_DENORMALS;
  for (int i = nframes; --i >= 0; ) {
    float y = demod_sam_process(&data->sam, *in0++ + I * *in1++);
    *out0++ = y;
  }
  return 0;
}

static int _get(ClientData clientData, Tcl_Interp *interp, int argc, Tcl_Obj* const *objv) {
  if (argc != 2)
    return fw_error_obj(interp, Tcl_ObjPrintf("usage: %s get", Tcl_GetString(objv[0])));
  _t *data = (_t *)clientData;
  Tcl_Obj *result[] = {
    Tcl_NewIntObj(jack_frame_time(data->fw.client)),
    Tcl_NewDoubleObj(data->sam.pll.freq.f),
    NULL
  };
  Tcl_SetObjResult(interp, Tcl_NewListObj(2, result));
  return TCL_OK;
}

static int _command(ClientData clientData, Tcl_Interp *interp, int argc, Tcl_Obj* const *objv) {
  return framework_command(clientData, interp, argc, objv);
}

static const fw_option_table_t _options[] = {
#include "framework_options.h"
  { NULL }
};

static const fw_subcommand_table_t _subcommands[] = {
#include "framework_subcommands.h"
  { "get", _get, "get the pll frequency" },
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
  2, 1, 0, 0, 0,		// inputs,outputs,midi_inputs,midi_outputs,midi_buffers
  "a synchronous AM demodulation component"
};

static int _factory(ClientData clientData, Tcl_Interp *interp, int argc, Tcl_Obj* const *objv) {
  return framework_factory(clientData, interp, argc, objv, &_template, sizeof(_t));
}

// the initialization function which installs the adapter factory
int DLLEXPORT Demod_sam_Init(Tcl_Interp *interp) {
  return framework_init(interp, "sdrkit::demod-sam", "1.0.0", "sdrkit::demod-sam", _factory);
}

