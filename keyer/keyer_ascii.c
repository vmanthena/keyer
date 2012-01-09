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

  Based on jack-1.9.8/example-clients/midiseq.c and
  dttsp-cgran-r624/src/keyboard-keyer.c

  jack-1.9.8/example-clients/midiseq.c is

    Copyright (C) 2004 Ian Esten

  dttsp-cgran-r624/src/keyboard-keyer.c

    Copyright (C) 2004, 2005, 2006, 2007, 2008 by Frank Brickle, AB2KT and Bob McGwier, N4HY
    Doxygen comments added by Dave Larsen, KV0S

*/

#define OPTIONS_TIMING	1
#define OPTIONS_TONE	1

#include "framework.h"
#include "options.h"
#include "../dspkit/midi.h"
#include "../dspkit/midi_buffer.h"
#include "timing.h"

typedef struct {
  framework_t fw;
  timing_t samples_per;
  options_t sent;
  char prosign[16], n_prosign, n_slash;
  unsigned long frames;
  midi_buffer_t midi;
} _t;

static char *preface(_t *dp, const char *file, int line) {
  static char buff[256];
  sprintf(buff, "%s:%s:%d@%ld", dp->fw.opts.client, file, line, dp->frames);
  return buff;
}
  
#define PREFACE	preface(dp, __FILE__, __LINE__)

static void _update(_t *dp) {
  if (dp->fw.opts.modified) {
    dp->fw.opts.modified = 0;

    if (dp->fw.opts.verbose > 2) fprintf(stderr, "%s _update\n", PREFACE);

    /* update timing computations */
    keyer_timing_update(&dp->fw.opts, &dp->samples_per);
    if (dp->fw.opts.verbose > 2) keyer_timing_report(stderr, &dp->fw.opts, &dp->samples_per);

    /* pass on parameters to tone keyer */
    char buffer[128];
    if (dp->sent.rise != dp->fw.opts.rise) { sprintf(buffer, "<rise%.1f>", dp->sent.rise = dp->fw.opts.rise); midi_buffer_write_sysex(&dp->midi, buffer); }
    if (dp->sent.fall != dp->fw.opts.fall) { sprintf(buffer, "<fall%.1f>", dp->sent.fall = dp->fw.opts.fall); midi_buffer_write_sysex(&dp->midi, buffer); }
    if (dp->sent.freq != dp->fw.opts.freq) { sprintf(buffer, "<freq%.1f>", dp->sent.freq = dp->fw.opts.freq); midi_buffer_write_sysex(&dp->midi, buffer); }
    if (dp->sent.gain != dp->fw.opts.gain) { sprintf(buffer, "<gain%.1f>", dp->sent.gain = dp->fw.opts.gain); midi_buffer_write_sysex(&dp->midi, buffer); }
    /* or to decoder */
    if (dp->sent.word != dp->fw.opts.word) { sprintf(buffer, "<word%.1f>", dp->sent.word = dp->fw.opts.word); midi_buffer_write_sysex(&dp->midi, buffer); }
    if (dp->sent.wpm != dp->fw.opts.wpm) { sprintf(buffer, "<wpm%.1f>", dp->sent.wpm = dp->fw.opts.wpm); midi_buffer_write_sysex(&dp->midi, buffer); }
  }
}

static void _init(void *arg) {
  _t *dp = (_t *)arg;
  dp->n_prosign = 0;
  dp->n_slash = 0;
  midi_buffer_init(&dp->midi);
}

