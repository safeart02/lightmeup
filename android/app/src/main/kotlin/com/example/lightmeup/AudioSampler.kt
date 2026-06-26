package com.example.lightmeup

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.projection.MediaProjection
import android.util.Log
import kotlin.math.*

class AudioSampler {

    companion object {
        private const val TAG         = "AudioSampler"
        private const val SAMPLE_RATE = 44100
        private const val FFT_SIZE    = 2048
        private const val CHANNEL_CFG = AudioFormat.CHANNEL_IN_STEREO
        private const val ENCODING    = AudioFormat.ENCODING_PCM_16BIT

        // Frequency band boundaries (Hz)
        private const val BASS_HI_HZ = 250f
        private const val MID_HI_HZ  = 2000f

        // Visual Smoothing (Heavy smoothing for fluid lights)
        private const val SMOOTH_ATTACK_BASS  = 0.35f
        private const val SMOOTH_RELEASE_BASS = 0.70f
        private const val SMOOTH_ATTACK_MID   = 0.20f
        private const val SMOOTH_RELEASE_MID  = 0.82f

        // Auto-gain
        private const val PEAK_DECAY = 0.990f

        // --- NEW BPM & METRONOME CONSTANTS ---
        private const val MIN_BPM = 70
        private const val MAX_BPM = 180
        private const val FLUX_THRESHOLD = 1.6f // Multiplier above average flux to trigger an onset
        private const val PLL_NUDGE = 0.1f      // How much the metronome snaps to the real audio (10%)
    }

    data class ChannelBands(
        val bass:   Float,
        val mid:    Float,
        val high:   Float,
        val isBeat: Boolean // Renamed for clarity, driven by the Metronome
    )

    data class StereoBands(
        val left:  ChannelBands,
        val right: ChannelBands,
        val macroEnergy: Float,
    ) {
        val mono get() = ChannelBands(
            bass   = (left.bass + right.bass) / 2f,
            mid    = (left.mid  + right.mid)  / 2f,
            high   = (left.high + right.high) / 2f,
            isBeat = left.isBeat || right.isBeat,
        )
    }

    data class Bands(val bass: Float, val mid: Float, val high: Float)

    @Volatile private var latestStereo = StereoBands(
        left  = ChannelBands(0f, 0f, 0f, false),
        right = ChannelBands(0f, 0f, 0f, false),
        macroEnergy = 0f
    )

    private var audioRecord:   AudioRecord? = null
    private var captureThread: Thread?      = null
    @Volatile private var running           = false

    // Visual state
    private var smL = FloatArray(3)
    private var smR = FloatArray(3)
    private var peakL = FloatArray(3) { 1e-6f }
    private var peakR = FloatArray(3) { 1e-6f }
    private var macroEnergy = 0f

    // --- NEW BEAT TRACKING STATE ---
    // We sum stereo to mono for beat detection to ensure a single, stable metronome
    private val prevMags = FloatArray(FFT_SIZE / 2)
    private var smoothFlux = 0f
    
    // Histogram to find the dominant BPM
    private val bpmBuckets = FloatArray(MAX_BPM + 1)
    private var lastOnsetMs = 0L
    
    // The Predictive Metronome
    private var currentBpm = 120
    private var lastMetronomeBeatMs = 0L

    fun start(projection: MediaProjection) {
        if (running) return

        val minBuf  = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CFG, ENCODING)
        val bufSize = maxOf(minBuf, FFT_SIZE * 4)

        val config = AudioPlaybackCaptureConfiguration.Builder(projection)
            .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
            .addMatchingUsage(AudioAttributes.USAGE_GAME)
            .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
            .build()

        val record = AudioRecord.Builder()
            .setAudioPlaybackCaptureConfig(config)
            .setAudioFormat(
                AudioFormat.Builder()
                    .setSampleRate(SAMPLE_RATE)
                    .setChannelMask(CHANNEL_CFG)
                    .setEncoding(ENCODING)
                    .build()
            )
            .setBufferSizeInBytes(bufSize)
            .build()

        if (record.state != AudioRecord.STATE_INITIALIZED) {
            Log.e(TAG, "AudioRecord failed to initialize")
            record.release()
            return
        }

        audioRecord = record
        running     = true
        record.startRecording()

