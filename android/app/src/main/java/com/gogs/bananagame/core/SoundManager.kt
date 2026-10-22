package com.gogs.bananagame.core

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.pow
import kotlin.math.sin

/**
 * Generates the game's sound effects in code (no audio files) — the iOS synthesizer's exact tones
 * (sine mixes with a 5 ms attack and a squared decay) are rendered once to small WAV files in the
 * cache directory and played through a [SoundPool] for low latency.
 */
object SoundManager {
    private const val KEY = "soundEnabled"
    private const val SAMPLE_RATE = 44_100

    private var enabledState by mutableStateOf(true)

    /** Master on/off for all sound effects. Persisted. */
    var isEnabled: Boolean
        get() = enabledState
        set(value) {
            enabledState = value
            Prefs.putBool(KEY, value)
        }

    /** Transient mute used while a manual's live demo is on screen. */
    @Volatile var suppressed = false

    private var pool: SoundPool? = null
    private val ids = HashMap<String, Int>()

    fun init(context: Context) {
        enabledState = Prefs.getBool(KEY, true)
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_GAME)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val p = SoundPool.Builder().setMaxStreams(8).setAudioAttributes(attrs).build()
        pool = p
        val dir = File(context.cacheDir, "sfx").apply { mkdirs() }
        fun make(name: String, vararg notes: Note) {
            val f = File(dir, "$name.wav")
            if (!f.exists() || f.length() < 64) writeWav(f, render(notes.toList()))
            ids[name] = p.load(f.absolutePath, 1)
        }
        make("tap", Note(doubleArrayOf(660.0, 990.0), 0.06, 0.45))
        make("success", Note(doubleArrayOf(523.0), 0.12, 0.5), Note(doubleArrayOf(659.0), 0.12, 0.5),
            Note(doubleArrayOf(784.0), 0.20, 0.5))
        make("error", Note(doubleArrayOf(150.0, 160.0), 0.22, 0.5))
        make("tick", Note(doubleArrayOf(700.0), 0.08, 0.4))
        make("go", Note(doubleArrayOf(1046.0), 0.16, 0.5))
        val scale = doubleArrayOf(392.0, 523.0, 659.0, 784.0)
        scale.forEachIndexed { i, f -> make("pad$i", Note(doubleArrayOf(f), 0.2, 0.5)) }
    }

    /** A quick pop — for tapping a banana / button. */
    fun tap() = play("tap")
    /** A rising three-note arpeggio — for beating a level. */
    fun success() = play("success")
    /** A low buzz — for a mistake. */
    fun error() = play("error")
    /** A soft blip — each "3 · 2 · 1" countdown tick. */
    fun countdownTick() = play("tick")
    /** A bright chime — the moment a game starts. */
    fun countdownGo() = play("go")
    /** A distinct musical note per pad — for the memory game. */
    fun padTone(index: Int) = play("pad${((index % 4) + 4) % 4}")

    private fun play(name: String) {
        if (!enabledState || suppressed) return
        val p = pool ?: return
        val id = ids[name] ?: return
        p.play(id, 1f, 1f, 1, 0, 1f)
    }

    private class Note(val freqs: DoubleArray, val duration: Double, val volume: Double)

    private fun render(notes: List<Note>): ShortArray {
        val out = ArrayList<Short>()
        for (n in notes) {
            val frames = (SAMPLE_RATE * n.duration).toInt()
            val attack = 0.005
            for (i in 0 until frames) {
                val t = i.toDouble() / SAMPLE_RATE
                var v = 0.0
                for (f in n.freqs) v += sin(2 * PI * f * t)
                v /= n.freqs.size
                val progress = t / n.duration
                val env = if (t < attack) t / attack else (1.0 - progress).pow(2.0)
                val s = (v * env * n.volume).coerceIn(-1.0, 1.0)
                out.add((s * Short.MAX_VALUE).toInt().toShort())
            }
        }
        return out.toShortArray()
    }

    private fun writeWav(file: File, pcm: ShortArray) {
        val dataLen = pcm.size * 2
        val b = ByteBuffer.allocate(44 + dataLen).order(ByteOrder.LITTLE_ENDIAN)
        b.put("RIFF".toByteArray()); b.putInt(36 + dataLen); b.put("WAVE".toByteArray())
        b.put("fmt ".toByteArray()); b.putInt(16); b.putShort(1); b.putShort(1)
        b.putInt(SAMPLE_RATE); b.putInt(SAMPLE_RATE * 2); b.putShort(2); b.putShort(16)
        b.put("data".toByteArray()); b.putInt(dataLen)
        for (s in pcm) b.putShort(s)
        FileOutputStream(file).use { it.write(b.array()) }
    }
}