/*
** jack process callback
*/
static int _process(jack_nframes_t nframes, void *arg) {
  _t *dp = (_t *)arg;
  void* midi_out = jack_port_get_buffer(framework_midi_output(dp,0), nframes);
  void* buffer_in = midi_buffer_get_buffer(&dp->midi, nframes, jack_last_frame_time(dp->fw.client));
  int buffer_event_index = 0, buffer_event_time = 0;
  int buffer_event_count = midi_buffer_get_event_count(buffer_in);
  jack_midi_event_t buffer_event;
  // find out what the midi_buffer has for us to do

  if (buffer_event_index < buffer_event_count) {
    midi_buffer_event_get(&buffer_event, buffer_in, buffer_event_index++);
    buffer_event_time = buffer_event.time;
  } else {
    buffer_event_time = nframes+1;
  }
  // clear the jack output buffer
  jack_midi_clear_buffer(midi_out);
  // update our options
  _update(dp);
  /* for each frame in this callback */
  for(int i = 0; i < nframes; i += 1) {
    /* process all midi output events at this sample frame */
    while (buffer_event_time == i) {
      if (buffer_event.size != 0) {
	unsigned char* buffer = jack_midi_event_reserve(midi_out, i, buffer_event.size);
	if (buffer == NULL) {
	  fprintf(stderr, "%s:%d:%ld: jack won't buffer %ld midi bytes!\n", __FILE__, __LINE__, dp->frames, buffer_event.size);
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
    /* bump the frame counter */
    dp->frames += 1;
  }
  return 0;
}

/*
** translate queued characters into morse code key transitions
*/
static char *_morse_table[128] = {
  /* 000 NUL */ 0, /* 001 SOH */ 0, /* 002 STX */ 0, /* 003 ETX */ 0,
  /* 004 EOT */ 0, /* 005 ENQ */ 0, /* 006 ACK */ 0, /* 007 BEL */ 0,
  /* 008  BS */ 0, /* 009  HT */ 0, /* 010  LF */ 0, /* 011  VT */ 0,
  /* 012  FF */ 0, /* 013  CR */ 0, /* 014  SO */ 0, /* 015  SI */ 0,
  /* 016 DLE */ 0, /* 017 DC1 */ 0, /* 018 DC2 */ 0, /* 019 DC3 */ 0,
  /* 020 DC4 */ 0, /* 021 NAK */ 0, /* 022 SYN */ 0, /* 023 ETB */ 0,
  /* 024 CAN */ 0, /* 025  EM */ 0, /* 026 SUB */ 0, /* 027 ESC */ 0,
  /* 028  FS */ 0, /* 029  GS */ 0, /* 030  RS */ 0, /* 031  US */ 0,
  /* 032  SP */ 0,
  /* 033   ! */ "...-.",	// [SN]
  /* 034   " */ ".-..-.",	// [RR]
  /* 035   # */ 0,
  /* 036   $ */ "...-..-",	// [SX]
  /* 037   % */ ".-...",	// [AS]
  /* 038   & */ 0,
  /* 039   ' */ ".----.",	// [WG]
  /* 040   ( */ "-.--.",	// [KN]
  /* 041   ) */ "-.--.-",	// [KK]
  /* 042   * */ "...-.-",	// [SK]
  /* 043   + */ ".-.-.",	// [AR]
  /* 044   , */ "--..--",
  /* 045   - */ "-....-",
  /* 046   . */ ".-.-.-",
  /* 047   / */ "-..-.",
  /* 048   0 */ "-----",
  /* 049   1 */ ".----",
  /* 050   2 */ "..---",
  /* 051   3 */ "...--",
  /* 052   4 */ "....-",
  /* 053   5 */ ".....",
  /* 054   6 */ "-....",
  /* 055   7 */ "--...",
  /* 056   8 */ "---..",
  /* 057   9 */ "----.",
  /* 058   : */ "---...",	// [OS]
  /* 059   ; */ "-.-.-.",	// [KR]
  /* 060   < */ 0,
  /* 061   = */ "-...-",	// [BT]
  /* 062   > */ 0,
  /* 063   ? */ "..--..",	// [IMI]
  /* 064   @ */ ".--.-.",
  /* 065   A */ ".-",
  /* 066   B */ "-...",
  /* 067   C */ "-.-.",
  /* 068   D */ "-..",
  /* 069   E */ ".",
  /* 070   F */ "..-.",
  /* 071   G */ "--.",
  /* 072   H */ "....",
  /* 073   I */ "..",
  /* 074   J */ ".---",
  /* 075   K */ "-.-",
  /* 076   L */ ".-..",
  /* 077   M */ "--",
  /* 078   N */ "-.",
  /* 079   O */ "---",
  /* 080   P */ ".--.",
  /* 081   Q */ "--.-",
  /* 082   R */ ".-.",
  /* 083   S */ "...",
  /* 084   T */ "-",
  /* 085   U */ "..-",
  /* 086   V */ "...-",
  /* 087   W */ ".--",
  /* 088   X */ "-..-",
  /* 089   Y */ "-.--",
  /* 090   Z */ "--..",
  /* 091   [ */ 0,
  /* 092   \ */ 0,
  /* 093   ] */ 0,
  /* 094   ^ */ 0,
  /* 095   _ */ "..--.-",	// [UK]
  /* 096   ` */ 0,
  /* 097   a */ ".-",
  /* 098   b */ "-...",
  /* 099   c */ "-.-.",
  /* 100   d */ "-..",
  /* 101   e */ ".",
  /* 102   f */ "..-.",
  /* 103   g */ "--.",
  /* 104   h */ "....",
  /* 105   i */ "..",
  /* 106   j */ ".---",
  /* 107   k */ "-.-",
  /* 108   l */ ".-..",
  /* 109   m */ "--",
  /* 110   n */ "-.",
  /* 111   o */ "---",
  /* 112   p */ ".--.",
  /* 113   q */ "--.-",
  /* 114   r */ ".-.",
  /* 115   s */ "...",
  /* 116   t */ "-",
  /* 117   u */ "..-",
  /* 118   v */ "...-",
  /* 119   w */ ".--",
  /* 120   x */ "-..-",
  /* 121   y */ "-.--",
  /* 122   z */ "--..",
  /* 123   { */ 0,
  /* 124   | */ 0,
  /* 125   } */ 0,
  /* 126   ~ */ 0,
  /* 127 DEL */ "........"
};

static void _flush_midi(_t *dp) {
  midi_buffer_queue_flush(&dp->midi);
}

/*
** queue a string of . and - as midi events
** terminate with an inter letter space unless continues
*/
static void _queue_midi(_t *dp, char c, char *p, int continues) {
  /* normal send single character */
  if (p == NULL) {
    if (c == ' ')
      if (dp->fw.opts.verbose > 2) fprintf(stderr, "%s _queue_midi delay %d\n", PREFACE, dp->samples_per.iws-dp->samples_per.ils);
    midi_buffer_queue_delay(&dp->midi, dp->samples_per.iws-dp->samples_per.ils);
  } else {
    while (*p != 0) {
      if (*p == '.') {
	if (dp->fw.opts.verbose > 2) fprintf(stderr, "%s _queue_midi dit %d\n", PREFACE, dp->samples_per.dit);
	midi_buffer_queue_note_on(&dp->midi, dp->samples_per.dit, dp->fw.opts.chan, dp->fw.opts.note, 0);
      } else if (*p == '-') {
	if (dp->fw.opts.verbose > 2) fprintf(stderr, "%s _queue_midi dah %d\n", PREFACE, dp->samples_per.dah);
	midi_buffer_queue_note_on(&dp->midi, dp->samples_per.dah, dp->fw.opts.chan, dp->fw.opts.note, 0);
      }
      if (p[1] != 0 || continues) {
	if (dp->fw.opts.verbose > 2) fprintf(stderr, "%s _queue_midi ies %d)\n", PREFACE, dp->samples_per.ies);
	midi_buffer_queue_note_off(&dp->midi, dp->samples_per.ies, dp->fw.opts.chan, dp->fw.opts.note, 0);
      } else {
	if (dp->fw.opts.verbose > 2) fprintf(stderr, "%s _queue_midi ils %d)\n", PREFACE, dp->samples_per.ils);
	midi_buffer_queue_note_off(&dp->midi, dp->samples_per.ils, dp->fw.opts.chan, dp->fw.opts.note, 0);
      }
      p += 1;
    }
  }
}

/*
** translate a single character into morse code
** but implement an escape to allow prosign construction
*/
static void _queue_char(char c, void *arg) {
  _t *dp = (_t *)arg;
  if (dp->fw.opts.verbose) fprintf(stderr, "%s _queue_char('%c')\n", PREFACE, c);
  if (dp->fw.opts.verbose > 1) fprintf(stderr, "%s _queue_char n_slash %d, n_prosign %d\n", PREFACE, dp->n_slash, dp->n_prosign);
  
  if (c == '\\') {
    /* use \ab to send prosign of a concatenated to b with no inter-letter space */
    /* multiple slashes to get longer prosigns, so \\sos or \s\os */
    dp->n_slash += 1;
  } else if (dp->n_slash != 0) {
    dp->prosign[dp->n_prosign++] = c;
    if (dp->n_prosign == dp->n_slash+1) {
      for (int i = 0; i < dp->n_prosign; i += 1) {
	_queue_midi(dp, dp->prosign[i], _morse_table[dp->prosign[i]&127], i != dp->n_prosign-1);
      }
      dp->n_prosign = 0;
      dp->n_slash = 0;
      _flush_midi(dp);
    }
  } else {
    _queue_midi(dp, c, _morse_table[c&0x7f], 0);
    _flush_midi(dp);
  }
}

static int _command(ClientData clientData, Tcl_Interp *interp, int argc, Tcl_Obj* const *objv) {
  _t *data = (_t *)clientData;
  if (argc > 1 && strcmp(Tcl_GetString(objv[1]),"puts") == 0) {
    // put the argument strings separated by spaces
    for (int i = 2; i < argc; i += 1) {
      for (char *p = Tcl_GetString(objv[i]); *p != 0; p += 1)
	_queue_char(*p, clientData);
      if (i != argc-1)
	_queue_char(' ', clientData);
    }
    return TCL_OK;
  }
  if (argc == 2 && strcmp(Tcl_GetString(objv[1]), "pending") == 0) {
    Tcl_SetObjResult(interp, Tcl_NewIntObj(midi_buffer_readable(&data->midi)));
    return TCL_OK;
  }
  if (argc == 2 && strcmp(Tcl_GetString(objv[1]), "available") == 0) {
    Tcl_SetObjResult(interp, Tcl_NewIntObj(midi_buffer_writeable(&data->midi)));
    return TCL_OK;
  }
  if (framework_command(clientData, interp, argc, objv) != TCL_OK)
    return TCL_ERROR;
  _update(clientData);
  return TCL_OK;
}

static int _factory(ClientData clientData, Tcl_Interp *interp, int argc, Tcl_Obj* const *objv) {
  return framework_factory(clientData, interp, argc, objv, 0,0,0,1, _command, _process, sizeof(_t), _init, NULL, "config|cget|cdoc|puts");
}

int DLLEXPORT Keyer_ascii_Init(Tcl_Interp *interp) {
  return framework_init(interp, "keyer", "1.0.0", "keyer::ascii", _factory);
}

