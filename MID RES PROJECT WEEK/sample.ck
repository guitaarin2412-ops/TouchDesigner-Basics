// --------------------------------------------------------------------
// Ambient Pad Looper (Continuous Rolling Overdub with Keyboard Exit & Slow Fade)
// --------------------------------------------------------------------

10::second => dur loopTime;

// Shared Reverb & Master Output
NRev rev => dac;
0.50 => rev.mix;

HPF hpf => dac; 
200.0 => hpf.freq;


// --- 1. Ambient Pad Looper Setup (Rolling 4-Buffer Sliding Window) ---
4 => int numPads;
LiSa pads[numPads];
ADSR padEnvs[numPads];
PitShift padPss[numPads];

for (0 => int i; i < numPads; i++) {
    adc => pads[i] => padEnvs[i] => padPss[i] => rev;
    pads[i].duration(loopTime);
    1 => pads[i].loop;
    pads[i].recRamp(20::ms);
    0 => pads[i].play;
    0 => pads[i].record;
    padEnvs[i].set(800::ms, 500::ms, 1.0, 3000::ms); // Longer release for smoother transitionsc
}

1.0 => float rate; 
if (me.args() > 0) {
    Std.atof(me.arg(0)) => rate;
    if (rate == 0) 1.0 => rate;
}

// Control flags
0 => int stopTriggered;
0 => int step;


// --- 2. Spork Keyboard Listener Shred ---
spork ~ keyboardListener();


// --- 3. Main Ambient Pad Looping Loop ---

// Initial recording (Pad 0)
cmsg("RECORDING initial ambient pad (10 seconds)...");
pads[0].rampUp(20::ms);
1 => pads[0].record;
loopTime => now;
pads[0].rampDown(20::ms);
0 => pads[0].record;

cmsg("PLAYING BACK initial ambient pad...");
0::ms => pads[0].playPos;
1 => pads[0].play;
padEnvs[0].keyOn();

1 => step; // Move past initial pad

while (!stopTriggered) 
{
    step % numPads => int recIndex;
    
    cmsg("RECORDING ambient pad layer " + recIndex + " (Press any key in terminal to stop)...");
    pads[recIndex].rampUp(20::ms);
    1 => pads[recIndex].record;         
    
    // Pitch shift modulation during the 10-second recording/playback cycle
    for (0 => float i; i < 10.0; 1.0 + i => i) {
        padPss[recIndex].shift(Math.random2f(-2.0, 2.0));
        1 => padPss[recIndex].mix;
        
        if (stopTriggered) break;
        
        loopTime/10.0 => now; 
    }
    
    pads[recIndex].rampDown(20::ms);
    0 => pads[recIndex].record;       
    
    if (stopTriggered) break;
    
    cmsg("PLAYING BACK ambient pad layer " + recIndex + "...");
    0::ms => pads[recIndex].playPos;  
    1 => pads[recIndex].play;
    padEnvs[recIndex].keyOn();
    
    // Maintain maximum of 3 active playbacks by removing the oldest layer when the 4th starts
    if (step >= 3) {
        (step - 3) % numPads => int stopIndex;
        cmsg("REMOVING oldest ambient pad layer " + stopIndex + "...");
        padEnvs[stopIndex].keyOff();
        pads[stopIndex].rampDown(50::ms);
        50::ms => now;
        0 => pads[stopIndex].play;
    }
    
    step++;
}


// --- 4. Graceful Exit Sequence (Slow Fade to Zero) ---
cmsg("Key pressed! Finishing current playback cycle...");
loopTime => now; // Let active playback finish out its cycle

cmsg("Slowly fading out all active pads to zero...");
3::second => dur fadeDuration;

for (0 => int i; i < numPads; i++) {
    padEnvs[i].keyOff();
    pads[i].rampDown(fadeDuration);
}

// Let the slow fade duration fully play out before stopping playback and exiting
fadeDuration => now;

for (0 => int i; i < numPads; i++) {
    0 => pads[i].play;
}

cmsg("Looper stopped successfully.");
me.exit();


// ====================================================================
// FUNCTIONS
// ====================================================================

// Keyboard Listener Shred using ChucK's native KBHit
fun void keyboardListener()
{
    KBHit kb;
    while(true)
    {
        kb => now; // Waits for a keypress event in the terminal window
        while(kb.more())
        {
            kb.getchar() => int c;
            cmsg("Key detected! Signaling graceful stop...");
            1 => stopTriggered;
        }
    }
}

fun void cmsg(string msg) {
    cherr <= "[Ambient Looper]: " <= msg <= IO.nl();
}