        captureThread = Thread({
            val pcm = ShortArray(FFT_SIZE * 2)
            val reL = FloatArray(FFT_SIZE);  val imL = FloatArray(FFT_SIZE)
            val reR = FloatArray(FFT_SIZE);  val imR = FloatArray(FFT_SIZE)
            
            Log.i(TAG, "Audio capture started (Flux + Predictive Metronome)")

            while (running) {
                val read = record.read(pcm, 0, pcm.size)
                if (read <= 0) continue

                val frames = minOf(read / 2, FFT_SIZE)
                val nowMs  = System.currentTimeMillis()

                // Deinterleave & Hann window
                for (i in 0 until frames) {
                    val w = hannWindow(i, FFT_SIZE)
                    reL[i] = (pcm[i * 2].toFloat()     / 32768f) * w;  imL[i] = 0f
                    reR[i] = (pcm[i * 2 + 1].toFloat() / 32768f) * w;  imR[i] = 0f
                }
                for (i in frames until FFT_SIZE) {
                    reL[i] = 0f; imL[i] = 0f; reR[i] = 0f; imR[i] = 0f
                }

                fft(reL, imL);  fft(reR, imR)

                // 1. Calculate Visual Bands (Smoothed)
                val hzPerBin  = SAMPLE_RATE.toFloat() / FFT_SIZE
                val bassHiBin = (BASS_HI_HZ / hzPerBin).toInt().coerceAtMost(FFT_SIZE / 2)
                val midHiBin  = (MID_HI_HZ  / hzPerBin).toInt().coerceAtMost(FFT_SIZE / 2)

                val rawL = computeBands(reL, imL, bassHiBin, midHiBin)
                val rawR = computeBands(reR, imR, bassHiBin, midHiBin)
                val nL = normalize(rawL, peakL)
                val nR = normalize(rawR, peakR)

                for (b in 0..2) {
                    val attack  = if (b == 0) SMOOTH_ATTACK_BASS  else SMOOTH_ATTACK_MID
                    val release = if (b == 0) SMOOTH_RELEASE_BASS else SMOOTH_RELEASE_MID
                    smL[b] = smoothBand(smL[b], nL[b], attack, release)
                    smR[b] = smoothBand(smR[b], nR[b], attack, release)
                }

                // 2. Calculate Spectral Flux (Raw transients across all frequencies)
                var currentFlux = 0f
                for (bin in 1 until FFT_SIZE / 2) {
                    // Mono mix for beat tracking
                    val magL = sqrt(reL[bin] * reL[bin] + imL[bin] * imL[bin])
                    val magR = sqrt(reR[bin] * reR[bin] + imR[bin] * imR[bin])
                    val magMono = (magL + magR) / 2f
                    
                    val difference = magMono - prevMags[bin]
                    if (difference > 0) {
                        currentFlux += difference // Only sum positive increases
                    }
                    prevMags[bin] = magMono
                }

                // Smooth the flux to create a dynamic threshold
                smoothFlux = smoothFlux * 0.8f + currentFlux * 0.2f
                
                // Onset Detection: Did energy spike suddenly?
                val isOnset = currentFlux > (smoothFlux * FLUX_THRESHOLD) && currentFlux > 0.05f

                // 3. Histogram BPM Tracker
                if (isOnset) {
                    val deltaMs = nowMs - lastOnsetMs
                    if (deltaMs in 200..2000) { // Ignore absurd jumps
                        val impliedBpm = (60000 / deltaMs).toInt()
                        
                        // Handle double-time/half-time wrapping
                        val normalizedBpm = when {
                            impliedBpm < MIN_BPM -> impliedBpm * 2
                            impliedBpm > MAX_BPM -> impliedBpm / 2
                            else -> impliedBpm
                        }.coerceIn(MIN_BPM, MAX_BPM)

                        // Vote for this BPM
                        bpmBuckets[normalizedBpm] += 1f
                    }
                    lastOnsetMs = nowMs
                }

                // Decay the histogram slowly so it can adapt to tempo changes
                var maxVotes = 0f
                var bestBpm = currentBpm
                for (i in MIN_BPM..MAX_BPM) {
                    bpmBuckets[i] *= 0.995f // Slow decay
                    if (bpmBuckets[i] > maxVotes) {
                        maxVotes = bpmBuckets[i]
                        bestBpm = i
                    }
                }
                // Only update BPM if we have strong confidence (avoids drift in silence)
                if (maxVotes > 2.0f) {
                    currentBpm = bestBpm
                }

                // 4. Predictive Metronome (Phase-Locked Loop)
                val beatIntervalMs = 60000 / currentBpm
                var metronomeBeat = false

                if (nowMs - lastMetronomeBeatMs >= beatIntervalMs) {
                    metronomeBeat = true
                    lastMetronomeBeatMs = nowMs
                }

                // If a real audio onset happens near our metronome, nudge the metronome to align
                if (isOnset) {
                    val timeSinceMetronome = nowMs - lastMetronomeBeatMs
                    if (timeSinceMetronome < beatIntervalMs / 4) {
                        // Onset is slightly late, pull metronome forward
                        lastMetronomeBeatMs += (timeSinceMetronome * PLL_NUDGE).toLong()
                    } else if (timeSinceMetronome > beatIntervalMs * 3 / 4) {
                        // Onset is slightly early, push metronome back
                        val earlyAmount = beatIntervalMs - timeSinceMetronome
                        lastMetronomeBeatMs -= (earlyAmount * PLL_NUDGE).toLong()
                    }
                }

                // Calculate total normalized energy for this frame across all bands
                val currentTotalEnergy = (smL[0] + smL[1] + smL[2] + smR[0] + smR[1] + smR[2]) / 6f

                // Slowly roll the average (98% old data, 2% new data) to track long-term song intensity
                macroEnergy = macroEnergy * 0.98f + currentTotalEnergy * 0.02f 

                // Dispatch state
                latestStereo = StereoBands(
                    left  = ChannelBands(smL[0], smL[1], smL[2], metronomeBeat),
                    right = ChannelBands(smR[0], smR[1], smR[2], metronomeBeat),
                    macroEnergy = macroEnergy // <--- Pass it to the visualizer
                )

            }

            record.stop()
            record.release()
            Log.i(TAG, "Audio capture stopped")
        }, "LightMeUpAudio").also { it.isDaemon = true }

