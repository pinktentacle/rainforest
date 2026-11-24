// Engine_Rainforest -- a rainforest, in layers and in voices.
//
// The layers are recordings that loop -- three rains, the day's insects, the
// night's, a frog chorus, a stream, wind, a dawn chorus, a waterfall, loud
// cicadas -- each read
// by two heads half a loop apart, panned apart, so a mono loop fills the
// width. Their levels are the script's, and move slowly.
//
// Under them, synthesis: drops ringing on leaves, the hiss of rain above what
// the recordings hold, wind in gusts and the leaves it shakes.
//
// Over them, voices played once -- birds, frogs, thunder, monkeys, a jaguar, a woodpecker --
// at a distance: further is darker, quieter and wetter.
//
//   buf(slot, path)                    read a sound (slots 1..128); 1..12 are the layers
//                                      and start looping as soon as they are read
//   layer(slot, amp)                   a layer's level (moves over 3 seconds)
//   shot(slot, amp, pan, rate, dist)   play a sound once, if it has loaded; dist 0 (here) .. 1 (far)
//   drops(x) hiss(x) wind(x)           the synthesis, 0..1
//   space(x) canopy(x) level(x)        the room's reverb, a darkening, the output

Engine_Rainforest : CroneEngine {
	var buffers, loaded, pending, lastRead, loops, amps, dryBus, wetBus, layerGroup, shotGroup, synth, master;

	*new { arg context, doneCallback;
		^super.new(context, doneCallback);
	}

	alloc {
		var s = context.server;

		SynthDef(\rf_loop, {
			var buf = \buf.kr(0), amp = Lag.kr(\amp.kr(0), 3), w = \width.kr(0.8);
			var n = BufFrames.kr(buf);
			var a = PlayBuf.ar(1, buf, BufRateScale.kr(buf), loop: 1);
			var b = PlayBuf.ar(1, buf, BufRateScale.kr(buf), startPos: n * 0.5, loop: 1);
			var sig = Pan2.ar(a, w.neg) + Pan2.ar(b, w);
			Out.ar(\out.kr(0), sig * amp * 0.7);
			Out.ar(\wet.kr(0), sig * amp * 0.08);
		}).add;

		SynthDef(\rf_synth, {
			var drops = Lag.kr(\drops.kr(0), 2), hiss = Lag.kr(\hiss.kr(0), 2), wind = Lag.kr(\wind.kr(0), 3);
			var trig, ping, air, gust, blow, rustle, sig;
			// drops on leaves: a ring at a random pitch, at a random place
			trig = Dust.ar(drops.squared * 60 + 0.01);
			ping = Pan2.ar(Ringz.ar(trig * TRand.ar(0.05, 0.25, trig), TExpRand.ar(900, 5200, trig), TRand.ar(0.008, 0.04, trig)),
				TRand.ar(-0.9, 0.9, trig));
			ping = ping * (drops > 0.02);
			// the hiss above what the recordings hold (they stop near 11 kHz)
			air = HPF.ar([PinkNoise.ar, PinkNoise.ar], 7500) * hiss * 0.12;
			// wind: a band of noise that wanders, swelling in gusts; leaves shaken by them
			gust = LFNoise2.kr(0.13).range(0, 1).squared;
			blow = BPF.ar([PinkNoise.ar, PinkNoise.ar], LFNoise2.kr(0.2).range(250, 800), 0.7) * (0.35 + gust) * wind * 0.5;
			rustle = HPF.ar(Dust.ar([1, 1] * (wind * gust * 140 + 0.01)) * 0.4, 2500);
			rustle = BPF.ar(rustle, 4000, 1.5) * wind;
			sig = ping + air + blow + rustle;
			Out.ar(\out.kr(0), sig);
			Out.ar(\wet.kr(0), ping * 0.5 + (blow * 0.1));
		}).add;

		SynthDef(\rf_shot, {
			var buf = \buf.kr(0), d = \dist.kr(0.3).clip(0, 1);
			var sig = PlayBuf.ar(1, buf, BufRateScale.kr(buf) * \rate.kr(1), doneAction: 2);
			sig = LPF.ar(sig, d.linexp(0, 1, 16000, 1600));
			sig = Pan2.ar(sig, \pan.kr(0) * (1 - (d * 0.5)), \amp.kr(0.5) * (1 - (d * 0.75)));
			Out.ar(\out.kr(0), sig);
			Out.ar(\wet.kr(0), sig * (0.15 + d));
		}).add;

		SynthDef(\rf_master, {
			var dry = In.ar(\dry.kr(0), 2), wet = In.ar(\wet.kr(0), 2);
			var space = Lag.kr(\space.kr(0.4), 0.3), canopy = Lag.kr(\canopy.kr(0), 0.5);
			var rev = FreeVerb2.ar(wet[0], wet[1], 1, 0.88, 0.55);
			var sig = dry + (rev * space * 2.2);
			sig = LPF.ar(sig, canopy.linexp(0, 1, 20000, 1500));
			sig = Limiter.ar(sig * Lag.kr(\level.kr(1), 0.2), 0.95, 0.01);
			Out.ar(\out.kr(0), sig);
		}).add;

		buffers = Array.newClear(128);
		// which sounds have arrived: a voice is only played once its buffer is filled
		loaded = Array.fill(128, false);
		pending = 0;
		lastRead = 0;
		loops = Array.newClear(12);
		amps = Array.fill(12, 0);
		dryBus = Bus.audio(s, 2);
		wetBus = Bus.audio(s, 2);
		layerGroup = Group.head(context.xg);
		shotGroup = Group.after(layerGroup);
		s.sync;
		synth = Synth.after(shotGroup, \rf_synth, [\out, dryBus, \wet, wetBus]);
		master = Synth.tail(context.xg, \rf_master, [\dry, dryBus, \wet, wetBus, \out, context.out_b]);

		this.addCommand("buf", "is", { arg msg;
			var slot = msg[1].asInteger.clip(1, 128) - 1;
			if (buffers[slot].notNil) { buffers[slot].free };
			loaded[slot] = false;
			pending = pending + 1;
			lastRead = Main.elapsedTime;
			buffers[slot] = Buffer.read(s, msg[2].asString, action: { arg b;
				pending = (pending - 1).max(0);
				if (loaded.notNil and: { b.numFrames.notNil } and: { b.numFrames > 0 }) { loaded[slot] = true };
				if (slot < 12 and: { loops.notNil } and: { loops[slot].isNil }) {
					loops[slot] = Synth(\rf_loop, [\buf, b, \amp, amps[slot], \out, dryBus, \wet, wetBus,
						\width, [0.8, 0.85, 0.9, 0.7, 0.75, 0.6, 0.5, 0.9, 0.7, 0.35, 0.7, 0.5][slot]], layerGroup);
				};
			});
		});

		this.addCommand("layer", "if", { arg msg;
			var slot = msg[1].asInteger.clip(1, 12) - 1;
			amps[slot] = msg[2];
			if (loops[slot].notNil) { loops[slot].set(\amp, msg[2]) };
		});

		this.addCommand("shot", "iffff", { arg msg;
			var slot = msg[1].asInteger.clip(1, 128) - 1;
			var buf = buffers[slot];
			// Nothing is played while sounds are still arriving: a voice started
			// while buffers are being filled can stall a slow host (norns-js
			// froze on it). Twenty seconds after the last request, a sound that
			// never answered stops holding the others back.
			if (buf.notNil and: { loaded[slot] == true }
				and: { pending == 0 or: { Main.elapsedTime - lastRead > 20 } }) {
				Synth(\rf_shot, [\buf, buf, \amp, msg[2], \pan, msg[3], \rate, msg[4], \dist, msg[5],
					\out, dryBus, \wet, wetBus], shotGroup);
			};
		});

		[\drops, \hiss, \wind].do({ arg name;
			this.addCommand(name.asString, "f", { arg msg; synth.set(name, msg[1]) });
		});
		[\space, \canopy, \level].do({ arg name;
			this.addCommand(name.asString, "f", { arg msg; master.set(name, msg[1]) });
		});
	}

	// Called twice when one script follows another: free what is still there.
	free {
		if (loops.notNil) { loops.do({ arg l; if (l.notNil) { l.free } }); loops = nil };
		if (synth.notNil) { synth.free; synth = nil };
		if (master.notNil) { master.free; master = nil };
		if (shotGroup.notNil) { shotGroup.free; shotGroup = nil };
		if (layerGroup.notNil) { layerGroup.free; layerGroup = nil };
		if (dryBus.notNil) { dryBus.free; dryBus = nil };
		if (wetBus.notNil) { wetBus.free; wetBus = nil };
		if (buffers.notNil) { buffers.do({ arg b; if (b.notNil) { b.free } }); buffers = nil };
		loaded = nil;
	}
}
