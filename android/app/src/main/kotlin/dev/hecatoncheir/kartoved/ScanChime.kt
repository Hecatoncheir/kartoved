package dev.hecatoncheir.kartoved

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool

class ScanChime(context: Context) {
    private val pool = SoundPool.Builder()
        .setAudioAttributes(AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build())
        .build()
    private var ready = false
    private var pending = false
    private val sound: Int

    init {
        pool.setOnLoadCompleteListener { player, id, status ->
            ready = status == 0
            if (ready && pending) player.play(id, 1f, 1f, 1, 0, 1f)
            pending = false
        }
        sound = pool.load(context, R.raw.card_added, 1)
    }

    fun play() {
        if (ready) pool.play(sound, 1f, 1f, 1, 0, 1f)
        else pending = true
    }

    fun close() = pool.release()
}
