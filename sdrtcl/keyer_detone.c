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
** keyer_detone uses a Goertzel filter to track the power on a specific tone
**
** a version with 128 stacked filters (one per MIDI note) might be nice once
** I understand how to decide what's on and what's off.
**
** Oh, it's a simple threshold model, the thresholding was implemented in Tcl,
** but it fits into this quite simply:
**	note_off and power > on-threshold emit note_on, 
**	note_on and power < off-threshold emit note_off
** add the thresholds and a midi out and we should be cool.
*/
#define FRAMEWORK_USES_JACK 1
#define FRAMEWORK_OPTIONS_MIDI 1

#include "../dspmath/filter_goertzel.h"
#include "../dspmath/midi.h"
#include "framework.h"

typedef struct {
#include "framework_options_vars.h"
  filter_goertzel_options_t fg;
  float on_threshold;
  float off_threshold;
  jack_nframes_t timeout;
} options_t;
  
typedef struct {
  framework_t fw;
  int modified;
  options_t opts;
  filter_goertzel_t fg;
  float power;
  int on;
  jack_nframes_t countdown;
} _t;

static void _update(_t *dp) {
  if (dp->modified) {
    dp->modified = dp->fw.busy = 0;
    filter_goertzel_configure(&dp->fg, &dp->opts.fg);
  }
}

static void *_init(void *arg) {
  _t *dp = (_t *)arg;
  dp->opts.fg.sample_rate = sdrkit_sample_rate(&dp->fw);
  void *p = filter_goertzel_preconfigure(&dp->fg, &dp->opts.fg); if (p != &dp->fg) return p;
  filter_goertzel_configure(&dp->fg, &dp->opts.fg);
  dp->on = 0;
  dp->countdown = 0;
  return arg;
}

/*
** Jack
*/

static int _process(jack_nframes_t nframes, void *arg) {
  // get our data pointer
  _t *dp = (_t *)arg;
  // get the input pointer
  float *in = jack_port_get_buffer(framework_input(dp,0), nframes);
  // get the output pointer and buffer
  void* midi_out = jack_port_get_buffer(framework_midi_output(dp,0), nframes);
  jack_midi_data_t cmd;
  // update parameters
  _update(dp);
  // clear the jack output buffer
  jack_midi_clear_buffer(midi_out);
  // for all frames in the buffer
  for(int i = 0; i < nframes; i++) {
    if (dp->countdown > 0)
      dp->countdown -= 1;
    if (filter_goertzel_process(&dp->fg, *in++)) {
      cmd = 0;
      if (dp->on != 0 && dp->fg.power < dp->opts.off_threshold) {
	cmd = MIDI_NOTE_OFF;	/* note change off */
      } else if (dp->on == 0 && dp->fg.power > dp->opts.on_threshold) {
	cmd = MIDI_NOTE_ON;	/* note change on */
      }
      if (cmd != 0) {
	/* prepare to send note change */
	unsigned char* buffer = jack_midi_event_reserve(midi_out, i, 3);
	if (buffer == NULL) {
	  fprintf(stderr, "%s:%d: jack won't buffer %d midi bytes!\n", __FILE__, __LINE__, 3);
	} else {
	  unsigned char note[3] = { MIDI_NOTE_ON | dp->opts.chan-1, dp->opts.note, (cmd == MIDI_NOTE_ON ? 1 : 0) };
	  // fprintf(stderr, "keyer_detone sending %x %x %x\n", note[0], note[1], note[2]);
	  memcpy(buffer, note, 3);
	  dp->on ^= 1;
	  dp->countdown = dp->opts.timeout; /* convert usec to frames? */
	}
      }
    }
  }
  return 0;
}

static int _get(ClientData clientData, Tcl_Interp *interp, int argc, Tcl_Obj* const *objv) {
  if (argc != 2)
    return fw_error_obj(interp, Tcl_ObjPrintf("usage: %s get", Tcl_GetString(objv[0])));
  _t *data = (_t *)clientData;
  Tcl_SetObjResult(interp, Tcl_NewDoubleObj(data->fg.power));
  return TCL_OK;
}
static int _command(ClientData clientData, Tcl_Interp *interp, int argc, Tcl_Obj* const *objv) {
  _t *data = (_t *)clientData;
  options_t save = data->opts;
  if (framework_command(clientData, interp, argc, objv) != TCL_OK) {
    data->opts = save;
    return TCL_ERROR;
  }
  data->modified = data->fw.busy = (data->modified || data->opts.fg.hertz != save.fg.hertz || data->opts.fg.bandwidth != save.fg.bandwidth);
  if (data->modified) {
    void *e = filter_goertzel_preconfigure(&data->fg, &data->opts.fg); if (e != &data->fg) {
      data->opts = save;
      data->modified = data->fw.busy = 0;
      return fw_error_str(interp, e);
    }
  }
  return TCL_OK;
}

static const fw_option_table_t _options[] = {
#include "framework_options.h"
  { "-freq",      "frequency", "AFHertz", "800.0", fw_option_float, fw_flag_none, offsetof(_t, opts.fg.hertz),     "frequency to tune in Hz"  },
  { "-bandwidth", "bandwidth", "BWHertz", "100.0", fw_option_float, fw_flag_none, offsetof(_t, opts.fg.bandwidth), "bandwidth of output signal in Hz" },
  { "-on",	  "onThresh",  "Thresh",  "4.0",   fw_option_float, fw_flag_none, offsetof(_t, opts.on_threshold), "on threshold value" },
  { "-off",	  "offThresh", "Thresh",  "3.0",   fw_option_float, fw_flag_none, offsetof(_t, opts.off_threshold),"off threshold value" },
  { "-timeout",	  "timeout",   "Timeout", "100",   fw_option_int,   fw_flag_none, offsetof(_t, opts.timeout),      "sample timeout between transitions" },
  { NULL }
};

static const fw_subcommand_table_t _subcommands[] = {
#include "framework_subcommands.h"
  { "get", _get, "fetch the current detected power of the filter" },
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
  1, 0, 0, 1, 0,		// inputs,outputs,midi_inputs,midi_outputs,midi_buffers
  "a component which converts audio tone to midi key on/off events"
};

static int _factory(ClientData clientData, Tcl_Interp *interp, int argc, Tcl_Obj* const *objv) {
  return framework_factory(clientData, interp, argc, objv, &_template, sizeof(_t));
}

int DLLEXPORT Keyer_detone_Init(Tcl_Interp *interp) {
  return framework_init(interp, "sdrtcl::keyer-detone", "1.0.0", "sdrtcl::keyer-detone", _factory);
}
