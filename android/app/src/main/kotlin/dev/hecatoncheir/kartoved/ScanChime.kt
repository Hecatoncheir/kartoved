package dev.hecatoncheir.kartoved

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool

class ScanChime(context: Context) {
    private val pool = SoundPool.Builder()
        .setMaxStreams(2)
        .setAudioAttributes(AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build())
        .build()
    private val ready = mutableSetOf<Int>()
    private val pending = mutableSetOf<Int>()
    private val added: Int
    private val found: Int
    private val review: Int

    init {
        pool.setOnLoadCompleteListener { player, id, status ->
            val shouldPlay = pending.remove(id)
            if (status == 0) {
                ready.add(id)
                if (shouldPlay) player.play(id, 1f, 1f, 1, 0, 1f)
            }
        }
        added = pool.load(context, R.raw.card_added, 1)
        found = pool.load(context, R.raw.card_found, 1)
        review = pool.load(context, R.raw.card_review, 1)
    }

    fun play(outcome: String?) {
        val sound = when (outcome) {
            "found" -> found
            "review" -> review
            else -> added
        }
        if (sound in ready) pool.play(sound, 1f, 1f, 1, 0, 1f)
        else pending.add(sound)
    }

    fun close() = pool.release()
}
