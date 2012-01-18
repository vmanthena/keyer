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
/** 

    keyer_ptt implements a push-to-talk switch on a keyer signal
    it has a keyer input midi signal, a keyer output midi signal,
    and a PTT output midi signal.

    The PTT output on happens when the keyer input goes on.

    The keyer output can be delayed by a specified period so the
    PTT signal can lead the key.

    The PTT off signal can be lagged behind the keyer off signal.
    
*/

#include "framework.h"
#include "../sdrkit/midi.h"
#include "../sdrkit/midi_buffer.h"

typedef struct {
  int verbose;		       /*  */
  int chan;		       /* midi channel */
  int note;		       /* midi note for keyer, ptt = note+1 */
  float ptt_delay;	       /* seconds ptt on leads keyer on */
  float ptt_hang;	       /* seconds ptt off trails keyer off */
} options_t;

typedef struct {
  framework_t fw;
  int modified;
  options_t opts;
  int ptt_delay_samples;
  int ptt_hang_samples;
  int ptt_on;
  int key_on;
  int ptt_hang_count;
  midi_buffer_t midi;
} _t;


// update the computed parameters
static void _update(_t *dp) {
  if (dp->modified) {
    dp->modified = 0;
    /* ptt recomputation */
    int sample_rate = sdrkit_sample_rate(dp);
    dp->ptt_delay_samples = dp->opts.ptt_delay * sample_rate;
    dp->ptt_hang_samples = dp->opts.ptt_hang * sample_rate;
  }
}

static void *_init(void *arg) {
  _t *dp = (_t *)arg;
  void *p = midi_buffer_init(&dp->midi); if (p != &dp->midi) return p;
  dp->ptt_on = 0;
  dp->key_on = 0;
  dp->modified = 1;
  _update(dp);
  return arg;
}

static void _send(_t *dp, void *midi_out, jack_nframes_t t, unsigned char cmd, unsigned char note) {
  unsigned char midi[] = { cmd | (dp->opts.chan-1), note, 0 };
  unsigned char* buffer = jack_midi_event_reserve(midi_out, t, 3);
  if (buffer == NULL) {
    fprintf(stderr, "jack won't buffer 3 midi bytes!\n");
  } else {
    memcpy(buffer, midi, 3);
  }
}

/*
** jack process callback
*/
static int _process(jack_nframes_t nframes, void *arg) {
  _t *dp = (_t *)arg;
  void *midi_in = jack_port_get_buffer(framework_midi_input(dp,0), nframes);
  void *midi_out = jack_port_get_buffer(framework_midi_output(dp,0), nframes);
  void* buffer_in = midi_buffer_get_buffer(&dp->midi, nframes, sdrkit_last_frame_time(dp));
  int in_event_count = jack_midi_get_event_count(midi_in), in_event_index = 0, in_event_time = 0;
  int buffer_event_count = midi_buffer_get_event_count(buffer_in), buffer_event_index = 0, buffer_event_time = 0;
  jack_midi_event_t in_event, buffer_event;
  // recompute timings if necessary
  _update(dp);
  // find out what input events we need to process
  if (in_event_index < in_event_count) {
    jack_midi_event_get(&in_event, midi_in, in_event_index++);
    in_event_time = in_event.time;
  } else {
    in_event_time = nframes+1;
  }
  // find out what buffered events we need to process
  if (buffer_event_index < buffer_event_count) {
    // fprintf(stderr, "iambic received %d events\n", buffer_event_count);
    midi_buffer_event_get(&buffer_event, buffer_in, buffer_event_index++);
    buffer_event_time = buffer_event.time;
  } else {
    buffer_event_time = nframes+1;
  }
  /* this is important, very strange if omitted */
  jack_midi_clear_buffer(midi_out);
  /* for all frames in the buffer */
  for (int i = 0; i < nframes; i++) {
    /* process all midi input events at this sample frame */
    while (in_event_time == i) {
      if (in_event.size == 3) {
	const unsigned char channel = (in_event.buffer[0]&0xF)+1;
	const unsigned char command = in_event.buffer[0]&0xF0;
	const unsigned char note = in_event.buffer[1];
	if (channel == dp->opts.chan && note == dp->opts.note) {
	  if (command == MIDI_NOTE_ON) {
	    if ( ! dp->ptt_on) {
	      dp->ptt_on = 1;
	      _send(dp, midi_out, i, command, dp->opts.note+1);
	    }
	    dp->key_on = 1;
	    if (i+dp->ptt_delay_samples < nframes) {
	      _send(dp, midi_out, i+dp->ptt_delay_samples, command, dp->opts.note);
	    } else {
	      midi_buffer_queue_delay(&dp->midi, i+dp->ptt_delay_samples-nframes);
	      midi_buffer_queue_note_on(&dp->midi, 0, channel, note, 0);
	    }
	  } else if (command == MIDI_NOTE_OFF) {
	    if (i+dp->ptt_delay_samples < nframes) {
	      dp->key_on = 0;
	      dp->ptt_hang_count = dp->ptt_hang_samples;
	      _send(dp, midi_out, i+dp->ptt_delay_samples, command, dp->opts.note);
	    } else {
	      midi_buffer_queue_delay(&dp->midi, i+dp->ptt_delay_samples-nframes);
	      midi_buffer_queue_note_off(&dp->midi, 0, channel, note, 0);
	    }
	  }
	}
      }
      // look for another event
      if (in_event_index < in_event_count) {
	jack_midi_event_get(&in_event, midi_in, in_event_index++);
	in_event_time = in_event.time;
      } else {
	in_event_time = nframes+1;
      }
    }
    /* process all midi output events at this sample frame */
    while (buffer_event_time == i) {
      if (buffer_event.size != 0) {
	const unsigned char command = buffer_event.buffer[0]&0xF0;
	if (command == MIDI_NOTE_ON) {
	  dp->key_on = 1;
	} else if (command == MIDI_NOTE_OFF) {
	  dp->key_on = 0;
	  dp->ptt_hang_count = dp->ptt_hang_samples;
	}
	unsigned char* buffer = jack_midi_event_reserve(midi_out, i, buffer_event.size);
	if (buffer == NULL) {
	  fprintf(stderr, "jack won't buffer %ld midi bytes!\n", buffer_event.size);
	} else {
	  memcpy(buffer, buffer_event.buffer, buffer_event.size);
	}
      }
      if (buffer_event_index < buffer_event_count) {
	midi_buffer_event_get(&buffer_event, buffer_in, buffer_event_index++);
	buffer_event_time = buffer_event.time;
      } else {
	buffer_event_time = nframes+1;
      }
    }
    /* clock the ptt hang time counter */
    if (dp->key_on == 0 && dp->ptt_on != 0 && --dp->ptt_hang_count <= 0) {
      dp->ptt_on = 0;
      _send(dp, midi_out, i, MIDI_NOTE_OFF, dp->opts.note+1);
    }
  }
  return 0;
}