        captureThread!!.start()
    }

    fun stop() {
        running = false
        captureThread?.join(500)
        captureThread = null
        audioRecord   = null
        
        // Reset state
        smL = FloatArray(3); smR = FloatArray(3)
        peakL = FloatArray(3) { 1e-6f }; peakR = FloatArray(3) { 1e-6f }
        prevMags.fill(0f)
        bpmBuckets.fill(0f)
        smoothFlux = 0f
        currentBpm = 120
        
        latestStereo = StereoBands(
            left  = ChannelBands(0f, 0f, 0f, false),
            right = ChannelBands(0f, 0f, 0f, false),
            macroEnergy = 0f
        )
    }

    fun getStereo(): StereoBands = latestStereo
    fun getBands(): Bands { val m = latestStereo.mono; return Bands(m.bass, m.mid, m.high) }
    val isRunning get() = running

    // -------------------------------------------------------------------------
    // DSP helpers
    // -------------------------------------------------------------------------

    private fun hannWindow(i: Int, n: Int) =
        (0.5f * (1f - cos(2.0 * PI * i / (n - 1)))).toFloat()

    private fun computeBands(re: FloatArray, im: FloatArray, bassHiBin: Int, midHiBin: Int): FloatArray {
        var bass = 0f; var mid = 0f; var high = 0f
        for (bin in 1 until FFT_SIZE / 2) {
            val mag = sqrt(re[bin] * re[bin] + im[bin] * im[bin])
            when {
                bin <= bassHiBin -> bass += mag
                bin <= midHiBin  -> mid  += mag
                else             -> high += mag
            }
        }
        bass /= bassHiBin.toFloat()
        mid  /= (midHiBin - bassHiBin).toFloat().coerceAtLeast(1f)
        high /= (FFT_SIZE / 2 - midHiBin).toFloat().coerceAtLeast(1f)
        return floatArrayOf(bass, mid, high)
    }

    private fun normalize(raw: FloatArray, peaks: FloatArray) = FloatArray(3) { b ->
        peaks[b] = maxOf(peaks[b] * PEAK_DECAY, raw[b])
        (raw[b] / peaks[b]).coerceIn(0f, 1f)
    }

    private fun smoothBand(current: Float, target: Float, attack: Float, release: Float): Float {
        val alpha = if (target > current) attack else release
        return current + alpha * (target - current)
    }

    private fun fft(re: FloatArray, im: FloatArray) {
        val n = re.size
        var j = 0
        for (i in 1 until n) {
            var bit = n shr 1
            while (j and bit != 0) { j = j xor bit; bit = bit shr 1 }
            j = j xor bit
            if (i < j) {
                var t = re[i]; re[i] = re[j]; re[j] = t
                    t = im[i]; im[i] = im[j]; im[j] = t
            }
        }
        var len = 2
        while (len <= n) {
            val half      = len / 2
            val angleStep = -2.0 * PI / len
            for (i in 0 until n step len) {
                for (k in 0 until half) {
                    val angle = angleStep * k
                    val wr = cos(angle).toFloat();  val wi = sin(angle).toFloat()
                    val ur = re[i + k];             val ui = im[i + k]
                    val vr = re[i + k + half] * wr - im[i + k + half] * wi
                    val vi = re[i + k + half] * wi + im[i + k + half] * wr
                    re[i + k]        = ur + vr;  im[i + k]        = ui + vi
                    re[i + k + half] = ur - vr;  im[i + k + half] = ui - vi
                }
            }
            len = len shl 1
        }
    }
}