static int _command(ClientData clientData, Tcl_Interp *interp, int argc, Tcl_Obj* const *objv) {
  _t *dp = (_t *)clientData;
  options_t save = dp->opts;
  if (framework_command(clientData, interp, argc, objv) != TCL_OK) {
    dp->opts = save;
    return TCL_ERROR;
  }
  dp->modified = (dp->opts.ptt_delay != save.ptt_delay || dp->opts.ptt_hang != save.ptt_hang);
  return TCL_OK;
}

static const fw_option_table_t _options[] = {
  // common options
  { "-server",  "server",  "Server",  "default",  fw_option_obj,   offsetof(_t, fw.server_name), "jack server name" },
  { "-client",  "client",  "Client",  NULL,       fw_option_obj,   offsetof(_t, fw.client_name), "jack client name" },
  { "-verbose", "verbose", "Verbose", "0",	  fw_option_int,   offsetof(_t, opts.verbose),   "amount of diagnostic output" },
  { "-chan",    "channel", "Channel", "1",        fw_option_int,   offsetof(_t, opts.chan),	 "midi channel used for keyer" },
  { "-note",    "note",    "Note",    "0",	  fw_option_int,   offsetof(_t, opts.note),	 "base midi note used for keyer" },
  // ptt options
  { "-delay",   "delay",   "Delay",   "0.0",      fw_option_float, offsetof(_t, opts.ptt_delay), "delay of keyer on behind ptt on in seconds" },
  { "-hang",    "hang",    "Hang",    "1.0",      fw_option_float, offsetof(_t, opts.ptt_hang),  "hang time of ptt off behind keyer off in seconds" },
  { NULL, NULL, NULL, NULL, fw_option_none, 0, NULL }
};

static const fw_subcommand_table_t _subcommands[] = {
  { "configure", fw_subcommand_configure },
  { "cget",      fw_subcommand_cget },
  { "cdoc",      fw_subcommand_cdoc },
  { NULL, NULL }
};

static const framework_t _template = {
  _options,			// option table
  _subcommands,			// subcommand table
  _init,			// initialization function
  _command,			// command function
  NULL,				// delete function
  NULL,				// sample rate function
  _process,			// process callback
  0, 0, 1, 1			// inputs,outputs,midi_inputs,midi_outputs
};

static int _factory(ClientData clientData, Tcl_Interp *interp, int argc, Tcl_Obj* const *objv) {
  return framework_factory(clientData, interp, argc, objv, &_template, sizeof(_t));
}

int DLLEXPORT Keyer_ptt_Init(Tcl_Interp *interp) {
  return framework_init(interp, "keyer::ptt", "1.0.0", "keyer::ptt", _factory);
}

